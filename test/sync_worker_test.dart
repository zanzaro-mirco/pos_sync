import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';
import 'package:pos_sync/features/orders/sync/sync_worker.dart';

import 'helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  Future<Order> createOrder() =>
      env.repository.createOrder(tableNumber: 1, lines: sampleLines);

  group('percorso felice', () {
    test('invia l ordine, lo marca sincronizzato e svuota la coda', () async {
      final Order order = await createOrder();

      final SyncResult result = await env.worker.drain();

      expect(result.sent, 1);
      expect(env.api.storedOrderIds, <String>{order.id});
      expect((await env.store.orderById(order.id))!.status, SyncStatus.synced);
      expect(await env.store.pendingOutbox(), isEmpty);
    });

    test('un secondo drenaggio non ha nulla da fare', () async {
      await createOrder();
      await env.worker.drain();
      expect((await env.worker.drain()).isIdle, isTrue);
    });

    test('il payload inviato è un DTO, non il modello di dominio', () async {
      await createOrder();
      await env.worker.drain();
      expect(env.api.received.single.lines.single.productId, 'p-01');
      expect(env.api.received.single.createdAtIso, isNotEmpty);
    });
  });

  group('rete assente', () {
    test('mantiene l ordine in coda e riprogramma il tentativo', () async {
      env.api.online = false;
      final Order order = await createOrder();

      final SyncResult result = await env.worker.drain();

      expect(result.retried, 1);
      expect(result.sent, 0);
      expect((await env.store.pendingOutbox()).single.attempts, 1);
      expect((await env.store.orderById(order.id))!.status, SyncStatus.pending);
    });

    test('non riprova prima che il backoff sia trascorso', () async {
      env.api.online = false;
      await createOrder();
      await env.worker.drain();

      final SyncResult immediately = await env.worker.drain();
      expect(immediately.skipped, 1);
      expect(immediately.retried, 0);
    });

    test('riprova quando il backoff è trascorso e va a buon fine', () async {
      env.api.online = false;
      final Order order = await createOrder();
      await env.worker.drain();

      env.clock.advance(const Duration(minutes: 10));
      env.api.online = true;

      expect((await env.worker.drain()).sent, 1);
      expect((await env.store.orderById(order.id))!.status, SyncStatus.synced);
    });

    test('dopo maxAttempts marca l ordine come fallito e lo registra',
        () async {
      env.api.online = false;
      final Order order = await createOrder();

      for (int i = 0; i < 5; i++) {
        await env.worker.drain();
        env.clock.advance(const Duration(minutes: 30));
      }

      expect((await env.store.orderById(order.id))!.status, SyncStatus.failed);
      expect(await env.store.pendingOutbox(), isEmpty);
      // Il logger iniettato permette di asserire su cosa è stato registrato,
      // invece di ispezionare la console.
      expect(env.logger.messages.any((String m) => m.contains('abbandonato')),
          isTrue);
    });
  });

  group('idempotenza', () {
    test('la risposta persa non genera un ordine duplicato', () async {
      // Il server registra l'ordine ma il client non riceve la conferma: è il
      // caso che rende necessario l'id generato dal client.
      env.api.loseResponse = true;
      final Order order = await createOrder();

      await env.worker.drain();
      env.clock.advance(const Duration(minutes: 10));
      env.api.loseResponse = false;
      await env.worker.drain();

      expect(env.api.receivedOrderIds.length, 2, reason: 'due invii');
      expect(env.api.storedOrderIds.length, 1, reason: 'un solo ordine');
      expect(env.api.duplicateCount, 1);
      expect((await env.store.orderById(order.id))!.status, SyncStatus.synced);
    });
  });

  group('errori definitivi', () {
    test('un errore permanente non viene ritentato', () async {
      final Order order = await createOrder();
      // Simula un payload rifiutato svuotando le righe dell'ordine salvato.
      await env.store.updateOrder(order.copyWith(lines: const <OrderLine>[]));

      final SyncResult result = await env.worker.drain();

      expect(result.failed, 1);
      expect(await env.store.pendingOutbox(), isEmpty);
      expect((await env.store.orderById(order.id))!.status, SyncStatus.failed);
    });

    test('rimuove le voci di coda orfane', () async {
      final Order order = await createOrder();
      await env.store.deleteOrder(order.id);

      expect((await env.worker.drain()).isIdle, isTrue);
      expect(await env.store.pendingOutbox(), isEmpty);
    });
  });

  test('due drenaggi concorrenti non inviano due volte', () async {
    await createOrder();

    await Future.wait<SyncResult>(<Future<SyncResult>>[
      env.worker.drain(),
      env.worker.drain(),
    ]);

    expect(env.api.receivedOrderIds.length, 1);
  });
}
