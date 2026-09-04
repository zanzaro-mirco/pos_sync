import 'dart:async';
import 'dart:math';

import '../../../core/logger.dart';
import 'connectivity_monitor.dart';
import 'sync_worker.dart';

/// Attesa prima di un drenaggio automatico, iniettabile.
///
/// Esiste per la stessa ragione di `Clock`: un test che verifica il jitter non
/// deve attenderlo davvero.
typedef Sleeper = Future<void> Function(Duration);

Future<void> _wait(Duration d) => Future<void>.delayed(d);

/// Collega la connettività al drenaggio della coda.
///
/// Il [SyncWorker] non ha timer né ascolti: espone `drain()` e basta. Questa
/// classe è chi lo chiama quando la rete torna. La separazione non è
/// cerimoniale — *cosa* fare e *quando* farlo cambiano per ragioni diverse, e
/// tenerli insieme significherebbe non poter più testare il drenaggio senza
/// simulare anche il tempo e la rete.
///
/// Due comportamenti meritano attenzione, perché sono quelli in cui è facile
/// sbagliare:
///
/// - **Si agisce sulla transizione, non sull'evento.** Passare da Wi-Fi a dati
///   mobili produce un altro `true`: senza il confronto con lo stato
///   precedente, ogni cambio di rete farebbe ripartire la coda.
/// - **Lo stato iniziale conta come transizione.** Un'app chiusa offline con
///   la coda piena e riaperta sotto rete non riceverebbe mai un cambiamento,
///   e la coda resterebbe ferma potenzialmente per sempre.
class AutoSync {
  AutoSync({
    required ConnectivityMonitor monitor,
    required SyncWorker worker,
    Duration maxDelay = const Duration(seconds: 5),
    Random? random,
    Sleeper sleeper = _wait,
    Logger logger = const SilentLogger(),
  })  : _monitor = monitor,
        _worker = worker,
        _maxDelay = maxDelay,
        _random = random ?? Random(),
        _sleeper = sleeper,
        _logger = logger;

  final ConnectivityMonitor _monitor;
  final SyncWorker _worker;
  final Duration _maxDelay;
  final Random _random;
  final Sleeper _sleeper;
  final Logger _logger;

  StreamSubscription<bool>? _subscription;
  bool _online = false;

  /// Comincia ad ascoltare. Idempotente.
  void start() {
    if (_subscription != null) return;
    _subscription = _monitor.onOnlineChanged.listen(_onNetworkEvent);
    // Lo stato di partenza va letto *dopo* la sottoscrizione: leggerlo prima
    // lascerebbe scoperta la finestra fra la lettura e l'ascolto, ed è proprio
    // il momento in cui la rete torna dopo l'avvio dell'app.
    unawaited(_monitor.isOnline().then(_onNetworkEvent));
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onNetworkEvent(bool online) {
    if (online == _online) return;
    _online = online;
    if (online) unawaited(_drainAfterJitter());
  }

  Future<void> _drainAfterJitter() async {
    await _sleeper(_jitter());

    // La rete può essere già ricaduta durante l'attesa: tentare adesso
    // significherebbe solo consumare un tentativo e allungare il backoff.
    if (!_online) return;

    try {
      final SyncResult result = await _worker.drain();
      _logger.info('Rete tornata, coda drenata: $result');
    } catch (error) {
      // Il drenaggio parte da un evento, non da una chiamata: se l'eccezione
      // sfuggisse non ci sarebbe nessuno ad attenderla e farebbe cadere la
      // zona invece di fermarsi qui.
      _logger.warning('Drenaggio automatico fallito', error);
    }
  }

  /// Ritardo casuale fra zero e [_maxDelay].
  ///
  /// È lo stesso jitter del backoff e per lo stesso motivo, ma su una scala
  /// diversa: quando un router torna su, tutti i dispositivi del locale
  /// vedono la rete nello stesso istante. Senza questo ritardo partirebbero
  /// insieme, e il backend riceverebbe l'intero parco in una volta proprio nel
  /// momento in cui è appena tornato disponibile.
  Duration _jitter() =>
      Duration(milliseconds: _random.nextInt(_maxDelay.inMilliseconds + 1));
}
