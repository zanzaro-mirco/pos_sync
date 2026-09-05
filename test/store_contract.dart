/// Suite di contratto dei quattro depositi.
///
/// È scritta una volta e girata su ogni implementazione. Serve a una cosa
/// precisa: le quattro interfacce di `order_store.dart` promettono un
/// comportamento, non solo delle firme — l'ordinamento degli ordini, l'ordine
/// delle righe dentro un ordine, il fatto che `updateOrder` sostituisca le
/// righe invece di aggiungerle, il fatto che `watch()` emetta una fotografia
/// coerente. Niente di tutto questo è verificabile guardando i tipi.
///
/// Un test che gira su una sola implementazione verifica *quella*. Lo stesso
/// test su due verifica il **contratto**, ed è la ragione per cui sostituire
/// il deposito non ha richiesto modifiche a chi lo usa.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/order_store.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_line_draft.dart';
import 'package:pos_sync/features/orders/domain/orders_snapshot.dart';
import 'package:pos_sync/features/orders/domain/outbox_entry.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';

/// I quattro contratti sono deliberatamente separati, quindi non esiste un
/// tipo che li riunisca: Dart non considera una classe assegnabile a
/// un'interfaccia solo perché ne ha i membri. Questo involucro fa da ponte, e
/// per giunta espone lo store esattamente come lo riceve il repository — un
/// riferimento per contratto, non un oggetto onnisciente.
class StoreHarness {
  StoreHarness({
    required this.orders,
    required this.outbox,
    required this.transaction,
    required this.watcher,
    required this.close,
  });

  final OrderStore orders;
  final OutboxStore outbox;
  final OrderOutboxTransaction transaction;
  final OrdersWatcher watcher;
  final Future<void> Function() close;
}

typedef ApriStore = Future<StoreHarness> Function();

const List<OrderLine> unaRiga = <OrderLine>[
  OrderLine(
    id: 'r-01',
    productId: 'p-01',
    description: 'Caffè',
    quantity: 2,
    unitPriceCents: 120,
  ),
];

const List<OrderLine> treRighe = <OrderLine>[
  OrderLine(
    id: 'r-01',
    productId: 'p-01',
    description: 'Antipasto',
    quantity: 1,
    unitPriceCents: 800,
  ),
  OrderLine(
    id: 'r-02',
    productId: 'p-02',
    description: 'Primo',
    quantity: 2,
    unitPriceCents: 1200,
  ),
  OrderLine(
    id: 'r-03',
    productId: 'p-03',
    description: 'Dolce',
    quantity: 1,
    unitPriceCents: 500,
  ),
];

/// Le stesse righe, come le passa chi usa il repository.
///
/// Il deposito riceve `OrderLine` già timbrate; il repository riceve bozze e
/// le timbra lui. Due costanti e non una conversione, perché sono due punti di
/// vista diversi sullo stesso dato e mescolarli nasconde chi assegna gli id.
const List<OrderLineDraft> unaRigaBozza = <OrderLineDraft>[
  OrderLineDraft(
    productId: 'p-01',
    description: 'Caffè',
    quantity: 2,
    unitPriceCents: 120,
  ),
];

const List<OrderLineDraft> treRigheBozza = <OrderLineDraft>[
  OrderLineDraft(
    productId: 'p-01',
    description: 'Antipasto',
    quantity: 1,
    unitPriceCents: 800,
  ),
  OrderLineDraft(
    productId: 'p-02',
    description: 'Primo',
    quantity: 2,
    unitPriceCents: 1200,
  ),
  OrderLineDraft(
    productId: 'p-03',
    description: 'Dolce',
    quantity: 1,
    unitPriceCents: 500,
  ),
];

Order ordine({
  required String id,
  required DateTime creato,
  int tavolo = 1,
  List<OrderLine> righe = unaRiga,
  SyncStatus stato = SyncStatus.pending,
}) =>
    Order(
      id: id,
      tableNumber: tavolo,
      lines: righe,
      createdAt: creato,
      status: stato,
    );

OutboxEntry voce({
  required String id,
  required String ordineId,
  required DateTime creato,
}) =>
    OutboxEntry(id: id, orderId: ordineId, createdAt: creato);

/// Il momento fisso da cui contano tutti i test: nessuna dipendenza
/// dall'orologio della macchina.
final DateTime t0 = DateTime(2026, 7, 27, 12);

