/// **Il criterio della voce 2.5.**
///
/// «Due istanze dell'app sulla stessa rete che si vedono gli ordini a vicenda
/// con il cloud spento.»
///
/// Il cloud qui non è spento: **non esiste proprio**. In questo cablaggio non
/// compare nessun `FakeRemoteApi` — c'è un tablet che tiene il registro e lo
/// espone su HTTP, e un tablet che glielo chiede. È la differenza fra provare
/// che il codice funziona senza rete e provare che funziona *su un'altra*
/// rete.
///
/// L'altra metà del criterio la fa il dispositivo: telefono e PC sulla stessa
/// Wi-Fi. Questo file verifica ciò che si può verificare a ogni push, e
/// verifica anche la parte che a mano non si guarda mai — il primario che
/// sparisce a metà servizio.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/lan/http_remote_api.dart';
import 'package:pos_sync/features/orders/lan/local_registry_api.dart';
import 'package:pos_sync/features/orders/lan/order_server.dart';

import 'helpers/fixtures.dart';

/// Ciò che due dispositivi devono vedere uguale.
///
/// Le righe sono una stringa e non una lista per la stessa ragione della voce
/// sui conflitti: due record con dentro delle `List` si confrontano per
/// identità, e il test fallirebbe mostrando due valori identici.
typedef Shared = ({int table, OrderState state, String lines, int total});

void main() {
  // Come in `order_server_test.dart`: `flutter_test` risponde 400 a ogni
  // richiesta HTTP senza toccare la rete, e qui la rete è il soggetto.
  setUpAll(() => HttpOverrides.global = null);

  late FakeServer registry;
  late OrderServer server;
  late TestEnv till; // la cassa: tiene il registro
  late TestEnv floor; // la sala: glielo chiede via HTTP
  late HttpRemoteApi floorApi;

  /// La porta va tenuta da parte: `OrderServer.stop()` la dimentica, e il test
  /// dell'interruzione deve far ripartire la cassa **dove il client la cerca**.
  late int port;

  Shared shared(Order o) => (
        table: o.tableNumber,
        state: o.state,
        lines: (o.lines.map((OrderLine l) => '${l.id}x${l.quantity}').toList()
              ..sort())
            .join(','),
        total: o.totalCents,
      );

  /// Fa girare la sincronizzazione finché non cambia più niente.
  ///
  /// L'orologio avanza fra un giro e l'altro: una voce già fallita porta un
  /// `nextAttemptAt` nel futuro, e con un orologio fermo resterebbe in coda per
  /// sempre. È il backoff che funziona, non un artificio.
  Future<void> settle({int rounds = 3}) async {
    for (int i = 0; i < rounds; i++) {
      till.clock.advance(const Duration(minutes: 5));
      floor.clock.advance(const Duration(minutes: 5));
      await till.worker.drain();
      await floor.worker.drain();
    }
  }

  Future<Order> orderOn(TestEnv env, String id) async =>
      (await env.store.orderById(id))!;

  setUp(() async {
    registry = FakeServer();
    server = OrderServer(registry: registry, deviceId: 'cassa');
    await server.start(port: 0);

    port = server.port!;

    till = TestEnv(
      deviceId: 'cassa',
      idPrefix: 'c',
      remoteApi: LocalRegistryApi(registry: registry, deviceId: 'cassa'),
    );

    floorApi = HttpRemoteApi(host: '127.0.0.1', port: port, deviceId: 'sala');
    floor = TestEnv(deviceId: 'sala', idPrefix: 's', remoteApi: floorApi);
  });

  tearDown(() async {
    floorApi.close();
    await server.stop();
    await till.dispose();
    await floor.dispose();
  });

  test('un ordine aperto in cassa arriva in sala', () async {
    final Order created =
        await till.repository.createOrder(tableNumber: 7, lines: sampleLines);
    await settle();

    expect(shared(await orderOn(floor, created.id)),
        shared(await orderOn(till, created.id)));
  });

  test('un ordine aperto in sala arriva in cassa', () async {
    final Order created =
        await floor.repository.createOrder(tableNumber: 12, lines: sampleLines);
    await settle();

    expect(shared(await orderOn(till, created.id)),
        shared(await orderOn(floor, created.id)));
  });

  test('si vedono a vicenda: è il criterio, in una riga', () async {
    final Order fromTill =
        await till.repository.createOrder(tableNumber: 7, lines: sampleLines);
    final Order fromFloor =
        await floor.repository.createOrder(tableNumber: 12, lines: sampleLines);
    await settle();

    expect((await till.store.allOrders()).map((Order o) => o.id).toSet(),
        <String>{fromTill.id, fromFloor.id});
    expect((await floor.store.allOrders()).map((Order o) => o.id).toSet(),
        <String>{fromTill.id, fromFloor.id});
  });

  test('la convergenza vale anche senza cloud in mezzo', () async {
    // Le stesse due modifiche, in ordine opposto sui due dispositivi: se
    // l'ordine di arrivo contasse ancora, qui si vedrebbe.
    final Order table =
        await till.repository.createOrder(tableNumber: 7, lines: sampleLines);
    await settle();

    await floor.repository.addLines(orderId: table.id, lines: sampleLines);
    await till.repository
        .changeState(orderId: table.id, state: OrderState.served);
    await settle();

    expect(shared(await orderOn(till, table.id)),
        shared(await orderOn(floor, table.id)));
    expect((await orderOn(floor, table.id)).lines, hasLength(2),
        reason: 'le righe si uniscono, non si sostituiscono');
  });

  test('la cassa che sparisce non fa perdere ordini', () async {
    // È il caso che a mano non si prova mai, ed è quello che distingue una
    // coda vera da una che butta via ciò che non riesce a mandare. Se la
    // traduzione degli errori marcasse la caduta come definitiva, l'ordine
    // uscirebbe dalla coda senza essere mai arrivato.
    await server.stop();

    final Order duringOutage =
        await floor.repository.createOrder(tableNumber: 21, lines: sampleLines);

    // Un tentativo solo, non `settle()`. Il budget di ritentativi è tre, e
    // consumarlo tutto con la cassa spenta marcherebbe l'ordine come fallito:
    // è la politica della voce 2.2 che fa il suo mestiere, ma questo test
    // misurerebbe quella invece della traduzione degli errori.
    await floor.worker.drain();

    expect(await floor.repository.pendingCount(), greaterThan(0),
        reason: 'con la cassa spenta l\'ordine deve restare in coda');
    expect(registry.allVersions(), isEmpty);

    // La cassa torna, sulla stessa porta: il client non sa nulla di questa
    // interruzione e continua a cercarla dov'era.
    server = OrderServer(registry: registry, deviceId: 'cassa');
    await server.start(port: port);
    await settle();

    expect(await till.store.orderById(duringOutage.id), isNotNull,
        reason: "l'ordine tenuto in coda arriva quando la cassa torna");
    expect(await floor.repository.pendingCount(), 0);
  });
}
