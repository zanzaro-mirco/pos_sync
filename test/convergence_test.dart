/// Il criterio della voce 2.4: due dispositivi che modificano lo stesso tavolo
/// in ordine invertito convergono allo stesso stato finale.
///
/// Il criterio chiede **convergenza**, non "il conflitto viene gestito", ed è
/// la differenza che conta: o l'ordine di arrivo smette di contare, o il test
/// fallisce. Non lo si soddisfa con un `if`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_conflict.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_line_draft.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';

import 'helpers/fixtures.dart';

const OrderLineDraft coffee = OrderLineDraft(
  productId: 'p-01',
  description: 'Caffè',
  quantity: 2,
  unitPriceCents: 120,
);

const OrderLineDraft croissant = OrderLineDraft(
  productId: 'p-02',
  description: 'Cornetto',
  quantity: 1,
  unitPriceCents: 150,
);

/// Ciò che i due dispositivi devono avere identico.
///
/// `status` è escluso di proposito: dice se *questo* dispositivo è riuscito a
/// mandare l'ordine, ed è giusto che i due non siano d'accordo. Confrontare
/// l'ordine intero significherebbe pretendere che un fatto locale sia
/// condiviso, cioè misurare la cosa sbagliata.
///
/// Le righe sono una stringa e non una lista perché i record confrontano i
/// campi con `==`, e per una `List` `==` è l'identità: due liste con lo stesso
/// contenuto risulterebbero diverse e il test fallirebbe mostrando due valori
/// identici.
typedef SharedState = ({
  int table,
  OrderState state,
  Revision revision,
  String lines,
  int total,
});

/// Ciò che vedrebbe una persona guardando il tablet.
///
/// Serve a confrontare *storie diverse* fra loro. Il contatore logico e gli
/// identificativi delle righe dipendono da quante operazioni quel dispositivo
/// ha fatto prima: un cameriere che serve prima di aggiungere arriva allo
/// stesso tavolo con numeri diversi da uno che fa il contrario. Preterderli
/// uguali significherebbe pretendere che due storie diverse siano la stessa
/// storia, non che portino allo stesso risultato.
typedef VisibleState = ({
  int table,
  OrderState state,
  String dishes,
  int total,
});

VisibleState visible(Order o) => (
      table: o.tableNumber,
      state: o.state,
      dishes: (o.lines
              .map((OrderLine l) => '${l.description} x${l.quantity}')
              .toList()
            ..sort())
          .join(', '),
      total: o.totalCents,
    );

SharedState shared(Order o) => (
      table: o.tableNumber,
      state: o.state,
      revision: o.stateRevision,
      lines:
          o.lines.map((OrderLine l) => '${l.id}:${l.description}').join(', '),
      total: o.totalCents,
    );

/// Due tablet nello stesso locale, con un ordine già condiviso fra i due.
class Room {
  Room._(this.a, this.b, this.orderId);

  static Future<Room> open() async {
    final FakeServer server = FakeServer();
    final TestEnv a =
        TestEnv(server: server, deviceId: 'tablet-a', idPrefix: 'a');
    final TestEnv b =
        TestEnv(server: server, deviceId: 'tablet-b', idPrefix: 'b');

    final Order order = await a.repository
        .createOrder(tableNumber: 7, lines: <OrderLineDraft>[coffee]);
    await a.worker.drain();
    await b.worker.drain(); // b lo riceve dal server

    return Room._(a, b, order.id);
  }

  final TestEnv a;
  final TestEnv b;
  final String orderId;

  /// Fa girare la sincronizzazione finché non cambia più niente.
  ///
  /// Non è un artificio del test: è quello che fanno i dispositivi veri, che
  /// sincronizzano a ogni ritorno della rete e ogni quarto d'ora. Il numero di
  /// giri è un limite superiore — se servissero più di così, il sistema non
  /// convergerebbe e il test lo direbbe.
  Future<void> settle({int rounds = 3}) async {
    for (int i = 0; i < rounds; i++) {
      // L'orologio avanza fra un giro e l'altro: una voce che ha già fallito
      // porta un `nextAttemptAt` nel futuro, e con un orologio fermo resterebbe
      // in coda per sempre. Non è un dettaglio del test — è il backoff che
      // funziona, e senza questo avanzamento si starebbe verificando la
      // convergenza di un dispositivo che non riprova mai.
      a.clock.advance(const Duration(minutes: 5));
      b.clock.advance(const Duration(minutes: 5));
      await a.worker.drain();
      await b.worker.drain();
    }
  }

  Future<Order> orderOf(TestEnv env) async =>
      (await env.store.orderById(orderId))!;

