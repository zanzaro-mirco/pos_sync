/// Registrazione degli eventi applicativi.
///
/// Esiste perché `print` dentro una classe di produzione è un problema
/// concreto: non si può disattivare, non si può reindirizzare a Crashlytics e
/// nei test sporca l'output. Con un'interfaccia il worker resta ignaro di dove
/// finiscono i suoi messaggi.
abstract interface class Logger {
  void info(String message);
  void warning(String message, [Object? error]);
}

/// Non fa niente. Predefinito in produzione finché non si collega un logger
/// vero, e utile nei test per silenziare l'output.
class SilentLogger implements Logger {
  const SilentLogger();

  @override
  void info(String message) {}

  @override
  void warning(String message, [Object? error]) {}
}

/// Raccoglie i messaggi in memoria: permette di asserire su cosa è stato
/// registrato invece di ispezionare la console.
class InMemoryLogger implements Logger {
  final List<String> messages = <String>[];

  @override
  void info(String message) => messages.add('INFO $message');

  @override
  void warning(String message, [Object? error]) =>
      messages.add('WARN $message${error == null ? '' : ' ($error)'}');
}
