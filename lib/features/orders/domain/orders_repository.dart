import 'order.dart';
import 'orders_snapshot.dart';
import 'order_line.dart';

/// Contratto del repository, visto dal dominio e dalla presentazione.
///
/// Non compare mai la parola "rete": chi legge gli ordini non deve sapere se
/// il dispositivo è online. È il cuore dell'approccio offline-first.
abstract interface class OrdersRepository {
  /// Flusso osservabile: emette una fotografia coerente a ogni cambiamento.
  Stream<OrdersSnapshot> watch();

  Future<List<Order>> loadOrders();

  /// Crea un ordine, lo persiste e lo accoda per l'invio.
  Future<Order> createOrder({
    required int tableNumber,
    required List<OrderLine> lines,
  });

  /// Numero di operazioni ancora da sincronizzare.
  Future<int> pendingCount();
}
