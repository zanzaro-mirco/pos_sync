import 'package:connectivity_plus/connectivity_plus.dart';

import '../sync/connectivity_monitor.dart';

/// Adattatore su `connectivity_plus`.
///
/// Tutto ciò che questa classe fa è collassare l'elenco delle interfacce di
/// rete in un booleano. È volutamente banale: il valore sta nel fatto che il
/// plugin non compare da nessun'altra parte, quindi cambiarlo — o affiancargli
/// una vera verifica di raggiungibilità — è un lavoro locale.
///
/// **Il segnale è grossolano, e va bene così.** Il plugin riporta l'interfaccia
/// di rete, non se il backend risponde: sotto un portale captivo o dietro un
/// router senza uscita risulta "online". È accettabile proprio grazie alla
/// coda: un invio che fallisce non perde niente, torna in coda e riparte con
/// il backoff. Un controllo di raggiungibilità vero costerebbe una richiesta a
/// ogni cambio di rete per anticipare un errore che il sistema già gestisce.
class ConnectivityPlusMonitor implements ConnectivityMonitor {
  ConnectivityPlusMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isOnline() async =>
      _anyInterfaceUp(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onOnlineChanged =>
      _connectivity.onConnectivityChanged.map(_anyInterfaceUp);

  /// `none` è l'unico valore che significa davvero "nessuna rete". Gli altri
  /// — compresi `bluetooth` e `other` — vengono trattati come un tentativo che
  /// vale la pena fare.
  static bool _anyInterfaceUp(List<ConnectivityResult> results) =>
      results.any((ConnectivityResult r) => r != ConnectivityResult.none);
}
