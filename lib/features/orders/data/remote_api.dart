import '../domain/order.dart';
import 'dto/order_dto.dart';

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
}

/// Backend simulato, con rete controllabile.
///
/// Serve alla modalità demo e ai test: permette di riprodurre a comando la
/// perdita di connettività e la risposta persa dopo che il server ha già
/// registrato l'ordine — il caso che rende necessaria l'idempotenza.
class FakeRemoteApi implements RemoteApi {
  FakeRemoteApi({this.online = true});

  bool online;

  /// Se vero, il server registra l'ordine ma la risposta non arriva al client.
  bool loseResponse = false;

  /// Payload effettivamente ricevuti, nell'ordine di arrivo.
  final List<OrderDto> received = <OrderDto>[];

  List<String> get receivedOrderIds =>
      received.map((OrderDto d) => d.id).toList();

  /// Ordini registrati, senza duplicati.
  Set<String> get storedOrderIds => receivedOrderIds.toSet();

  int get duplicateCount => receivedOrderIds.length - storedOrderIds.length;

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
    received.add(OrderDto.fromDomain(order));
    if (loseResponse) {
      throw const TransientApiFailure('Timeout in attesa della risposta');
    }
  }
}
