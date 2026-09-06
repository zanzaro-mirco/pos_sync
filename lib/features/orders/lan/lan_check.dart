import 'package:equatable/equatable.dart';

import '../data/order_registry.dart';
import 'http_remote_api.dart';
import 'peer_discovery.dart';
import 'peer_settings.dart';

/// Cosa si è scoperto provando la rete locale.
///
/// Tre campi e nessuna frase: il testo lo scrive la schermata, che è il posto
/// dove le parole si possono provare. Qui stanno solo i fatti.
class LanCheck extends Equatable {
  const LanCheck({
    this.primary,
    this.address,
    this.senders = const <String>[],
    this.problem,
  });

  /// Chi ha risposto, con il proprio identificativo.
  final String? primary;

  /// Dove ha risposto. Serve a distinguere «l'ho trovata da sé» da «era quella
  /// che avevi digitato».
  final PeerAddress? address;

  /// I dispositivi che hanno depositato ordini nel registro di questo
  /// dispositivo. Significativo solo per la cassa.
  final List<String> senders;

  /// Cosa non ha funzionato, se non ha funzionato.
  final String? problem;

  bool get ok => problem == null;

  @override
  List<Object?> get props => <Object?>[primary, address, senders, problem];
}

/// Prova la rete locale e riferisce, invece di lasciare indovinare.
///
/// Esiste per una domanda che il sistema non sapeva rispondere: **questi due
/// dispositivi si stanno parlando?** Finora l'unico segnale era indiretto — il
/// contatore «da inviare» che sale — e non distingue «la cassa non risponde» da
/// «la cassa risponde ma non le ho ancora mandato niente».
///
/// Le due metà della risposta sono diverse e stanno su dispositivi diversi:
///
/// - **In sala** la domanda è «qualcuno risponde, e chi?». Si chiede a
///   `/health`, che restituisce l'identificativo e non un sì/no.
/// - **In cassa** la domanda è «qualcuno mi ha scritto?». La risposta sta nel
///   registro: i dispositivi che vi hanno depositato una versione sono la sola
///   prova che il traffico è arrivato davvero. Una porta aperta dice che il
///   servizio c'è, non che qualcuno l'abbia usata.
class LanChecker {
  const LanChecker({
    required PeerDiscovery discovery,
    required OrderRegistry registry,
    required Future<String> Function() deviceId,
  })  : _discovery = discovery,
        _registry = registry,
        _deviceId = deviceId;

  final PeerDiscovery _discovery;
  final OrderRegistry _registry;
  final Future<String> Function() _deviceId;

  /// Prova [settings] così come sono, anche se non sono ancora state salvate:
  /// chi sta configurando vuole sapere se *questa* impostazione funziona, non
  /// se funzionava quella di prima.
  Future<LanCheck> check(PeerSettings settings) async {
    switch (settings.role) {
      case PeerRole.standalone:
        return const LanCheck(
          problem: 'La rete locale è spenta su questo dispositivo.',
        );

      case PeerRole.primary:
        return LanCheck(
          primary: await _deviceId(),
          senders: _registry.senders().toList()..sort(),
        );

      case PeerRole.follower:
        return _reachPrimary(settings);
    }
  }

  Future<LanCheck> _reachPrimary(PeerSettings settings) async {
    final PeerAddress? where = settings.primaryHost.isNotEmpty
        ? PeerAddress(host: settings.primaryHost, port: settings.primaryPort)
        : await _discovery.findPrimary();

    if (where == null) {
      return const LanCheck(
        problem: 'Nessuna cassa trovata sulla rete. Se il Wi-Fi filtra il '
            'multicast, scrivi il suo indirizzo qui sopra.',
      );
    }

    final HttpRemoteApi client = HttpRemoteApi(
      host: where.host,
      port: where.port,
      deviceId: await _deviceId(),
    );
    try {
      final String? who = await client.primaryDeviceId();
      if (who == null) {
        return LanCheck(
          address: where,
          problem: 'Nessuna risposta da $where. Controlla che la cassa sia '
              'accesa e sulla stessa rete.',
        );
      }
      return LanCheck(primary: who, address: where);
    } finally {
      // Un client per una domanda sola: tenerlo aperto significherebbe una
      // connessione in più che nessuno userà.
      client.close();
    }
  }
}
