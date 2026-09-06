import '../../../core/logger.dart';
import '../data/order_registry.dart';
import '../data/remote_api.dart';
import '../domain/order.dart';
import 'http_remote_api.dart';
import 'local_registry_api.dart';
import 'order_server.dart';
import 'peer_discovery.dart';
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
    PeerDiscovery discovery = const NoDiscovery(),
    Logger logger = const SilentLogger(),
  })  : _settings = settings,
        _registry = registry,
        _deviceId = deviceId,
        _standalone = standalone,
        _discovery = discovery,
        _logger = logger;

  final PeerSettingsStore _settings;
  final OrderRegistry _registry;
  final Future<String> Function() _deviceId;
  final RemoteApi _standalone;
  final PeerDiscovery _discovery;
  final Logger _logger;

  OrderServer? _server;
  HttpRemoteApi? _client;
  RemoteApi? _delegate;
  PeerSettings _current = const PeerSettings();

  /// Se l'indirizzo in uso l'abbiamo trovato noi invece di leggerlo dalle
  /// impostazioni. Decide se ha senso ricercarlo quando smette di rispondere.
  bool _addressDiscovered = false;

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
    final String me = await _deviceId();

    switch (wanted.role) {
      case PeerRole.standalone:
        return _delegate = _standalone;

      case PeerRole.primary:
        final OrderServer server = OrderServer(
          registry: _registry,
          deviceId: me,
          logger: _logger,
        );
        await server.start(port: wanted.primaryPort);
        _server = server;
        await _announce(me, server.port ?? wanted.primaryPort);
        _logger.info('Rete locale: $wanted');
        // Il primario deposita la propria versione come chiunque altro: il
        // registro deve poterla tenere distinta da quelle dei follower.
        return _delegate = LocalRegistryApi(registry: _registry, deviceId: me);

      case PeerRole.follower:
        final PeerAddress? where = await _primaryAddress(wanted);
        if (where == null) {
          // Nessun delegato memorizzato di proposito: al prossimo giro si
          // torna a cercare, invece di restare fermi su un fallimento.
          _logger.info('Nessuna cassa raggiungibile');
          return const _UnreachablePrimary();
        }
        final HttpRemoteApi client = HttpRemoteApi(
          host: where.host,
          port: where.port,
          deviceId: me,
        );
        _client = client;
        _logger.info('Rete locale: cassa a $where');
        return _delegate = client;
    }
  }

  /// Dove bussare, se si riesce a saperlo.
  ///
  /// **L'indirizzo digitato ha la precedenza.** Nei locali il Wi-Fi ospiti
  /// blocca spesso il multicast, e chi ha scritto un indirizzo a mano lo ha
  /// fatto per una ragione: scavalcarlo con ciò che si trova in rete
  /// significherebbe ignorare l'unica configurazione che si può sempre far
  /// funzionare.
  Future<PeerAddress?> _primaryAddress(PeerSettings wanted) async {
    if (wanted.primaryHost.isNotEmpty) {
      _addressDiscovered = false;
      return PeerAddress(host: wanted.primaryHost, port: wanted.primaryPort);
    }
    final PeerAddress? found = await _discovery.findPrimary();
    _addressDiscovered = found != null;
    return found;
  }

  /// Si annuncia, e non si ferma se non ci riesce.
  ///
  /// Una rete che filtra il multicast non deve impedire alla cassa di *essere*
  /// la cassa: chi conosce l'indirizzo la raggiunge lo stesso, ed è esattamente
  /// il caso per cui l'indirizzo manuale è rimasto.
  Future<void> _announce(String deviceId, int port) async {
    try {
      await _discovery.advertise(deviceId: deviceId, port: port);
    } catch (e) {
      _logger.warning('Annuncio in rete non riuscito: $e');
    }
  }

  Future<void> _teardown() async {
    _client?.close();
    _client = null;
    await _server?.stop();
    _server = null;
    _delegate = null;
    _addressDiscovered = false;
    try {
      await _discovery.stopAdvertising();
    } catch (e) {
      _logger.warning('Annuncio non ritirato: $e');
    }
  }

  /// Chiude tutto. Da chiamare quando l'applicazione termina.
  Future<void> dispose() => _teardown();

  /// Esegue la chiamata e, se fallisce per ragioni di rete, dimentica un
  /// indirizzo che avevamo scoperto noi.
  ///
  /// Serve a un caso concreto: la cassa riceve un indirizzo diverso dal router
  /// dopo un riavvio. Senza questo, i tablet continuerebbero a bussare al
  /// vecchio indirizzo per sempre, e l'unico rimedio sarebbe riavviare l'app —
  /// cioè la scoperta automatica funzionerebbe una volta sola.
  ///
  /// Un indirizzo **digitato** non si dimentica: è una decisione di chi l'ha
  /// scritto, e sostituirla con ciò che passa per la rete sarebbe scavalcarlo.
  Future<T> _guard<T>(Future<T> Function(RemoteApi api) call) async {
    final RemoteApi api = await _resolve();
    try {
      return await call(api);
    } on TransientApiFailure {
      if (_addressDiscovered) await _teardown();
      rethrow;
    }
  }

  @override
  Future<void> submitOrder(Order order) =>
      _guard((RemoteApi api) => api.submitOrder(order));

  @override
  Future<List<Order>> fetchOrders() =>
      _guard((RemoteApi api) => api.fetchOrders());
}

/// Il backend di chi è in sala e non sa dove sia la cassa.
///
/// Fallisce in modo **recuperabile**, e la differenza conta: la coda tiene gli
/// ordini e riprova. Ripiegare sul backend simulato — che era il comportamento
/// prima della scoperta automatica — li avrebbe accettati tutti, marcandoli
/// come inviati verso un registro che vive nel processo di questo tablet e che
/// nessun altro leggerà mai.
class _UnreachablePrimary implements RemoteApi {
  const _UnreachablePrimary();

  static const ApiFailure _failure =
      TransientApiFailure('Nessuna cassa raggiungibile in rete locale');

  @override
  Future<void> submitOrder(Order order) async => throw _failure;

  @override
  Future<List<Order>> fetchOrders() async => throw _failure;
}
