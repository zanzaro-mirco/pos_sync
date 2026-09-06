import 'package:equatable/equatable.dart';

import 'order_line.dart';
import 'order_state.dart';
import 'revision.dart';
import 'sync_status.dart';

/// Ordine di un tavolo.
///
/// L'`id` è generato dal client, non dal server: è la chiave che rende l'invio
/// idempotente. Se la risposta del server si perde e il dispositivo riprova,
/// il server riconosce lo stesso id e non crea un duplicato.
///
/// Due campi hanno vite diverse ed è bene non confonderli. [status] è locale:
/// dice se questo dispositivo è riuscito a mandare l'ordine, e non viaggia.
/// [state] è condiviso: dice cosa sta succedendo al tavolo, lo possono cambiare
/// tutti, e per questo porta con sé la [stateRevision] che dice quando.
class Order extends Equatable {
  Order({
    required this.id,
    required this.tableNumber,
    required List<OrderLine> lines,
    required this.createdAt,
    this.status = SyncStatus.pending,
    this.state = OrderState.open,
    this.stateRevision = const Revision.initial(),
  }) : lines = List<OrderLine>.unmodifiable(lines);

  final String id;
  final int tableNumber;
  final List<OrderLine> lines;
  final DateTime createdAt;

  /// Stato di sincronizzazione, **locale a questo dispositivo**.
  final SyncStatus status;

  /// Stato del tavolo, **condiviso fra i dispositivi**.
  final OrderState state;

  /// Quando lo stato del tavolo è stato cambiato l'ultima volta.
  ///
  /// È il dato su cui si decide chi vince quando due dispositivi cambiano lo
  /// stesso tavolo: non l'ora di arrivo, non l'ora di sistema.
  final Revision stateRevision;

  int get totalCents =>
      lines.fold<int>(0, (int acc, OrderLine l) => acc + l.totalCents);

  int get itemCount =>
      lines.fold<int>(0, (int acc, OrderLine l) => acc + l.quantity);

  Order copyWith({
    SyncStatus? status,
    List<OrderLine>? lines,
    OrderState? state,
    Revision? stateRevision,
  }) =>
      Order(
        id: id,
        tableNumber: tableNumber,
        lines: lines ?? this.lines,
        createdAt: createdAt,
        status: status ?? this.status,
        state: state ?? this.state,
        stateRevision: stateRevision ?? this.stateRevision,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        tableNumber,
        lines,
        createdAt,
        status,
        state,
        stateRevision,
      ];
}
