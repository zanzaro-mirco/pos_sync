import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../features/orders/data/local/app_database.dart';
import '../features/orders/sync/sync_worker.dart';
import 'di.dart';

/// Nome con cui Android conosce il lavoro periodico.
///
/// Deve restare stabile: è la chiave con cui WorkManager riconosce un lavoro
/// già pianificato invece di accumularne uno nuovo a ogni avvio.
const String periodicDrainTask = 'pos-sync-drenaggio-coda';

/// Intervallo minimo concesso da Android ai lavori periodici. Chiederne uno più
/// corto non produce un errore: il sistema lo allunga in silenzio.
const Duration _androidMinimumFrequency = Duration(minutes: 15);

/// Pianifica il drenaggio della coda anche ad applicazione chiusa.
///
/// [AutoSync] copre il caso in cui l'app è aperta e la rete torna. Questo copre
/// l'altro: il cameriere chiude l'app in una sala senza campo e la riapre solo
/// il giorno dopo. Senza un lavoro di sistema, quegli ordini restano fermi.
///
/// Il vincolo di rete è ciò che rende il lavoro economico: Android non sveglia
/// il processo finché non c'è connettività, quindi non si paga un risveglio per
/// scoprire di non poter fare niente.
Future<void> scheduleBackgroundDrain() async {
  // Solo Android. Su iOS il modello è diverso (BGTaskScheduler decide *se*
  // eseguire, non *quando*) e prometterlo senza averlo verificato su un
  // dispositivo Apple sarebbe una dichiarazione non sostenuta.
  if (defaultTargetPlatform != TargetPlatform.android) return;

  await Workmanager().initialize(backgroundEntryPoint);
  await Workmanager().registerPeriodicTask(
    periodicDrainTask,
    periodicDrainTask,
    frequency: _androidMinimumFrequency,
    constraints: Constraints(networkType: NetworkType.connected),
    // `update` invece di `keep`: se domani cambia la frequenza, `keep`
    // lascerebbe girare per sempre quella registrata la prima volta.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// Punto di ingresso del lavoro in background.
///
/// Android lo invoca in un motore Flutter separato, senza interfaccia: qui non
/// esiste niente di ciò che `main()` ha costruito, e il grafo delle dipendenze
/// va montato da capo. È anche il motivo dell'annotazione — senza, il
/// compilatore AOT eliminerebbe una funzione che nessuno chiama dal codice
/// Dart.
@pragma('vm:entry-point')
void backgroundEntryPoint() {
  Workmanager().executeTask((String task, Map<String, Object?>? inputData) {
    return _drainQueue();
  });
}

Future<bool> _drainQueue() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Quando l'app è viva il lavoro può essere eseguito nel suo stesso processo,
  // dove il grafo esiste già: registrarlo di nuovo solleverebbe un'eccezione, e
  // chiudere il database sotto i piedi dell'interfaccia sarebbe peggio.
  final bool ownsGraph = !sl.isRegistered<SyncWorker>();
  if (ownsGraph) setUpDependencies();

  try {
    final SyncResult outcome = await sl<SyncWorker>().drain();
    // Un ordine abbandonato in modo definitivo non è un fallimento del lavoro:
    // la decisione è già stata presa dalla politica di ritentativo, e dire
    // "riprova" ad Android farebbe ripetere un drenaggio che non ha più niente
    // da mandare.
    debugPrint('[pos_sync] drenaggio in background: $outcome');
    return true;
  } catch (error) {
    // `false` chiede ad Android di riprovare secondo la propria politica di
    // backoff — quella di sistema, che tiene conto anche della batteria.
    debugPrint('[pos_sync] drenaggio in background fallito: $error');
    return false;
  } finally {
    // Il file va chiuso: il motore in background può sopravvivere al lavoro, e
    // una connessione aperta terrebbe il blocco su un database che l'app vuole
    // riaprire. Se il grafo non era nostro non è nostro nemmeno il database.
    if (ownsGraph) {
      await sl<AppDatabase>().close();
      await sl.reset();
    }
  }
}
