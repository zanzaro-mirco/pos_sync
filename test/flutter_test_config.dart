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
/// davvero, e non aggiungono binari da versionare. In cambio la suite dipende
/// dalla versione di Flutter installata — motivo per cui la pipeline la fissa
/// invece di seguire il canale stabile.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _registra('MaterialIcons', 'materialicons-regular.otf');
  await _registra('Roboto', 'roboto-regular.ttf');
  return testMain();
}

Future<void> _registra(String famiglia, String nomeFile) async {
  final String? radice = Platform.environment['FLUTTER_ROOT'];
  if (radice == null) {
    throw StateError(
      'FLUTTER_ROOT non è impostata: i font della suite non sono '
      'raggiungibili. Eseguire i test con `flutter test`, non con `dart test`.',
    );
  }

  final File file = File(
    '$radice/bin/cache/artifacts/material_fonts/$nomeFile',
  );
  if (!file.existsSync()) {
    // Meglio fermarsi che proseguire in silenzio: senza il font i golden
    // fallirebbero tutti insieme, e il messaggio parlerebbe di pixel diversi
    // invece che del file mancante.
    throw StateError('Font non trovato: ${file.path}');
  }

  final FontLoader loader = FontLoader(famiglia)
    ..addFont(
      Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
    );
  await loader.load();
}
