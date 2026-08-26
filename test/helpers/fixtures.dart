import 'dart:math';

import 'package:pos_sync/core/clock.dart';
import 'package:pos_sync/core/id_generator.dart';
import 'package:pos_sync/core/logger.dart';
import 'package:pos_sync/features/orders/data/in_memory_order_store.dart';
import 'package:pos_sync/features/orders/data/orders_repository_impl.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/sync/backoff.dart';
import 'package:pos_sync/features/orders/sync/retry_policy.dart';
import 'package:pos_sync/features/orders/sync/sync_worker.dart';

const List<OrderLine> sampleLines = <OrderLine>[
  OrderLine(
    productId: 'p-01',
    description: 'Caffè',
    quantity: 2,
    unitPriceCents: 120,
  ),
];

/// Ambiente di test completo, cablato con doppi deterministici.
///
/// Raccoglierlo qui evita di ripetere il montaggio in ogni file e rende
/// evidente quali dipendenze sono state rese sostituibili: tempo,
/// identificativi, rete, politica di ritentativo e log.
class TestEnv {
  TestEnv({DateTime? now, int maxAttempts = 3}) {
    clock = FakeClock(now ?? DateTime(2026, 7, 27, 12));
    store = InMemoryOrderStore();
    api = FakeRemoteApi();
    logger = InMemoryLogger();
    ids = SequentialIdGenerator();
    repository = OrdersRepositoryImpl(
      orderStore: store,
      outboxStore: store,
      transaction: store,
      watcher: store,
      clock: clock,
      idGenerator: ids,
    );
    worker = SyncWorker(
      orderStore: store,
      outboxStore: store,
      api: api,
      clock: clock,
      logger: logger,
      retryPolicy: BackoffRetryPolicy(
        backoff: Backoff(maxAttempts: maxAttempts, random: Random(1)),
      ),
    );
  }

  late final FakeClock clock;
  late final InMemoryOrderStore store;
  late final FakeRemoteApi api;
  late final InMemoryLogger logger;
  late final SequentialIdGenerator ids;
  late final OrdersRepositoryImpl repository;
  late final SyncWorker worker;

  Future<void> dispose() => store.dispose();
}
