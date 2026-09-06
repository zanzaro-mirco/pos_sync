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
import 'package:pos_sync/features/orders/sync/sync_worker.dart';
import 'package:pos_sync/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Una porta diversa da quella di esercizio, e non e' pignoleria.
  ///
  /// `HttpServer.bind` usa `shared: true`, quindi legare una porta gia' presa
  /// **riesce** e le richieste si dividono fra i due ascoltatori. Se sulla
  /// stessa macchina girasse l'app vera in modalita' cassa, questi test
  /// potrebbero parlare con lei invece che con l'istanza in prova: passerebbero
  /// per la ragione sbagliata, che e' peggio di fallire.
  const int portaDiProva = 53171;

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

  /// Chiude tutto come farebbe l'uscita dall'app, e riapre.
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
    // Smontare l'albero **prima** di chiudere non e' pulizia: e' la sostanza
    // del riavvio. Ripompando lo stesso widget radice, Flutter lo riconosce e
    // riusa gli elementi — `BlocProvider.create` non viene richiamato e il
    // cubit vecchio sopravvive, con dentro il repository di prima. Il test
    // misurerebbe la memoria invece del file, e passerebbe anche con una base
    // dati volatile: verificato togliendo questa riga.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await shutdown();
    await launch(tester);
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

    await tester.tap(find.byKey(const Key('add-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table-number-confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(OrderTile), findsOneWidget);

    await restart(tester);

    expect(
      find.byType(OrderTile),
      findsOneWidget,
      reason: 'la sorgente di verità è il file, non la memoria',
    );
  });

  testWidgets('svuotare gli ordini sopravvive al riavvio',
      (WidgetTester tester) async {
    // Cancellare dalla memoria e cancellare dal file sono due cose diverse, e
    // solo qui si vede la differenza.
    await launch(tester);
    await tester.tap(find.byKey(const Key('add-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table-number-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(OrderTile), findsOneWidget);

    await tester.tap(find.byKey(const Key('overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-orders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-confirm')));
    await tester.pumpAndSettle();

    await restart(tester);

    expect(find.byKey(const Key('empty-text')), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('add-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table-number-confirm')));
    await tester.pumpAndSettle();
    // La sincronizzazione porta l'ordine nel registro che il server espone.
    await sl<SyncWorker>().drain();

    final HttpRemoteApi visitatore = HttpRemoteApi(
      host: '127.0.0.1',
      port: portaDiProva,
      deviceId: 'tablet-di-prova',
    );
    addTearDown(visitatore.close);

    expect(
      await visitatore.primaryDeviceId(),
      isNotNull,
      reason: 'la cassa deve dire chi è, non solo accettare la connessione',
    );

    final List<Order> visti = await visitatore.fetchOrders();
    expect(visti, hasLength(1));
    expect(visti.single.tableNumber, isPositive);
  });

  testWidgets('la prova del collegamento riferisce chi ha scritto al registro',
      (WidgetTester tester) async {
    // La diagnostica messa alla prova su socket veri: quello che si legge
    // nelle impostazioni deve corrispondere a ciò che è successo davvero.
    await launch(tester);
    await sl<PeerSettingsStore>().save(
      const PeerSettings(role: PeerRole.primary, primaryPort: portaDiProva),
    );

    final LanCheck prima = await sl<LanChecker>()
        .check(const PeerSettings(role: PeerRole.primary));
    expect(prima.senders, isEmpty);

    final HttpRemoteApi cameriere = HttpRemoteApi(
      host: '127.0.0.1',
      port: portaDiProva,
      deviceId: 'tablet-in-sala',
    );
    addTearDown(cameriere.close);

    await tester.tap(find.byKey(const Key('add-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table-number-confirm')));
    await tester.pumpAndSettle();
    // Esplicito e non affidato alla sincronizzazione automatica: quella parte
    // senza essere attesa, e un test che ci contasse fallirebbe a caso.
    await sl<SyncWorker>().drain();

    final List<Order> miei = await cameriere.fetchOrders();
    await cameriere.submitOrder(miei.single);

    final LanCheck dopo = await sl<LanChecker>()
        .check(const PeerSettings(role: PeerRole.primary));
    expect(dopo.senders, contains('tablet-in-sala'));
  });
}
