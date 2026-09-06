/// L'app vera, sul dispositivo vero.
///
/// Widget test e golden girano sul motore di Flutter, non su un sistema
/// operativo: i canali di piattaforma non ci sono, il file su disco nemmeno, e
/// nessuna porta viene mai aperta davvero. Tutto ciò che sta **sotto** al
/// livello Dart — `path_provider` che restituisce una cartella scrivibile,
/// sqlite3 caricato dal sistema, un socket che si lega, il permesso di rete
/// dichiarato nel manifest — resta scoperto, e sono esattamente le cose che
/// falliscono sul dispositivo di qualcun altro.
///
/// Qui gira il grafo di produzione: `setUpDependencies` senza sostituzioni, la
/// stessa `PosSyncApp` di `main()`, la base dati sul filesystem del
/// dispositivo. Niente doppi, nemmeno per il tempo.
///
/// **Niente `pumpAndSettle` per aspettare un risultato.** Quel metodo aspetta
/// che non ci siano più frame in coda, non che le promesse siano risolte: una
/// scrittura su SQLite non produce frame finché non arriva in fondo. Su un
/// disco veloce la differenza non si vede, su un emulatore sì — ed è il motivo
/// per cui la prima versione di questi test passava in locale e falliva in
/// pipeline. Qui si aspetta la **condizione**, con `pumpUntil`.
///
/// **Come si esegue**
///
/// ```
/// flutter test integration_test                 # sul dispositivo collegato
/// flutter test integration_test -d windows      # sulla build desktop
/// ```
///
/// In CI gira su un emulatore Android, che è l'unico modo di far vedere a una
/// macchina senza schermo che l'app parte davvero.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pos_sync/core/di.dart';
import 'package:pos_sync/features/orders/data/demo_reset.dart';
import 'package:pos_sync/features/orders/data/local/app_database.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/lan/http_remote_api.dart';
import 'package:pos_sync/features/orders/lan/lan_check.dart';
import 'package:pos_sync/features/orders/lan/lan_coordinator.dart';
import 'package:pos_sync/features/orders/lan/peer_settings.dart';
import 'package:pos_sync/features/orders/presentation/order_tile.dart';
import 'package:pos_sync/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Una porta diversa da quella di esercizio, e non è pignoleria.
  ///
  /// `HttpServer.bind` usa `shared: true`, quindi legare una porta già presa
  /// **riesce** e le richieste si dividono fra i due ascoltatori. Se sulla
  /// stessa macchina girasse l'app vera in modalità cassa, questi test
  /// potrebbero parlare con lei invece che con l'istanza in prova: passerebbero
  /// per la ragione sbagliata, che è peggio di fallire.
  const int portaDiProva = 53171;

  /// Pompa finché [condizione] non è vera, e fallisce dicendo cosa aspettava.
  ///
  /// È la differenza fra «l'interfaccia si è fermata» e «il lavoro è finito».
  /// Il tempo massimo è largo di proposito: su un emulatore la prima scrittura
  /// paga il caricamento della libreria nativa, e un limite stretto
  /// trasformerebbe questi test in una misura della velocità della macchina.
  Future<void> pumpUntil(
    WidgetTester tester,
    FutureOr<bool> Function() condizione, {
    required String aspettando,
    Duration entro = const Duration(seconds: 30),
  }) async {
    final DateTime limite = DateTime.now().add(entro);
    while (DateTime.now().isBefore(limite)) {
      if (await condizione()) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('$aspettando — non è successo entro $entro');
  }

  /// Monta l'applicazione come farebbe `main()`.
  ///
  /// `pumpWidget` invece di `runApp` per una ragione sola: il test deve poter
  /// decidere quando avanzano i frame. Tutto il resto — registrazioni, servizi
  /// di sfondo, widget radice — è quello di produzione.
  Future<void> launch(WidgetTester tester) async {
    setUpDependencies();
    startBackgroundServices();
    await tester.pumpWidget(const PosSyncApp());
    await tester.pumpAndSettle();
  }

  /// Chiude tutto come farebbe l'uscita dall'app.
  ///
  /// La base dati va chiusa **prima** di dimenticare le registrazioni:
  /// lasciarne aperte due sullo stesso file significherebbe misurare il
  /// comportamento di SQLite sotto due connessioni invece che quello dell'app.
  /// Per la stessa ragione il coordinatore va fermato: un server ancora in
  /// ascolto terrebbe occupata la porta al riavvio.
  Future<void> shutdown() async {
    if (sl.isRegistered<LanCoordinator>()) await sl<LanCoordinator>().dispose();
    if (sl.isRegistered<AppDatabase>()) await sl<AppDatabase>().close();
    await sl.reset();
  }

  /// Riapre l'app sullo stesso file: è la simulazione più vicina a chiudere e
  /// riaprire che un test possa fare senza uscire dal processo.
  Future<void> restart(WidgetTester tester) async {
    // Smontare l'albero **prima** di chiudere non è pulizia: è la sostanza del
    // riavvio. Ripompando lo stesso widget radice, Flutter lo riconosce e riusa
    // gli elementi — `BlocProvider.create` non viene richiamato e il cubit
    // vecchio sopravvive, con dentro il repository di prima. Il test
    // misurerebbe la memoria invece del file, e passerebbe anche con una base
    // dati volatile: verificato togliendo questa riga.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // Creare un ordine avvia una sincronizzazione che nessuno attende. Chiudere
    // la base dati mentre quella la sta interrogando produce un errore dopo la
    // fine del test: vero, ma senza colpa dell'app — è il test che le toglie il
    // tavolo da sotto.
    await tester.pump(const Duration(milliseconds: 500));

    await shutdown();
    await launch(tester);
  }

  /// Crea un ordine dall'interfaccia e aspetta di vederlo in lista.
  Future<void> creaOrdine(WidgetTester tester) async {
    final int prima = find.byType(OrderTile).evaluate().length;

    await tester.tap(find.byKey(const Key('add-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table-number-confirm')));

    await pumpUntil(
      tester,
      () => find.byType(OrderTile).evaluate().length > prima,
      aspettando: "l'ordine appena creato compare in lista",
    );
  }

  setUp(() async {
    // Il file sul dispositivo sopravvive fra un test e l'altro — è il
    // comportamento giusto dell'app e scomodo qui. Si parte sempre da vuoto,
    // usando la stessa azione che l'interfaccia offre.
    setUpDependencies();
    await sl<DemoReset>().clearEverything();
    await sl<PeerSettingsStore>().save(const PeerSettings());
    await shutdown();
  });

  tearDown(shutdown);

  testWidgets('l app parte, crea un ordine e lo ritrova dopo un riavvio',
      (WidgetTester tester) async {
    // Il giro che nessun altro test copre per intero: `path_provider` deve
    // restituire una cartella scrivibile, sqlite3 deve caricarsi dal sistema,
    // e lo schema deve arrivare alla versione corrente su un file nuovo.
    await launch(tester);
    expect(find.byKey(const Key('empty-text')), findsOneWidget);

    await creaOrdine(tester);
    await restart(tester);

    await pumpUntil(
      tester,
      () => find.byType(OrderTile).evaluate().isNotEmpty,
      aspettando: "l'ordine si ritrova dopo il riavvio, perché sta nel file",
    );
  });

  testWidgets('svuotare gli ordini sopravvive al riavvio',
      (WidgetTester tester) async {
    // Cancellare dalla memoria e cancellare dal file sono due cose diverse, e
    // solo qui si vede la differenza.
    await launch(tester);
    await creaOrdine(tester);

    await tester.tap(find.byKey(const Key('overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-orders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-confirm')));

    await pumpUntil(
      tester,
      () => find.byType(OrderTile).evaluate().isEmpty,
      aspettando: 'la lista si svuota',
    );

    await restart(tester);

    await pumpUntil(
      tester,
      () => find.byKey(const Key('empty-text')).evaluate().isNotEmpty,
      aspettando: 'dopo il riavvio la lista è ancora vuota',
    );
  });

  testWidgets('da cassa apre davvero una porta, e risponde a chi bussa',
      (WidgetTester tester) async {
    // Su Android questo passa dal permesso INTERNET dichiarato nel manifest:
    // un test sul motore di Flutter non lo attraverserebbe mai, e la mancanza
    // si scoprirebbe sul dispositivo di un cliente.
    await launch(tester);
    await sl<PeerSettingsStore>().save(
      const PeerSettings(role: PeerRole.primary, primaryPort: portaDiProva),
    );

    await creaOrdine(tester);

    final HttpRemoteApi visitatore = HttpRemoteApi(
      host: '127.0.0.1',
      port: portaDiProva,
      deviceId: 'tablet-di-prova',
    );
    addTearDown(visitatore.close);

    // Si aspetta che risponda invece di chiederlo una volta sola. Il server si
    // accende alla prima sincronizzazione, e quella parte da sé quando l'ordine
    // viene creato: un `drain()` esplicito qui non aiuterebbe, perché la
    // guardia di concorrenza del worker lo farebbe uscire subito trovandone uno
    // già in corso. È il difetto che ha fatto fallire questo test in pipeline
    // mentre passava in locale.
    await pumpUntil(
      tester,
      () async => await visitatore.primaryDeviceId() != null,
      aspettando: 'la cassa apre la porta e dice chi è',
    );

    await pumpUntil(
      tester,
      () async => (await visitatore.fetchOrders()).isNotEmpty,
      aspettando: "l'ordine arriva a chi lo chiede da fuori",
    );

    final List<Order> visti = await visitatore.fetchOrders();
    expect(visti, hasLength(1));
    expect(visti.single.tableNumber, isPositive);
  });

  testWidgets('la prova del collegamento riferisce chi ha scritto al registro',
      (WidgetTester tester) async {
    // La diagnostica messa alla prova su socket veri: quello che si legge nelle
    // impostazioni deve corrispondere a ciò che è successo davvero.
    const PeerSettings daCassa =
        PeerSettings(role: PeerRole.primary, primaryPort: portaDiProva);

    await launch(tester);
    await sl<PeerSettingsStore>().save(daCassa);

    final LanCheck prima = await sl<LanChecker>().check(daCassa);
    expect(prima.senders, isEmpty);

    final HttpRemoteApi cameriere = HttpRemoteApi(
      host: '127.0.0.1',
      port: portaDiProva,
      deviceId: 'tablet-in-sala',
    );
    addTearDown(cameriere.close);

    await creaOrdine(tester);
    await pumpUntil(
      tester,
      () async => (await cameriere.fetchOrders()).isNotEmpty,
      aspettando: 'la cassa ha di che rispondere',
    );

    final List<Order> miei = await cameriere.fetchOrders();
    await cameriere.submitOrder(miei.single);

    final LanCheck dopo = await sl<LanChecker>().check(daCassa);
    expect(dopo.senders, contains('tablet-in-sala'));
  });
}
