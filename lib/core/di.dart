import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:get_it/get_it.dart';

import '../features/orders/data/connectivity_plus_monitor.dart';
import '../features/orders/data/local/app_database.dart';
import '../features/orders/data/local/drift_device_store.dart';
import '../features/orders/data/local/drift_order_store.dart';
import '../features/orders/data/order_store.dart';
import '../features/orders/data/orders_repository_impl.dart';
import '../features/orders/data/remote_api.dart';
import '../features/orders/data/second_device.dart';
import '../features/orders/domain/orders_repository.dart';
import '../features/orders/sync/auto_sync.dart';
import '../features/orders/sync/conflict_policy.dart';
import '../features/orders/sync/connectivity_monitor.dart';
import '../features/orders/sync/inbound_merger.dart';
import '../features/orders/sync/sync_worker.dart';
import 'background_sync.dart';
import 'clock.dart';
import 'id_generator.dart';
import 'logger.dart';
import 'logical_clock.dart';

final GetIt sl = GetIt.instance;

/// Registrazione delle dipendenze — composition root.
///
/// È l'unico punto dell'applicazione che conosce le classi concrete. La stessa
/// istanza di [DriftOrderStore] viene registrata sotto quattro contratti
/// diversi: chi la usa vede solo il pezzo che gli serve, ma il deposito resta
/// uno solo, che è ciò che rende possibile la scrittura atomica.
///
/// Il passaggio da memoria a SQLite è costato esattamente queste righe:
/// repository, worker e presentazione non sanno che è successo.
///
/// `driftDatabase` apre il file pigramente, alla prima interrogazione, quindi
/// questa funzione resta sincrona e `main()` non cambia.
void setUpDependencies({bool demoMode = true}) {
  sl.registerLazySingleton<AppDatabase>(
      () => AppDatabase(driftDatabase(name: 'pos_sync')));
  sl.registerLazySingleton<DriftOrderStore>(
      () => DriftOrderStore(sl<AppDatabase>()));
  sl.registerLazySingleton<OrderStore>(() => sl<DriftOrderStore>());
  sl.registerLazySingleton<OutboxStore>(() => sl<DriftOrderStore>());
  sl.registerLazySingleton<OrderOutboxTransaction>(() => sl<DriftOrderStore>());
  sl.registerLazySingleton<OrdersWatcher>(() => sl<DriftOrderStore>());
  sl.registerLazySingleton<ConflictStore>(() => sl<DriftOrderStore>());

  // L'identità del dispositivo e il suo contatore logico stanno nella stessa
  // base dati degli ordini che numerano: un contatore che vive altrove può
  // disallinearsi da ciò che ha numerato, e se torna indietro l'ordine totale
  // su cui si regge la convergenza smette di essere tale.
  sl.registerLazySingleton<LogicalClockStore>(() =>
      DriftDeviceStore(sl<AppDatabase>(), idGenerator: sl<IdGenerator>()));
  sl.registerLazySingleton<LogicalClock>(
      () => LamportClock(sl<LogicalClockStore>()));

  sl.registerLazySingleton<Clock>(SystemClock.new);
  sl.registerLazySingleton<IdGenerator>(UuidGenerator.new);
  sl.registerLazySingleton<Logger>(SilentLogger.new);

  // Registrato anche sotto il tipo concreto, come il deposito: in demo la
  // composition root ha bisogno di raggiungerne l'interruttore della rete.
  sl.registerLazySingleton<FakeRemoteApi>(
      () => FakeRemoteApi(online: demoMode));
  sl.registerLazySingleton<RemoteApi>(() => sl<FakeRemoteApi>());

  // Il secondo tablet esiste solo in demo, ed è l'unica dipendenza registrata
  // sotto condizione: senza di lui il rientro non trova mai niente — c'è un
  // dispositivo solo — e la parte più interessante del sistema resterebbe
  // visibile nei soli test. Chi la usa controlla se c'è, invece di darla per
  // scontata.
  if (demoMode) {
    sl.registerLazySingleton<SecondDevice>(
        () => SecondDevice(server: sl<FakeRemoteApi>().server));
  }

  sl.registerLazySingleton<ConnectivityMonitor>(ConnectivityPlusMonitor.new);

  sl.registerLazySingleton<OrdersRepository>(
    () => OrdersRepositoryImpl(
      orderStore: sl<OrderStore>(),
      outboxStore: sl<OutboxStore>(),
      transaction: sl<OrderOutboxTransaction>(),
      watcher: sl<OrdersWatcher>(),
      conflictStore: sl<ConflictStore>(),
      logicalClock: sl<LogicalClock>(),
      clock: sl<Clock>(),
      idGenerator: sl<IdGenerator>(),
    ),
  );

  // Il verso di rientro. Registrato a parte e passato al worker: tirare,
  // fondere e registrare i conflitti non sono compiti di chi orchestra la coda.
  sl.registerLazySingleton<InboundMerger>(
    () => InboundMerger(
      orderStore: sl<OrderStore>(),
      conflictStore: sl<ConflictStore>(),
      api: sl<RemoteApi>(),
      logicalClock: sl<LogicalClock>(),
      policy: const OrderConflictPolicy(),
      clock: sl<Clock>(),
      idGenerator: sl<IdGenerator>(),
      logger: sl<Logger>(),
    ),
  );

  sl.registerLazySingleton<SyncWorker>(
    () => SyncWorker(
      orderStore: sl<OrderStore>(),
      outboxStore: sl<OutboxStore>(),
      api: sl<RemoteApi>(),
      inbound: sl<InboundMerger>(),
      clock: sl<Clock>(),
      logger: sl<Logger>(),
    ),
  );

  sl.registerLazySingleton<AutoSync>(
    () => AutoSync(
      monitor: sl<ConnectivityMonitor>(),
      worker: sl<SyncWorker>(),
      logger: sl<Logger>(),
    ),
  );
}

/// Avvia gli ascolti che devono vivere quanto l'applicazione.
///
/// Separata da [setUpDependencies] di proposito: registrare non è avviare. Un
/// test che monta il grafo per ispezionarlo non deve ritrovarsi con una
/// sottoscrizione alla rete ancora viva alla fine.
void startBackgroundServices({bool demoMode = true}) {
  // In demo il backend simulato segue la rete vera del dispositivo. Senza
  // questo collegamento la modalità aereo non produrrebbe nessuna coda — il
  // finto server risponderebbe lo stesso — e la sincronizzazione automatica
  // resterebbe invisibile proprio nella prova che serve a dimostrarla.
  if (demoMode) {
    final FakeRemoteApi api = sl<FakeRemoteApi>();
    final ConnectivityMonitor monitor = sl<ConnectivityMonitor>();
    unawaited(monitor.isOnline().then((bool online) => api.online = online));
    monitor.onOnlineChanged.listen((bool online) => api.online = online);
  }

  sl<AutoSync>().start();

  // Non attesa di proposito: pianificare un lavoro di sistema passa dal canale
  // della piattaforma, e `main()` non deve restare fermo su una promessa che
  // riguarda il giorno dopo.
  unawaited(scheduleBackgroundDrain());
}
