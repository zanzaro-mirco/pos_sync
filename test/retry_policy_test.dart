import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/sync/backoff.dart';
import 'package:pos_sync/features/orders/sync/retry_policy.dart';

void main() {
  RetryPolicy policy({int maxAttempts = 3}) => BackoffRetryPolicy(
        backoff: Backoff(maxAttempts: maxAttempts, random: Random(1)),
      );

  group('BackoffRetryPolicy', () {
    test('un errore recuperabile viene ritentato con un ritardo', () {
      final RetryDecision d = policy().decide(
        failure: const TransientApiFailure('rete assente'),
        attempts: 0,
      );
      expect(d, isA<RetryAfter>());
      expect((d as RetryAfter).delay.inMilliseconds, greaterThan(0));
    });

    test('un errore definitivo non viene mai ritentato', () {
      final RetryDecision d = policy().decide(
        failure: const PermanentApiFailure('payload non valido'),
        attempts: 0,
      );
      expect(d, isA<GiveUp>());
      expect((d as GiveUp).reason, 'payload non valido');
    });

    test('esauriti i tentativi si rinuncia anche sugli errori recuperabili',
        () {
      final RetryDecision d = policy(maxAttempts: 2).decide(
        failure: const TransientApiFailure('rete assente'),
        attempts: 2,
      );
      expect(d, isA<GiveUp>());
    });

    test('il ritardo cresce con i tentativi', () {
      final RetryPolicy p = policy(maxAttempts: 10);
      Duration delay(int attempts) => (p.decide(
            failure: const TransientApiFailure('x'),
            attempts: attempts,
          ) as RetryAfter)
              .delay;
      expect(delay(2) > delay(0), isTrue);
    });
  });

  test('una politica alternativa non richiede di toccare il worker', () {
    // Dimostrazione concreta dell Open/Closed: cambiare comportamento
    // significa passare un altro oggetto, non modificare il codice esistente.
    final RetryDecision d = _NeverRetryPolicy().decide(
      failure: const TransientApiFailure('rete assente'),
      attempts: 0,
    );
    expect(d, isA<GiveUp>());
  });
}

/// Politica che non ritenta mai: utile per test manuali e modalità diagnostica.
class _NeverRetryPolicy implements RetryPolicy {
  @override
  RetryDecision decide({required ApiFailure failure, required int attempts}) =>
      const GiveUp('Ritentativi disattivati');
}
