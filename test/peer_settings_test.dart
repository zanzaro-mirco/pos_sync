/// Il ruolo in sala: come si salva e cosa ne discende.
///
/// Tre cose distinte finiscono qui perché si tengono a vicenda: la
/// configurazione, il coordinatore che la applica, e la politica di ritentativo
/// che ne dipende. Separarle in tre file renderebbe più difficile vedere che
/// cambiare ruolo cambia *tutte e tre*.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/local/app_database.dart';
import 'package:pos_sync/features/orders/data/local/drift_device_store.dart';
import 'package:pos_sync/features/orders/data/local/drift_peer_settings.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/lan/lan_coordinator.dart';
import 'package:pos_sync/features/orders/lan/lan_protocol.dart';
import 'package:pos_sync/features/orders/lan/peer_retry_policy.dart';
import 'package:pos_sync/features/orders/lan/peer_settings.dart';
import 'package:pos_sync/features/orders/sync/retry_policy.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  group('PeerSettings', () {
    test('un dispositivo appena installato non fa parte di nessuna rete', () {
      // Il valore predefinito non è una comodità: l'app deve funzionare prima
      // che qualcuno abbia configurato qualcosa.
      const PeerSettings fresh = PeerSettings();

      expect(fresh.role, PeerRole.standalone);
      expect(fresh.primaryHost, isEmpty);
    });

    test('un follower senza indirizzo è configurato, non a metà', () {
      // Da quando la cassa si annuncia, l'indirizzo vuoto ha un significato
      // suo: «cercala». Prima era una configurazione incompleta e il
      // dispositivo ripiegava sul backend simulato — cioè accettava ordini che
      // nessun altro avrebbe mai letto.
      const PeerSettings looking = PeerSettings(role: PeerRole.follower);

      expect(looking.role, PeerRole.follower);
      expect(looking.toString(), contains('da cercare'));
      expect(
        looking.copyWith(primaryHost: '192.168.1.7').toString(),
        contains('192.168.1.7'),
        reason: 'un indirizzo digitato deve restare leggibile nei log',
      );
    });

    test('il nome del ruolo sopravvive al viaggio su disco', () {
      for (final PeerRole role in PeerRole.values) {
        expect(parsePeerRole(peerRoleName(role)), role);
      }
    });

    test('un ruolo sconosciuto degrada a standalone', () {
      // Come per lo stato del tavolo: meglio un dispositivo che non partecipa
      // alla rete locale di uno che non si apre.
      expect(parsePeerRole('capostazione'), PeerRole.standalone);
    });

    test('la porta predefinita è quella del protocollo', () {
      // Il valore di default della colonna è scritto a mano in `tables.dart`,
      // perché drift ricopia l'espressione nel codice generato e lì l'import
      // non c'è. Questo test è l'unico modo per accorgersene se i due
      // divergono.
      expect(const PeerSettings().primaryPort, lanPort);
    });
  });

  group('DriftPeerSettings', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('il ruolo sopravvive alla chiusura dell\'app', () async {
      // Un tablet che dimentica di essere la cassa a ogni riavvio smetterebbe
      // di esserlo proprio quando la sala si riempie.
      await DriftPeerSettings(db).save(const PeerSettings(
        role: PeerRole.follower,
        primaryHost: '192.168.1.7',
        primaryPort: 6000,
      ));

      final PeerSettings reread = await DriftPeerSettings(db).load();

      expect(reread.role, PeerRole.follower);
      expect(reread.primaryHost, '192.168.1.7');
      expect(reread.primaryPort, 6000);
    });

    test('condivide la riga con l\'identità senza calpestarla', () async {
      // Ruolo e contatore logico vivono nella stessa cassetta: salvare l'uno
      // non deve azzerare l'altro.
      final DriftDeviceStore identity = DriftDeviceStore(db);
      final String device = await identity.loadDeviceId();
      await identity.saveCounter(42);

      await DriftPeerSettings(db).save(
        const PeerSettings(role: PeerRole.primary),
      );

      expect(await identity.loadDeviceId(), device);
      expect(await identity.loadCounter(), 42);
      expect((await DriftPeerSettings(db).load()).role, PeerRole.primary);
    });
  });

  group('LanCoordinator', () {
    late FakeServer registry;
    late FakeRemoteApi standalone;
    late InMemoryPeerSettings settings;
    late LanCoordinator coordinator;

    setUp(() {
      registry = FakeServer();
      standalone = FakeRemoteApi(deviceId: 'io', server: FakeServer());
      settings = InMemoryPeerSettings();
      coordinator = LanCoordinator(
        settings: settings,
        registry: registry,
        deviceId: () async => 'io',
        standalone: standalone,
      );
    });

    tearDown(() => coordinator.dispose());

    test('senza configurazione parla con il backend di prima', () async {
      await coordinator.fetchOrders();

      expect(coordinator.role, PeerRole.standalone);
      expect(coordinator.localRegistry, isNull);
    });

    test('da primario tiene il registro e risponde sulla rete', () async {
      await settings.save(
        const PeerSettings(role: PeerRole.primary, primaryPort: 0),
      );
      await coordinator.fetchOrders();

      expect(coordinator.role, PeerRole.primary);
      expect(coordinator.localRegistry, same(registry),
          reason: 'il primario scrive nel registro che espone');
    });

    test('cambiare ruolo non richiede di riavviare l\'app', () async {
      // È la ragione per cui questo oggetto esiste: davanti a qualcuno che
      // guarda, «adesso riavvia» non è una risposta.
      await coordinator.fetchOrders();
      expect(coordinator.role, PeerRole.standalone);

      await settings.save(
        const PeerSettings(role: PeerRole.primary, primaryPort: 0),
      );
      await coordinator.fetchOrders();

      expect(coordinator.role, PeerRole.primary);
    });

    test('un follower che non trova la cassa non ripiega sul finto backend',
        () async {
      // Senza scoperta configurata non c'è nessuna cassa da trovare. Il
      // dispositivo fallisce in modo recuperabile invece di depositare gli
      // ordini nel registro in processo, che nessun altro leggerebbe mai.
      await settings.save(const PeerSettings(role: PeerRole.follower));

      await expectLater(
        coordinator.fetchOrders(),
        throwsA(isA<TransientApiFailure>()),
      );
      expect(coordinator.role, PeerRole.follower);
      expect(coordinator.localRegistry, isNull);
    });
  });

  group('PeerAwareRetryPolicy', () {
    late InMemoryPeerSettings settings;
    late LanCoordinator coordinator;
    late PeerAwareRetryPolicy policy;

    setUp(() {
      settings = InMemoryPeerSettings();
      coordinator = LanCoordinator(
        settings: settings,
        registry: FakeServer(),
        deviceId: () async => 'io',
        standalone: FakeRemoteApi(server: FakeServer()),
      );
      policy = PeerAwareRetryPolicy(coordinator: coordinator);
    });

    tearDown(() => coordinator.dispose());

    const ApiFailure transient = TransientApiFailure('cassa spenta');

    test('verso il cloud si rinuncia dopo il budget breve', () {
      expect(policy.decide(failure: transient, attempts: 20), isA<GiveUp>());
    });

    test('in rete locale si insiste molto più a lungo', () async {
      // La cassa spenta per venti minuti non è un guasto: rinunciare
      // marcherebbe come falliti ordini di tavoli ancora occupati.
      await settings.save(
        const PeerSettings(role: PeerRole.primary, primaryPort: 0),
      );
      await coordinator.fetchOrders();

      expect(
          policy.decide(failure: transient, attempts: 20), isA<RetryAfter>());
    });

    test('un errore definitivo resta definitivo anche in sala', () async {
      // Insistere di più non significa insistere sempre: una richiesta che il
      // primario rifiuta darà lo stesso esito al centesimo tentativo.
      await settings.save(
        const PeerSettings(role: PeerRole.primary, primaryPort: 0),
      );
      await coordinator.fetchOrders();

      expect(
        policy.decide(
          failure: const PermanentApiFailure('rifiutato'),
          attempts: 0,
        ),
        isA<GiveUp>(),
      );
    });

    test(
        'il tetto in sala è più basso: la cassa che torna viene ripresa '
        'subito', () {
      // Un tetto di cinque minuti farebbe aspettare fino a cinque minuti dopo
      // il ritorno della cassa, per un'attesa maturata mentre era spenta.
      final RetryAfter lan = BackoffRetryPolicy(backoff: lanBackoff())
          .decide(failure: transient, attempts: 20) as RetryAfter;

      expect(lan.delay, lessThanOrEqualTo(const Duration(minutes: 1)));
    });
  });
}
