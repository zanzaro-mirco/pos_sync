import '../domain/order.dart';
import 'dto/order_dto.dart';
import 'order_registry.dart';

/// Errori del trasporto, modellati come gerarchia chiusa.
///
/// Prima la distinzione fra recuperabile e definitivo era affidata a due
/// classi non imparentate e a due `catch` separati nel worker: aggiungere una
/// terza categoria — per esempio "rifiutato ma ritentabile più tardi" —
/// significava *modificare* il worker. Con una gerarchia sealed la decisione
/// si sposta nella politica di ritentativo, che è un oggetto sostituibile.
sealed class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;
}

/// Errore recuperabile: ha senso riprovare.
class TransientApiFailure extends ApiFailure {
  const TransientApiFailure(super.message);
  @override
  String toString() => 'TransientApiFailure: $message';
}

/// Errore definitivo: riprovare non serve.
class PermanentApiFailure extends ApiFailure {
  const PermanentApiFailure(super.message);
  @override
  String toString() => 'PermanentApiFailure: $message';
}

/// Contratto verso il backend.
abstract interface class RemoteApi {
  /// Invia l'ordine. Deve essere idempotente rispetto a `order.id`.
  Future<void> submitOrder(Order order);

  /// Versioni note al server, di tutti i dispositivi.
  ///
  /// Restituisce **una voce per dispositivo**, non una sola versione fusa.
  /// La differenza conta: la versione di un dispositivo è ciò che *quel*
  /// dispositivo credeva, e fondendola sul server quella provenienza andrebbe
  /// perduta. Senza, non si può più rispondere alla domanda da cui dipende il
  /// riconoscimento di un conflitto — chi ha incassato aveva davanti questa
  /// riga? — perché la versione fusa le contiene tutte per costruzione.
  ///
  /// La fusione è quindi lavoro del dispositivo, non del server. È anche la
  /// scelta che tiene la porta aperta al punto 2.5: fra due tablet in rete
  /// locale un server che fonde non c'è.
  Future<List<Order>> fetchOrders();
}

/// Stato condiviso del finto backend: cosa il server sa, di chi.
///
/// Oggetto a sé perché è *il server*, e i client sono un'altra cosa. Due
/// `FakeRemoteApi` che puntano allo stesso [FakeServer] sono due dispositivi
/// che parlano con lo stesso backend — che è esattamente lo scenario da
/// riprodurre per verificare la convergenza, e che con una classe sola non si
/// poteva esprimere.
class FakeServer implements OrderRegistry {
  /// Per ogni ordine, l'ultima versione ricevuta da ciascun dispositivo.
  final Map<String, Map<String, Order>> _versions =
      <String, Map<String, Order>>{};

  /// Payload effettivamente ricevuti, nell'ordine di arrivo.
  final List<OrderDto> received = <OrderDto>[];

  List<String> get receivedOrderIds =>
      received.map((OrderDto d) => d.id).toList();

  /// Ordini registrati, senza duplicati.
  Set<String> get storedOrderIds => _versions.keys.toSet();

  /// Quante volte lo stesso ordine è stato ricevuto più di una volta.
  ///
  /// È la misura dell'idempotenza: il server accetta il duplicato senza
  /// crearne uno nuovo, e questo contatore lo rende visibile ai test.
  int get duplicateCount => receivedOrderIds.length - storedOrderIds.length;

  @override
  void store(Order order, String deviceId) {
    received.add(OrderDto.fromDomain(order));
    (_versions[order.id] ??= <String, Order>{})[deviceId] = order;
  }

  /// Tutte le versioni conosciute, appiattite.
  @override
  List<Order> allVersions() => <Order>[
        for (final Map<String, Order> byDevice in _versions.values)
          ...byDevice.values,
      ];

  /// Le versioni degli *altri* dispositivi.
  ///
  /// L'esclusione guarda chi ha inviato, non cosa contiene la versione: è il
  /// server a saperlo, ed è l'unico posto in cui l'informazione esiste.
  @override
  List<Order> versionsExcept(String deviceId) => <Order>[
        for (final Map<String, Order> byDevice in _versions.values)
          for (final MapEntry<String, Order> e in byDevice.entries)
            if (e.key != deviceId) e.value,
      ];

  @override
  Set<String> senders() => <String>{
        for (final Map<String, Order> byDevice in _versions.values)
          ...byDevice.keys,
      };

  @override
  void clear() {
    _versions.clear();
    received.clear();
  }
}

/// Backend simulato, con rete controllabile.
///
/// Serve alla modalità demo e ai test: permette di riprodurre a comando la
/// perdita di connettività e la risposta persa dopo che il server ha già
/// registrato l'ordine — il caso che rende necessaria l'idempotenza.
///
/// Un'istanza è **un dispositivo**: ha il proprio interruttore della rete e il
/// proprio identificativo. Lo stato del server è fuori, in [FakeServer], e si
/// condivide passando lo stesso oggetto a due client.
class FakeRemoteApi implements RemoteApi {
  FakeRemoteApi({
    this.online = true,
    this.deviceId = 'dispositivo-1',
    FakeServer? server,
  }) : server = server ?? FakeServer();

  final FakeServer server;

  /// Identificativo del dispositivo che usa questo client.
  final String deviceId;

  bool online;

  /// Se vero, il server registra l'ordine ma la risposta non arriva al client.
  bool loseResponse = false;

  List<OrderDto> get received => server.received;
  List<String> get receivedOrderIds => server.receivedOrderIds;
  Set<String> get storedOrderIds => server.storedOrderIds;
  int get duplicateCount => server.duplicateCount;

  @override
  Future<void> submitOrder(Order order) async {
    if (!online) {
      throw const TransientApiFailure('Nessuna connettività');
    }
    if (order.lines.isEmpty) {
      throw const PermanentApiFailure('Ordine senza righe');
    }
    // Il dominio non conosce il formato di trasporto: la traduzione avviene
    // qui, sul confine.
    server.store(order, deviceId);
    if (loseResponse) {
      throw const TransientApiFailure('Timeout in attesa della risposta');
    }
  }

  @override
  Future<List<Order>> fetchOrders() async {
    if (!online) {
      throw const TransientApiFailure('Nessuna connettività');
    }
    // La versione inviata da questo stesso dispositivo non torna indietro:
    // fonderla con la copia locale sarebbe un'operazione nulla, perché la
    // copia locale è la stessa o più recente.
    return server.versionsExcept(deviceId);
  }
}
