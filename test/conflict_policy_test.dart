import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';
import 'package:pos_sync/features/orders/sync/conflict_policy.dart';

final DateTime t0 = DateTime(2026, 9, 5, 20);

Revision rev(int counter, String device) =>
    Revision(counter: counter, deviceId: device);

OrderLine riga(String id,
        {int counter = 1, String device = 'a', int qta = 1}) =>
    OrderLine(
      id: id,
      productId: 'p-$id',
      description: 'Piatto $id',
      quantity: qta,
      unitPriceCents: 500,
      addedAt: rev(counter, device),
    );

Order ordine({
  required List<OrderLine> righe,
  OrderState stato = OrderState.aperto,
  Revision? revisione,
}) =>
    Order(
      id: 'o-1',
      tableNumber: 7,
      lines: righe,
      createdAt: t0,
      state: stato,
      stateRevision: revisione ?? const Revision.initial(),
    );

/// Estrae il valore da una fusione riuscita, fallendo con un messaggio utile
/// se invece si è fermata.
Order risolto(Resolution<Order> r) {
  if (r is Resolved<Order>) return r.value;
  throw TestFailure('Atteso Resolved, ottenuto NeedsDecision: '
      '${(r as NeedsDecision<Order>).reason}');
}

void main() {
  const AppendOnlyLines righe = AppendOnlyLines();
  const LastWriteWinsState stato = LastWriteWinsState();
  const OrderConflictPolicy politica = OrderConflictPolicy();

  group('AppendOnlyLines · le righe si uniscono', () {
    test('unisce due insiemi disgiunti', () {
      final Resolution<List<OrderLine>> r = righe.merge(
        <OrderLine>[riga('1')],
        <OrderLine>[riga('2', device: 'b')],
      );
      expect((r as Resolved<List<OrderLine>>).value.length, 2);
    });

    test('è commutativa: l ordine di arrivo non conta', () {
      // È la proprietà da cui discende la convergenza. Se `merge(a, b)` e
      // `merge(b, a)` dessero risultati diversi, due dispositivi che ricevono
      // le stesse modifiche in ordine diverso finirebbero in stati diversi, e
      // nessun'altra precauzione potrebbe rimediare.
      final List<OrderLine> a = <OrderLine>[riga('1'), riga('3', counter: 5)];
      final List<OrderLine> b = <OrderLine>[riga('2', device: 'b', counter: 2)];

      final List<OrderLine> ab =
          (righe.merge(a, b) as Resolved<List<OrderLine>>).value;
      final List<OrderLine> ba =
          (righe.merge(b, a) as Resolved<List<OrderLine>>).value;

      expect(ab, ba);
    });

    test('è idempotente: sincronizzare due volte non duplica', () {
      final List<OrderLine> a = <OrderLine>[riga('1'), riga('2')];
      final List<OrderLine> unaVolta =
          (righe.merge(a, a) as Resolved<List<OrderLine>>).value;
      final List<OrderLine> dueVolte =
          (righe.merge(unaVolta, a) as Resolved<List<OrderLine>>).value;

      expect(unaVolta.length, 2);
      expect(dueVolte, unaVolta);
    });

    test('nessuna riga si perde, da nessuna delle due parti', () {
      final List<OrderLine> merged = (righe.merge(
        <OrderLine>[riga('1'), riga('2')],
        <OrderLine>[riga('2'), riga('3', device: 'b')],
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
      final StampedState mia = StampedState(OrderState.servito, rev(2, 'a'));
      final StampedState sua = StampedState(OrderState.pagato, rev(5, 'b'));

      expect((stato.merge(mia, sua) as Resolved<StampedState>).value, sua);
      expect((stato.merge(sua, mia) as Resolved<StampedState>).value, sua,
          reason: 'invertendo gli argomenti deve vincere lo stesso');
    });

    test('a parità di contatore decide il dispositivo, ma decide sempre', () {
      final StampedState a =
          StampedState(OrderState.servito, rev(4, 'tablet-a'));
      final StampedState b =
          StampedState(OrderState.pagato, rev(4, 'tablet-b'));

      expect((stato.merge(a, b) as Resolved<StampedState>).value, b);
      expect((stato.merge(b, a) as Resolved<StampedState>).value, b);
    });
  });

  group('OrderConflictPolicy · cosa converge da solo', () {
    test('due dispositivi che aggiungono piatti non sono in conflitto', () {
      final Order fuso = risolto(politica.merge(
        ordine(righe: <OrderLine>[riga('1')]),
        ordine(righe: <OrderLine>[riga('2', device: 'b')]),
      ));

      expect(fuso.lines.length, 2);
      expect(fuso.state, OrderState.aperto);
    });

    test('uno serve mentre l altro aggiunge: nessuna interruzione', () {
      final Order fuso = risolto(politica.merge(
        ordine(
          righe: <OrderLine>[riga('1')],
          stato: OrderState.servito,
          revisione: rev(3, 'a'),
        ),
        ordine(righe: <OrderLine>[riga('1'), riga('2', device: 'b')]),
      ));

      expect(fuso.state, OrderState.servito);
      expect(fuso.lines.length, 2);
    });

    test('entrambi hanno già incassato: non c è niente da chiedere', () {
      final Order fuso = risolto(politica.merge(
        ordine(
          righe: <OrderLine>[riga('1')],
          stato: OrderState.pagato,
          revisione: rev(4, 'a'),
        ),
        ordine(
          righe: <OrderLine>[riga('1')],
          stato: OrderState.pagato,
          revisione: rev(2, 'b'),
        ),
      ));

      expect(fuso.state, OrderState.pagato);
    });
  });

  group('OrderConflictPolicy · dove si ferma', () {
    test('pagato contro righe che chi ha incassato non aveva davanti', () {
      // Le due politiche prese alla lettera darebbero un tavolo pagato con
      // dentro roba non pagata: un risultato che non fa rumore da nessuna
      // parte tranne che in cassa a fine serata.
      final Resolution<Order> esito = politica.merge(
        ordine(
          righe: <OrderLine>[riga('1')],
          stato: OrderState.pagato,
          revisione: rev(4, 'cassa'),
        ),
        ordine(
            righe: <OrderLine>[riga('1'), riga('2', device: 'sala', qta: 2)]),
      );

      expect(esito, isA<NeedsDecision<Order>>());
      final NeedsDecision<Order> fermata = esito as NeedsDecision<Order>;
      expect(fermata.reason, contains('tavolo 7'));
      expect(fermata.reason, contains('2 articoli'));
      expect(fermata.mine.state, OrderState.pagato);
      expect(fermata.theirs.state, OrderState.aperto);
    });

    test('si ferma anche se a incassare è stato l altro dispositivo', () {
      final Resolution<Order> esito = politica.merge(
        ordine(righe: <OrderLine>[riga('1'), riga('2', device: 'sala')]),
        ordine(
          righe: <OrderLine>[riga('1')],
          stato: OrderState.pagato,
          revisione: rev(9, 'cassa'),
        ),
      );

      expect(esito, isA<NeedsDecision<Order>>());
    });

    test('non si ferma se chi ha incassato aveva già tutte le righe', () {
      final Order fuso = risolto(politica.merge(
        ordine(
          righe: <OrderLine>[riga('1'), riga('2', device: 'sala')],
          stato: OrderState.pagato,
          revisione: rev(9, 'cassa'),
        ),
        ordine(righe: <OrderLine>[riga('1'), riga('2', device: 'sala')]),
      ));

      expect(fuso.state, OrderState.pagato);
      expect(fuso.lines.length, 2);
    });

    test('il riconoscimento non dipende dai contatori', () {
      // Con un orologio di Lamport una riga aggiunta da un dispositivo che non
      // aveva ancora visto il pagamento porta un contatore *più basso*. Un
      // controllo del tipo "la riga è successiva al pagamento?" la lascerebbe
      // passare in silenzio: qui la riga vale 1, il pagamento 50.
      final Resolution<Order> esito = politica.merge(
        ordine(
          righe: <OrderLine>[riga('1', counter: 50, device: 'cassa')],
          stato: OrderState.pagato,
          revisione: rev(50, 'cassa'),
        ),
        ordine(
          righe: <OrderLine>[
            riga('1', counter: 50, device: 'cassa'),
            riga('2', counter: 1, device: 'sala'),
          ],
        ),
      );

      expect(esito, isA<NeedsDecision<Order>>(),
          reason: 'una riga mai vista da chi ha incassato resta un problema '
              'anche se il suo contatore è più basso');
    });
  });
}
