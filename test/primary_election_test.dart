/// Chi prende il posto della cassa quando la cassa non c'è più.
///
/// La regola riusa un ordine che nel sistema esiste già — il confronto fra
/// identificativi che rompe la parità fra due `Revision` — e non è economia:
/// è ciò che permette a tutti i dispositivi di calcolare lo stesso risultato
/// senza mettersi d'accordo, che è l'unica cosa che rende possibile
/// un'elezione senza coordinatore.
///
/// I test insistono più sui casi in cui **non** ci si promuove, perché sono
/// quelli che tengono il sistema insieme: promuoversi troppo facilmente
/// produce due registri, e due registri sono peggio di una cassa spenta.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/lan/peer_discovery.dart';
import 'package:pos_sync/features/orders/lan/peer_settings.dart';
import 'package:pos_sync/features/orders/lan/primary_election.dart';

import 'helpers/fake_discovery.dart';

void main() {
  const String me = 'tablet-m';

  late FakeDiscovery discovery;
  late InMemoryPeerSettings settings;
  late PrimaryElection election;

  setUp(() {
    discovery = FakeDiscovery();
    settings = InMemoryPeerSettings(
      const PeerSettings(role: PeerRole.follower),
    );
    election = PrimaryElection(
      discovery: discovery,
      settings: settings,
      deviceId: () async => me,
    );
  });

  Future<bool> failTimes(int n) async {
    bool promoted = false;
    for (int i = 0; i < n; i++) {
      promoted = await election.failed();
    }
    return promoted;
  }

  Future<PeerRole> savedRole() async => (await settings.load()).role;

  test('un solo giro andato male non cambia niente', () async {
    // Un errore isolato è una rete che fa il suo mestiere. Promuoversi al primo
    // intoppo produrrebbe un cambio di cassa a ogni pacchetto perso.
    expect(await failTimes(1), isFalse);
    expect(await savedRole(), PeerRole.follower);
  });

  test('dopo la soglia, senza nessun altro in rete, si prende il registro',
      () async {
    expect(await failTimes(3), isTrue);
    expect(await savedRole(), PeerRole.primary);
  });

  test('una cassa che si annuncia ancora non viene sostituita', () async {
    // Non raggiungerla è un problema di questo tablet: mettergliene accanto
    // un'altra sposterebbe il guasto su tutti gli altri.
    discovery.nodes = <PeerNode>[node('tablet-a', role: PeerRole.primary)];

    expect(await failTimes(5), isFalse);
    expect(await savedRole(), PeerRole.follower);
  });

  test('se c\'è un identificativo più basso del mio, tocca a lui', () async {
    discovery.nodes = <PeerNode>[node('tablet-a'), node('tablet-z')];

    expect(await failTimes(3), isFalse);
    expect(await savedRole(), PeerRole.follower);
  });

  test('con identificativi più alti del mio, tocca a me', () async {
    discovery.nodes = <PeerNode>[node('tablet-x'), node('tablet-z')];

    expect(await failTimes(3), isTrue);
    expect(await savedRole(), PeerRole.primary);
  });

  test('due tablet non si promuovono insieme', () async {
    // La proprietà che conta: sugli stessi dati tutti scelgono lo stesso, ed è
    // ciò che evita due registri senza che nessuno coordini niente.
    final List<String> ids = <String>['tablet-m', 'tablet-a', 'tablet-z'];
    final List<String> promoted = <String>[];

    for (final String who in ids) {
      final InMemoryPeerSettings own = InMemoryPeerSettings(
        const PeerSettings(role: PeerRole.follower),
      );
      final PrimaryElection theirs = PrimaryElection(
        discovery: FakeDiscovery(
          nodes: <PeerNode>[
            for (final String other in ids)
              if (other != who) node(other),
          ],
        ),
        settings: own,
        deviceId: () async => who,
      );
      for (int i = 0; i < 3; i++) {
        if (await theirs.failed()) promoted.add(who);
      }
    }

    expect(promoted, <String>['tablet-a']);
  });

  test('una cassa che torna a rispondere azzera il conteggio', () async {
    // Senza questo, tre fallimenti sparsi in una serata basterebbero a
    // scatenare un'elezione mentre la cassa funziona.
    await failTimes(2);
    election.succeeded();

    expect(await failTimes(2), isFalse);
    expect(await savedRole(), PeerRole.follower);
    expect(election.failures, 2);
  });

  test('promuoversi non cancella l\'indirizzo digitato', () async {
    // Non è un dato di questo ruolo, ma è una configurazione che qualcuno ha
    // scritto a mano, e l'elezione potrebbe non essere definitiva.
    await settings.save(
      const PeerSettings(role: PeerRole.follower, primaryHost: '192.168.1.7'),
    );

    expect(await failTimes(3), isTrue);
    expect((await settings.load()).primaryHost, '192.168.1.7');
  });
}
