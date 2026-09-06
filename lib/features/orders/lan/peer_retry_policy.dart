import 'dart:math';

import '../data/remote_api.dart';
import '../sync/backoff.dart';
import '../sync/retry_policy.dart';
import 'lan_coordinator.dart';
import 'peer_settings.dart';

/// Quanto insistere quando dall'altra parte c'è un tablet e non un cloud.
///
/// Il budget predefinito — otto tentativi con un tetto di cinque minuti —
/// copre in tutto una decina di minuti, ed è tarato su un servizio remoto: se
/// non risponde per un quarto d'ora, è rotto.
///
/// In sala il ragionamento si rovescia. La cassa spenta per venti minuti non è
/// un guasto: è qualcuno che l'ha riavviata, o spostata, o messa in carica di
/// là. Rinunciare dopo dieci minuti significherebbe marcare come `failed`
/// ordini di tavoli ancora occupati — il modo più silenzioso di perdere una
/// comanda.
///
/// Insistere costa poco: nessuna bolletta, nessun consumo apprezzabile con un
/// tentativo al minuto, e un tablet nella stessa stanza che o risponde subito
/// o non c'è.
Backoff lanBackoff({Random? random}) => Backoff(
      // Tetto basso: appena la cassa torna deve essere ripresa in fretta,
      // non dopo l'attesa lunga maturata mentre era spenta.
      maxDelay: const Duration(minutes: 1),
      maxAttempts: 60,
      random: random,
    );

/// Sceglie il budget di ritentativi in base al ruolo corrente.
///
/// Esiste perché `RetryPolicy` era già una strategia sostituibile: non è
/// servito toccare il worker, che continua a chiedere «riprovo?» a un oggetto
/// senza sapere quale. È il genere di cosa che si scopre utile solo quando
/// arriva il secondo caso — e questo è il secondo caso.
///
/// La decisione è **sincrona**, e per questo legge il ruolo già noto al
/// coordinatore invece di andarselo a prendere: un ritentativo non può
/// aspettare una lettura da SQLite per decidere se aspettare.
class PeerAwareRetryPolicy implements RetryPolicy {
  PeerAwareRetryPolicy({
    required LanCoordinator coordinator,
    RetryPolicy? cloud,
    RetryPolicy? lan,
    Random? random,
  })  : _coordinator = coordinator,
        _cloud = cloud ?? BackoffRetryPolicy(),
        _lan = lan ?? BackoffRetryPolicy(backoff: lanBackoff(random: random));

  final LanCoordinator _coordinator;
  final RetryPolicy _cloud;
  final RetryPolicy _lan;

  @override
  RetryDecision decide({required ApiFailure failure, required int attempts}) =>
      switch (_coordinator.role) {
        PeerRole.standalone => _cloud.decide(
            failure: failure,
            attempts: attempts,
          ),
        PeerRole.primary || PeerRole.follower => _lan.decide(
            failure: failure,
            attempts: attempts,
          ),
      };
}
