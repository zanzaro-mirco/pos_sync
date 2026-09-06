import 'package:pos_sync/features/orders/lan/peer_discovery.dart';
import 'package:pos_sync/features/orders/lan/peer_settings.dart';

/// Una rete locale che risponde ciò che gli si dice.
///
/// La scoperta vera passa dai canali di piattaforma e in `flutter test` non
/// esiste: questo doppio è ciò che rende verificabile il comportamento del
/// coordinatore e dell'elezione — cosa fanno quando la cassa non si trova,
/// quando cambia indirizzo, quando l'annuncio fallisce, quando due tablet
/// potrebbero promuoversi insieme.
class FakeDiscovery implements PeerDiscovery {
  FakeDiscovery({this.primary, List<PeerNode>? nodes})
      : nodes = nodes ?? <PeerNode>[];

  /// Cosa c'è in rete, o `null` se non c'è nessuna cassa.
  PeerAddress? primary;

  /// Chi si annuncia, questo dispositivo escluso.
  List<PeerNode> nodes;

  /// Se annunciarsi deve fallire, come su una rete che filtra il multicast.
  bool failAdvertising = false;

  /// Quante volte è stata cercata una cassa. Serve a distinguere «ha usato
  /// l'indirizzo digitato» da «è andato a cercarlo».
  int lookups = 0;

  String? advertisedDevice;
  int? advertisedPort;
  PeerRole? advertisedRole;

  @override
  Future<void> advertise({
    required String deviceId,
    required int port,
    required PeerRole role,
  }) async {
    if (failAdvertising) throw StateError('multicast filtrato');
    advertisedDevice = deviceId;
    advertisedPort = port;
    advertisedRole = role;
  }

  @override
  Future<void> stopAdvertising() async {
    advertisedDevice = null;
    advertisedPort = null;
    advertisedRole = null;
  }

  @override
  Future<PeerAddress?> findPrimary() async {
    lookups++;
    return primary;
  }

  @override
  Future<List<PeerNode>> peers() async => nodes;
}

/// Un dispositivo che si annuncia, scritto in breve.
PeerNode node(
  String deviceId, {
  PeerRole role = PeerRole.follower,
  String host = '192.168.1.9',
}) =>
    PeerNode(
      deviceId: deviceId,
      address: PeerAddress(host: host),
      role: role,
    );
