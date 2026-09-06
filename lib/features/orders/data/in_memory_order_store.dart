import 'dart:async';

import '../domain/order.dart';
import '../domain/order_conflict.dart';
import '../domain/orders_snapshot.dart';
import '../domain/outbox_entry.dart';
import 'order_store.dart';

/// Implementazione in memoria dei tre contratti di persistenza.
///
/// Una classe può implementare più interfacce strette: è esattamente il punto
/// dell'Interface Segregation Principle. Chi la usa vede solo il contratto di
/// cui ha bisogno, ma l'implementazione resta una sola e condivide lo stato,
/// che è ciò che rende possibile la scrittura atomica.
///
/// Non è codice di scarto: è l'implementazione usata dai test e dalla modalità
/// demo. La versione su SQLite implementerà le stesse interfacce senza che il
/// resto dell'applicazione se ne accorga.
class InMemoryOrderStore
    implements
        OrderStore,
        OutboxStore,
        OrderOutboxTransaction,
        OrdersWatcher,
        ConflictStore {
  final Map<String, Order> _orders = <String, Order>{};
  final Map<String, OutboxEntry> _outbox = <String, OutboxEntry>{};
  final Map<String, OrderConflict> _conflicts = <String, OrderConflict>{};
  final StreamController<OrdersSnapshot> _controller =
      StreamController<OrdersSnapshot>.broadcast();

  List<Order> get _sorted {
    final List<Order> list = _orders.values.toList()
      ..sort((Order a, Order b) => b.createdAt.compareTo(a.createdAt));
    return List<Order>.unmodifiable(list);
  }

  OrdersSnapshot get _snapshot => OrdersSnapshot(
        orders: _sorted,
        pending: _outbox.length,
        conflicts: _sortedConflicts,
      );

  List<OrderConflict> get _sortedConflicts {
    final List<OrderConflict> list = _conflicts.values.toList()
      ..sort((OrderConflict a, OrderConflict b) =>
          a.detectedAt.compareTo(b.detectedAt));
    return List<OrderConflict>.unmodifiable(list);
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_snapshot);
  }

  // --- OrderStore ---

  @override
  Future<List<Order>> allOrders() async => _sorted;

  @override
  Future<Order?> orderById(String id) async => _orders[id];

  @override
  Future<void> updateOrder(Order order) async {
    _orders[order.id] = order;
    _emit();
  }

  @override
  Future<void> deleteOrder(String id) async {
    _orders.remove(id);
    _emit();
  }

  // --- OutboxStore ---

  @override
  Future<List<OutboxEntry>> pendingOutbox() async {
    final List<OutboxEntry> list = _outbox.values.toList()
      ..sort(
          (OutboxEntry a, OutboxEntry b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<void> updateOutboxEntry(OutboxEntry entry) async {
    _outbox[entry.id] = entry;
    _emit();
  }

  @override
  Future<void> removeOutboxEntry(String id) async {
    _outbox.remove(id);
    _emit();
  }

  @override
  Future<int> pendingCount() async => _outbox.length;

  // --- OrdersWatcher ---

  @override
  Stream<OrdersSnapshot> watch() async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  // --- OrderOutboxTransaction ---

  @override
  Future<void> saveOrderWithOutbox(Order order, OutboxEntry entry) async {
    // In memoria l'atomicità è banale; su SQLite qui va aperta una transazione
    // che comprende entrambe le scritture.
    _orders[order.id] = order;
    _outbox[entry.id] = entry;
    _emit();
  }

  // --- ConflictStore ---

  @override
  Future<List<OrderConflict>> openConflicts() async => _sortedConflicts;

  @override
  Future<void> recordConflict(OrderConflict conflict) async {
    _conflicts[conflict.id] = conflict;
    _emit();
  }

  @override
  Future<void> removeConflict(String id) async {
    _conflicts.remove(id);
    _emit();
  }

  Future<void> dispose() => _controller.close();
}
