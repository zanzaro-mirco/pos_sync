/// La finestra che chiede il numero del tavolo.
///
/// Esiste come file a sé per una ragione precisa: la prima versione viveva
/// dentro `main.dart`, dove nessun test la poteva raggiungere, e liberava il
/// suo `TextEditingController` con `whenComplete` sul futuro di `showDialog`.
/// Quel futuro si completa alla `pop`, mentre l'animazione di uscita sta ancora
/// ridisegnando il campo: sul dispositivo la build cadeva, in suite non se ne
/// accorgeva nessuno.
///
/// Da qui il test più importante del file, quello che aspetta che la finestra
/// finisca di chiudersi. Un widget test fallisce su qualunque eccezione
/// sollevata durante un fotogramma, quindi `pumpAndSettle` dopo la chiusura è
/// esattamente la rete che mancava.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/presentation/table_number_dialog.dart';

void main() {
  /// Monta un pulsante che apre la finestra e raccoglie ciò che restituisce.
  Future<List<int?>> apri(WidgetTester tester, {int proposto = 3}) async {
    final List<int?> risposte = <int?>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              key: const Key('apri'),
              onPressed: () async =>
                  risposte.add(await chiediNumeroTavolo(context, proposto)),
              child: const Text('apri'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('apri')));
    await tester.pumpAndSettle();
    return risposte;
  }

  testWidgets('propone il tavolo successivo, e confermarlo basta',
      (WidgetTester tester) async {
    final List<int?> risposte = await apri(tester, proposto: 3);

    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('table-number-confirm')));
    await tester.pumpAndSettle();

    expect(risposte, <int?>[3]);
  });

  testWidgets('si può ripetere un tavolo già aperto',
      (WidgetTester tester) async {
    // È il motivo per cui questa finestra esiste: con il numero incrementato
    // d'ufficio, due ordini sullo stesso tavolo non si potevano creare, e senza
    // quello non c'è niente da fondere e niente da mostrare.
    final List<int?> risposte = await apri(tester, proposto: 3);

    await tester.enterText(find.byKey(const Key('table-number-field')), '7');
    await tester.tap(find.byKey(const Key('table-number-confirm')));
    await tester.pumpAndSettle();

    expect(risposte, <int?>[7]);
  });

  testWidgets('annullare non crea niente', (WidgetTester tester) async {
    final List<int?> risposte = await apri(tester);

    await tester.tap(find.byKey(const Key('table-number-cancel')));
    await tester.pumpAndSettle();

    expect(risposte, <int?>[null]);
  });

  testWidgets('un campo vuoto non crea niente', (WidgetTester tester) async {
    // Meglio non fare niente che inventare un numero: creare il tavolo
    // proposto quando chi guarda ha appena cancellato il campo sarebbe la
    // risposta sbagliata alla domanda che ha appena posto.
    final List<int?> risposte = await apri(tester);

    await tester.enterText(find.byKey(const Key('table-number-field')), '');
    await tester.tap(find.byKey(const Key('table-number-confirm')));
    await tester.pumpAndSettle();

    expect(risposte, <int?>[null]);
  });

  testWidgets('confermare da tastiera equivale al pulsante',
      (WidgetTester tester) async {
    final List<int?> risposte = await apri(tester);

    await tester.enterText(find.byKey(const Key('table-number-field')), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(risposte, <int?>[12]);
  });

  testWidgets('la finestra si chiude fino in fondo senza cadere',
      (WidgetTester tester) async {
    // La regressione. `pumpAndSettle` porta a termine l'animazione di uscita:
    // se il campo dipendesse da qualcosa liberato alla `pop`, il fotogramma
    // successivo solleverebbe un'eccezione e questo test fallirebbe.
    await apri(tester);

    await tester.tap(find.byKey(const Key('table-number-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('table-number-field')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
