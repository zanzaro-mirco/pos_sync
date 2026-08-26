import 'package:equatable/equatable.dart';

/// Voce della coda di uscita.
///
/// Ogni operazione destinata al server viene scritta qui **nella stessa
/// transazione** che modifica il dato locale: o vengono salvate entrambe o
/// nessuna delle due. È l'invariante che impedisce di avere un ordine in
/// locale che il server non vedrà mai.
class OutboxEntry extends Equatable {
  const OutboxEntry({
    required this.id,
    required this.orderId,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  final String id;
  final String orderId;
  final DateTime createdAt;

  /// Numero di tentativi già effettuati.
  final int attempts;

  /// Istante prima del quale non ha senso riprovare (backoff).
  final DateTime? nextAttemptAt;

  final String? lastError;

  bool isDueAt(DateTime now) =>
      nextAttemptAt == null || !now.isBefore(nextAttemptAt!);

  OutboxEntry withFailure({
    required DateTime nextAttemptAt,
    required String error,
  }) =>
      OutboxEntry(
        id: id,
        orderId: orderId,
        createdAt: createdAt,
        attempts: attempts + 1,
        nextAttemptAt: nextAttemptAt,
        lastError: error,
      );

  @override
  List<Object?> get props =>
      <Object?>[id, orderId, createdAt, attempts, nextAttemptAt, lastError];
}
