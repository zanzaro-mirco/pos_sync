import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/sync/backoff.dart';

void main() {
  group('Backoff', () {
    // Random con seme fisso: il jitter resta casuale ma il test è deterministico.
    Backoff make() => Backoff(random: Random(42));

    test('cresce in modo esponenziale', () {
      final Backoff b = make();
      final Duration d0 = b.delayFor(0);
      final Duration d1 = b.delayFor(1);
      final Duration d2 = b.delayFor(2);
      expect(d1 > d0, isTrue);
      expect(d2 > d1, isTrue);
    });

    test('non supera mai il tetto massimo', () {
      final Backoff b = Backoff(
        maxDelay: const Duration(seconds: 30),
        random: Random(1),
      );
      for (int attempt = 0; attempt < 20; attempt++) {
        expect(b.delayFor(attempt) <= const Duration(seconds: 30), isTrue);
      }
    });

    test('il jitter non produce mai un ritardo negativo', () {
      final Backoff b = make();
      for (int attempt = 0; attempt < 20; attempt++) {
        expect(b.delayFor(attempt).inMilliseconds >= 0, isTrue);
      }
    });

    test('il jitter produce valori diversi tra loro', () {
      final Backoff b = Backoff(random: Random(7));
      final Set<int> values = <int>{
        for (int i = 0; i < 30; i++) b.delayFor(3).inMilliseconds,
      };
      expect(values.length > 1, isTrue,
          reason: 'senza jitter tutti i dispositivi riproverebbero insieme');
    });

    test('smette di riprovare dopo maxAttempts', () {
      final Backoff b = Backoff(maxAttempts: 3, random: Random(1));
      expect(b.shouldRetry(2), isTrue);
      expect(b.shouldRetry(3), isFalse);
      expect(b.shouldRetry(10), isFalse);
    });

    test('rifiuta un numero di tentativo negativo', () {
      expect(() => make().delayFor(-1), throwsArgumentError);
    });
  });
}
