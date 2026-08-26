import 'package:equatable/equatable.dart';

/// Riga di un ordine.
///
/// Modello di dominio puro: nessun `toJson`, nessuna conoscenza del formato di
/// rete. La traduzione verso il trasporto sta nei DTO del livello dati — se
/// cambia il contratto dell'API cambia il mapper, non il dominio.
class OrderLine extends Equatable {
  const OrderLine({
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
  });

  final String productId;
  final String description;
  final int quantity;
  final int unitPriceCents;

  int get totalCents => unitPriceCents * quantity;

  @override
  List<Object?> get props =>
      <Object?>[productId, description, quantity, unitPriceCents];
}
