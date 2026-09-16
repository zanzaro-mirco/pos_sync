import 'dart:async';

import '../../../core/feature_flags.dart';
import '../../../core/logger.dart';
import 'sync_worker.dart';

/// Fa girare la coda ogni volta che un flag cambia.
///
/// È ciò che fa entrare in vigore un flag **subito**: il coordinatore rilegge
/// l'interruttore della rete locale a ogni giro, ma un giro parte solo da un
/// ordine preso, da un comando o dalla rete che torna. Senza questo, la cassa
/// spenta da remoto continuerebbe a rispondere agli altri tablet fino al
/// prossimo ordine — cioè proprio mentre la si vuole fermare.
///
/// Stesso schema di `AutoSync`, e per la stessa ragione sta fuori dal worker:
/// *cosa* fa un giro e *quando* farlo cambiano per motivi diversi.
StreamSubscription<void> drainOnFlagChange({
  required FeatureFlags flags,
  required SyncWorker worker,
  Logger logger = const SilentLogger(),
}) =>
    flags.changes.listen((_) async {
      try {
        await worker.drain();
      } catch (error) {
        // Nessuno attende questo giro: un errore che ne uscisse arriverebbe a
        // Crashlytics come crash, invece che come l'avviso che è.
        logger.warning('Giro della coda dopo un cambio di flag fallito', error);
      }
    });
