import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../feature_flags.dart';
import '../logger.dart';

/// I flag letti da Remote Config.
///
/// **Un flag spento non raggiunge un tablet che non vede internet**, ed è il
/// limite da dire per primo, perché la rete locale esiste proprio per quando il
/// cloud non si vede. Il valore però resta: Remote Config conserva l'ultimo
/// ricevuto, e un tablet che lo ha visto spento una volta resta spento anche
/// offline, anche dopo un riavvio.
class RemoteConfigFlags implements FeatureFlags {
  RemoteConfigFlags(this._config, {Logger logger = const SilentLogger()})
      : _logger = logger;

  /// Il nome del parametro nella console di Firebase.
  static const String peerSyncKey = 'peer_sync_enabled';

  /// I valori finché la console non ne ha dati altri. Sono quelli di
  /// `FixedFeatureFlags`: accendere Firebase non deve cambiare niente.
  static const Map<String, Object> defaults = <String, Object>{
    peerSyncKey: true,
  };

  final FirebaseRemoteConfig _config;
  final Logger _logger;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  bool get peerSyncEnabled => _config.getBool(peerSyncKey);

  @override
  Stream<void> get changes => _changes.stream;

  /// Prepara i valori e comincia ad ascoltare.
  ///
  /// Si attende solo ciò che è locale: i predefiniti e l'ultimo valore
  /// ricevuto, che Remote Config tiene su disco. La richiesta al cloud parte e
  /// non si aspetta — un tablet senza rete deve aprire l'app lo stesso, e in
  /// fretta.
  ///
  /// [fromCloud] a `false` nel lavoro in background: dura pochi secondi, e il
  /// motore che lo esegue si chiude di solito prima che il cloud risponda, e
  /// la risposta non troverebbe più nessuno. Lì basta l'ultimo valore
  /// ricevuto dall'app aperta.
  Future<void> start({bool fromCloud = true}) async {
    await _config.setDefaults(defaults);
    await _config.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // L'intervallo vale solo per la lettura all'avvio. Il cambiamento
        // spinto dal cloud qui sotto non lo rispetta, ed è quello che conta
        // quando si spegne qualcosa: arriva in pochi secondi, non fra un'ora.
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );

    if (!fromCloud) return;

    unawaited(
      _config.fetchAndActivate().then((bool changed) {
        if (changed) _changes.add(null);
      }).catchError((Object error) {
        _logger.info('Remote Config non raggiungibile: $error');
      }),
    );

    _config.onConfigUpdated.listen(
      (RemoteConfigUpdate update) async {
        await _config.activate();
        _logger.info('Flag aggiornati: ${update.updatedKeys.join(', ')}');
        _changes.add(null);
      },
      onError: (Object error) {
        _logger.info('Aggiornamenti dei flag interrotti: $error');
      },
    );
  }
}
