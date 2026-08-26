import 'package:equatable/equatable.dart';

import 'order_line.dart';
import 'sync_status.dart';

/// Ordine di un tavolo.
///
/// L'`id` è generato dal client, non dal server: è la chiave che rende l'invio
/// idempotente. Se la risposta del server si perde e il dispositivo riprova,
/// il server riconosce lo stesso id e non crea un duplicato.
class Order extends Equatable {
  Order({
    required this.id,
    required this.tableNumber,
    required List<OrderLine> lines,
    required this.createdAt,
    this.status = SyncStatus.pending,
  }) : lines = List<OrderLine>.unmodifiable(lines);

  final String id;
  final int tableNumber;
  final List<OrderLine> lines;
  final DateTime createdAt;
  final SyncStatus status;

  int get totalCents =>
      lines.fold<int>(0, (int acc, OrderLine l) => acc + l.totalCents);

  int get itemCount =>
      lines.fold<int>(0, (int acc, OrderLine l) => acc + l.quantity);

  Order copyWith({SyncStatus? status, List<OrderLine>? lines}) => Order(
        id: id,
        tableNumber: tableNumber,
        lines: lines ?? this.lines,
        createdAt: createdAt,
        status: status ?? this.status,
      );

  @override
  List<Object?> get props =>
      <Object?>[id, tableNumber, lines, createdAt, status];
}
