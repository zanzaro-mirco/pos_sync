import 'package:equatable/equatable.dart';

import 'lan_protocol.dart';
import 'peer_settings.dart';

/// Dove risponde un dispositivo primario.
class PeerAddress extends Equatable {
  const PeerAddress({required this.host, this.port = lanPort});

  final String host;
  final int port;

  @override
  List<Object?> get props => <Object?>[host, port];

  @override
  String toString() => '$host:$port';
}

/// Un dispositivo che si annuncia sulla rete, con la parte che dice di fare.
class PeerNode extends Equatable {
  const PeerNode({
    required this.deviceId,
    required this.address,
    required this.role,
  });

  final String deviceId;
  final PeerAddress address;
  final PeerRole role;

  @override
  List<Object?> get props => <Object?>[deviceId, address, role];

  @override
  String toString() => '${peerRoleName(role)} $deviceId a $address';
}

/// Come un tablet trova la cassa senza che nessuno ne digiti l'indirizzo.
///
/// L'indirizzo manuale continua a esistere e ha la precedenza: nei locali il
/// Wi-Fi ospiti blocca spesso il multicast, e una scoperta che lì non funziona
/// lascerebbe l'app senza alternative. Non è un ripiego di serie B — è il caso
/// che si può sempre far funzionare, mentre questo è quello comodo.
///
/// **Anche chi è in sala si annuncia**, e non solo la cassa. Serve
/// all'elezione: promuovere «il dispositivo con l'identificativo più basso fra
/// quelli noti» richiede di poterli contare, e un tablet che tace non è
/// contabile. Il servizio che annuncia non ascolta finché non viene promosso —
/// dichiara una presenza, non un servizio pronto — e nessuno ci si collega,
/// perché [findPrimary] filtra per ruolo.
///
/// **Un'interfaccia e non direttamente `nsd`.** La scoperta passa dai canali
/// di piattaforma, quindi in un test di widget non esiste: senza questo
/// confine il comportamento del coordinatore — cosa fa quando la cassa non si
/// trova, quando cambia indirizzo, quando l'annuncio fallisce — resterebbe
/// verificabile solo su due dispositivi veri.
abstract interface class PeerDiscovery {
  /// Annuncia questo dispositivo, con la parte che fa.
  ///
  /// Idempotente rispetto al ruolo: annunciarsi due volte con lo stesso ruolo
  /// non pubblica due servizi. Cambiare ruolo invece ripubblica, perché è
  /// esattamente l'informazione che gli altri leggono.
  Future<void> advertise({
    required String deviceId,
    required int port,
    required PeerRole role,
  });

  /// Smette di annunciarsi.
  ///
  /// Va chiamata quando il ruolo cambia: un annuncio che sopravvive al ruolo
  /// manderebbe gli altri tablet a bussare a una porta che non ascolta più.
  Future<void> stopAdvertising();

  /// Cerca un punto di raccolta sulla rete. `null` se non ne trova.
  ///
  /// Non trovarlo non è un errore: può non essercene ancora uno, o il
  /// multicast può essere filtrato. Chi chiama decide cosa farne.
  Future<PeerAddress?> findPrimary();

  /// Tutti i dispositivi che si annunciano, questo escluso.
  ///
  /// Serve solo all'elezione, ed è il motivo per cui esiste come metodo a sé:
  /// la sincronizzazione ordinaria non ha bisogno di sapere chi altro c'è.
  Future<List<PeerNode>> peers();
}

/// Nessuna scoperta: l'indirizzo si digita e basta.
///
/// Serve dove i canali di piattaforma non ci sono — i test — e come risposta
/// onesta su una piattaforma che non fosse supportata: il resto continua a
/// funzionare con l'indirizzo manuale.
class NoDiscovery implements PeerDiscovery {
  const NoDiscovery();

  @override
  Future<void> advertise({
    required String deviceId,
    required int port,
    required PeerRole role,
  }) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<PeerAddress?> findPrimary() async => null;

  @override
  Future<List<PeerNode>> peers() async => const <PeerNode>[];
}
