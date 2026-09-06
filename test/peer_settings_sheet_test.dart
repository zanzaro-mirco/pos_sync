/// Il foglio con cui si sceglie che parte fa questo dispositivo.
///
/// È l'unico punto in cui la rete locale si configura col dito, e senza di
/// esso tutto il resto della voce 2.5 resterebbe raggiungibile solo dai test —
/// lo stesso difetto che i conflitti avevano prima di `SecondDevice`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/lan/lan_check.dart';
import 'package:pos_sync/features/orders/lan/peer_discovery.dart';
import 'package:pos_sync/features/orders/lan/lan_protocol.dart';
import 'package:pos_sync/features/orders/lan/peer_settings.dart';
import 'package:pos_sync/features/orders/presentation/peer_settings_sheet.dart';

void main() {
  /// Monta il foglio e raccoglie ciò che viene salvato.
  Future<List<PeerSettings>> show(
    WidgetTester tester, {
    PeerSettings initial = const PeerSettings(),
    List<String> addresses = const <String>[],
    Future<LanCheck> Function(PeerSettings)? onCheck,
  }) async {
    final List<PeerSettings> saved = <PeerSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: Scaffold(
          body: PeerSettingsSheet(
            initial: initial,
            localAddresses: addresses,
            onSave: saved.add,
            onCheck: onCheck,
          ),
        ),
      ),
    );
    return saved;
  }

  testWidgets('le tre scelte dicono cosa comportano, non come si chiamano',
      (WidgetTester tester) async {
    // «Primario» richiede di sapere già come funziona il sistema; «questo
    // dispositivo è la cassa» dice a chi installa l'app dove va il tablet.
    await show(tester);

    expect(find.text('Questo dispositivo è la cassa'), findsOneWidget);
    expect(find.text('Questo dispositivo è in sala'), findsOneWidget);
    expect(find.text('Nessuna rete locale'), findsOneWidget);
  });

  testWidgets("l'indirizzo si chiede solo a chi ne ha bisogno",
      (WidgetTester tester) async {
    // Un campo sempre presente e quasi sempre da ignorare è un invito a
    // compilarlo per sbaglio.
    await show(tester);
    expect(find.byKey(const Key('peer-host-field')), findsNothing);

    await tester.tap(find.byKey(const Key('peer-role-follower')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('peer-host-field')), findsOneWidget);
  });

  testWidgets('la porta non si digita in nessun ruolo',
      (WidgetTester tester) async {
    // Vale `lanPort` su entrambi i lati, quindi non c'è niente da concordare.
    // Chiederla darebbe solo il modo di scriverne una diversa su un tablet
    // solo, e il guasto si presenterebbe come «non arriva niente».
    final List<PeerSettings> saved = await show(tester);

    for (final PeerRole role in PeerRole.values) {
      await tester.tap(find.byKey(Key('peer-role-${peerRoleName(role)}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('peer-port-field')), findsNothing,
          reason: 'nessun ruolo deve poter cambiare la porta');
    }

    await tester.tap(find.byKey(const Key('peer-save')));
    await tester.pumpAndSettle();

    expect(saved.single.primaryPort, lanPort);
  });

  testWidgets('la cassa mostra il proprio indirizzo, che è quello da digitare',
      (WidgetTester tester) async {
    // Senza, configurare il secondo tablet vorrebbe dire uscire dall'app per
    // andare a cercare l'indirizzo nelle impostazioni di sistema.
    await show(tester, addresses: <String>['192.168.1.7']);
    expect(find.byKey(const Key('peer-own-address')), findsNothing);

    await tester.tap(find.byKey(const Key('peer-role-primary')));
    await tester.pumpAndSettle();

    expect(find.textContaining('192.168.1.7'), findsOneWidget);
  });

  testWidgets('salvare restituisce ruolo e indirizzo',
      (WidgetTester tester) async {
    final List<PeerSettings> saved = await show(tester);

    await tester.tap(find.byKey(const Key('peer-role-follower')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('peer-host-field')), ' 192.168.1.7 ');
    await tester.tap(find.byKey(const Key('peer-save')));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.role, PeerRole.follower);
    expect(saved.single.primaryHost, '192.168.1.7',
        reason: 'gli spazi intorno a un indirizzo copiato non devono contare');
  });

  testWidgets('una porta già impostata si riporta, non si riscrive',
      (WidgetTester tester) async {
    // Questo foglio non modifica la porta, ma nemmeno la azzera: riscriverla
    // con il valore predefinito cancellerebbe in silenzio l'unico caso in cui
    // è diversa.
    final List<PeerSettings> saved = await show(
      tester,
      initial: const PeerSettings(
        role: PeerRole.follower,
        primaryHost: '192.168.1.7',
        primaryPort: 6000,
      ),
    );

    await tester.tap(find.byKey(const Key('peer-save')));
    await tester.pumpAndSettle();

    expect(saved.single.primaryPort, 6000);
  });

  group('la prova del collegamento', () {
    testWidgets('non compare se questa build non ha niente da provare',
        (WidgetTester tester) async {
      await show(tester);
      expect(find.byKey(const Key('peer-check')), findsNothing);
    });

    testWidgets('riferisce chi ha risposto', (WidgetTester tester) async {
      // «Risponde qualcuno» non basta: dopo un'elezione all'indirizzo noto può
      // rispondere un dispositivo diverso.
      await show(
        tester,
        initial: const PeerSettings(
          role: PeerRole.follower,
          primaryHost: '192.168.1.7',
        ),
        onCheck: (PeerSettings s) async => const LanCheck(
          primary: 'tablet-cassa',
          address: PeerAddress(host: '192.168.1.7'),
        ),
      );

      await tester.tap(find.byKey(const Key('peer-check')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('tablet-cassa'),
        findsOneWidget,
        reason: 'chi risponde è metà della diagnosi',
      );
    });

    testWidgets('la prova usa ciò che è scritto adesso, non ciò che è salvato',
        (WidgetTester tester) async {
      // Chi sta configurando vuole sapere se funziona l'indirizzo che ha
      // appena digitato: provarne un altro sarebbe rispondere a un'altra
      // domanda.
      final List<PeerSettings> provate = <PeerSettings>[];
      await show(
        tester,
        initial: const PeerSettings(role: PeerRole.follower),
        onCheck: (PeerSettings s) async {
          provate.add(s);
          return const LanCheck(primary: 'x');
        },
      );

      await tester.enterText(
          find.byKey(const Key('peer-host-field')), '10.0.0.4');
      await tester.tap(find.byKey(const Key('peer-check')));
      await tester.pumpAndSettle();

      expect(provate.single.primaryHost, '10.0.0.4');
    });

    testWidgets('in cassa dice chi ha inviato ordini, non chi risponde',
        (WidgetTester tester) async {
      // Domanda diversa: una porta aperta dice che il servizio c'è, non che
      // qualcuno lo stia usando.
      await show(
        tester,
        initial: const PeerSettings(role: PeerRole.primary),
        onCheck: (PeerSettings s) async => const LanCheck(
          primary: 'io',
          senders: <String>['tablet-b'],
        ),
      );

      await tester.tap(find.byKey(const Key('peer-check')));
      await tester.pumpAndSettle();

      expect(find.textContaining('tablet-b'), findsOneWidget);
    });

    testWidgets('un problema si legge come tale', (WidgetTester tester) async {
      await show(
        tester,
        initial: const PeerSettings(role: PeerRole.follower),
        onCheck: (PeerSettings s) async =>
            const LanCheck(problem: 'Nessuna cassa trovata sulla rete.'),
      );

      await tester.tap(find.byKey(const Key('peer-check')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('peer-check-result')), findsOneWidget);
      expect(find.textContaining('Nessuna cassa'), findsOneWidget);
    });
  });

  testWidgets('annullare non salva niente', (WidgetTester tester) async {
    final List<PeerSettings> saved = await show(tester);

    await tester.tap(find.byKey(const Key('peer-role-primary')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('peer-cancel')));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
  });

  testWidgets('riaprendolo si ritrova la scelta di prima',
      (WidgetTester tester) async {
    await show(
      tester,
      initial: const PeerSettings(
        role: PeerRole.follower,
        primaryHost: '10.0.0.4',
        primaryPort: 6000,
      ),
    );

    expect(find.byKey(const Key('peer-host-field')), findsOneWidget,
        reason: 'il ruolo salvato decide cosa si vede all\'apertura');
    expect(find.text('10.0.0.4'), findsOneWidget);
  });
}
