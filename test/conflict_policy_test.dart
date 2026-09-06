import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';
import 'package:pos_sync/features/orders/sync/conflict_policy.dart';

final DateTime t0 = DateTime(2026, 9, 5, 20);

Revision rev(int counter, String device) =>
    Revision(counter: counter, deviceId: device);

OrderLine line(String id,
        {int counter = 1, String device = 'a', int qty = 1}) =>
    OrderLine(
      id: id,
      productId: 'p-$id',
      description: 'Piatto $id',
      quantity: qty,
      unitPriceCents: 500,
      addedAt: rev(counter, device),
    );

Order order({
  required List<OrderLine> lines,
  OrderState state = OrderState.open,
  Revision? revision,
}) =>
    Order(
      id: 'o-1',
      tableNumber: 7,
      lines: lines,
      createdAt: t0,
      state: state,
      stateRevision: revision ?? const Revision.initial(),
    );

/// Estrae il valore da una fusione riuscita, fallendo con un messaggio utile
/// se invece si è fermata.
Order resolved(Resolution<Order> r) {
  if (r is Resolved<Order>) return r.value;
  throw TestFailure('Atteso Resolved, ottenuto NeedsDecision: '
      '${(r as NeedsDecision<Order>).reason}');
}

void main() {
  const AppendOnlyLines linePolicy = AppendOnlyLines();
  const LastWriteWinsState statePolicy = LastWriteWinsState();
  const OrderConflictPolicy policy = OrderConflictPolicy();

  group('AppendOnlyLines · le righe si uniscono', () {
    test('unisce due insiemi disgiunti', () {
      final Resolution<List<OrderLine>> r = linePolicy.merge(
        <OrderLine>[line('1')],
        <OrderLine>[line('2', device: 'b')],
      );
      expect((r as Resolved<List<OrderLine>>).value.length, 2);
    });

    test('è commutativa: l ordine di arrivo non conta', () {
      // È la proprietà da cui discende la convergenza. Se `merge(a, b)` e
      // `merge(b, a)` dessero risultati diversi, due dispositivi che ricevono
      // le stesse modifiche in ordine diverso finirebbero in stati diversi, e
      // nessun'altra precauzione potrebbe rimediare.
      final List<OrderLine> a = <OrderLine>[line('1'), line('3', counter: 5)];
      final List<OrderLine> b = <OrderLine>[line('2', device: 'b', counter: 2)];

      final List<OrderLine> ab =
          (linePolicy.merge(a, b) as Resolved<List<OrderLine>>).value;
      final List<OrderLine> ba =
          (linePolicy.merge(b, a) as Resolved<List<OrderLine>>).value;

      expect(ab, ba);
    });

    test('è idempotente: sincronizzare due volte non duplica', () {
      final List<OrderLine> a = <OrderLine>[line('1'), line('2')];
      final List<OrderLine> once =
          (linePolicy.merge(a, a) as Resolved<List<OrderLine>>).value;
      final List<OrderLine> twice =
          (linePolicy.merge(once, a) as Resolved<List<OrderLine>>).value;

      expect(once.length, 2);
      expect(twice, once);
    });

    test('nessuna riga si perde, da nessuna delle due parti', () {
      final List<OrderLine> merged = (linePolicy.merge(
        <OrderLine>[line('1'), line('2')],
        <OrderLine>[line('2'), line('3', device: 'b')],
      ) as Resolved<List<OrderLine>>)
          .value;

      expect(
        merged.map((OrderLine l) => l.id).toSet(),
        <String>{'1', '2', '3'},
      );
    });
  });

  group('LastWriteWinsState · lo stato del tavolo', () {
    test('vince la revisione più alta, non chi arriva per ultimo', () {
      final StampedState mine = StampedState(OrderState.served, rev(2, 'a'));
      final StampedState theirs = StampedState(OrderState.paid, rev(5, 'b'));

      expect((statePolicy.merge(mine, theirs) as Resolved<StampedState>).value,
          theirs);
      expect((statePolicy.merge(theirs, mine) as Resolved<StampedState>).value,
          theirs,
          reason: 'invertendo gli argomenti deve vincere lo stesso');
    });

    test('a parità di contatore decide il dispositivo, ma decide sempre', () {
      final StampedState a =
          StampedState(OrderState.served, rev(4, 'tablet-a'));
      final StampedState b = StampedState(OrderState.paid, rev(4, 'tablet-b'));

      expect((statePolicy.merge(a, b) as Resolved<StampedState>).value, b);
      expect((statePolicy.merge(b, a) as Resolved<StampedState>).value, b);
    });
  });

  group('OrderConflictPolicy · cosa converge da solo', () {
    test('due dispositivi che aggiungono piatti non sono in conflitto', () {
      final Order merged = resolved(policy.merge(
        order(lines: <OrderLine>[line('1')]),
        order(lines: <OrderLine>[line('2', device: 'b')]),
      ));

      expect(merged.lines.length, 2);
      expect(merged.state, OrderState.open);
    });

    test('uno serve mentre l altro aggiunge: nessuna interruzione', () {
      final Order merged = resolved(policy.merge(
        order(
          lines: <OrderLine>[line('1')],
          state: OrderState.served,
          revision: rev(3, 'a'),
        ),
        order(lines: <OrderLine>[line('1'), line('2', device: 'b')]),
      ));

      expect(merged.state, OrderState.served);
      expect(merged.lines.length, 2);
    });

    test('entrambi hanno già incassato: non c è niente da chiedere', () {
      final Order merged = resolved(policy.merge(
        order(
          lines: <OrderLine>[line('1')],
          state: OrderState.paid,
          revision: rev(4, 'a'),
        ),
        order(
          lines: <OrderLine>[line('1')],
          state: OrderState.paid,
          revision: rev(2, 'b'),
        ),
      ));

      expect(merged.state, OrderState.paid);
    });
  });

  group('OrderConflictPolicy · dove si ferma', () {
    test('pagato contro righe che chi ha incassato non aveva davanti', () {
      // Le due politiche prese alla lettera darebbero un tavolo pagato con
      // dentro roba non pagata: un risultato che non fa rumore da nessuna
      // parte tranne che in cassa a fine serata.
      final Resolution<Order> outcome = policy.merge(
        order(
          lines: <OrderLine>[line('1')],
          state: OrderState.paid,
          revision: rev(4, 'cassa'),
        ),
        order(lines: <OrderLine>[line('1'), line('2', device: 'sala', qty: 2)]),
      );

      expect(outcome, isA<NeedsDecision<Order>>());
      final NeedsDecision<Order> stopped = outcome as NeedsDecision<Order>;
      expect(stopped.reason, contains('tavolo 7'));
      expect(stopped.reason, contains('2 articoli'));
      expect(stopped.mine.state, OrderState.paid);
      expect(stopped.theirs.state, OrderState.open);
    });

    test('si ferma anche se a incassare è stato l altro dispositivo', () {
      final Resolution<Order> outcome = policy.merge(
        order(lines: <OrderLine>[line('1'), line('2', device: 'sala')]),
        order(
          lines: <OrderLine>[line('1')],
          state: OrderState.paid,
          revision: rev(9, 'cassa'),
        ),
      );

      expect(outcome, isA<NeedsDecision<Order>>());
    });

    test('non si ferma se chi ha incassato aveva già tutte le righe', () {
      final Order merged = resolved(policy.merge(
        order(
          lines: <OrderLine>[line('1'), line('2', device: 'sala')],
          state: OrderState.paid,
          revision: rev(9, 'cassa'),
        ),
        order(lines: <OrderLine>[line('1'), line('2', device: 'sala')]),
      ));

      expect(merged.state, OrderState.paid);
      expect(merged.lines.length, 2);
    });

    test('il riconoscimento non dipende dai contatori', () {
      // Con un orologio di Lamport una riga aggiunta da un dispositivo che non
      // aveva ancora visto il pagamento porta un contatore *più basso*. Un
      // controllo del tipo "la riga è successiva al pagamento?" la lascerebbe
      // passare in silenzio: qui la riga vale 1, il pagamento 50.
      final Resolution<Order> outcome = policy.merge(
        order(
          lines: <OrderLine>[line('1', counter: 50, device: 'cassa')],
          state: OrderState.paid,
          revision: rev(50, 'cassa'),
        ),
        order(
          lines: <OrderLine>[
            line('1', counter: 50, device: 'cassa'),
            line('2', counter: 1, device: 'sala'),
          ],
        ),
      );

      expect(outcome, isA<NeedsDecision<Order>>(),
          reason: 'una riga mai vista da chi ha incassato resta un problema '
              'anche se il suo contatore è più basso');
    });
  });
}
