import 'package:equatable/equatable.dart';

import 'lan_protocol.dart';

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

/// Come un tablet trova la cassa senza che nessuno ne digiti l'indirizzo.
///
/// L'indirizzo manuale continua a esistere e ha la precedenza: nei locali il
/// Wi-Fi ospiti blocca spesso il multicast, e una scoperta che lì non funziona
/// lascerebbe l'app senza alternative. Non è un ripiego di serie B — è il caso
/// che si può sempre far funzionare, mentre questo è quello comodo.
///
/// **Un'interfaccia e non direttamente `nsd`.** La scoperta passa dai canali
/// di piattaforma, quindi in un test di widget non esiste: senza questo
/// confine il comportamento del coordinatore — cosa fa quando la cassa non si
/// trova, quando cambia indirizzo, quando l'annuncio fallisce — resterebbe
/// verificabile solo su due dispositivi veri.
abstract interface class PeerDiscovery {
  /// Annuncia questo dispositivo come punto di raccolta.
  ///
  /// Idempotente: annunciarsi due volte non pubblica due servizi.
  Future<void> advertise({required String deviceId, required int port});

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
  }) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<PeerAddress?> findPrimary() async => null;
}
