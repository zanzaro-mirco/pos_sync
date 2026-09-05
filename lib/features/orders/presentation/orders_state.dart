import 'package:equatable/equatable.dart';

import '../domain/order.dart';
import '../domain/order_conflict.dart';

enum OrdersStatus { initial, loading, ready, error }

class OrdersState extends Equatable {
  const OrdersState({
    this.status = OrdersStatus.initial,
    this.orders = const <Order>[],
    this.pending = 0,
    this.conflicts = const <OrderConflict>[],
    this.message,
  });

  final OrdersStatus status;
  final List<Order> orders;

  /// Operazioni ancora da sincronizzare: è l'informazione che l'utente deve
  /// vedere, molto più utile di un'icona "online/offline".
  final int pending;

  /// Fusioni ferme in attesa di una decisione dell'operatore.
  final List<OrderConflict> conflicts;

  final String? message;

  bool get hasPending => pending > 0;

  bool get hasConflicts => conflicts.isNotEmpty;

  OrdersState copyWith({
    OrdersStatus? status,
    List<Order>? orders,
    int? pending,
    List<OrderConflict>? conflicts,
    String? message,
  }) =>
      OrdersState(
        status: status ?? this.status,
        orders: orders ?? this.orders,
        pending: pending ?? this.pending,
        conflicts: conflicts ?? this.conflicts,
        message: message,
      );

  @override
  List<Object?> get props =>
      <Object?>[status, orders, pending, conflicts, message];
}
