import '../../../core/logger.dart';
import 'peer_discovery.dart';
import 'peer_settings.dart';

/// Chi diventa la cassa quando la cassa non c'è più.
///
/// La regola è una sola, e riusa un ordine che nel sistema esiste già: si
/// promuove **il dispositivo con l'identificativo più basso** fra quelli che
/// si annunciano. È lo stesso confronto che rompe la parità fra due `Revision`
/// nella politica di fusione, applicato a una domanda diversa. Riusarlo non è
/// solo economia: significa che tutti i dispositivi calcolano lo stesso
/// risultato senza doversi mettere d'accordo, che è l'unica cosa che rende
/// un'elezione senza coordinatore possibile.
///
/// **Due condizioni prima di promuoversi**, ed entrambe servono:
///
/// 1. *Aver fallito [threshold] giri di seguito.* Un solo errore è una rete che
///    fa il suo mestiere; promuoversi al primo intoppo produrrebbe un cambio di
///    cassa a ogni pacchetto perso.
/// 2. *Che nessuno si annunci come cassa.* Se la cassa c'è e si dichiara, non
///    raggiungerla è un problema di questo tablet: sostituirla creerebbe un
///    secondo registro dove il guasto è la nostra rete.
///
/// **Lo split-brain resta possibile e va dichiarato.** Una rete che si spezza
/// in due tronconi produce due casse, una per troncone, perché ciascuna metà
/// vede solo sé stessa. È sopravvivibile grazie alla politica di fusione: le
/// righe si uniscono perché l'unione è commutativa, lo stato lo decide la
/// revisione più alta. Quando i due tronconi si ritrovano, gli ordini
/// convergono; ciò che si perde è l'ordine di arrivo, non il contenuto.
class PrimaryElection {
  PrimaryElection({
    required PeerDiscovery discovery,
    required PeerSettingsStore settings,
    required Future<String> Function() deviceId,
    this.threshold = 3,
    Logger logger = const SilentLogger(),
  })  : _discovery = discovery,
        _settings = settings,
        _deviceId = deviceId,
        _logger = logger;

  final PeerDiscovery _discovery;
  final PeerSettingsStore _settings;
  final Future<String> Function() _deviceId;
  final Logger _logger;

  /// Quanti giri falliti di seguito prima di considerare la cassa perduta.
  final int threshold;

  int _failures = 0;

  /// Quanti giri falliti si sono accumulati. Utile solo a leggere lo stato.
  int get failures => _failures;

  /// La cassa ha risposto: si riparte da zero.
  void succeeded() => _failures = 0;

  /// Un giro verso la cassa è fallito. Restituisce `true` se, come
  /// conseguenza, questo dispositivo si è promosso.
  Future<bool> failed() async {
    if (++_failures < threshold) return false;

    final List<PeerNode> nodes = await _discovery.peers();
    if (nodes.any((PeerNode n) => n.role == PeerRole.primary)) {
      _logger.info('Una cassa si annuncia ancora: non mi promuovo');
      return false;
    }

    final String me = await _deviceId();
    final List<String> candidates = <String>[
      me,
      for (final PeerNode n in nodes)
        if (n.role == PeerRole.follower) n.deviceId,
    ];
    candidates.sort();
    if (candidates.first != me) {
      _logger.info('Tocca a ${candidates.first}, non a me');
      return false;
    }

    // Il ruolo cambia, l'indirizzo digitato no: non è un dato di questo ruolo,
    // e cancellarlo butterebbe via una configurazione che qualcuno ha scritto
    // a mano, per un'elezione che potrebbe non essere definitiva.
    final PeerSettings current = await _settings.load();
    await _settings.save(current.copyWith(role: PeerRole.primary));
    _failures = 0;
    _logger.info('Nessuna cassa in rete: prendo io il registro ($me)');
    return true;
  }
}
