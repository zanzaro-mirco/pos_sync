/// Trovare la cassa senza digitarne l'indirizzo.
///
/// La scoperta vera è mDNS e passa dai canali di piattaforma: qui gira un
/// [FakeDiscovery], mentre il filo fra i due dispositivi resta HTTP vero su
/// una porta effimera. È la divisione che conta — ciò che si può sbagliare sta
/// nel coordinatore, non nelle venti righe che parlano con `nsd`.
///
/// Il caso su cui insistono più test è **la cassa che non si trova**. Prima
/// della scoperta automatica un follower senza indirizzo ripiegava sul backend
/// simulato: accettava gli ordini, li marcava come inviati e li depositava in
/// un registro che vive nel processo di quel tablet e che nessun altro leggerà
/// mai. Un modo silenzioso di perdere il servizio di una serata.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/order_registry.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';
import 'package:pos_sync/features/orders/lan/lan_coordinator.dart';
import 'package:pos_sync/features/orders/lan/order_server.dart';
import 'package:pos_sync/features/orders/lan/peer_discovery.dart';
import 'package:pos_sync/features/orders/lan/peer_settings.dart';

import 'helpers/fake_discovery.dart';

void main() {
  // `flutter_test` installa un HttpOverrides che risponde 400 a qualunque
  // richiesta HTTP senza toccare la rete. Qui il trasporto è la cosa in prova,
  // quindi va tolto — con il doppio in mezzo ogni traduzione degli errori
  // risulterebbe verificata e sarebbe falso.
  setUpAll(() => HttpOverrides.global = null);

  const String me = 'tablet-sala';

  Order order(String id, {String device = 'tablet-cassa'}) => Order(
        id: id,
        tableNumber: 7,
        createdAt: DateTime.utc(2026, 9, 6, 12),
        state: OrderState.open,
        stateRevision: Revision(counter: 1, deviceId: device),
        lines: <OrderLine>[
          OrderLine(
            id: '$id:0',
            productId: 'p-01',
            description: 'Caffè',
            quantity: 1,
            unitPriceCents: 120,
            addedAt: Revision(counter: 1, deviceId: device),
          ),
        ],
      );

  /// Una cassa accesa su una porta effimera, con dentro [orders].
  Future<OrderServer> tillWith(List<Order> orders) async {
    final OrderRegistry registry = FakeServer();
    for (final Order o in orders) {
      registry.store(o, 'tablet-cassa');
    }
    final OrderServer server =
        OrderServer(registry: registry, deviceId: 'tablet-cassa');
    await server.start(port: 0);
    return server;
  }

  late FakeServer registry;
  late FakeRemoteApi standalone;
  late InMemoryPeerSettings settings;
  late FakeDiscovery discovery;
  late LanCoordinator coordinator;

  setUp(() {
    registry = FakeServer();
    standalone = FakeRemoteApi(deviceId: me, server: FakeServer());
    settings = InMemoryPeerSettings();
    discovery = FakeDiscovery();
    coordinator = LanCoordinator(
      settings: settings,
      registry: registry,
      deviceId: () async => me,
      standalone: standalone,
      discovery: discovery,
    );
  });

  tearDown(() => coordinator.dispose());

  group('la cassa si annuncia', () {
    test('con la porta su cui ascolta davvero', () async {
      // Con `primaryPort: 0` il sistema ne assegna una libera: annunciare lo
      // zero manderebbe tutti i tablet a bussare a una porta che non esiste.
      await settings.save(
        const PeerSettings(role: PeerRole.primary, primaryPort: 0),
      );
      await coordinator.fetchOrders();

      expect(discovery.advertisedDevice, me);
      expect(discovery.advertisedPort, isNot(0));
      expect(discovery.advertisedPort, greaterThan(0));
    });

    test('un annuncio non riuscito non le impedisce di fare la cassa',
        () async {
      // Una rete che filtra il multicast non deve impedire alla cassa di
      // essere la cassa: chi conosce l'indirizzo la raggiunge lo stesso.
      discovery.failAdvertising = true;
      await settings.save(
        const PeerSettings(role: PeerRole.primary, primaryPort: 0),
      );

      await coordinator.fetchOrders();

      expect(coordinator.role, PeerRole.primary);
      expect(coordinator.localRegistry, same(registry));
    });

    test('smettere di essere la cassa ritira l\'annuncio', () async {
      // Un annuncio che sopravvive al ruolo manderebbe gli altri a bussare a
      // una porta che non ascolta più.
      await settings.save(
        const PeerSettings(role: PeerRole.primary, primaryPort: 0),
      );
      await coordinator.fetchOrders();
      expect(discovery.advertisedDevice, isNotNull);

      await settings.save(const PeerSettings());
      await coordinator.fetchOrders();

      expect(discovery.advertisedDevice, isNull);
    });
  });

  group('il tablet in sala cerca la cassa', () {
    test('senza indirizzo digitato la trova da sé', () async {
      final OrderServer till = await tillWith(<Order>[order('ord-1')]);
      addTearDown(till.stop);
      discovery.primary = PeerAddress(host: '127.0.0.1', port: till.port!);

      await settings.save(const PeerSettings(role: PeerRole.follower));
      final List<Order> seen = await coordinator.fetchOrders();

      expect(seen.map((Order o) => o.id), <String>['ord-1']);
      expect(discovery.lookups, 1);
    });

    test('un indirizzo digitato ha la precedenza su ciò che si trova in rete',
        () async {
      // Chi l'ha scritto lo ha fatto per una ragione — spesso perché il
      // multicast in quel locale non passa. Scavalcarlo con ciò che si trova
      // significherebbe ignorare l'unica configurazione che si può sempre far
      // funzionare.
      final OrderServer till = await tillWith(<Order>[order('ord-1')]);
      addTearDown(till.stop);
      discovery.primary =
          const PeerAddress(host: '203.0.113.9', port: 9); // mai raggiunta

      await settings.save(
        PeerSettings(
          role: PeerRole.follower,
          primaryHost: '127.0.0.1',
          primaryPort: till.port!,
        ),
      );
      final List<Order> seen = await coordinator.fetchOrders();

      expect(seen.map((Order o) => o.id), <String>['ord-1']);
      expect(discovery.lookups, 0, reason: 'non c\'era niente da cercare');
    });

    test('la cerca una volta sola finché risponde', () async {
      final OrderServer till = await tillWith(<Order>[order('ord-1')]);
      addTearDown(till.stop);
      discovery.primary = PeerAddress(host: '127.0.0.1', port: till.port!);

      await settings.save(const PeerSettings(role: PeerRole.follower));
      await coordinator.fetchOrders();
      await coordinator.fetchOrders();
      await coordinator.fetchOrders();

      expect(discovery.lookups, 1,
          reason: 'cercare a ogni giro terrebbe occupata la radio per niente');
    });
  });

  group('nessuna cassa in rete', () {
    setUp(() async {
      discovery.primary = null;
      await settings.save(const PeerSettings(role: PeerRole.follower));
    });

    test('gli ordini restano in coda invece di sparire', () async {
      // Recuperabile e non definitivo: il worker decide su questa distinzione,
      // e un errore definitivo farebbe uscire l'ordine dalla coda senza che sia
      // mai arrivato da nessuna parte.
      await expectLater(
        coordinator.submitOrder(order('ord-1', device: me)),
        throwsA(isA<TransientApiFailure>()),
      );
    });

    test('non si ripiega sul backend simulato', () async {
      // È il difetto che questa voce chiude: prima l\'ordine veniva accettato
      // e depositato in un registro che vive solo in questo processo.
      await expectLater(
        coordinator.submitOrder(order('ord-1', device: me)),
        throwsA(isA<ApiFailure>()),
      );

      expect(standalone.storedOrderIds, isEmpty);
      expect(registry.storedOrderIds, isEmpty);
    });

    test('al giro dopo torna a cercarla', () async {
      // Senza questo la ricerca fallita sarebbe definitiva, e accendere la
      // cassa dopo i tablet non basterebbe più.
      await expectLater(coordinator.fetchOrders(), throwsA(isA<ApiFailure>()));

      final OrderServer till = await tillWith(<Order>[order('ord-1')]);
      addTearDown(till.stop);
      discovery.primary = PeerAddress(host: '127.0.0.1', port: till.port!);

      expect((await coordinator.fetchOrders()).single.id, 'ord-1');
      expect(discovery.lookups, 2);
    });
  });

  group('la cassa cambia indirizzo', () {
    test('un indirizzo scoperto si dimentica quando smette di rispondere',
        () async {
      // Caso concreto: la cassa riavvia e il router le dà un indirizzo diverso.
      // Senza questo i tablet busserebbero al vecchio per sempre, e la scoperta
      // automatica funzionerebbe una volta sola.
      final OrderServer before = await tillWith(<Order>[order('prima')]);
      discovery.primary = PeerAddress(host: '127.0.0.1', port: before.port!);
      await settings.save(const PeerSettings(role: PeerRole.follower));

      expect((await coordinator.fetchOrders()).single.id, 'prima');
      await before.stop();

      await expectLater(
        coordinator.fetchOrders(),
        throwsA(isA<TransientApiFailure>()),
      );

      final OrderServer after = await tillWith(<Order>[order('dopo')]);
      addTearDown(after.stop);
      discovery.primary = PeerAddress(host: '127.0.0.1', port: after.port!);

      expect((await coordinator.fetchOrders()).single.id, 'dopo');
      expect(discovery.lookups, 2);
    });

    test('un indirizzo digitato non si dimentica', () async {
      // La cassa spenta per venti minuti non è una ragione per scavalcare chi
      // ha scritto quell\'indirizzo a mano.
      final OrderServer till = await tillWith(<Order>[order('ord-1')]);
      final int port = till.port!;
      await till.stop();

      await settings.save(
        PeerSettings(
          role: PeerRole.follower,
          primaryHost: '127.0.0.1',
          primaryPort: port,
        ),
      );

      await expectLater(
        coordinator.fetchOrders(),
        throwsA(isA<TransientApiFailure>()),
      );
      await expectLater(
        coordinator.fetchOrders(),
        throwsA(isA<TransientApiFailure>()),
      );

      expect(discovery.lookups, 0);
    });
  });
}
