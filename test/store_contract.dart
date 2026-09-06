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

typedef OpenStore = Future<StoreHarness> Function();

const List<OrderLine> oneLine = <OrderLine>[
  OrderLine(
    id: 'r-01',
    productId: 'p-01',
    description: 'Caffè',
    quantity: 2,
    unitPriceCents: 120,
  ),
];

const List<OrderLine> threeLines = <OrderLine>[
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
const List<OrderLineDraft> oneLineDraft = <OrderLineDraft>[
  OrderLineDraft(
    productId: 'p-01',
    description: 'Caffè',
    quantity: 2,
    unitPriceCents: 120,
  ),
];

const List<OrderLineDraft> threeLineDrafts = <OrderLineDraft>[
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

Order order({
  required String id,
  required DateTime created,
  int table = 1,
  List<OrderLine> lines = oneLine,
  SyncStatus status = SyncStatus.pending,
}) =>
    Order(
      id: id,
      tableNumber: table,
      lines: lines,
      createdAt: created,
      status: status,
    );

OutboxEntry entry({
  required String id,
  required String orderId,
  required DateTime created,
}) =>
    OutboxEntry(id: id, orderId: orderId, createdAt: created);

/// Il momento fisso da cui contano tutti i test: nessuna dipendenza
/// dall'orologio della macchina.
final DateTime t0 = DateTime(2026, 7, 27, 12);

void runOrderStoreContract(String name, OpenStore open) {
  group(name, () {
    late StoreHarness h;

    setUp(() async {
      h = await open();
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
        order(id: 'o-1', created: t0),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );
      final List<Order> list = await h.orders.allOrders();
      expect(
        () => list.add(order(id: 'o-2', created: t0)),
        throwsUnsupportedError,
      );
    });

    // --- scrittura atomica ---

    test('salva ordine e voce di coda nella stessa operazione', () async {
      await h.transaction.saveOrderWithOutbox(
        order(id: 'o-1', created: t0, table: 7),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );

      final Order saved = (await h.orders.allOrders()).single;
      expect(saved.id, 'o-1');
      expect(saved.tableNumber, 7);
      expect(saved.status, SyncStatus.pending);
      expect((await h.outbox.pendingOutbox()).single.orderId, 'o-1');
      expect(await h.outbox.pendingCount(), 1);
    });

    test('l istante di creazione sopravvive al giro completo', () async {
      // Un istante con i microsecondi diversi da zero: un deposito che salva
      // secondi o millisecondi qui perde informazione, e si vede.
      final DateTime exact = DateTime(2026, 7, 27, 12, 34, 56, 789, 123);
      await h.transaction.saveOrderWithOutbox(
        order(id: 'o-1', created: exact),
        entry(id: 'q-1', orderId: 'o-1', created: exact),
      );

      expect((await h.orders.allOrders()).single.createdAt, exact);
      expect((await h.outbox.pendingOutbox()).single.createdAt, exact);
    });

    // --- ordinamenti ---

    test('gli ordini escono dal più recente al più vecchio', () async {
      for (final int i in <int>[1, 2, 3]) {
        await h.transaction.saveOrderWithOutbox(
          order(id: 'o-$i', created: t0.add(Duration(minutes: i))),
          entry(
              id: 'q-$i',
              orderId: 'o-$i',
              created: t0.add(Duration(minutes: i))),
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
          order(id: 'o-$i', created: t0.add(Duration(minutes: i))),
          entry(
              id: 'q-$i',
              orderId: 'o-$i',
              created: t0.add(Duration(minutes: i))),
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
        order(id: 'o-1', created: t0, lines: threeLines),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );

      expect((await h.orders.allOrders()).single.lines, threeLines);
    });

    // --- lettura per identificativo ---

    test('orderById restituisce l ordine completo delle sue righe', () async {
      await h.transaction.saveOrderWithOutbox(
        order(id: 'o-1', created: t0, lines: threeLines),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );

      final Order? loaded = await h.orders.orderById('o-1');
      expect(loaded, isNotNull);
      expect(loaded!.lines, threeLines);
      expect(loaded.totalCents, 3700);
      expect(loaded.itemCount, 4);
    });

    // --- aggiornamento ---

    test('updateOrder cambia lo stato di sincronizzazione', () async {
      final Order o = order(id: 'o-1', created: t0);
      await h.transaction.saveOrderWithOutbox(
          o, entry(id: 'q-1', orderId: 'o-1', created: t0));

      await h.orders.updateOrder(o.copyWith(status: SyncStatus.synced));

      expect((await h.orders.orderById('o-1'))!.status, SyncStatus.synced);
      expect((await h.orders.allOrders()).length, 1, reason: 'non duplica');
    });

    test('updateOrder sostituisce le righe invece di aggiungerle', () async {
      final Order o = order(id: 'o-1', created: t0, lines: threeLines);
      await h.transaction.saveOrderWithOutbox(
          o, entry(id: 'q-1', orderId: 'o-1', created: t0));

      await h.orders.updateOrder(o.copyWith(lines: oneLine));

      expect((await h.orders.orderById('o-1'))!.lines, oneLine);
    });

    test('updateOrder scrive anche un ordine mai visto prima', () async {
      // È il comportamento su cui conta il worker: aggiorna senza chiedersi
      // se la testata esista già.
      await h.orders.updateOrder(order(id: 'o-9', created: t0));

      expect(await h.orders.orderById('o-9'), isNotNull);
    });

    // --- cancellazione ---

    test('deleteOrder rimuove l ordine e lascia la coda al suo posto',
        () async {
      // La voce di coda deve poter sopravvivere al suo ordine: il worker
      // gestisce esplicitamente quel caso, e se il deposito la cancellasse per
      // conto suo quel ramo diventerebbe codice morto.
      await h.transaction.saveOrderWithOutbox(
        order(id: 'o-1', created: t0),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );

      await h.orders.deleteOrder('o-1');

      expect(await h.orders.allOrders(), isEmpty);
      expect(await h.outbox.pendingCount(), 1);
    });

    // --- coda ---

    test('updateOutboxEntry conserva tentativi, scadenza ed errore', () async {
      final OutboxEntry e = entry(id: 'q-1', orderId: 'o-1', created: t0);
      await h.transaction.saveOrderWithOutbox(order(id: 'o-1', created: t0), e);

      final DateTime next = t0.add(const Duration(seconds: 4));
      await h.outbox.updateOutboxEntry(
        e.withFailure(nextAttemptAt: next, error: 'timeout'),
      );

      final OutboxEntry reread = (await h.outbox.pendingOutbox()).single;
      expect(reread.attempts, 1);
      expect(reread.nextAttemptAt, next);
      expect(reread.lastError, 'timeout');
      expect(reread.isDueAt(next), isTrue);
      expect(reread.isDueAt(t0), isFalse);
      expect(await h.outbox.pendingCount(), 1, reason: 'aggiorna, non duplica');
    });

    test('una voce senza prossimo tentativo resta senza', () async {
      await h.transaction.saveOrderWithOutbox(
        order(id: 'o-1', created: t0),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );

      final OutboxEntry reread = (await h.outbox.pendingOutbox()).single;
      expect(reread.nextAttemptAt, isNull);
      expect(reread.lastError, isNull);
      expect(reread.attempts, 0);
    });

    test('removeOutboxEntry rimuove solo la voce indicata', () async {
      for (final int i in <int>[1, 2]) {
        await h.transaction.saveOrderWithOutbox(
          order(id: 'o-$i', created: t0.add(Duration(minutes: i))),
          entry(
              id: 'q-$i',
              orderId: 'o-$i',
              created: t0.add(Duration(minutes: i))),
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
        order(id: 'o-1', created: t0),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );

      final OrdersSnapshot before = await h.watcher.watch().first;

      expect(before.orders.single.id, 'o-1');
      expect(before.pending, 1);
    });

    test('watch riemette a ogni scrittura, e lista e contatore sono coerenti',
        () async {
      final List<OrdersSnapshot> seen = <OrdersSnapshot>[];
      final StreamSubscription<OrdersSnapshot> sub =
          h.watcher.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(seen.length, 1);
      expect(seen.last.orders, isEmpty);
      expect(seen.last.pending, 0);

      await h.transaction.saveOrderWithOutbox(
        order(id: 'o-1', created: t0),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );
      await pumpEventQueue();

      // Lista e contatore arrivano insieme: non esiste un istante in cui si
      // vede l'ordine nuovo con il contatore vecchio.
      expect(seen.last.orders.single.id, 'o-1');
      expect(seen.last.pending, 1);

      await h.outbox.removeOutboxEntry('q-1');
      await pumpEventQueue();

      expect(seen.last.orders.single.id, 'o-1');
      expect(seen.last.pending, 0);
    });
  });
}
