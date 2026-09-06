import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/local/app_database.dart';
import 'package:pos_sync/features/orders/data/local/drift_order_store.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/orders_snapshot.dart';
import 'package:pos_sync/features/orders/domain/outbox_entry.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';

import 'store_contract.dart';

/// Base dati che fa fallire la scrittura delle righe.
///
/// Serve a provare il rollback: la testata dell'ordine viene inserita prima
/// delle righe, quindi se la transazione non annullasse tutto resterebbe un
/// ordine senza righe e senza voce in coda — cioè esattamente lo stato
/// incoerente che `OutboxEntry` dichiara impossibile.
class _FailingDatabase extends AppDatabase {
  _FailingDatabase(super.executor);

  @override
  Future<void> batch(FutureOr<void> Function(Batch batch) runInBatch) =>
      Future<void>.error(StateError('scrittura interrotta'));
}

void main() {
  // Alcuni test aprono un secondo `AppDatabase` — sullo stesso file ma dopo
  // aver chiuso il primo, oppure su un esecutore diverso. Drift non può
  // distinguere questi casi da due istanze concorrenti sullo stesso file, che
  // sarebbero un errore vero, e avverte comunque. Qui l'avviso è un falso
  // positivo e coprirebbe l'output della suite.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  // --- la stessa suite dell'implementazione in memoria ---

  runOrderStoreContract('DriftOrderStore', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    final DriftOrderStore store = DriftOrderStore(db);
    return StoreHarness(
      orders: store,
      outbox: store,
      transaction: store,
      watcher: store,
      close: db.close,
    );
  });

  // --- quello che solo un deposito vero può dimostrare ---

  group('DriftOrderStore, oltre il contratto', () {
    late AppDatabase db;
    late DriftOrderStore store;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftOrderStore(db);
    });
    tearDown(() => db.close());

    test('i vincoli di integrità sono davvero accesi', () async {
      // SQLite li disattiva per connessione: se `beforeOpen` non facesse il
      // suo lavoro, questa riga orfana entrerebbe senza protestare e la
      // cascata su `deleteOrder` sarebbe decorativa.
      await expectLater(
        db.into(db.orderLines).insert(const OrderLineRow(
              orderId: 'ordine-che-non-esiste',
              position: 0,
              lineId: 'r-01',
              addedAtCounter: 0,
              addedAtDevice: '',
              productId: 'p-01',
              description: 'Caffè',
              quantity: 1,
              unitPriceCents: 120,
            )),
        throwsA(isA<Exception>()),
      );
    });

    test('deleteOrder porta via le righe per cascata', () async {
      await store.saveOrderWithOutbox(
        order(id: 'o-1', created: t0, lines: threeLines),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );
      expect((await db.select(db.orderLines).get()).length, 3);

      await store.deleteOrder('o-1');

      expect(await db.select(db.orderLines).get(), isEmpty);
    });

    test('una scrittura fallita non lascia l ordine a metà', () async {
      final AppDatabase broken = _FailingDatabase(NativeDatabase.memory());
      addTearDown(broken.close);
      final DriftOrderStore fragile = DriftOrderStore(broken);

      await expectLater(
        fragile.saveOrderWithOutbox(
          order(id: 'o-1', created: t0),
          entry(id: 'q-1', orderId: 'o-1', created: t0),
        ),
        throwsA(isA<StateError>()),
      );

      // La testata era già stata inserita quando la scrittura è fallita: se
      // fosse ancora qui, la transazione non esisterebbe.
      expect(await broken.select(broken.orders).get(), isEmpty);
      expect(await broken.select(broken.outbox).get(), isEmpty);
    });

    test('una transazione produce una sola emissione, non una per tabella',
        () async {
      final List<OrdersSnapshot> seen = <OrdersSnapshot>[];
      final StreamSubscription<OrdersSnapshot> sub =
          store.watch().listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.length, 1);

      // Tre scritture — ordine, righe, coda — dentro una transazione.
      await store.saveOrderWithOutbox(
        order(id: 'o-1', created: t0, lines: threeLines),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );
      await pumpEventQueue();

      expect(seen.length, 2, reason: 'una fotografia in più, non tre');
    });

    test('i dati sopravvivono alla chiusura e alla riapertura', () async {
      // Il criterio della roadmap, nella sua forma più diretta. In memoria
      // questo test non si può nemmeno scrivere.
      final Directory directory =
          Directory.systemTemp.createTempSync('pos_sync_persistenza');
      final File file = File('${directory.path}/pos_sync.db');

      final AppDatabase before = AppDatabase(NativeDatabase(file));
      await DriftOrderStore(before).saveOrderWithOutbox(
        order(
          id: 'o-1',
          created: t0,
          table: 12,
          lines: threeLines,
          status: SyncStatus.pending,
        ),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );
      await before.close();

      expect(file.existsSync(), isTrue, reason: 'il file deve esistere');

      final AppDatabase after = AppDatabase(NativeDatabase(file));
      // Su Windows un file aperto non si cancella: prima si chiude, poi si
      // toglie la cartella.
      addTearDown(() async {
        await after.close();
        directory.deleteSync(recursive: true);
      });
      final DriftOrderStore reopened = DriftOrderStore(after);

      final Order found = (await reopened.allOrders()).single;
      expect(found.id, 'o-1');
      expect(found.tableNumber, 12);
      expect(found.createdAt, t0);
      expect(found.lines, threeLines);
      expect(found.status, SyncStatus.pending);
      expect((await reopened.pendingOutbox()).single.id, 'q-1');
    });

    test('uno stato sconosciuto degrada a pending', () async {
      // Simula un file scritto da una versione futura dell'app.
      await db.into(db.orders).insert(OrderRow(
            id: 'o-1',
            tableNumber: 1,
            createdAt: t0.microsecondsSinceEpoch,
            state: OrderState.open.name,
            stateRevisionCounter: 0,
            stateRevisionDevice: '',
            status: 'stato-inventato',
          ));

      expect((await store.allOrders()).single.status, SyncStatus.pending);
    });

    test('un ordine senza righe si legge senza esplodere', () async {
      // Il repository non lo permette, ma il deposito non deve dipendere da
      // quella difesa: un file può sempre arrivare da fuori.
      await db.into(db.orders).insert(OrderRow(
            id: 'o-1',
            tableNumber: 1,
            createdAt: t0.microsecondsSinceEpoch,
            status: SyncStatus.pending.name,
            state: OrderState.open.name,
            stateRevisionCounter: 0,
            stateRevisionDevice: '',
          ));

      final Order loaded = (await store.allOrders()).single;
      expect(loaded.lines, isEmpty);
      expect(loaded.totalCents, 0);
    });

    test('le righe di ordini diversi non si mescolano', () async {
      await store.saveOrderWithOutbox(
        order(id: 'o-1', created: t0, lines: threeLines),
        entry(id: 'q-1', orderId: 'o-1', created: t0),
      );
      await store.saveOrderWithOutbox(
        order(
          id: 'o-2',
          created: t0.add(const Duration(minutes: 1)),
          lines: oneLine,
        ),
        entry(
          id: 'q-2',
          orderId: 'o-2',
          created: t0.add(const Duration(minutes: 1)),
        ),
      );

      final List<Order> orders = await store.allOrders();
      expect(orders.first.id, 'o-2');
      expect(orders.first.lines, oneLine);
      expect(orders.last.lines, threeLines);
    });

    test('la coda conserva i tentativi di una voce riprovata', () async {
      final OutboxEntry e = entry(id: 'q-1', orderId: 'o-1', created: t0);
      await store.saveOrderWithOutbox(order(id: 'o-1', created: t0), e);

      OutboxEntry current = e;
      for (int i = 1; i <= 3; i++) {
        current = current.withFailure(
          nextAttemptAt: t0.add(Duration(seconds: i * 2)),
          error: 'tentativo $i',
        );
        await store.updateOutboxEntry(current);
      }

      final OutboxEntry reread = (await store.pendingOutbox()).single;
      expect(reread.attempts, 3);
      expect(reread.lastError, 'tentativo 3');
      expect(await store.pendingCount(), 1);
    });
  });
}
