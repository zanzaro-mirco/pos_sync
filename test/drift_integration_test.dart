/// Repository e worker sopra la persistenza vera.
///
/// La suite di contratto verifica i metodi del deposito uno per uno; questo
/// file verifica il **cablaggio**: che `OrdersRepositoryImpl` e `SyncWorker` —
/// scritti mesi prima che SQLite esistesse in questo progetto e qui usati
/// senza modifiche — funzionino sopra `DriftOrderStore`.
///
/// Non passa da `TestEnv`: quell'ambiente monta l'implementazione in memoria e
/// serve ai test esistenti così com'è. Il montaggio qui è esplicito, ed è
/// anche la dimostrazione che le dipendenze da sostituire sono cinque righe.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/core/clock.dart';
import 'package:pos_sync/core/id_generator.dart';
import 'package:pos_sync/core/logger.dart';
import 'package:pos_sync/features/orders/data/local/app_database.dart';
import 'package:pos_sync/features/orders/data/local/drift_order_store.dart';
import 'package:pos_sync/features/orders/data/orders_repository_impl.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/orders_snapshot.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';
import 'package:pos_sync/features/orders/sync/sync_worker.dart';

import 'store_contract.dart';

void main() {
  late AppDatabase db;
  late DriftOrderStore store;
  late FakeClock clock;
  late FakeRemoteApi api;
  late OrdersRepositoryImpl repository;
  late SyncWorker worker;

  void monta(AppDatabase database) {
    db = database;
    store = DriftOrderStore(db);
    clock = FakeClock(t0);
    api = FakeRemoteApi();
    repository = OrdersRepositoryImpl(
      orderStore: store,
      outboxStore: store,
      transaction: store,
      watcher: store,
      clock: clock,
      idGenerator: SequentialIdGenerator(),
    );
    worker = SyncWorker(
      orderStore: store,
      outboxStore: store,
      api: api,
      clock: clock,
      logger: InMemoryLogger(),
    );
  }

  // Vedi la nota in `drift_order_store_test.dart`: l'ultimo test riapre di
  // proposito il file dopo averlo chiuso, e l'avviso di Drift qui non si
  // applica.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() => monta(AppDatabase(NativeDatabase.memory())));
  tearDown(() => db.close());

  test('un ordine creato dal repository finisce nel database', () async {
    final Order creato =
        await repository.createOrder(tableNumber: 4, lines: unaRiga);

    expect((await store.allOrders()).single.id, creato.id);
    expect((await store.pendingOutbox()).single.orderId, creato.id);
    expect(await repository.pendingCount(), 1);
  });

  test('il worker svuota la coda e segna l ordine come sincronizzato',
      () async {
    final Order creato =
        await repository.createOrder(tableNumber: 4, lines: unaRiga);

    final SyncResult esito = await worker.drain();

    expect(esito.sent, 1);
    expect(api.storedOrderIds, <String>{creato.id});
    expect((await store.orderById(creato.id))!.status, SyncStatus.synced);
    expect(await repository.pendingCount(), 0);
  });

  test('offline l ordine resta in coda, e il ritentativo non duplica',
      () async {
    api.online = false;
    final Order creato =
        await repository.createOrder(tableNumber: 4, lines: unaRiga);

    await worker.drain();
    expect((await store.pendingOutbox()).single.attempts, 1);
    expect((await store.orderById(creato.id))!.status, SyncStatus.pending);

    // Torna la rete, e il tempo supera il backoff.
    api.online = true;
    clock.advance(const Duration(minutes: 1));
    await worker.drain();

    expect(await store.pendingOutbox(), isEmpty);
    expect(api.duplicateCount, 0, reason: 'l id del client rende idempotente');
  });

  test('il flusso del repository segue le scritture del worker', () async {
    final List<OrdersSnapshot> visti = <OrdersSnapshot>[];
    final StreamSubscription<OrdersSnapshot> sub =
        repository.watch().listen(visti.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await repository.createOrder(tableNumber: 4, lines: unaRiga);
    await pumpEventQueue();
    expect(visti.last.orders.length, 1);
    expect(visti.last.pending, 1);

    await worker.drain();
    await pumpEventQueue();

    expect(visti.last.orders.single.status, SyncStatus.synced);
    expect(visti.last.pending, 0);
  });

  test('lo stato di sincronizzazione sopravvive alla riapertura', () async {
    // È la prova che chiude il cerchio: non solo i dati restano, ma restano
    // con il lavoro già fatto sopra di loro. Riaprendo, la coda è vuota e non
    // c'è niente da rimandare.
    final Directory cartella =
        Directory.systemTemp.createTempSync('pos_sync_integrazione');
    // Su Windows un file aperto non si cancella: prima si chiude la base dati,
    // poi si toglie la cartella.
    addTearDown(() async {
      await db.close();
      cartella.deleteSync(recursive: true);
    });
    final File file = File('${cartella.path}/pos_sync.db');

    monta(AppDatabase(NativeDatabase(file)));
    final Order creato =
        await repository.createOrder(tableNumber: 9, lines: treRighe);
    await worker.drain();
    await db.close();

    monta(AppDatabase(NativeDatabase(file)));
    final Order riletto = (await store.allOrders()).single;

    expect(riletto.id, creato.id);
    expect(riletto.status, SyncStatus.synced);
    expect(riletto.lines, treRighe);
    expect(await repository.pendingCount(), 0);
  });
}
