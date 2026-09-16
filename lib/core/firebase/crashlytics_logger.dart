import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../logger.dart';

/// Il logger che manda i messaggi a Crashlytics.
///
/// Era la ragione dichiarata dell'interfaccia `Logger` fin dal primo giorno, e
/// collegarlo non ha toccato nessuna delle classi che registrano qualcosa.
///
/// **Un avviso diventa un errore da contare solo se porta con sé un errore.**
/// Gli avvisi senza — un conflitto sul tavolo, un annuncio in rete non
/// riuscito — descrivono il sistema che fa il suo lavoro in condizioni
/// difficili, e restano come contesto. Con un errore allegato — un ordine
/// abbandonato, un drenaggio fallito — sono il genere di cosa che dopo un
/// rilascio deve comparire in un grafico, anche se l'app non è caduta.
class CrashlyticsLogger implements Logger {
  const CrashlyticsLogger(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  /// Resta nel registro breve che Crashlytics allega al prossimo errore: è
  /// ciò che dice cosa stava facendo il tablet quando è successo.
  @override
  void info(String message) => _crashlytics.log(message);

  @override
  void warning(String message, [Object? error]) {
    _crashlytics.log('AVVISO $message');
    if (error == null) return;
    _crashlytics.recordError(
      error,
      StackTrace.current,
      reason: message,
      fatal: false,
    );
  }
}
