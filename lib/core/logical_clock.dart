import '../features/orders/domain/revision.dart';

/// Deposito dell'identità del dispositivo e del suo contatore logico.
///
/// Separato dall'orologio per la stessa ragione per cui il deposito degli
/// ordini è separato dal repository: *dove* si scrive il contatore non è
/// compito di chi sa *come* si conta.
abstract interface class LogicalClockStore {
  /// Identificativo di questo dispositivo, creandolo alla prima chiamata.
  Future<String> loadDeviceId();

  Future<int> loadCounter();
  Future<void> saveCounter(int counter);
}

/// Orologio logico di Lamport.
///
/// Due sole operazioni, e sono quelle che rendono confrontabili modifiche fatte
/// da dispositivi che non si parlano:
///
/// - [tick] prima di ogni modifica locale: il contatore avanza di uno;
/// - [witness] su ogni revisione che arriva da fuori: il contatore sale almeno
///   a quello visto, così la prossima modifica locale risulterà successiva a
///   tutto ciò che il dispositivo ha già visto.
///
/// È il secondo passo a fare il lavoro. Senza, due dispositivi conterebbero per
/// conto proprio e chi ha lavorato di più vincerebbe sempre, a prescindere da
/// chi ha modificato per ultimo.
abstract interface class LogicalClock {
  /// Avanza e restituisce la revisione da apporre a una modifica locale.
  Future<Revision> tick();

  /// Prende atto di una revisione vista altrove.
  Future<void> witness(Revision seen);
}

class LamportClock implements LogicalClock {
  LamportClock(this._store);

  final LogicalClockStore _store;

  String _deviceId = '';
  int _counter = 0;
  bool _caricato = false;

  /// Contatore corrente, per i test e per la diagnostica.
  int get counter => _counter;

  @override
  Future<Revision> tick() async {
    await _carica();
    _counter++;
    // Persistito *prima* di restituire la revisione. Se dopo un riavvio il
    // contatore ripartisse da un valore già usato, due modifiche diverse dello
    // stesso dispositivo porterebbero la stessa revisione e l'ordine totale
    // smetterebbe di essere tale.
    await _store.saveCounter(_counter);
    return Revision(counter: _counter, deviceId: _deviceId);
  }

  @override
  Future<void> witness(Revision seen) async {
    await _carica();
    if (seen.counter <= _counter) return;
    _counter = seen.counter;
    await _store.saveCounter(_counter);
  }

  /// Legge identità e contatore alla prima occasione utile.
  ///
  /// Pigro di proposito: la composition root resta sincrona, e un dispositivo
  /// che non modifica niente non apre la base dati per sapere come si chiama.
  Future<void> _carica() async {
    if (_caricato) return;
    _deviceId = await _store.loadDeviceId();
    _counter = await _store.loadCounter();
    _caricato = true;
  }
}

/// Deposito in memoria, per i test e per la modalità demo.
class InMemoryLogicalClockStore implements LogicalClockStore {
  InMemoryLogicalClockStore({this.deviceId = 'dispositivo-1', int counter = 0})
      : _counter = counter;

  final String deviceId;
  int _counter;

  int get counter => _counter;

  @override
  Future<String> loadDeviceId() async => deviceId;

  @override
  Future<int> loadCounter() async => _counter;

  @override
  Future<void> saveCounter(int counter) async => _counter = counter;
}
