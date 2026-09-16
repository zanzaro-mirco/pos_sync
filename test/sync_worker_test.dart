import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/core/product_metrics.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
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
      expect(env.fake.storedOrderIds, <String>{order.id});
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
      expect(env.fake.received.single.lines.single.productId, 'p-01');
      expect(env.fake.received.single.createdAtIso, isNotEmpty);
    });
  });

  group('rete assente', () {
    test('mantiene l ordine in coda e riprogramma il tentativo', () async {
      env.fake.online = false;
      final Order order = await createOrder();

      final SyncResult result = await env.worker.drain();

      expect(result.retried, 1);
      expect(result.sent, 0);
      expect((await env.store.pendingOutbox()).single.attempts, 1);
      expect((await env.store.orderById(order.id))!.status, SyncStatus.pending);
    });

    test('non riprova prima che il backoff sia trascorso', () async {
      env.fake.online = false;
      await createOrder();
      await env.worker.drain();

      final SyncResult immediately = await env.worker.drain();
      expect(immediately.skipped, 1);
      expect(immediately.retried, 0);
    });

    test('riprova quando il backoff è trascorso e va a buon fine', () async {
      env.fake.online = false;
      final Order order = await createOrder();
      await env.worker.drain();

      env.clock.advance(const Duration(minutes: 10));
      env.fake.online = true;

      expect((await env.worker.drain()).sent, 1);
      expect((await env.store.orderById(order.id))!.status, SyncStatus.synced);
    });

    test('dopo maxAttempts marca l ordine come fallito e lo registra',
        () async {
      env.fake.online = false;
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
      env.fake.loseResponse = true;
      final Order order = await createOrder();

      await env.worker.drain();
      env.clock.advance(const Duration(minutes: 10));
      env.fake.loseResponse = false;
      await env.worker.drain();

      expect(env.fake.receivedOrderIds.length, 2, reason: 'due invii');
      expect(env.fake.storedOrderIds.length, 1, reason: 'un solo ordine');
      expect(env.fake.duplicateCount, 1);
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

    expect(env.fake.receivedOrderIds.length, 1);
  });

  test(
      'un ordine creato durante un drenaggio parte in quel giro, non al prossimo',
      () async {
    // Prima della correzione la seconda chiamata tornava subito a mani vuote,
    // e l'ordine restava in coda finché qualcos'altro non faceva ripartire la
    // coda: un comando, un cambio di rete, o il lavoro di sistema dopo un quarto
    // d'ora. Con ogni probabilità è anche ciò che ha fatto fallire una volta in
    // pipeline il test di integrazione della cassa: il drenaggio dell'avvio
    // poteva essere ancora in corso quando il test creava l'ordine.
    final _GatedApi api = _GatedApi();
    final TestEnv gated = TestEnv(remoteApi: api);
    addTearDown(gated.dispose);

    final Order first =
        await gated.repository.createOrder(tableNumber: 1, lines: sampleLines);
    final Future<SyncResult> running = gated.worker.drain();
    await api.entered.future;

    final Order second =
        await gated.repository.createOrder(tableNumber: 2, lines: sampleLines);
    final Future<SyncResult> requested = gated.worker.drain();
    api.gate.complete();

    // Chi ha chiesto il drenaggio a metà giro aspetta anche il giro in più:
    // quando la sua chiamata torna, il suo ordine è già partito.
    await requested;
    expect(api.storedOrderIds, <String>{first.id, second.id});
    expect(await gated.store.pendingOutbox(), isEmpty);

    await running;
    expect(api.receivedOrderIds, hasLength(2), reason: 'nessun doppio invio');
  });

  group('metrica di prodotto', () {
    late RecordedMetrics metrics;
    late TestEnv measured;

    setUp(() {
      metrics = RecordedMetrics();
      measured = TestEnv(metrics: metrics);
    });
    tearDown(() => measured.dispose());

    test('conta gli invii riusciti, una volta per giro', () async {
      await measured.repository.createOrder(tableNumber: 1, lines: sampleLines);
      await measured.repository.createOrder(tableNumber: 2, lines: sampleLines);

      await measured.worker.drain();

      expect(metrics.synced, <int>[2]);
    });

    test('un giro senza invii non produce nessun evento', () async {
      // Un evento con zero dentro sporcherebbe la serie: una sera senza
      // ordini e una sera in cui la coda gira a vuoto ogni minuto
      // sembrerebbero la stessa cosa.
      await measured.worker.drain();

      expect(metrics.synced, isEmpty);
    });

    test('un invio fallito non conta', () async {
      measured.fake.online = false;
      await measured.repository.createOrder(tableNumber: 1, lines: sampleLines);

      await measured.worker.drain();

      expect(metrics.synced, isEmpty);
    });
  });
}

/// Un backend che trattiene il primo invio finché il test non lo lascia
/// andare: è il modo di avere un drenaggio sicuramente a metà.
class _GatedApi extends FakeRemoteApi {
  final Completer<void> entered = Completer<void>();
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> submitOrder(Order order) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return super.submitOrder(order);
  }
}

class RecordedMetrics implements ProductMetrics {
  final List<int> synced = <int>[];

  @override
  void ordersSynced(int count) => synced.add(count);
}
