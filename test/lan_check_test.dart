/// «Questi due dispositivi si stanno parlando?»
///
/// È una domanda che il sistema non sapeva rispondere. L'unico segnale era
/// indiretto — il contatore «da inviare» che sale — e non distingue «la cassa
/// non risponde» da «la cassa risponde ma non le ho ancora mandato niente».
///
/// Le due metà della risposta stanno su dispositivi diversi, e i test lo
/// rispettano: in sala si chiede *chi risponde*, in cassa *chi ha scritto*.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';
import 'package:pos_sync/features/orders/lan/lan_check.dart';
import 'package:pos_sync/features/orders/lan/order_server.dart';
import 'package:pos_sync/features/orders/lan/peer_discovery.dart';
import 'package:pos_sync/features/orders/lan/peer_settings.dart';

import 'helpers/fake_discovery.dart';

void main() {
  // Qui si parla HTTP vero su loopback: l'override di `flutter_test`
  // risponderebbe 400 a tutto senza toccare la rete, e la prova direbbe
  // «nessuna risposta» per una ragione inventata.
  setUpAll(() => HttpOverrides.global = null);

  const String me = 'tablet-sala';

  late FakeServer registry;
  late FakeDiscovery discovery;
  late LanChecker checker;

  setUp(() {
    registry = FakeServer();
    discovery = FakeDiscovery();
    checker = LanChecker(
      discovery: discovery,
      registry: registry,
      deviceId: () async => me,
    );
  });

  Future<OrderServer> till({String deviceId = 'tablet-cassa'}) async {
    final OrderServer server =
        OrderServer(registry: FakeServer(), deviceId: deviceId);
    await server.start(port: 0);
    addTearDown(server.stop);
    return server;
  }

  Order order(String id) => Order(
        id: id,
        tableNumber: 7,
        createdAt: DateTime.utc(2026, 9, 6, 12),
        state: OrderState.open,
        stateRevision: const Revision(counter: 1, deviceId: 'x'),
        lines: const <OrderLine>[],
      );

  test('senza rete locale lo dice invece di far finta di provare', () async {
    final LanCheck result = await checker.check(const PeerSettings());

    expect(result.ok, isFalse);
    expect(result.problem, contains('spenta'));
  });

  group('in sala', () {
    test('risponde la cassa, e con il suo identificativo', () async {
      // Non un sì/no: dopo un'elezione all'indirizzo noto può rispondere un
      // dispositivo diverso, e saperlo è metà della diagnosi.
      final OrderServer server = await till();
      final LanCheck result = await checker.check(
        PeerSettings(
          role: PeerRole.follower,
          primaryHost: '127.0.0.1',
          primaryPort: server.port!,
        ),
      );

      expect(result.ok, isTrue);
      expect(result.primary, 'tablet-cassa');
      expect(result.address?.port, server.port);
    });

    test('senza indirizzo la cerca, e riferisce dove l\'ha trovata', () async {
      final OrderServer server = await till();
      discovery.primary = PeerAddress(host: '127.0.0.1', port: server.port!);

      final LanCheck result =
          await checker.check(const PeerSettings(role: PeerRole.follower));

      expect(result.primary, 'tablet-cassa');
      expect(result.address?.host, '127.0.0.1');
      expect(discovery.lookups, 1);
    });

    test('se non c\'è nessuna cassa suggerisce cosa fare', () async {
      // Un messaggio che dice solo «errore» lascia chi legge senza mosse. Qui
      // il caso più frequente — il multicast filtrato — ha il suo rimedio
      // scritto accanto.
      final LanCheck result =
          await checker.check(const PeerSettings(role: PeerRole.follower));

      expect(result.ok, isFalse);
      expect(result.problem, contains('indirizzo'));
    });

    test('un indirizzo dove non ascolta nessuno lo dice, e quale', () async {
      final OrderServer server = await till();
      final int port = server.port!;
      await server.stop();

      final LanCheck result = await checker.check(
        PeerSettings(
          role: PeerRole.follower,
          primaryHost: '127.0.0.1',
          primaryPort: port,
        ),
      );

      expect(result.ok, isFalse);
      expect(result.problem, contains('$port'),
          reason: 'dire dove non ha risposto è metà della diagnosi');
    });
  });

  group('in cassa', () {
    test('senza nessuno che abbia scritto, lo dice', () async {
      final LanCheck result =
          await checker.check(const PeerSettings(role: PeerRole.primary));

      expect(result.ok, isTrue);
      expect(result.senders, isEmpty);
    });

    test('elenca chi ha depositato ordini nel registro', () async {
      // È la sola prova che il traffico è arrivato davvero: una porta aperta
      // dice che il servizio c'è, non che qualcuno l'abbia usata.
      registry.store(order('ord-1'), 'tablet-b');
      registry.store(order('ord-2'), 'tablet-a');
      registry.store(order('ord-3'), 'tablet-b');

      final LanCheck result =
          await checker.check(const PeerSettings(role: PeerRole.primary));

      expect(result.senders, <String>['tablet-a', 'tablet-b']);
    });
  });
}
