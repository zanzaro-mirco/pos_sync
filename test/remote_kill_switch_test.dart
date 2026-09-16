/// L'interruttore remoto della rete locale.
///
/// Il criterio della voce è «spegnere una funzionalità da remoto senza
/// pubblicare una nuova versione». Remote Config è la metà che non si prova
/// qui: consegna un booleano, e lo fa da sé. La metà che si prova è l'altra,
/// quella che può essere sbagliata: che il booleano, arrivato, **fermi davvero
/// la rete locale**, e che lo faccia subito.
///
/// Per questo niente doppi sul trasporto: la cassa apre una porta vera, e
/// «smette di rispondere» vuol dire che una connessione a quella porta viene
/// rifiutata.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/lan/lan_coordinator.dart';
import 'package:pos_sync/features/orders/lan/peer_settings.dart';
import 'package:pos_sync/features/orders/sync/drain_on_flag_change.dart';

import 'helpers/fixtures.dart';
import 'helpers/switchable_flags.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late SwitchableFlags flags;
  late FakeServer cloud;
  late InMemoryPeerSettings settings;
  late LanCoordinator coordinator;
  late int port;

  /// Una porta libera adesso. Il coordinatore non dice su quale porta ascolta,
  /// e non deve: la porta la sceglie la configurazione, quindi la sceglie il
  /// test.
  Future<int> freePort() async {
    final ServerSocket probe =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int free = probe.port;
    await probe.close();
    return free;
  }

  Future<bool> tillAnswers() async {
    try {
      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  setUp(() async {
    flags = SwitchableFlags();
    cloud = FakeServer();
    settings = InMemoryPeerSettings();
    port = await freePort();
    coordinator = LanCoordinator(
      settings: settings,
      registry: FakeServer(),
      deviceId: () async => 'cassa',
      standalone: FakeRemoteApi(deviceId: 'cassa', server: cloud),
      flags: flags,
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await flags.dispose();
  });

  group('spenta da remoto', () {
    test('la cassa smette di rispondere agli altri tablet', () async {
      await settings
          .save(PeerSettings(role: PeerRole.primary, primaryPort: port));
      await coordinator.fetchOrders();
      expect(await tillAnswers(), isTrue, reason: 'prima risponde');

      flags.peerSyncEnabled = false;
      await coordinator.fetchOrders();

      expect(await tillAnswers(), isFalse);
      expect(coordinator.role, PeerRole.standalone);
      expect(coordinator.localRegistry, isNull);
    });

    test('un tablet in sala manda gli ordini al backend', () async {
      // Nessuna cassa configurata risponderebbe: se l'interruttore non
      // funzionasse, l'invio fallirebbe invece di arrivare al cloud.
      await settings.save(
        const PeerSettings(
            role: PeerRole.follower, primaryHost: '10.255.255.1'),
      );
      flags.peerSyncEnabled = false;

      final TestEnv floor = TestEnv(deviceId: 'cassa', remoteApi: coordinator);
      addTearDown(floor.dispose);
      await floor.repository.createOrder(tableNumber: 4, lines: sampleLines);
      await floor.worker.drain();

      expect(cloud.allVersions(), hasLength(1));
      expect(await floor.repository.pendingCount(), 0);
    });

    test('le impostazioni restano, e riaccesa ognuno riprende il suo ruolo',
        () async {
      final PeerSettings till =
          PeerSettings(role: PeerRole.primary, primaryPort: port);
      await settings.save(till);
      flags.peerSyncEnabled = false;
      await coordinator.fetchOrders();
      expect(await tillAnswers(), isFalse);

      expect(await settings.load(), till,
          reason: 'il flag decide se valgono, non cosa contengono');

      flags.peerSyncEnabled = true;
      await coordinator.fetchOrders();

      expect(coordinator.role, PeerRole.primary);
      expect(await tillAnswers(), isTrue);
    });
  });

  group('un flag cambiato vale subito', () {
    test('la cassa si ferma senza aspettare il prossimo ordine', () async {
      await settings
          .save(PeerSettings(role: PeerRole.primary, primaryPort: port));
      final TestEnv till = TestEnv(deviceId: 'cassa', remoteApi: coordinator);
      addTearDown(till.dispose);
      await till.worker.drain();
      expect(await tillAnswers(), isTrue);

      final subscription = drainOnFlagChange(flags: flags, worker: till.worker);
      addTearDown(subscription.cancel);

      // Nessun ordine, nessun comando: solo il flag.
      flags.setPeerSync(false);

      await expectLater(
        Stream<void>.periodic(const Duration(milliseconds: 20))
            .asyncMap((_) => tillAnswers())
            .firstWhere((bool answers) => !answers)
            .timeout(const Duration(seconds: 5)),
        completion(isFalse),
      );
    });

    test('un giro che fallisce resta un avviso, non un crash', () async {
      // Un errore che la coda non sa gestire. Se uscisse dall'ascolto, il
      // test fallirebbe per un errore non preso: in produzione, Crashlytics lo
      // conterebbe come crash.
      final TestEnv broken = TestEnv(remoteApi: _BrokenApi());
      addTearDown(broken.dispose);

      final subscription = drainOnFlagChange(
        flags: flags,
        worker: broken.worker,
        logger: broken.logger,
      );
      addTearDown(subscription.cancel);

      flags.setPeerSync(false);
      await pumpEventQueue();

      expect(
        broken.logger.messages,
        contains(startsWith('WARN Giro della coda dopo un cambio di flag')),
      );
    });
  });
}

/// Un backend che fallisce in un modo che nessuna politica prevede.
class _BrokenApi implements RemoteApi {
  @override
  Future<void> submitOrder(Order order) async => throw StateError('rotto');

  @override
  Future<List<Order>> fetchOrders() async => throw StateError('rotto');
}