void runOrderStoreContract(String nome, ApriStore apri) {
  group(nome, () {
    late StoreHarness h;

    setUp(() async {
      h = await apri();
    });
    tearDown(() => h.close());

    // --- lettura di uno store vuoto ---

    test('uno store nuovo non ha ordini ne voci in coda', () async {
      expect(await h.orders.allOrders(), isEmpty);
      expect(await h.outbox.pendingOutbox(), isEmpty);
      expect(await h.outbox.pendingCount(), 0);
      expect(await h.orders.orderById('inesistente'), isNull);
    });

    test('la lista degli ordini non è modificabile da fuori', () async {
      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: t0),
        voce(id: 'q-1', ordineId: 'o-1', creato: t0),
      );
      final List<Order> lista = await h.orders.allOrders();
      expect(
        () => lista.add(ordine(id: 'o-2', creato: t0)),
        throwsUnsupportedError,
      );
    });

    // --- scrittura atomica ---

    test('salva ordine e voce di coda nella stessa operazione', () async {
      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: t0, tavolo: 7),
        voce(id: 'q-1', ordineId: 'o-1', creato: t0),
      );

      final Order salvato = (await h.orders.allOrders()).single;
      expect(salvato.id, 'o-1');
      expect(salvato.tableNumber, 7);
      expect(salvato.status, SyncStatus.pending);
      expect((await h.outbox.pendingOutbox()).single.orderId, 'o-1');
      expect(await h.outbox.pendingCount(), 1);
    });

    test('l istante di creazione sopravvive al giro completo', () async {
      // Un istante con i microsecondi diversi da zero: un deposito che salva
      // secondi o millisecondi qui perde informazione, e si vede.
      final DateTime preciso = DateTime(2026, 7, 27, 12, 34, 56, 789, 123);
      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: preciso),
        voce(id: 'q-1', ordineId: 'o-1', creato: preciso),
      );

      expect((await h.orders.allOrders()).single.createdAt, preciso);
      expect((await h.outbox.pendingOutbox()).single.createdAt, preciso);
    });

    // --- ordinamenti ---

    test('gli ordini escono dal più recente al più vecchio', () async {
      for (final int i in <int>[1, 2, 3]) {
        await h.transaction.saveOrderWithOutbox(
          ordine(id: 'o-$i', creato: t0.add(Duration(minutes: i))),
          voce(
              id: 'q-$i',
              ordineId: 'o-$i',
              creato: t0.add(Duration(minutes: i))),
        );
      }

      expect(
        (await h.orders.allOrders()).map((Order o) => o.id).toList(),
        <String>['o-3', 'o-2', 'o-1'],
      );
    });

    test('la coda esce dalla voce più vecchia alla più recente', () async {
      for (final int i in <int>[1, 2, 3]) {
        await h.transaction.saveOrderWithOutbox(
          ordine(id: 'o-$i', creato: t0.add(Duration(minutes: i))),
          voce(
              id: 'q-$i',
              ordineId: 'o-$i',
              creato: t0.add(Duration(minutes: i))),
        );
      }

      expect(
        (await h.outbox.pendingOutbox()).map((OutboxEntry e) => e.id).toList(),
        <String>['q-1', 'q-2', 'q-3'],
      );
    });

    test('le righe di un ordine mantengono la loro posizione', () async {
      // Le righe di una tabella SQL non hanno ordine: se il deposito non lo
      // registra, questa lista torna rimescolata.
      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: t0, righe: treRighe),
        voce(id: 'q-1', ordineId: 'o-1', creato: t0),
      );

      expect((await h.orders.allOrders()).single.lines, treRighe);
    });

    // --- lettura per identificativo ---

    test('orderById restituisce l ordine completo delle sue righe', () async {
      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: t0, righe: treRighe),
        voce(id: 'q-1', ordineId: 'o-1', creato: t0),
      );

      final Order? letto = await h.orders.orderById('o-1');
      expect(letto, isNotNull);
      expect(letto!.lines, treRighe);
      expect(letto.totalCents, 3700);
      expect(letto.itemCount, 4);
    });

    // --- aggiornamento ---

    test('updateOrder cambia lo stato di sincronizzazione', () async {
      final Order o = ordine(id: 'o-1', creato: t0);
      await h.transaction
          .saveOrderWithOutbox(o, voce(id: 'q-1', ordineId: 'o-1', creato: t0));

      await h.orders.updateOrder(o.copyWith(status: SyncStatus.synced));

      expect((await h.orders.orderById('o-1'))!.status, SyncStatus.synced);
      expect((await h.orders.allOrders()).length, 1, reason: 'non duplica');
    });

    test('updateOrder sostituisce le righe invece di aggiungerle', () async {
      final Order o = ordine(id: 'o-1', creato: t0, righe: treRighe);
      await h.transaction
          .saveOrderWithOutbox(o, voce(id: 'q-1', ordineId: 'o-1', creato: t0));

      await h.orders.updateOrder(o.copyWith(lines: unaRiga));

      expect((await h.orders.orderById('o-1'))!.lines, unaRiga);
    });

    test('updateOrder scrive anche un ordine mai visto prima', () async {
      // È il comportamento su cui conta il worker: aggiorna senza chiedersi
      // se la testata esista già.
      await h.orders.updateOrder(ordine(id: 'o-9', creato: t0));

      expect(await h.orders.orderById('o-9'), isNotNull);
    });

    // --- cancellazione ---

    test('deleteOrder rimuove l ordine e lascia la coda al suo posto',
        () async {
      // La voce di coda deve poter sopravvivere al suo ordine: il worker
      // gestisce esplicitamente quel caso, e se il deposito la cancellasse per
      // conto suo quel ramo diventerebbe codice morto.
      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: t0),
        voce(id: 'q-1', ordineId: 'o-1', creato: t0),
      );

      await h.orders.deleteOrder('o-1');

      expect(await h.orders.allOrders(), isEmpty);
      expect(await h.outbox.pendingCount(), 1);
    });

    // --- coda ---

    test('updateOutboxEntry conserva tentativi, scadenza ed errore', () async {
      final OutboxEntry e = voce(id: 'q-1', ordineId: 'o-1', creato: t0);
      await h.transaction.saveOrderWithOutbox(ordine(id: 'o-1', creato: t0), e);

      final DateTime prossimo = t0.add(const Duration(seconds: 4));
      await h.outbox.updateOutboxEntry(
        e.withFailure(nextAttemptAt: prossimo, error: 'timeout'),
      );

      final OutboxEntry riletta = (await h.outbox.pendingOutbox()).single;
      expect(riletta.attempts, 1);
      expect(riletta.nextAttemptAt, prossimo);
      expect(riletta.lastError, 'timeout');
      expect(riletta.isDueAt(prossimo), isTrue);
      expect(riletta.isDueAt(t0), isFalse);
      expect(await h.outbox.pendingCount(), 1, reason: 'aggiorna, non duplica');
    });

    test('una voce senza prossimo tentativo resta senza', () async {
      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: t0),
        voce(id: 'q-1', ordineId: 'o-1', creato: t0),
      );

      final OutboxEntry riletta = (await h.outbox.pendingOutbox()).single;
      expect(riletta.nextAttemptAt, isNull);
      expect(riletta.lastError, isNull);
      expect(riletta.attempts, 0);
    });

    test('removeOutboxEntry rimuove solo la voce indicata', () async {
      for (final int i in <int>[1, 2]) {
        await h.transaction.saveOrderWithOutbox(
          ordine(id: 'o-$i', creato: t0.add(Duration(minutes: i))),
          voce(
              id: 'q-$i',
              ordineId: 'o-$i',
              creato: t0.add(Duration(minutes: i))),
        );
      }

      await h.outbox.removeOutboxEntry('q-1');

      expect(
        (await h.outbox.pendingOutbox()).map((OutboxEntry e) => e.id).toList(),
        <String>['q-2'],
      );
      expect(await h.outbox.pendingCount(), 1);
      expect((await h.orders.allOrders()).length, 2,
          reason: 'gli ordini non c entrano');
    });

    // --- osservazione ---

    test('watch emette subito la fotografia corrente', () async {
      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: t0),
        voce(id: 'q-1', ordineId: 'o-1', creato: t0),
      );

      final OrdersSnapshot prima = await h.watcher.watch().first;

      expect(prima.orders.single.id, 'o-1');
      expect(prima.pending, 1);
    });

    test('watch riemette a ogni scrittura, e lista e contatore sono coerenti',
        () async {
      final List<OrdersSnapshot> visti = <OrdersSnapshot>[];
      final StreamSubscription<OrdersSnapshot> sub =
          h.watcher.watch().listen(visti.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(visti.length, 1);
      expect(visti.last.orders, isEmpty);
      expect(visti.last.pending, 0);

      await h.transaction.saveOrderWithOutbox(
        ordine(id: 'o-1', creato: t0),
        voce(id: 'q-1', ordineId: 'o-1', creato: t0),
      );
      await pumpEventQueue();

      // Lista e contatore arrivano insieme: non esiste un istante in cui si
      // vede l'ordine nuovo con il contatore vecchio.
      expect(visti.last.orders.single.id, 'o-1');
      expect(visti.last.pending, 1);

      await h.outbox.removeOutboxEntry('q-1');
      await pumpEventQueue();

      expect(visti.last.orders.single.id, 'o-1');
      expect(visti.last.pending, 0);
    });
  });
}
