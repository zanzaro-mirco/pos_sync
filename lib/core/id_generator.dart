import 'package:uuid/uuid.dart';

/// Generazione degli identificativi.
///
/// Astratta per la stessa ragione dell'orologio: un id casuale rende i test
/// non deterministici e impedisce di asserire su valori precisi. Qui in più
/// c'è un motivo di dominio — l'id dell'ordine è la chiave di idempotenza,
/// quindi vale la pena poterlo controllare nei test.
abstract interface class IdGenerator {
  String next();
}

class UuidGenerator implements IdGenerator {
  const UuidGenerator([this._uuid = const Uuid()]);

  final Uuid _uuid;

  @override
  String next() => _uuid.v4();
}

/// Generatore sequenziale, per i test: `id-1`, `id-2`, ...
class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator({this.prefix = 'id'});

  final String prefix;
  int _counter = 0;

  @override
  String next() => '$prefix-${++_counter}';
}
