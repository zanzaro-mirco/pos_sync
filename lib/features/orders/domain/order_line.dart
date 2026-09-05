import 'package:equatable/equatable.dart';

import 'revision.dart';

/// Riga di un ordine.
///
/// Modello di dominio puro: nessun `toJson`, nessuna conoscenza del formato di
/// rete. La traduzione verso il trasporto sta nei DTO del livello dati — se
/// cambia il contratto dell'API cambia il mapper, non il dominio.
///
/// Le righe sono **append-only**: si aggiungono e non si modificano. È la
/// ragione per cui portano un [id] e una [addedAt] e non hanno un `copyWith`.
/// Due camerieri che aggiungono piatti allo stesso tavolo non sono in
/// conflitto: la fusione è l'unione dei due insiemi, che è commutativa e quindi
/// indifferente all'ordine di arrivo.
class OrderLine extends Equatable {
  const OrderLine({
    required this.id,
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    this.addedAt = const Revision.initial(),
  });

  /// Identificativo della riga, generato dal dispositivo che la aggiunge.
  ///
  /// È la chiave dell'unione: senza, due sincronizzazioni della stessa riga la
  /// aggiungerebbero due volte e l'operazione non sarebbe idempotente.
  final String id;

  /// Quando la riga è stata aggiunta, in tempo logico.
  ///
  /// Serve a rispondere a una domanda che l'unione da sola non pone: questa
  /// riga è arrivata *prima o dopo* che il tavolo fosse dato per pagato?
  final Revision addedAt;

  final String productId;
  final String description;
  final int quantity;
  final int unitPriceCents;

  int get totalCents => unitPriceCents * quantity;

  @override
  List<Object?> get props =>
      <Object?>[id, addedAt, productId, description, quantity, unitPriceCents];
}