  Future<void> close() async {
    await a.dispose();
    await b.dispose();
  }
}

void main() {
  group('Il criterio', () {
    test('due dispositivi, ordine invertito, stesso stato finale', () async {
      // Andata: prima aggiunge A, poi serve B.
      final Room forward = await Room.open();
      await forward.a.repository.addLines(
          orderId: forward.orderId, lines: <OrderLineDraft>[croissant]);
      await forward.a.worker.drain();
      await forward.b.repository
          .changeState(orderId: forward.orderId, state: OrderState.served);
      await forward.b.worker.drain();
      await forward.settle();

      // Ritorno: le stesse due modifiche, nell'ordine opposto.
      final Room reversed = await Room.open();
      await reversed.b.repository
          .changeState(orderId: reversed.orderId, state: OrderState.served);
      await reversed.b.worker.drain();
      await reversed.a.repository.addLines(
          orderId: reversed.orderId, lines: <OrderLineDraft>[croissant]);
      await reversed.a.worker.drain();
      await reversed.settle();

      // I due dispositivi della stessa sala sono d'accordo fra loro...
      expect(
        shared(await forward.orderOf(forward.a)),
        shared(await forward.orderOf(forward.b)),
        reason: 'i due tablet della prima sala non convergono',
      );
      expect(
        shared(await reversed.orderOf(reversed.a)),
        shared(await reversed.orderOf(reversed.b)),
        reason: 'i due tablet della seconda sala non convergono',
      );

      // ...e le due sale sono arrivate allo stesso posto, pur avendo visto le
      // stesse modifiche in ordine opposto.
      expect(
        shared(await forward.orderOf(forward.a)),
        shared(await reversed.orderOf(reversed.a)),
        reason: "l'ordine delle modifiche ha cambiato il risultato",
      );

      final Order finalOrder = await forward.orderOf(forward.a);
      expect(finalOrder.state, OrderState.served);
      expect(finalOrder.lines.length, 2, reason: 'nessuna riga si perde');
      expect(finalOrder.totalCents, 240 + 150);

      await forward.close();
      await reversed.close();
    });

    test('tre modifiche, tutte e sei le sequenze, un solo risultato', () async {
      // La convergenza è una proprietà, non un caso fortunato: qui si prova su
      // ogni ordine possibile invece che su quello che è venuto in mente.
      final List<VisibleState> outcomes = <VisibleState>[];

      for (final List<int> sequence in <List<int>>[
        <int>[0, 1, 2],
        <int>[0, 2, 1],
        <int>[1, 0, 2],
        <int>[1, 2, 0],
        <int>[2, 0, 1],
        <int>[2, 1, 0],
      ]) {
        final Room room = await Room.open();

        for (final int move in sequence) {
          switch (move) {
            case 0:
              await room.a.repository.addLines(
                  orderId: room.orderId, lines: <OrderLineDraft>[croissant]);
              await room.a.worker.drain();
            case 1:
              await room.b.repository.addLines(
                  orderId: room.orderId, lines: <OrderLineDraft>[coffee]);
              await room.b.worker.drain();
            case 2:
              await room.b.repository
                  .changeState(orderId: room.orderId, state: OrderState.served);
              await room.b.worker.drain();
          }
        }
        await room.settle();

        expect(
          shared(await room.orderOf(room.a)),
          shared(await room.orderOf(room.b)),
          reason: 'sequenza $sequence: i due dispositivi non convergono',
        );
        outcomes.add(visible(await room.orderOf(room.a)));
        await room.close();
      }

      for (final VisibleState outcome in outcomes) {
        expect(outcome, outcomes.first,
            reason: 'sequenze diverse hanno prodotto tavoli diversi');
      }
      expect(outcomes.first.dishes.split(', '), hasLength(3));
    });
  });

  group('Il tempo logico', () {
    test('chi modifica dopo aver visto la modifica altrui la batte', () async {
      // La convergenza da sola non basta a dire che il sistema è corretto: due
      // dispositivi possono essere perfettamente d'accordo sulla risposta
      // sbagliata. Questa è la proprietà che tiene in piedi il `witness`.
      //
      // Il tablet A lavora molto e il suo contatore sale; B non ha ancora
      // fatto niente. Quando B vede il tavolo servito e decide di incassare,
      // la sua decisione è la più recente e deve vincere — anche se il suo
      // contatore, contato per conto proprio, sarebbe più basso di quello di A.
      final Room room = await Room.open();

      for (int i = 0; i < 4; i++) {
        await room.a.repository.addLines(
            orderId: room.orderId, lines: <OrderLineDraft>[croissant]);
      }
      await room.a.repository
          .changeState(orderId: room.orderId, state: OrderState.served);
      await room.a.worker.drain();

      await room.b.worker.drain(); // qui B prende atto del tempo di A
      await room.b.repository
          .changeState(orderId: room.orderId, state: OrderState.paid);
      await room.b.worker.drain();
      await room.settle();

      expect((await room.orderOf(room.b)).state, OrderState.paid);
      expect(
        (await room.orderOf(room.a)).state,
        OrderState.paid,
        reason: "l'ultima decisione presa è stata scartata: senza `witness` il "
            'contatore di B nasce più basso di quello di A e perde',
      );

      await room.close();
    });
  });

  group('Quando invece serve una persona', () {
    test('pagare mentre l altro aggiunge apre un conflitto su entrambi',
        () async {
      final Room room = await Room.open();

      // La cassa incassa senza sapere che in sala stanno ancora ordinando.
      await room.a.repository
          .changeState(orderId: room.orderId, state: OrderState.paid);
      await room.b.repository
          .addLines(orderId: room.orderId, lines: <OrderLineDraft>[croissant]);

      await room.a.worker.drain();
      await room.b.worker.drain();
      await room.a.worker.drain();

      final List<OrderConflict> onA = await room.a.store.openConflicts();
      final List<OrderConflict> onB = await room.b.store.openConflicts();

      expect(onA, hasLength(1),
          reason: 'la cassa deve sapere di quel cornetto');
      expect(onB, hasLength(1), reason: 'anche la sala deve saperlo');
      expect(onA.single.reason, contains('pagato'));
      expect(onA.single.reason, contains('1 articolo'));

      await room.close();
    });

    test('la decisione di uno chiude il conflitto anche sull altro', () async {
      final Room room = await Room.open();
      await room.a.repository
          .changeState(orderId: room.orderId, state: OrderState.paid);
      await room.b.repository
          .addLines(orderId: room.orderId, lines: <OrderLineDraft>[croissant]);
      await room.a.worker.drain();
      await room.b.worker.drain();
      await room.a.worker.drain();

      // In sala si decide: il tavolo si riapre, il cornetto va incassato.
      // `mine` è la versione di *questo* dispositivo, cioè quella della sala,
      // dove il tavolo è ancora aperto.
      final OrderConflict conflict =
          (await room.b.store.openConflicts()).single;
      await room.b.repository.resolveConflict(conflict.id, ConflictChoice.mine);
      await room.settle();

      expect(await room.b.store.openConflicts(), isEmpty);
      expect(await room.a.store.openConflicts(), isEmpty,
          reason: 'nessuno deve decidere due volte la stessa cosa');

      final Order onA = await room.orderOf(room.a);
      expect(shared(onA), shared(await room.orderOf(room.b)));
      expect(onA.state, OrderState.open);
      expect(onA.lines.length, 2,
          reason: 'il cornetto resta, comunque si scelga');

      await room.close();
    });

    test('tenere il pagamento non fa sparire le righe arrivate dopo', () async {
      // È la ragione per cui è sicuro chiedere: nessuna delle due risposte
      // cancella una comanda.
      final Room room = await Room.open();
      await room.a.repository
          .changeState(orderId: room.orderId, state: OrderState.paid);
      await room.b.repository
          .addLines(orderId: room.orderId, lines: <OrderLineDraft>[croissant]);
      await room.a.worker.drain();
      await room.b.worker.drain();
      await room.a.worker.drain();

      final OrderConflict conflict =
          (await room.a.store.openConflicts()).single;
      await room.a.repository.resolveConflict(conflict.id, ConflictChoice.mine);
      await room.settle();

      final Order onA = await room.orderOf(room.a);
      expect(onA.state, OrderState.paid);
      expect(onA.lines.length, 2);
      expect(shared(onA), shared(await room.orderOf(room.b)));

      await room.close();
    });
  });

  group('Offline', () {
    test('un dispositivo scollegato non blocca l altro, e rientra dopo',
        () async {
      final Room room = await Room.open();
      room.b.fake.online = false;

      await room.a.repository
          .addLines(orderId: room.orderId, lines: <OrderLineDraft>[croissant]);
      await room.a.worker.drain();
      await room.b.repository
          .changeState(orderId: room.orderId, state: OrderState.served);
      await room.b.worker.drain(); // non esce niente

      expect((await room.orderOf(room.b)).lines.length, 1,
          reason: 'offline non si vede il cornetto');

      room.b.fake.online = true;
      await room.settle();

      expect(
        shared(await room.orderOf(room.a)),
        shared(await room.orderOf(room.b)),
      );
      expect((await room.orderOf(room.b)).lines.length, 2);

      await room.close();
    });
  });
}
