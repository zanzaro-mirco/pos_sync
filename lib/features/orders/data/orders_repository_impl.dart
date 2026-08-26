import '../../../core/clock.dart';
import '../../../core/id_generator.dart';
import '../domain/order.dart';
import '../domain/order_line.dart';
import '../domain/orders_repository.dart';
import '../domain/orders_snapshot.dart';
import '../domain/outbox_entry.dart';
import 'order_store.dart';
import 'outbox_scheduler.dart';

class OrdersRepositoryImpl implements OrdersRepository {
  OrdersRepositoryImpl({
    required OrderStore orderStore,
    required OutboxStore outboxStore,
    required OrderOutboxTransaction transaction,
    required OrdersWatcher watcher,
    OutboxScheduler? scheduler,
    Clock clock = const SystemClock(),
    IdGenerator idGenerator = const UuidGenerator(),
  })  : _orders = orderStore,
        _outbox = outboxStore,
        _transaction = transaction,
        _watcher = watcher,
        _clock = clock,
        _ids = idGenerator,
        _scheduler = scheduler ??
            OutboxScheduler(idGenerator: idGenerator, clock: clock);

  final OrderStore _orders;
  final OutboxStore _outbox;
  final OrderOutboxTransaction _transaction;
  final OrdersWatcher _watcher;
  final OutboxScheduler _scheduler;
  final Clock _clock;
  final IdGenerator _ids;

  @override
  Stream<OrdersSnapshot> watch() => _watcher.watch();

  @override
  Future<List<Order>> loadOrders() => _orders.allOrders();

  @override
  Future<Order> createOrder({
    required int tableNumber,
    required List<OrderLine> lines,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Un ordine deve avere almeno una riga');
    }

    // L'id è generato qui, sul client, prima di qualsiasi tentativo di invio:
    // è ciò che rende il retry sicuro.
    final Order order = Order(
      id: _ids.next(),
      tableNumber: tableNumber,
      lines: lines,
      createdAt: _clock.now(),
    );

    final OutboxEntry entry = _scheduler.scheduleFor(order);
    await _transaction.saveOrderWithOutbox(order, entry);
    return order;
  }

  @override
  Future<int> pendingCount() => _outbox.pendingCount();
}
