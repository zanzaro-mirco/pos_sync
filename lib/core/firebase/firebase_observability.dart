import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../observability.dart';
import 'analytics_metrics.dart';
import 'crashlytics_logger.dart';
import 'remote_config_flags.dart';

/// Accende Firebase, se può, e restituisce cosa è riuscito ad accendere.
///
/// Due casi in cui non può, e nessuno dei due è un errore:
///
/// - **non Android.** La build per Windows fa da cassa in rete locale, e
///   Crashlytics e Analytics su Windows non esistono. Remote Config sì, ma
///   attraverso l'SDK C++ per desktop, che Google dichiara adatto allo
///   sviluppo e non alla produzione;
/// - **manca `google-services.json`**, che non è nel repository. Senza, Gradle
///   non applica i plugin e `initializeApp` fallisce.
///
/// In entrambi l'app parte uguale, con [Observability.off].
///
/// [background] per il lavoro di sistema, che gira in un motore a parte:
/// registra crash e metriche, e legge i flag dall'ultimo valore salvato invece
/// di chiederli al cloud.
Future<Observability> startObservability({bool background = false}) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return Observability.off;
  }

  try {
    await Firebase.initializeApp();
  } on Exception catch (error) {
    debugPrint('[pos_sync] Firebase non configurato, osservabilità spenta: '
        '$error');
    return Observability.off;
  }

  final FirebaseCrashlytics crashlytics = FirebaseCrashlytics.instance;
  // In debug no: i crash di chi sta scrivendo il codice finirebbero nello
  // stesso grafico di quelli dei tablet in sala, e il grafico smetterebbe di
  // dire qualcosa sul rilascio.
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  _reportUncaughtErrors(crashlytics);

  final CrashlyticsLogger logger = CrashlyticsLogger(crashlytics);
  final RemoteConfigFlags flags =
      RemoteConfigFlags(FirebaseRemoteConfig.instance, logger: logger);
  await flags.start(fromCloud: !background);

  return Observability(
    logger: logger,
    flags: flags,
    metrics: AnalyticsMetrics(FirebaseAnalytics.instance),
  );
}

/// Le due strade da cui un errore esce senza che nessuno lo prenda.
///
/// `FlutterError.onError` per quelli dentro il framework — un widget che non
/// si disegna. `PlatformDispatcher.onError` per tutti gli altri: un `Future`
/// fallito che nessuno attendeva, cioè il caso tipico di un bug in una
/// sincronizzazione partita da un evento. Senza la seconda, Crashlytics
/// vedrebbe solo i crash dell'interfaccia.
void _reportUncaughtErrors(FirebaseCrashlytics crashlytics) {
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}
