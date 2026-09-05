import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/order.dart';
import '../../domain/order_conflict.dart';
import '../../domain/order_line.dart';
import '../../domain/orders_snapshot.dart';
import '../../domain/outbox_entry.dart';
import '../../domain/revision.dart';
import '../../domain/sync_status.dart';
import '../dto/order_dto.dart';
import '../order_store.dart';
import 'app_database.dart';

/// Implementazione su SQLite dei quattro contratti di persistenza.
///
/// Le firme sono quelle già usate da repository e worker: nessuno dei due sa
/// che sotto è cambiato il deposito. È la verifica di una promessa lasciata
/// scritta nel commento di `InMemoryOrderStore`.
///
/// L'implementazione in memoria non viene buttata: resta quella dei test
/// veloci e della modalità demo, e soprattutto resta il termine di paragone
/// contro cui questa classe viene messa alla prova dalla stessa suite.
class DriftOrderStore
    implements
        OrderStore,
        OutboxStore,
        OrderOutboxTransaction,
        OrdersWatcher,
        ConflictStore {
  DriftOrderStore(this._db);

  final AppDatabase _db;

  // --- OrderStore ---

  @override
  Future<List<Order>> allOrders() async {
    final List<OrderRow> rows = await (_db.select(_db.orders)
          ..orderBy(<OrderClauseGenerator<$OrdersTable>>[
            ($OrdersTable t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
    return _hydrate(rows);
  }

  @override
  Future<Order?> orderById(String id) async {
    final OrderRow? row = await (_db.select(_db.orders)
          ..where(($OrdersTable t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final List<Order> orders = await _hydrate(<OrderRow>[row]);
    return orders.single;
  }

  @override
  Future<void> updateOrder(Order order) =>
      _db.transaction(() => _writeOrder(order));

  @override
  Future<void> deleteOrder(String id) async {
    // Le righe se ne vanno per cascata: il vincolo è dichiarato nello schema
    // e acceso in `beforeOpen`.
    await (_db.delete(_db.orders)..where(($OrdersTable t) => t.id.equals(id)))
        .go();
  }

  // --- OutboxStore ---

  @override
  Future<List<OutboxEntry>> pendingOutbox() async {
    final List<OutboxRow> rows = await (_db.select(_db.outbox)
          ..orderBy(<OrderClauseGenerator<$OutboxTable>>[
            ($OutboxTable t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
    return rows.map(_toEntry).toList();
  }

  @override
  Future<void> updateOutboxEntry(OutboxEntry entry) async {
    await _db.into(_db.outbox).insertOnConflictUpdate(_toOutboxRow(entry));
  }

  @override
  Future<void> removeOutboxEntry(String id) async {
    await (_db.delete(_db.outbox)..where(($OutboxTable t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<int> pendingCount() async {
    final Expression<int> conteggio = countAll();
    final JoinedSelectStatement<$OutboxTable, OutboxRow> query =
        _db.selectOnly(_db.outbox)..addColumns(<Expression<Object>>[conteggio]);
    final TypedResult riga = await query.getSingle();
    return riga.read(conteggio) ?? 0;
  }

  // --- OrdersWatcher ---

  /// Emette la fotografia corrente, poi una nuova a ogni cambiamento.
  ///
  /// La query è un segnaposto: non serve il suo risultato, serve `readsFrom`,
  /// che dichiara a Drift quali tabelle deve osservare. La fotografia vera
  /// viene poi letta in transazione da [_snapshot].
  ///
  /// Il giro dalla query invece che da `tableUpdates` non è un vezzo: qui la
  /// sottoscrizione ai cambiamenti viene registrata **al momento
  /// dell'ascolto**, insieme alla prima emissione. Con un generatore `async*`
  /// che emette prima e si sottoscrive dopo, una scrittura arrivata nel mezzo
  /// non verrebbe notificata a nessuno.
  ///
  /// Drift raggruppa le notifiche per transazione: un `saveOrderWithOutbox`
  /// produce **una** emissione, non tre. È anche il motivo per cui non serve
  /// combinare due stream separati con `rxdart` — che oltretutto potrebbe far
  /// vedere la lista nuova con il contatore vecchio, cioè esattamente
  /// l'incoerenza che `OrdersSnapshot` esiste per impedire.
  @override
  Stream<OrdersSnapshot> watch() => _db
      .customSelect(
        'SELECT 1',
        readsFrom: <ResultSetImplementation<Object, Object>>{
          _db.orders,
          _db.orderLines,
          _db.outbox,
          _db.conflicts,
        },
      )
      .watch()
      .asyncMap((List<QueryRow> _) => _snapshot());

  // --- OrderOutboxTransaction ---

  /// Ordine, righe e voce di coda in un'unica transazione.
  ///
  /// In memoria l'atomicità era gratis e quindi non dimostrava niente. Qui
  /// l'invariante dichiarata da `OutboxEntry` — o si salvano insieme o non si
  /// salva niente — diventa verificabile con un rollback vero.
  @override
  Future<void> saveOrderWithOutbox(Order order, OutboxEntry entry) =>
      _db.transaction(() async {
        await _writeOrder(order);
        await _db.into(_db.outbox).insertOnConflictUpdate(_toOutboxRow(entry));
      });

  // --- interno ---

  /// Scrive l'ordine e **sostituisce** le sue righe.
  ///
  /// `copyWith` può cambiare la lista, quindi aggiornare la sola testata
  /// lascerebbe le righe della versione precedente.
  Future<void> _writeOrder(Order order) async {
    await _db.into(_db.orders).insertOnConflictUpdate(_toOrderRow(order));
    await (_db.delete(_db.orderLines)
          ..where(($OrderLinesTable t) => t.orderId.equals(order.id)))
        .go();
    await _db.batch((Batch b) {
      b.insertAll(_db.orderLines, _toLineRows(order));
    });
  }

  /// Lettura coerente: la lista e il contatore vengono dalla stessa
  /// transazione, quindi non possono raccontare due momenti diversi.
  Future<OrdersSnapshot> _snapshot() => _db.transaction(() async {
        return OrdersSnapshot(
          orders: await allOrders(),
          pending: await pendingCount(),
          conflicts: await openConflicts(),
        );
      });

  // --- ConflictStore ---

  @override
  Future<List<OrderConflict>> openConflicts() async {
    final List<ConflictRow> rows = await (_db.select(_db.conflicts)
          ..orderBy(<OrderClauseGenerator<$ConflictsTable>>[
            ($ConflictsTable t) => OrderingTerm.asc(t.detectedAt),
          ]))
        .get();
    return rows.map(_toConflict).toList();
  }

  @override
  Future<void> recordConflict(OrderConflict conflict) async {
    await _db
        .into(_db.conflicts)
        .insertOnConflictUpdate(_toConflictRow(conflict));
  }

  @override
  Future<void> removeConflict(String id) async {
    await (_db.delete(_db.conflicts)
          ..where(($ConflictsTable t) => t.id.equals(id)))
        .go();
  }

  Future<List<Order>> _hydrate(List<OrderRow> rows) async {
    if (rows.isEmpty) return List<Order>.unmodifiable(const <Order>[]);

    // Una sola interrogazione per tutte le righe, invece di una per ordine.
    final List<String> ids = rows.map((OrderRow r) => r.id).toList();
    final List<OrderLineRow> lineRows = await (_db.select(_db.orderLines)
          ..where(($OrderLinesTable t) => t.orderId.isIn(ids))
          ..orderBy(<OrderClauseGenerator<$OrderLinesTable>>[
            ($OrderLinesTable t) => OrderingTerm.asc(t.position),
          ]))
        .get();

    final Map<String, List<OrderLineRow>> perOrdine =
        <String, List<OrderLineRow>>{};
    for (final OrderLineRow riga in lineRows) {
      (perOrdine[riga.orderId] ??= <OrderLineRow>[]).add(riga);
    }

    return List<Order>.unmodifiable(rows.map((OrderRow r) =>
        _toOrder(r, perOrdine[r.id] ?? const <OrderLineRow>[])));
  }

  // --- mappatura riga <-> dominio ---

  OrderRow _toOrderRow(Order order) => OrderRow(
        id: order.id,
        tableNumber: order.tableNumber,
        createdAt: order.createdAt.microsecondsSinceEpoch,
        status: order.status.name,
        state: order.state.name,
        stateRevisionCounter: order.stateRevision.counter,
        stateRevisionDevice: order.stateRevision.deviceId,
      );

  List<OrderLineRow> _toLineRows(Order order) {
    final List<OrderLineRow> rows = <OrderLineRow>[];
    for (int i = 0; i < order.lines.length; i++) {
      final OrderLine line = order.lines[i];
      rows.add(OrderLineRow(
        orderId: order.id,
        position: i,
        lineId: line.id,
        addedAtCounter: line.addedAt.counter,
        addedAtDevice: line.addedAt.deviceId,
        productId: line.productId,
        description: line.description,
        quantity: line.quantity,
        unitPriceCents: line.unitPriceCents,
      ));
    }
    return rows;
  }

  Order _toOrder(OrderRow row, List<OrderLineRow> lines) => Order(
        id: row.id,
        tableNumber: row.tableNumber,
        lines: lines.map(_toLine).toList(),
        createdAt: DateTime.fromMicrosecondsSinceEpoch(row.createdAt),
        status: _statusFrom(row.status),
        state: parseOrderState(row.state),
        stateRevision: Revision(
          counter: row.stateRevisionCounter,
          deviceId: row.stateRevisionDevice,
        ),
      );

  OrderLine _toLine(OrderLineRow row) => OrderLine(
        id: row.lineId,
        productId: row.productId,
        description: row.description,
        quantity: row.quantity,
        unitPriceCents: row.unitPriceCents,
        addedAt: Revision(
          counter: row.addedAtCounter,
          deviceId: row.addedAtDevice,
        ),
      );

  ConflictRow _toConflictRow(OrderConflict conflict) => ConflictRow(
        id: conflict.id,
        orderId: conflict.orderId,
        mine: _encode(conflict.mine),
        theirs: _encode(conflict.theirs),
        reason: conflict.reason,
        detectedAt: conflict.detectedAt.microsecondsSinceEpoch,
      );

  OrderConflict _toConflict(ConflictRow row) => OrderConflict(
        id: row.id,
        mine: _decode(row.mine),
        theirs: _decode(row.theirs),
        reason: row.reason,
        detectedAt: DateTime.fromMicrosecondsSinceEpoch(row.detectedAt),
      );

  static String _encode(Order order) =>
      jsonEncode(OrderDto.fromDomain(order).toJson());

  /// Un conflitto illeggibile non deve impedire di aprire la schermata.
  ///
  /// Se il JSON è rovinato si restituisce un ordine vuoto con l'identificativo
  /// giusto: l'operatore vede che qualcosa non torna e può chiudere il
  /// conflitto, invece di trovarsi la lista degli ordini che non si carica.
  static Order _decode(String raw) {
    try {
      final Object? json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        final Order? order = OrderDto.fromJson(json).toDomain();
        if (order != null) return order;
      }
    } on FormatException {
      // Cade nel ripiego qui sotto.
    }
    return Order(
      id: '',
      tableNumber: 0,
      lines: const <OrderLine>[],
      createdAt: DateTime.fromMicrosecondsSinceEpoch(0),
    );
  }

  OutboxRow _toOutboxRow(OutboxEntry entry) => OutboxRow(
        id: entry.id,
        orderId: entry.orderId,
        createdAt: entry.createdAt.microsecondsSinceEpoch,
        attempts: entry.attempts,
        nextAttemptAt: entry.nextAttemptAt?.microsecondsSinceEpoch,
        lastError: entry.lastError,
      );

  OutboxEntry _toEntry(OutboxRow row) => OutboxEntry(
        id: row.id,
        orderId: row.orderId,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(row.createdAt),
        attempts: row.attempts,
        nextAttemptAt: row.nextAttemptAt == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(row.nextAttemptAt!),
        lastError: row.lastError,
      );

  /// Uno stato sconosciuto degrada a `pending` invece di far fallire la
  /// lettura: una versione futura potrebbe averne scritto uno che questa non
  /// conosce, e un ordine non ancora inviato è l'ipotesi prudente.
  SyncStatus _statusFrom(String raw) => SyncStatus.values.firstWhere(
        (SyncStatus s) => s.name == raw,
        orElse: () => SyncStatus.pending,
      );
}
