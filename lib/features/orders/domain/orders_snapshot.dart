import 'package:equatable/equatable.dart';

import 'order.dart';
import 'order_conflict.dart';

/// Fotografia coerente di ciò che la schermata deve mostrare.
///
/// Modello di lettura a sé: la UI ha bisogno degli ordini *e* di quante
/// operazioni restano da sincronizzare, e le due informazioni devono arrivare
/// insieme. Emetterle separatamente produce stati intermedi incoerenti — la
/// lista aggiornata con il contatore vecchio — che poi si vedono come sfarfallii
/// nell'interfaccia.
class OrdersSnapshot extends Equatable {
  const OrdersSnapshot({
    required this.orders,
    required this.pending,
    this.conflicts = const <OrderConflict>[],
  });

  const OrdersSnapshot.empty()
      : orders = const <Order>[],
        pending = 0,
        conflicts = const <OrderConflict>[];

  final List<Order> orders;
  final int pending;

  /// Fusioni che si sono fermate e aspettano una decisione.
  ///
  /// Viaggiano nella stessa fotografia degli ordini per la stessa ragione del
  /// contatore: un conflitto riguarda un ordine, e mostrarne l'avviso mentre la
  /// lista racconta ancora il momento precedente è il modo per far apparire un
  /// avviso su un tavolo che nel frattempo è cambiato.
  final List<OrderConflict> conflicts;

  @override
  List<Object?> get props => <Object?>[orders, pending, conflicts];
}
