import '../../../../core/id_generator.dart';
import '../../../../core/logical_clock.dart';
import 'app_database.dart';

/// Identità del dispositivo e contatore logico, su SQLite.
///
/// Classe a sé e non un metodo in più di `DriftOrderStore`: chi conta le
/// revisioni non ha niente a che vedere con chi salva gli ordini, e tenerli
/// insieme costringerebbe ogni doppio di test a implementare anche l'altro.
///
/// La riga è una sola, con chiave fissa a 1. L'identificativo si genera alla
/// prima apertura e non cambia più: è metà della revisione, e un dispositivo
/// che cambia nome a ogni avvio renderebbe l'ordine totale una finzione.
class DriftDeviceStore implements LogicalClockStore {
  DriftDeviceStore(this._db, {IdGenerator idGenerator = const UuidGenerator()})
      : _ids = idGenerator;

  static const int _singleRowId = 1;

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<String> loadDeviceId() async => (await _row()).deviceId;

  @override
  Future<int> loadCounter() async => (await _row()).counter;

  @override
  Future<void> saveCounter(int counter) async {
    final DeviceRow row = await _row();
    await _db
        .into(_db.deviceIdentity)
        .insertOnConflictUpdate(row.copyWith(counter: counter));
  }

  Future<DeviceRow> _row() => _db.transaction(() async {
        final DeviceRow? existing = await (_db.select(_db.deviceIdentity)
              ..where(($DeviceIdentityTable t) => t.id.equals(_singleRowId)))
            .getSingleOrNull();
        if (existing != null) return existing;

        final DeviceRow created = DeviceRow(
          id: _singleRowId,
          deviceId: _ids.next(),
          counter: 0,
          // Il ruolo in rete locale vive nella stessa riga ma non è affare di
          // questa classe: qui si scrivono i valori predefiniti e basta, e a
          // cambiarli ci pensa `DriftPeerSettings`.
          role: 'standalone',
          primaryHost: '',
          primaryPort: 53170,
        );
        await _db.into(_db.deviceIdentity).insert(created);
        return created;
      });
}
