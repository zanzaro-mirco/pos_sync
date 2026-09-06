import '../../../../core/id_generator.dart';
import '../../lan/peer_settings.dart';
import 'app_database.dart';

/// Il ruolo in rete locale, su SQLite.
///
/// Condivide la riga con l'identità del dispositivo — è la stessa cassetta —
/// ma è una classe a sé: chi decide se questo tablet è la cassa non ha niente
/// a che vedere con chi conta le revisioni, e tenerli insieme costringerebbe
/// ogni doppio di test a implementare anche l'altro.
class DriftPeerSettings implements PeerSettingsStore {
  DriftPeerSettings(this._db, {IdGenerator idGenerator = const UuidGenerator()})
      : _ids = idGenerator;

  static const int _singleRowId = 1;

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<PeerSettings> load() async {
    final DeviceRow row = await _row();
    return PeerSettings(
      role: parsePeerRole(row.role),
      primaryHost: row.primaryHost,
      primaryPort: row.primaryPort,
    );
  }

  @override
  Future<void> save(PeerSettings settings) async {
    final DeviceRow row = await _row();
    await _db.into(_db.deviceIdentity).insertOnConflictUpdate(
          row.copyWith(
            role: peerRoleName(settings.role),
            primaryHost: settings.primaryHost,
            primaryPort: settings.primaryPort,
          ),
        );
  }

  /// La riga, creandola alla prima lettura.
  ///
  /// Duplica di proposito la logica di `DriftDeviceStore`: le due classi
  /// scrivono nella stessa riga ma non si conoscono, e farle dipendere l'una
  /// dall'altra per risparmiare otto righe legherebbe il ruolo in sala al
  /// contatore logico — due cose che cambiano per ragioni diverse.
  Future<DeviceRow> _row() => _db.transaction(() async {
        final DeviceRow? existing = await (_db.select(_db.deviceIdentity)
              ..where(($DeviceIdentityTable t) => t.id.equals(_singleRowId)))
            .getSingleOrNull();
        if (existing != null) return existing;

        final DeviceRow created = DeviceRow(
          id: _singleRowId,
          deviceId: _ids.next(),
          counter: 0,
          role: peerRoleName(PeerRole.standalone),
          primaryHost: '',
          primaryPort: const PeerSettings().primaryPort,
        );
        await _db.into(_db.deviceIdentity).insert(created);
        return created;
      });
}
