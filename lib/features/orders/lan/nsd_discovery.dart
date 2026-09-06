import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../../../core/logger.dart';
import 'lan_protocol.dart';
import 'peer_discovery.dart';
import 'peer_settings.dart';

/// La scoperta vera, sopra mDNS.
///
/// **Questo file non ha test, ed è deliberato.** `nsd` parla con il sistema
/// attraverso i canali di piattaforma, che in `flutter test` non esistono:
/// qualunque prova qui verificherebbe un simulacro. Per questo il file è
/// sottile fino alla noia — nessuna decisione, solo traduzione fra l'API del
/// pacchetto e [PeerDiscovery] — e tutto ciò che si può sbagliare sta nel
/// coordinatore e nell'elezione, dove un falso di prova li raggiunge.
class NsdDiscovery implements PeerDiscovery {
  NsdDiscovery({
    Duration timeout = const Duration(seconds: 3),
    Logger logger = const SilentLogger(),
  })  : _timeout = timeout,
        _logger = logger;

  /// Quanto si aspetta prima di dire «non l'ho trovata».
  ///
  /// Corto di proposito: chi apre le impostazioni sta guardando lo schermo, e
  /// la risposta «nessuna cassa in rete» è utile solo se arriva prima che
  /// rinunci. Se la cassa c'è, risponde in molto meno.
  final Duration _timeout;
  final Logger _logger;

  nsd.Registration? _registration;
  PeerRole? _advertisedRole;

  @override
  Future<void> advertise({
    required String deviceId,
    required int port,
    required PeerRole role,
  }) async {
    if (_registration != null && _advertisedRole == role) return;
    // Il ruolo cambia: si ritira l'annuncio vecchio prima di pubblicarne uno
    // nuovo, altrimenti sulla rete resterebbero due voci per lo stesso
    // dispositivo, una delle quali con il ruolo sbagliato.
    await stopAdvertising();

    // Il nome è l'identificativo del dispositivo, lo stesso che `/health`
    // restituisce: così chi trova un servizio sa già con chi sta parlando,
    // senza doverglielo chiedere.
    _registration = await nsd.register(
      nsd.Service(
        name: deviceId,
        type: lanServiceType,
        port: port,
        txt: <String, Uint8List?>{
          roleKey: Uint8List.fromList(utf8.encode(peerRoleName(role))),
        },
      ),
    );
    _advertisedRole = role;
    _logger.info('Annunciato come ${peerRoleName(role)} sulla porta $port');
  }

  @override
  Future<void> stopAdvertising() async {
    final nsd.Registration? registration = _registration;
    _registration = null;
    _advertisedRole = null;
    if (registration != null) await nsd.unregister(registration);
  }

  @override
  Future<PeerAddress?> findPrimary() async {
    final List<PeerNode> found = await _browse(
      stopAt: (PeerNode node) => node.role == PeerRole.primary,
    );
    for (final PeerNode node in found) {
      if (node.role == PeerRole.primary) return node.address;
    }
    return null;
  }

  @override
  Future<List<PeerNode>> peers() => _browse();

  /// Guarda chi c'è sulla rete per [_timeout], o finché [stopAt] è soddisfatta.
  ///
  /// La scorciatoia serve alla ricerca della cassa: aspettare comunque tre
  /// secondi quando la risposta è già arrivata è tempo tolto a chi guarda lo
  /// schermo. Il censimento per l'elezione invece aspetta tutto il tempo,
  /// perché lì la domanda è «chi c'è», e rispondere presto significherebbe
  /// rispondere con meno di quelli che ci sono.
  Future<List<PeerNode>> _browse({bool Function(PeerNode node)? stopAt}) async {
    final nsd.Discovery discovery = await nsd.startDiscovery(
      lanServiceType,
      // Senza questo `addresses` resta vuoto e resterebbe solo il nome host,
      // che su una rete di locale non è detto si risolva.
      ipLookupType: nsd.IpLookupType.v4,
    );

    final List<PeerNode> found = <PeerNode>[];
    final Completer<void> enough = Completer<void>();

    void onService(nsd.Service service, nsd.ServiceStatus status) {
      if (status != nsd.ServiceStatus.found) return;
      final PeerNode? node = _toNode(service);
      if (node == null) return;
      found.add(node);
      if (stopAt != null && stopAt(node) && !enough.isCompleted) {
        enough.complete();
      }
    }

    discovery.addServiceListener(onService);
    try {
      await enough.future.timeout(_timeout, onTimeout: () {});
      return found;
    } on nsd.NsdError catch (e) {
      // Il multicast può essere filtrato, o il servizio di sistema assente.
      // Non è un guasto dell'app: resta l'indirizzo manuale.
      _logger.warning('Scoperta non riuscita: $e');
      return const <PeerNode>[];
    } finally {
      discovery.removeServiceListener(onService);
      // Anche in caso di errore: una scoperta lasciata aperta tiene occupata
      // la radio, ed è la ragione per cui la documentazione di Android insiste
      // sul fermarla.
      await nsd.stopDiscovery(discovery);
    }
  }

  /// Il servizio tradotto, se ha tutto ciò che serve per parlarci.
  PeerNode? _toNode(nsd.Service service) {
    final String? name = service.name;
    final int? port = service.port;
    if (name == null || port == null) return null;

    for (final InternetAddress address in service.addresses ?? const []) {
      if (address.type != InternetAddressType.IPv4) continue;
      return PeerNode(
        deviceId: name,
        address: PeerAddress(host: address.address, port: port),
        role: _roleOf(service),
      );
    }
    return null;
  }

  /// Il ruolo dichiarato nel record TXT.
  ///
  /// Un annuncio senza ruolo leggibile vale `standalone`, cioè «non
  /// partecipa»: è la stessa scelta fatta per un ruolo sconosciuto letto da
  /// disco, e per la stessa ragione — meglio un dispositivo che non prende
  /// parte di uno che viene contato come qualcosa che non è.
  PeerRole _roleOf(nsd.Service service) {
    final Uint8List? raw = service.txt?[roleKey];
    if (raw == null) return PeerRole.standalone;
    try {
      return parsePeerRole(utf8.decode(raw));
    } on FormatException {
      return PeerRole.standalone;
    }
  }
}
