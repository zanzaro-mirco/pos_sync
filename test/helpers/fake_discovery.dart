import 'package:pos_sync/features/orders/lan/peer_discovery.dart';

/// Una rete locale che risponde ciò che gli si dice.
///
/// La scoperta vera passa dai canali di piattaforma e in `flutter test` non
/// esiste: questo doppio è ciò che rende verificabile il comportamento del
/// coordinatore — cosa fa quando la cassa non si trova, quando cambia
/// indirizzo, quando l'annuncio fallisce.
class FakeDiscovery implements PeerDiscovery {
  FakeDiscovery({this.primary});

  /// Cosa c'è in rete, o `null` se non c'è nessuna cassa.
  PeerAddress? primary;

  /// Se annunciarsi deve fallire, come su una rete che filtra il multicast.
  bool failAdvertising = false;

  /// Quante volte è stata cercata una cassa. Serve a distinguere «ha usato
  /// l'indirizzo digitato» da «è andato a cercarlo».
  int lookups = 0;

  String? advertisedDevice;
  int? advertisedPort;

  @override
  Future<void> advertise({
    required String deviceId,
    required int port,
  }) async {
    if (failAdvertising) throw StateError('multicast filtrato');
    advertisedDevice = deviceId;
    advertisedPort = port;
  }

  @override
  Future<void> stopAdvertising() async {
    advertisedDevice = null;
    advertisedPort = null;
  }

  @override
  Future<PeerAddress?> findPrimary() async {
    lookups++;
    return primary;
  }
}
