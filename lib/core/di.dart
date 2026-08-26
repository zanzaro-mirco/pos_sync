import 'package:get_it/get_it.dart';

import '../features/orders/data/in_memory_order_store.dart';
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
/// È l'unico punto dell'applicazione che conosce le classi concrete. Nota che
/// la stessa istanza di [InMemoryOrderStore] viene registrata sotto tre
/// contratti diversi: chi la usa vede solo il pezzo che gli serve, ma lo stato
/// resta condiviso. Passare a SQLite significa cambiare queste tre righe.
void setUpDependencies({bool demoMode = true}) {
  sl.registerLazySingleton<InMemoryOrderStore>(InMemoryOrderStore.new);
  sl.registerLazySingleton<OrderStore>(() => sl<InMemoryOrderStore>());
  sl.registerLazySingleton<OutboxStore>(() => sl<InMemoryOrderStore>());
  sl.registerLazySingleton<OrderOutboxTransaction>(
      () => sl<InMemoryOrderStore>());
  sl.registerLazySingleton<OrdersWatcher>(() => sl<InMemoryOrderStore>());

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
