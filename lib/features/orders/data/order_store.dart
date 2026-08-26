import '../domain/order.dart';
import '../domain/orders_snapshot.dart';
import '../domain/outbox_entry.dart';

/// Persistenza degli ordini.
///
/// Interfaccia stretta e volutamente separata da quella della coda. Prima
/// esisteva un unico `OrderStore` con sette metodi, e nessuno dei due
/// collaboratori li usava tutti: il repository ne usava quattro, il worker
/// cinque. Era una violazione dell'Interface Segregation Principle, e in
/// pratica significava che un doppio di test doveva implementare anche i
/// metodi che non gli servivano.
abstract interface class OrderStore {
  Future<List<Order>> allOrders();
  Future<Order?> orderById(String id);
  Future<void> updateOrder(Order order);
  Future<void> deleteOrder(String id);
}

/// Modello di lettura osservabile.
///
/// Contratto separato dalla scrittura: chi mostra i dati non ha bisogno di
/// poterli modificare, e chi li modifica non ha bisogno di osservarli. È la
/// stessa idea alla base di CQRS, applicata in piccolo.
///
/// È anche l'alternativa al ricaricare tutto dopo ogni operazione: chi osserva
/// riceve i dati quando cambiano, invece di chiederli di continuo.
abstract interface class OrdersWatcher {
  Stream<OrdersSnapshot> watch();
}

/// Persistenza della coda di uscita.
abstract interface class OutboxStore {
  Future<List<OutboxEntry>> pendingOutbox();
  Future<void> updateOutboxEntry(OutboxEntry entry);
  Future<void> removeOutboxEntry(String id);
  Future<int> pendingCount();
}

/// Scrittura atomica di ordine e voce di coda.
///
/// È un contratto a sé perché è l'unica operazione che *deve* attraversare
/// entrambi i depositi: o si salvano insieme o non si salva niente. Tenerla
/// separata rende esplicito che è una transazione, invece di nasconderla fra
/// i metodi ordinari.
abstract interface class OrderOutboxTransaction {
  Future<void> saveOrderWithOutbox(Order order, OutboxEntry entry);
}
