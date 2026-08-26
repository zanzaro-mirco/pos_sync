import 'package:equatable/equatable.dart';

import 'order.dart';

/// Fotografia coerente di ciò che la schermata deve mostrare.
///
/// Modello di lettura a sé: la UI ha bisogno degli ordini *e* di quante
/// operazioni restano da sincronizzare, e le due informazioni devono arrivare
/// insieme. Emetterle separatamente produce stati intermedi incoerenti — la
/// lista aggiornata con il contatore vecchio — che poi si vedono come sfarfallii
/// nell'interfaccia.
class OrdersSnapshot extends Equatable {
  const OrdersSnapshot({required this.orders, required this.pending});

  const OrdersSnapshot.empty()
      : orders = const <Order>[],
        pending = 0;

  final List<Order> orders;
  final int pending;

  @override
  List<Object?> get props => <Object?>[orders, pending];
}
