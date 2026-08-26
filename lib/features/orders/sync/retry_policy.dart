import '../data/remote_api.dart';
import 'backoff.dart';

/// Decisione presa dopo un tentativo fallito.
sealed class RetryDecision {
  const RetryDecision();
}

/// Riprovare dopo [delay].
class RetryAfter extends RetryDecision {
  const RetryAfter(this.delay);
  final Duration delay;
}

/// Rinunciare in modo definitivo.
class GiveUp extends RetryDecision {
  const GiveUp(this.reason);
  final String reason;
}

/// Decide se e quando riprovare.
///
/// Estratta dal `SyncWorker`, che prima faceva cinque cose: orchestrare la
/// coda, classificare gli errori, calcolare il backoff, aggiornare gli stati e
/// registrare i messaggi. Ora la politica è un oggetto sostituibile: si può
/// averne una diversa per gli ordini e per i pagamenti senza duplicare il
/// worker, e si può testarla da sola.
abstract interface class RetryPolicy {
  RetryDecision decide({required ApiFailure failure, required int attempts});
}

class BackoffRetryPolicy implements RetryPolicy {
  BackoffRetryPolicy({Backoff? backoff}) : _backoff = backoff ?? Backoff();

  final Backoff _backoff;

  @override
  RetryDecision decide({required ApiFailure failure, required int attempts}) {
    return switch (failure) {
      PermanentApiFailure() => GiveUp(failure.message),
      TransientApiFailure() => _backoff.shouldRetry(attempts + 1)
          ? RetryAfter(_backoff.delayFor(attempts))
          : const GiveUp('Tentativi esauriti'),
    };
  }
}
