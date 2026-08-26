/// Astrazione sul tempo.
///
/// Il tempo è una dipendenza come le altre: se il codice chiama
/// `DateTime.now()` direttamente, i test sul backoff e sulla scadenza dei
/// tentativi diventano lenti e non deterministici.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Orologio controllabile, per i test.
class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}
