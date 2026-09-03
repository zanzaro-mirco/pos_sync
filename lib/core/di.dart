import 'package:drift_flutter/drift_flutter.dart';
import 'package:get_it/get_it.dart';

import '../features/orders/data/local/app_database.dart';
import '../features/orders/data/local/drift_order_store.dart';
import '../features/orders/data/order_store.dart';
import '../features/orders/data/orders_repository_impl.dart';
import '../features/orders/data/remote_api.dart';
import '../features/orders/domain/orders_repository.dart';
import '../features/orders/sync/sync_worker.dart';
import 'clock.dart';
import 'id_generator.dart';
import 'logger.dart';

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

  sl.registerLazySingleton<Clock>(SystemClock.new);
  sl.registerLazySingleton<IdGenerator>(UuidGenerator.new);
  sl.registerLazySingleton<Logger>(SilentLogger.new);

  sl.registerLazySingleton<RemoteApi>(() => FakeRemoteApi(online: demoMode));

  sl.registerLazySingleton<OrdersRepository>(
    () => OrdersRepositoryImpl(
      orderStore: sl<OrderStore>(),
      outboxStore: sl<OutboxStore>(),
      transaction: sl<OrderOutboxTransaction>(),
      watcher: sl<OrdersWatcher>(),
      clock: sl<Clock>(),
      idGenerator: sl<IdGenerator>(),
    ),
  );

  sl.registerLazySingleton<SyncWorker>(
    () => SyncWorker(
      orderStore: sl<OrderStore>(),
      outboxStore: sl<OutboxStore>(),
      api: sl<RemoteApi>(),
      clock: sl<Clock>(),
      logger: sl<Logger>(),
    ),
  );
}
