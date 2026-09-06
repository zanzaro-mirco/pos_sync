import '../../../core/logger.dart';
import '../data/order_registry.dart';
import '../data/remote_api.dart';
import '../domain/order.dart';
import 'http_remote_api.dart';
import 'local_registry_api.dart';
import 'order_server.dart';
import 'peer_settings.dart';

/// Tiene insieme il ruolo, il server e il backend, e li fa cambiare insieme.
///
/// È un `RemoteApi` che delega a un altro `RemoteApi`, scelto in base al ruolo
/// configurato. Il resto del sistema continua a vedere un backend solo e non
/// si accorge di niente — è la stessa idea per cui il worker non sa se dietro
/// c'è il cloud o il tablet di un collega, applicata un livello più in su.
///
/// **Senza questo, cambiare ruolo richiederebbe di riavviare l'app.** In un
/// test si accetta; davanti a qualcuno che guarda, no.
///
/// Il ruolo si rilegge a ogni chiamata invece di essere osservato: le chiamate
/// sono due, arrivano ogni volta che la coda gira, e una lettura da una riga
/// indicizzata costa meno di tenere in piedi uno stream per un dato che cambia
/// una volta all'anno.
class LanCoordinator implements RemoteApi {
  LanCoordinator({
    required PeerSettingsStore settings,
    required OrderRegistry registry,
    required Future<String> Function() deviceId,
    required RemoteApi standalone,
    Logger logger = const SilentLogger(),
  })  : _settings = settings,
        _registry = registry,
        _deviceId = deviceId,
        _standalone = standalone,
        _logger = logger;

  final PeerSettingsStore _settings;
  final OrderRegistry _registry;
  final Future<String> Function() _deviceId;
  final RemoteApi _standalone;
  final Logger _logger;

  OrderServer? _server;
  HttpRemoteApi? _client;
  RemoteApi? _delegate;
  PeerSettings _current = const PeerSettings();

  /// L'ultimo ruolo osservato, senza attese.
  ///
  /// Serve a chi deve decidere in fretta e non può aspettare una lettura —
  /// la politica di ritentativo, che risponde in modo sincrono.
  PeerRole get role => _current.role;

  /// Il registro, quando questo dispositivo è il primario. Altrimenti `null`.
  OrderRegistry? get localRegistry =>
      _current.role == PeerRole.primary ? _registry : null;

  /// Applica la configurazione, avviando o spegnendo ciò che serve.
  ///
  /// Idempotente: chiamata con impostazioni immutate non tocca niente. È la
  /// ragione per cui può stare sul percorso di ogni sincronizzazione senza
  /// riaprire un server a ogni giro.
  Future<RemoteApi> _resolve() async {
    final PeerSettings wanted = await _settings.load();
    if (_delegate != null && wanted == _current) return _delegate!;

    await _teardown();
    _current = wanted;

    if (!wanted.isUsable) {
      // Un follower senza indirizzo: configurazione a metà, non un errore.
      // Si continua a fare ciò che si faceva prima invece di rompersi.
      _logger.info('Configurazione di rete incompleta: $wanted');
      return _delegate = _standalone;
    }

    final String me = await _deviceId();

    switch (wanted.role) {
      case PeerRole.standalone:
        _delegate = _standalone;

      case PeerRole.primary:
        final OrderServer server = OrderServer(
          registry: _registry,
          deviceId: me,
          logger: _logger,
        );
        await server.start(port: wanted.primaryPort);
        _server = server;
        // Il primario deposita la propria versione come chiunque altro: il
        // registro deve poterla tenere distinta da quelle dei follower.
        _delegate = LocalRegistryApi(registry: _registry, deviceId: me);

      case PeerRole.follower:
        final HttpRemoteApi client = HttpRemoteApi(
          host: wanted.primaryHost,
          port: wanted.primaryPort,
          deviceId: me,
        );
        _client = client;
        _delegate = client;
    }

    _logger.info('Rete locale: $wanted');
    return _delegate!;
  }

  Future<void> _teardown() async {
    _client?.close();
    _client = null;
    await _server?.stop();
    _server = null;
    _delegate = null;
  }

  /// Chiude tutto. Da chiamare quando l'applicazione termina.
  Future<void> dispose() => _teardown();

  @override
  Future<void> submitOrder(Order order) async =>
      (await _resolve()).submitOrder(order);

  @override
  Future<List<Order>> fetchOrders() async => (await _resolve()).fetchOrders();
}
