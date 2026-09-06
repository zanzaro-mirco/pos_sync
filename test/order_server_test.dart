/// Il filo fra due tablet, su HTTP vero.
///
/// Niente doppi: qui girano un `HttpServer` di `dart:io` su una porta effimera
/// e un `HttpClient` che ci parla davvero. Un test che simulasse il trasporto
/// verificherebbe la simulazione — e il trasporto è esattamente la parte nuova.
///
/// La metà che conta di più è la **traduzione degli errori**. Coda, backoff e
/// ritentativi esistono da tre voci fa e decidono sulla gerarchia sealed di
/// `ApiFailure`: se un primario spento risultasse un errore definitivo, gli
/// ordini uscirebbero dalla coda senza essere mai arrivati, in silenzio.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';
import 'package:pos_sync/features/orders/lan/http_remote_api.dart';
import 'package:pos_sync/features/orders/lan/order_server.dart';

void main() {
  const String primaryId = 'tablet-cassa';

  late FakeServer registry;
  late OrderServer server;

  Order order(
    String id, {
    int table = 7,
    OrderState state = OrderState.open,
    int counter = 1,
    String device = 'tablet-a',
  }) =>
      Order(
        id: id,
        tableNumber: table,
        createdAt: DateTime.utc(2026, 9, 6, 12),
        state: state,
        stateRevision: Revision(counter: counter, deviceId: device),
        lines: <OrderLine>[
          OrderLine(
            id: '$id:0',
            productId: 'p-01',
            description: 'Caffè',
            quantity: 2,
            unitPriceCents: 120,
            addedAt: Revision(counter: counter, deviceId: device),
          ),
        ],
      );

  /// Un client come lo userebbe il dispositivo [device].
  HttpRemoteApi clientFor(String device) {
    final HttpRemoteApi api = HttpRemoteApi(
      host: '127.0.0.1',
      port: server.port!,
      deviceId: device,
    );
    addTearDown(api.close);
    return api;
  }

  // Senza questa riga il file non verifica niente.
  //
  // `flutter_test` installa un `HttpOverrides` globale che intercetta ogni
  // `HttpClient` e risponde **400 senza toccare la rete**. È una protezione
  // sensata — impedisce a una suite di chiamare un servizio vero — ma qui la
  // rete è il soggetto: con l'intercettazione attiva, ogni richiesta
  // risulterebbe un errore definitivo, e i test sulla traduzione degli errori
  // passerebbero per il motivo sbagliato.
  //
  // Si disattiva solo per questa suite, e il traffico resta comunque su
  // 127.0.0.1: la protezione serve contro le chiamate all'esterno, che qui non
  // ci sono.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    registry = FakeServer();
    server = OrderServer(registry: registry, deviceId: primaryId);
    // Porta zero: il sistema ne assegna una libera, e due esecuzioni in
    // parallelo non si contendono la 53170.
    await server.start(port: 0);
  });

  tearDown(() => server.stop());

  test('una versione depositata torna agli altri, non a chi l\'ha mandata',
      () async {
    final HttpRemoteApi a = clientFor('tablet-a');
    final HttpRemoteApi b = clientFor('tablet-b');

    await a.submitOrder(order('o-1'));

    expect(await b.fetchOrders(), hasLength(1));
    expect(await a.fetchOrders(), isEmpty,
        reason: 'rimandare indietro la propria versione è lavoro sprecato');
  });

  test('il viaggio non perde niente: righe, stato e revisione', () async {
    // È la ragione per cui il formato sul filo è lo stesso `OrderDto` del
    // database: se la revisione si perdesse per strada, il last-write-wins
    // deciderebbe su un dato inventato e la convergenza sarebbe una finzione.
    final HttpRemoteApi a = clientFor('tablet-a');
    final Order sent = order('o-1', state: OrderState.paid, counter: 9);

    await a.submitOrder(sent);
    final Order received = (await clientFor('tablet-b').fetchOrders()).single;

    expect(received.id, sent.id);
    expect(received.tableNumber, sent.tableNumber);
    expect(received.createdAt, sent.createdAt);
    expect(received.state, OrderState.paid);
    expect(received.stateRevision, sent.stateRevision);
    expect(received.lines.single.id, sent.lines.single.id);
    expect(received.lines.single.addedAt, sent.lines.single.addedAt);
    expect(received.totalCents, sent.totalCents);
  });

  test('inviare due volte lo stesso ordine non lo duplica', () async {
    // L'idempotenza che il resto del sistema dà per scontata quando una
    // risposta si perde: il ritentativo deve sovrascrivere, non accumulare.
    final HttpRemoteApi a = clientFor('tablet-a');

    await a.submitOrder(order('o-1'));
    await a.submitOrder(order('o-1', state: OrderState.served, counter: 2));

    final List<Order> seen = await clientFor('tablet-b').fetchOrders();
    expect(seen, hasLength(1));
    expect(seen.single.state, OrderState.served,
        reason: 'vince l\'ultima versione di quel dispositivo');
  });

  test('due dispositivi restano due versioni distinte', () async {
    // È la proprietà su cui si regge il riconoscimento dei conflitti: il
    // registro non fonde, tiene separato chi credeva cosa.
    await clientFor('tablet-a').submitOrder(order('o-1'));
    await clientFor('tablet-b')
        .submitOrder(order('o-1', state: OrderState.paid, device: 'tablet-b'));

    expect(await clientFor('tablet-c').fetchOrders(), hasLength(2));
    expect(registry.allVersions(), hasLength(2));
  });

  test('il riconoscimento dice chi risponde, non solo che qualcuno risponde',
      () async {
    // Dopo un'elezione all'indirizzo noto può rispondere un dispositivo
    // diverso: una connessione riuscita da sola non lo direbbe.
    expect(await clientFor('tablet-a').primaryDeviceId(), primaryId);
  });

  group('la traduzione degli errori', () {
    test('un primario spento è recuperabile: la coda deve riprovare', () async {
      final HttpRemoteApi a = clientFor('tablet-a');
      await server.stop();

      await expectLater(
        a.submitOrder(order('o-1')),
        throwsA(isA<TransientApiFailure>()),
      );
    });

    test('un primario spento non risponde al riconoscimento', () async {
      final HttpRemoteApi a = clientFor('tablet-a');
      await server.stop();

      expect(await a.primaryDeviceId(), isNull);
    });

    test('una richiesta senza mittente è definitiva: riprovarla non aiuta',
        () async {
      // Il registro deve sapere da chi tenere distinta la versione. È un
      // errore del chiamante, e ritentarlo identico darebbe lo stesso esito.
      final HttpRemoteApi anonimo = clientFor('');

      await expectLater(
        anonimo.submitOrder(order('o-1')),
        throwsA(isA<PermanentApiFailure>()),
      );
    });

    test('un percorso sconosciuto è definitivo', () async {
      final HttpRemoteApi a = clientFor('tablet-a');
      await server.stop();
      server = OrderServer(registry: registry, deviceId: primaryId);
      await server.start(port: 0);

      // Il client di prima punta a una porta ora chiusa: recuperabile, non
      // definitivo. Serve a distinguere «non c'è nessuno» da «ha detto no».
      await expectLater(
        a.fetchOrders(),
        throwsA(isA<TransientApiFailure>()),
      );
    });
  });
}
