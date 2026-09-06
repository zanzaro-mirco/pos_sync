import 'dart:async';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

import '../../../core/logger.dart';
import 'lan_protocol.dart';
import 'peer_discovery.dart';

/// La scoperta vera, sopra mDNS.
///
/// **Questo file non ha test, ed è deliberato.** `nsd` parla con il sistema
/// attraverso i canali di piattaforma, che in `flutter test` non esistono:
/// qualunque prova qui verificherebbe un simulacro. Per questo il file è
/// sottile fino alla noia — nessuna decisione, solo traduzione fra l'API del
/// pacchetto e [PeerDiscovery] — e tutto ciò che si può sbagliare sta nel
/// coordinatore, dove un falso di prova lo raggiunge.
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

  @override
  Future<void> advertise({
    required String deviceId,
    required int port,
  }) async {
    if (_registration != null) return;
    // Il nome è l'identificativo del dispositivo, lo stesso che `/health`
    // restituisce: così chi trova un servizio sa già con chi sta parlando,
    // senza doverglielo chiedere.
    _registration = await nsd.register(
      nsd.Service(name: deviceId, type: lanServiceType, port: port),
    );
    _logger.info('Annunciato come $lanServiceType sulla porta $port');
  }

  @override
  Future<void> stopAdvertising() async {
    final nsd.Registration? registration = _registration;
    _registration = null;
    if (registration != null) await nsd.unregister(registration);
  }

  @override
  Future<PeerAddress?> findPrimary() async {
    final nsd.Discovery discovery = await nsd.startDiscovery(
      lanServiceType,
      // Senza questo `addresses` resta vuoto e resterebbe solo il nome host,
      // che su una rete di locale non è detto si risolva.
      ipLookupType: nsd.IpLookupType.v4,
    );

    final Completer<PeerAddress?> found = Completer<PeerAddress?>();
    void onService(nsd.Service service, nsd.ServiceStatus status) {
      if (found.isCompleted || status != nsd.ServiceStatus.found) return;
      final PeerAddress? address = _toAddress(service);
      if (address != null) found.complete(address);
    }

    discovery.addServiceListener(onService);
    try {
      return await found.future.timeout(_timeout, onTimeout: () => null);
    } on nsd.NsdError catch (e) {
      // Il multicast può essere filtrato, o il servizio di sistema assente.
      // Non è un guasto dell'app: resta l'indirizzo manuale.
      _logger.warning('Scoperta non riuscita: $e');
      return null;
    } finally {
      discovery.removeServiceListener(onService);
      // Anche in caso di errore: una scoperta lasciata aperta tiene occupata
      // la radio, ed è la ragione per cui la documentazione di Android insiste
      // sul fermarla.
      await nsd.stopDiscovery(discovery);
    }
  }

  /// Il primo indirizzo IPv4 utilizzabile del servizio, se c'è.
  PeerAddress? _toAddress(nsd.Service service) {
    final int? port = service.port;
    if (port == null) return null;
    for (final InternetAddress address in service.addresses ?? const []) {
      if (address.type == InternetAddressType.IPv4) {
        return PeerAddress(host: address.address, port: port);
      }
    }
    return null;
  }
}
