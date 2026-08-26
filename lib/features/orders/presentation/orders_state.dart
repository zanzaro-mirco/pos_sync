import 'package:equatable/equatable.dart';

import '../domain/order.dart';

enum OrdersStatus { initial, loading, ready, error }

class OrdersState extends Equatable {
  const OrdersState({
    this.status = OrdersStatus.initial,
    this.orders = const <Order>[],
    this.pending = 0,
    this.message,
  });

  final OrdersStatus status;
  final List<Order> orders;

  /// Operazioni ancora da sincronizzare: è l'informazione che l'utente deve
  /// vedere, molto più utile di un'icona "online/offline".
  final int pending;

  final String? message;

  bool get hasPending => pending > 0;

  OrdersState copyWith({
    OrdersStatus? status,
    List<Order>? orders,
    int? pending,
    String? message,
  }) =>
      OrdersState(
        status: status ?? this.status,
        orders: orders ?? this.orders,
        pending: pending ?? this.pending,
        message: message,
      );

  @override
  List<Object?> get props => <Object?>[status, orders, pending, message];
}
