import '../../../core/clock.dart';
import '../../../core/id_generator.dart';
import '../../../core/logical_clock.dart';
import '../domain/order.dart';
import '../domain/order_conflict.dart';
import '../domain/order_line.dart';
import '../domain/order_line_draft.dart';
import '../domain/order_state.dart';
import '../domain/orders_repository.dart';
import '../domain/orders_snapshot.dart';
import '../domain/outbox_entry.dart';
import '../domain/revision.dart';
import '../sync/conflict_policy.dart';
import 'order_store.dart';
import 'outbox_scheduler.dart';

class OrdersRepositoryImpl implements OrdersRepository {
  OrdersRepositoryImpl({
    required OrderStore orderStore,
    required OutboxStore outboxStore,
    required OrderOutboxTransaction transaction,
    required OrdersWatcher watcher,
    required ConflictStore conflictStore,
    required LogicalClock logicalClock,
    OutboxScheduler? scheduler,
    ConflictPolicy<List<OrderLine>> lineMerge = const AppendOnlyLines(),
    Clock clock = const SystemClock(),
    IdGenerator idGenerator = const UuidGenerator(),
  })  : _orders = orderStore,
        _outbox = outboxStore,
        _transaction = transaction,
        _watcher = watcher,
        _conflicts = conflictStore,
        _logical = logicalClock,
        _lineMerge = lineMerge,
        _clock = clock,
        _ids = idGenerator,
        _scheduler = scheduler ??
            OutboxScheduler(idGenerator: idGenerator, clock: clock);

  final OrderStore _orders;
  final OutboxStore _outbox;
  final OrderOutboxTransaction _transaction;
  final OrdersWatcher _watcher;
  final ConflictStore _conflicts;
  final LogicalClock _logical;
  final ConflictPolicy<List<OrderLine>> _lineMerge;
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
    required List<OrderLineDraft> lines,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Un ordine deve avere almeno una riga');
    }

    // L'id è generato qui, sul client, prima di qualsiasi tentativo di invio:
    // è ciò che rende il retry sicuro.
    final Order order = Order(
      id: _ids.next(),
      tableNumber: tableNumber,
      lines: await _stamp(lines),
      createdAt: _clock.now(),
    );

    await _enqueue(order);
    return order;
  }

  @override
  Future<Order> addLines({
    required String orderId,
    required List<OrderLineDraft> lines,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Nessuna riga da aggiungere');
    }
    final Order order = await _require(orderId);

    // Le righe nuove passano dalla stessa unione che fonde quelle degli altri
    // dispositivi. Concatenarle e basta funzionerebbe qui e produrrebbe un
    // ordinamento diverso da quello che si ottiene sincronizzando, cioè due
    // liste con gli stessi elementi che non si possono confrontare.
    final List<OrderLine> added = await _stamp(lines);
    final Resolution<List<OrderLine>> merged =
        _lineMerge.merge(order.lines, added);
    final List<OrderLine> allLines = merged is Resolved<List<OrderLine>>
        ? merged.value
        : <OrderLine>[...order.lines, ...added];

    final Order updated = order.copyWith(lines: allLines);
    await _enqueue(updated);
    return updated;
  }

  @override
  Future<Order> changeState({
    required String orderId,
    required OrderState state,
  }) async {
    final Order order = await _require(orderId);
    final Order updated = order.copyWith(
      state: state,
      stateRevision: await _logical.tick(),
    );
    await _enqueue(updated);
    return updated;
  }

  @override
  Future<void> resolveConflict(String conflictId, ConflictChoice choice) async {
    OrderConflict? conflict;
    for (final OrderConflict c in await _conflicts.openConflicts()) {
      if (c.id == conflictId) {
        conflict = c;
        break;
      }
    }
    // Già risolto altrove, o l'app è stata riaperta nel frattempo: non è un
    // errore, è la conseguenza di un dato condiviso.
    if (conflict == null) return;

    final Order winner =
        choice == ConflictChoice.mine ? conflict.mine : conflict.theirs;

    // Le righe si uniscono comunque: la decisione riguarda lo stato del tavolo,
    // non cosa è stato ordinato. È la ragione per cui è sicuro chiedere — non
    // esiste una risposta che faccia sparire una comanda.
    final Resolution<List<OrderLine>> lines =
        _lineMerge.merge(conflict.mine.lines, conflict.theirs.lines);

    // La revisione è nuova e non quella della versione scelta: la decisione è
    // essa stessa una modifica, e deve battere entrambe le versioni che l'hanno
    // provocata anche sugli altri dispositivi. Senza, l'altro dispositivo
    // rifonderebbe le stesse due e ricadrebbe nello stesso conflitto.
    final Order resolved = conflict.mine.copyWith(
      lines: lines is Resolved<List<OrderLine>> ? lines.value : null,
      state: winner.state,
      stateRevision: await _logical.tick(),
    );

    await _enqueue(resolved);
    await _conflicts.removeConflict(conflictId);
  }

  @override
  Future<int> pendingCount() => _outbox.pendingCount();

  /// Salva l'ordine e la voce di coda nella stessa transazione.
  Future<void> _enqueue(Order order) async {
    final OutboxEntry entry = _scheduler.scheduleFor(order);
    await _transaction.saveOrderWithOutbox(order, entry);
  }

  Future<Order> _require(String orderId) async {
    final Order? order = await _orders.orderById(orderId);
    if (order == null) {
      throw ArgumentError.value(orderId, 'orderId', 'Ordine inesistente');
    }
    return order;
  }

  /// Assegna a ogni bozza un identificativo e la revisione corrente.
  ///
  /// Una sola revisione per tutte le righe della stessa operazione: sono state
  /// aggiunte insieme, e numerarle una per una direbbe che sono arrivate in
  /// momenti diversi.
  Future<List<OrderLine>> _stamp(List<OrderLineDraft> drafts) async {
    final Revision revision = await _logical.tick();
    return <OrderLine>[
      for (final OrderLineDraft d in drafts)
        OrderLine(
          id: _ids.next(),
          productId: d.productId,
          description: d.description,
          quantity: d.quantity,
          unitPriceCents: d.unitPriceCents,
          addedAt: revision,
        ),
    ];
  }
}
