import 'dart:math';

import 'package:pos_sync/core/clock.dart';
import 'package:pos_sync/core/id_generator.dart';
import 'package:pos_sync/core/logger.dart';
import 'package:pos_sync/core/logical_clock.dart';
import 'package:pos_sync/features/orders/data/in_memory_order_store.dart';
import 'package:pos_sync/features/orders/data/orders_repository_impl.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order_line_draft.dart';
import 'package:pos_sync/features/orders/sync/backoff.dart';
import 'package:pos_sync/features/orders/sync/inbound_merger.dart';
import 'package:pos_sync/features/orders/sync/retry_policy.dart';
import 'package:pos_sync/features/orders/sync/sync_worker.dart';

const List<OrderLineDraft> sampleLines = <OrderLineDraft>[
  OrderLineDraft(
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
/// identificativi, rete, politica di ritentativo, log e — da quando esistono i
/// conflitti — identità del dispositivo e contatore logico.
///
/// **Un'istanza è un dispositivo.** Due istanze che condividono lo stesso
/// [FakeServer] sono due tablet nello stesso locale, ed è così che si mette
/// alla prova la convergenza. Perché funzioni, ciascuna deve avere il proprio
/// [deviceId] e il proprio prefisso per gli identificativi: due dispositivi che
/// coniassero gli stessi id produrrebbero collisioni che nella realtà non
/// possono avvenire, e il test misurerebbe un problema inventato.
class TestEnv {
  TestEnv({
    DateTime? now,
    int maxAttempts = 3,
    FakeServer? server,
    this.deviceId = 'dispositivo-1',
    String idPrefix = 'id',
    bool withInbound = true,
  }) {
    clock = FakeClock(now ?? DateTime(2026, 7, 27, 12));
    store = InMemoryOrderStore();
    api = FakeRemoteApi(deviceId: deviceId, server: server);
    logger = InMemoryLogger();
    ids = SequentialIdGenerator(prefix: idPrefix);
    clockStore = InMemoryLogicalClockStore(deviceId: deviceId);
    logical = LamportClock(clockStore);

    repository = OrdersRepositoryImpl(
      orderStore: store,
      outboxStore: store,
      transaction: store,
      watcher: store,
      conflictStore: store,
      logicalClock: logical,
      clock: clock,
      idGenerator: ids,
    );

    merger = InboundMerger(
      orderStore: store,
      conflictStore: store,
      api: api,
      logicalClock: logical,
      clock: clock,
      idGenerator: ids,
      logger: logger,
    );

    worker = SyncWorker(
      orderStore: store,
      outboxStore: store,
      api: api,
      inbound: withInbound ? merger : null,
      clock: clock,
      logger: logger,
      retryPolicy: BackoffRetryPolicy(
        backoff: Backoff(maxAttempts: maxAttempts, random: Random(1)),
      ),
    );
  }

  final String deviceId;

  late final FakeClock clock;
  late final InMemoryOrderStore store;
  late final FakeRemoteApi api;
  late final InMemoryLogger logger;
  late final SequentialIdGenerator ids;
  late final InMemoryLogicalClockStore clockStore;
  late final LamportClock logical;
  late final OrdersRepositoryImpl repository;
  late final InboundMerger merger;
  late final SyncWorker worker;

  Future<void> dispose() => store.dispose();
}
