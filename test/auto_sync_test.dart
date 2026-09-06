import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/core/logger.dart';
import 'package:pos_sync/features/orders/data/order_store.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/outbox_entry.dart';
import 'package:pos_sync/features/orders/sync/auto_sync.dart';
import 'package:pos_sync/features/orders/sync/connectivity_monitor.dart';
import 'package:pos_sync/features/orders/sync/sync_worker.dart';

import 'helpers/fixtures.dart';

void main() {
  group('AutoSync', () {
    late TestEnv env;
    late FakeConnectivityMonitor monitor;
    late List<Duration> waits;

    setUp(() {
      env = TestEnv();
      monitor = FakeConnectivityMonitor();
      waits = <Duration>[];
    });

    tearDown(() async {
      await monitor.dispose();
      await env.dispose();
    });

    /// Costruisce l'AutoSync sotto test.
    ///
    /// L'attesa viene registrata invece che subita: è ciò che permette di
    /// asserire sul jitter senza che la suite duri secondi.
    AutoSync makeAutoSync({
      SyncWorker? worker,
      Duration maxDelay = const Duration(seconds: 5),
      Random? random,
      Logger? logger,
      Sleeper? sleeper,
    }) {
      final AutoSync auto = AutoSync(
        monitor: monitor,
        worker: worker ?? env.worker,
        maxDelay: maxDelay,
        random: random ?? Random(1),
        logger: logger ?? const SilentLogger(),
        sleeper: sleeper ??
            (Duration d) async {
              waits.add(d);
            },
      );
      addTearDown(auto.stop);
      return auto;
    }

    /// Lascia girare le microtask finché la condizione si avvera.
    ///
    /// Il drenaggio parte da un evento e nessuno restituisce un future da
    /// attendere: è esattamente il punto della funzionalità.
    Future<void> waitUntil(
      Future<bool> Function() condition,
      String description,
    ) async {
      for (int i = 0; i < 100; i++) {
        if (await condition()) return;
        await Future<void>.delayed(Duration.zero);
      }
      fail('Mai avvenuto: $description');
    }

    Future<void> pump() async {
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // -------------------------------------------------------------------
    // Il criterio di fatto della voce 2.2 della roadmap.
    // -------------------------------------------------------------------
    test('il monitor passa a online e la coda si svuota da sola', () async {
      env.api.online = false;
      makeAutoSync().start();

      await env.repository.createOrder(tableNumber: 7, lines: sampleLines);
      expect(await env.store.pendingCount(), 1,
          reason: 'creato offline, deve restare in coda');

      // La rete torna. Da qui in avanti nessuno chiama drain().
      env.api.online = true;
      monitor.emit(true);

      await waitUntil(
        () async => await env.store.pendingCount() == 0,
        'la coda non si è svuotata da sola',
      );
      expect(env.api.storedOrderIds, <String>{'id-1'});
      expect(waits, hasLength(1), reason: 'un solo drenaggio');
    });

    test('lo stato iniziale online conta come transizione', () async {
      env.api.online = false;
      await env.repository.createOrder(tableNumber: 1, lines: sampleLines);

      // Coda sopravvissuta alla sessione precedente, app riaperta sotto rete:
      // non arriva nessun cambiamento, quindi senza questo la coda resterebbe
      // ferma per sempre.
      env.api.online = true;
      monitor.emit(true);
      makeAutoSync().start();

      await waitUntil(
        () async => await env.store.pendingCount() == 0,
        'la coda non è stata drenata allo start',
      );
    });

    test('lo stato iniziale offline non drena', () async {
      makeAutoSync().start();
      await pump();
      expect(waits, isEmpty);
    });

    test('un secondo evento online non fa ripartire la coda', () async {
      makeAutoSync().start();
      monitor.emit(true);
      await pump();

      // Wi-Fi che diventa dati mobili: cambia la rete, non lo stato.
      monitor.emit(true);
      await pump();

      expect(waits, hasLength(1));
    });

    test('il passaggio a offline non drena', () async {
      makeAutoSync().start();
      monitor
        ..emit(true)
        ..emit(false);
      await pump();
      expect(waits, hasLength(1), reason: 'solo quello di andata');
    });

    test('dopo stop() le transizioni vengono ignorate', () async {
      final AutoSync auto = makeAutoSync();
      auto.start();
      await auto.stop();

      monitor.emit(true);
      await pump();
      expect(waits, isEmpty);
    });

    test('start() è idempotente', () async {
      makeAutoSync()
        ..start()
        ..start();

      monitor.emit(true);
      await pump();
      expect(waits, hasLength(1), reason: 'una sola sottoscrizione');
    });

    test('il ritardo resta dentro il massimo e non è sempre lo stesso',
        () async {
      const Duration maximum = Duration(seconds: 4);
      makeAutoSync(maxDelay: maximum).start();

      for (int i = 0; i < 20; i++) {
        monitor
          ..emit(true)
          ..emit(false);
        await pump();
      }

      expect(waits, hasLength(20));
      expect(
        waits.every((Duration d) => d >= Duration.zero && d <= maximum),
        isTrue,
        reason: 'jitter fuori dai limiti: $waits',
      );
      expect(waits.toSet().length, greaterThan(1),
          reason: 'un ritardo costante non distribuirebbe niente');
    });

    test('se la rete ricade durante attesa il drenaggio non parte', () async {
      env.api.online = false;
      await env.repository.createOrder(tableNumber: 1, lines: sampleLines);

      makeAutoSync(
        sleeper: (Duration d) async {
          monitor.emit(false);
          await Future<void>.delayed(Duration.zero);
        },
      ).start();

      env.api.online = true;
      monitor.emit(true);
      await pump();

      expect(env.api.received, isEmpty);
      expect(await env.store.pendingCount(), 1);
    });

    test('un drenaggio che esplode viene registrato e non sfugge', () async {
      final InMemoryLogger logger = InMemoryLogger();
      makeAutoSync(
        worker: SyncWorker(
          orderStore: _BrokenStore(),
          outboxStore: _BrokenStore(),
          api: env.api,
        ),
        logger: logger,
      ).start();

      monitor.emit(true);
      await waitUntil(
        () async => logger.messages.isNotEmpty,
        'niente è finito nel log',
      );
      expect(logger.messages.single, contains('Drenaggio automatico fallito'));
    });
  });
}

/// Deposito che fallisce alla prima lettura della coda.
class _BrokenStore implements OrderStore, OutboxStore {
  @override
  Future<List<OutboxEntry>> pendingOutbox() =>
      Future<List<OutboxEntry>>.error(StateError('file illeggibile'));

  @override
  Future<List<Order>> allOrders() => throw UnimplementedError();

  @override
  Future<Order?> orderById(String id) => throw UnimplementedError();

  @override
  Future<void> updateOrder(Order order) => throw UnimplementedError();

  @override
  Future<void> deleteOrder(String id) => throw UnimplementedError();

  @override
  Future<void> updateOutboxEntry(OutboxEntry entry) =>
      throw UnimplementedError();

  @override
  Future<void> removeOutboxEntry(String id) => throw UnimplementedError();

  @override
  Future<int> pendingCount() => throw UnimplementedError();
}
