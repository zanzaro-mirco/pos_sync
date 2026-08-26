import 'dart:math';

/// Calcolo del ritardo prima del tentativo successivo.
///
/// Backoff esponenziale con jitter. Il jitter non è un dettaglio: senza, un
/// parco di dispositivi che perde la rete nello stesso momento la ritrova
/// nello stesso momento e riprova tutto insieme, mettendo giù il backend
/// proprio quando torna disponibile.
class Backoff {
  Backoff({
    this.base = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.maxAttempts = 8,
    Random? random,
  }) : _random = random ?? Random();

  final Duration base;
  final Duration maxDelay;
  final int maxAttempts;
  final Random _random;

  /// Ritardo per il tentativo numero [attempt] (a partire da 0).
  Duration delayFor(int attempt) {
    if (attempt < 0) {
      throw ArgumentError.value(attempt, 'attempt', 'Non può essere negativo');
    }
    final int exponential = base.inMilliseconds * pow(2, attempt).toInt();
    final int capped = min(exponential, maxDelay.inMilliseconds);
    // Jitter fino al 25% in meno, mai oltre il cap.
    final int jitter = _random.nextInt((capped * 0.25).round() + 1);
    return Duration(milliseconds: capped - jitter);
  }

  /// Indica se vale ancora la pena riprovare.
  bool shouldRetry(int attempts) => attempts < maxAttempts;
}
