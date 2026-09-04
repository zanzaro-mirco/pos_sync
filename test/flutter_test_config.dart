import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Configurazione applicata a tutta la suite: `flutter test` chiama questo file
/// prima di ogni `main()` che trova sotto `test/`.
///
/// Esiste per una ragione sola, i golden test. Senza font registrati, nei test
/// Flutter ripiega su un carattere segnaposto: il testo diventa una fila di
/// rettangoli e le icone dei quadrati vuoti. I riferimenti resterebbero
/// deterministici — e il colore si vedrebbe lo stesso — ma sarebbero immagini
/// che nessuno può guardare per capire se un cambiamento è quello voluto, ed è
/// esattamente ciò che un golden dovrebbe permettere di fare.
///
/// I font vengono dall'SDK, non dal repository: sono gli stessi che l'app usa
/// davvero e non aggiungono un megabyte e mezzo di binari da versionare. Il
/// prezzo è che devono *esserci*: `flutter test` da solo non li scarica, perché
/// senza questo file non gli servirebbero. La pipeline chiama `flutter precache`
/// prima dei test per questo motivo.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _registra('MaterialIcons', 'materialicons-regular.otf');
  await _registra('Roboto', 'roboto-regular.ttf');
  return testMain();
}

Future<void> _registra(String famiglia, String nomeFile) async {
  final File file = _trova(nomeFile);
  final FontLoader loader = FontLoader(famiglia)
    ..addFont(
      Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
    );
  await loader.load();
}

File _trova(String nomeFile) {
  final String? radice = Platform.environment['FLUTTER_ROOT'];
  if (radice == null) {
    throw StateError(
      'FLUTTER_ROOT non è impostata: i font della suite non sono '
      'raggiungibili. Eseguire i test con `flutter test`, non con `dart test`.',
    );
  }

  final Directory cartella =
      Directory('$radice/bin/cache/artifacts/material_fonts');
  if (!cartella.existsSync()) {
    throw StateError(
      'Cartella dei font assente: ${cartella.path}\n'
      'Gli artefatti dell SDK si scaricano su richiesta: eseguire '
      '`flutter precache` prima dei test.',
    );
  }

  // Confronto senza distinzione di maiuscole: il nome dei file dentro
  // l'artefatto è cambiato fra le versioni dell'SDK, e su Windows la
  // differenza non si nota finché non si esegue la suite su Linux.
  final List<File> file = cartella
      .listSync()
      .whereType<File>()
      .where((File f) =>
          f.uri.pathSegments.last.toLowerCase() == nomeFile.toLowerCase())
      .toList();

  if (file.isEmpty) {
    // L'elenco nel messaggio non è verbosità: se questo scatta, scatta su una
    // macchina a cui non si ha accesso, e la sola cosa utile è sapere cosa c'è
    // davvero in quella cartella.
    final String presenti = cartella
        .listSync()
        .map((FileSystemEntity e) => e.uri.pathSegments.last)
        .join(', ');
    throw StateError(
      'Font "$nomeFile" non trovato in ${cartella.path}\nPresenti: $presenti',
    );
  }

  return file.first;
}
