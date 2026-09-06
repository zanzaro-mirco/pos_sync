/// Rimettere in coda gli ordini quando la cassa cambia.
///
/// Nasce da un errore nel piano di questa voce, che vale la pena tenere
/// scritto: ci avevo messo che dopo un'elezione «i dispositivi ripubblicano le
/// proprie versioni al giro successivo». È falso. La coda si svuota quando
/// l'invio riesce, quindi un ordine già consegnato alla vecchia cassa non
/// verrebbe mai rispedito, e il registro della nuova nascerebbe vuoto per
/// restarci — con tutti i tablet connessi e nessun errore da mostrare.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/core/id_generator.dart';
import 'package:pos_sync/features/orders/data/outbox_scheduler.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/sync/backoff.dart';
import 'package:pos_sync/features/orders/sync/order_republisher.dart';
import 'package:pos_sync/features/orders/sync/retry_policy.dart';
import 'package:pos_sync/features/orders/sync/sync_worker.dart';

import 'helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late OrderRepublisher republisher;

  setUp(() {
    env = TestEnv();
    republisher = OrderRepublisher(
      orders: env.store,
      outbox: env.store,
      transaction: env.store,
      scheduler: OutboxScheduler(
        idGenerator: SequentialIdGenerator(prefix: 'ri'),
        clock: env.clock,
      ),
      logger: env.logger,
    );
  });

  tearDown(() => env.dispose());

  test('un ordine già consegnato torna in coda', () async {
    // È il caso che conta: senza, resterebbe solo sul dispositivo che l'ha
    // creato, e la cassa nuova non saprebbe che esiste.
    await env.repository.createOrder(tableNumber: 7, lines: sampleLines);
    await env.worker.drain();
    expect(await env.store.pendingCount(), 0,
        reason: 'consegnato alla vecchia');

    expect(await republisher.republishAll(), 1);
    expect(await env.store.pendingCount(), 1);
  });

  test('chi è già in coda non viene raddoppiato', () async {
    // Non sarebbe un danno — il registro è idempotente sulla coppia (ordine,
    // dispositivo) — ma sarebbe lavoro doppio proprio mentre la rete è già in
    // difficoltà.
    await env.repository.createOrder(tableNumber: 7, lines: sampleLines);

    expect(await republisher.republishAll(), 0);
    expect(await env.store.pendingCount(), 1);
  });

  test('senza ordini non fa niente', () async {
    expect(await republisher.republishAll(), 0);
    expect(await env.store.pendingCount(), 0);
  });

  test('gli ordini riaccodati arrivano davvero alla cassa nuova', () async {
    // La prova che il meccanismo serve a qualcosa: un registro nuovo e vuoto,
    // come quello di un dispositivo appena promosso, torna a conoscere gli
    // ordini di prima. Qui gira il worker vero, non un suo sosia: se la coda
    // non contenesse davvero quegli ordini, non partirebbe niente.
    await env.repository.createOrder(tableNumber: 7, lines: sampleLines);
    await env.repository.createOrder(tableNumber: 9, lines: sampleLines);
    await env.worker.drain();

    final FakeServer newTill = FakeServer();
    final SyncWorker toNewTill = SyncWorker(
      orderStore: env.store,
      outboxStore: env.store,
      api: FakeRemoteApi(deviceId: env.deviceId, server: newTill),
      clock: env.clock,
      logger: env.logger,
      retryPolicy: BackoffRetryPolicy(backoff: Backoff(random: Random(1))),
    );

    await toNewTill.drain();
    expect(newTill.storedOrderIds, isEmpty,
        reason: 'la coda era vuota: senza riaccodare non parte niente');

    expect(await republisher.republishAll(), 2);
    await toNewTill.drain();

    expect(newTill.storedOrderIds, hasLength(2));
  });
}
