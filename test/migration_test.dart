/// La migrazione dello schema, con dentro dei dati.
///
/// Su un tablet di sala la base dati contiene ordini che non sono ancora
/// arrivati al server: ricrearla per aggiungere tre colonne significherebbe
/// perderli. Questo file apre una base dati **scritta dalla versione
/// precedente**, la fa migrare e verifica che ci sia ancora tutto.
///
/// Fino alla versione 1 fra le semplificazioni consapevoli c'era scritto
/// «nessuna migrazione oltre la versione 1». Questa voce l'ha chiusa, e un
/// `onUpgrade` senza un test che lo esegua è una dichiarazione d'intenti.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:pos_sync/features/orders/data/local/app_database.dart';
import 'package:pos_sync/features/orders/data/local/drift_device_store.dart';
import 'package:pos_sync/features/orders/data/local/drift_order_store.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_conflict.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/outbox_entry.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';

/// Lo schema della versione 1, scritto a mano.
///
/// Copiato dalla forma che le tabelle avevano prima di questa voce, non
/// generato: un test di migrazione che si costruisse lo schema di partenza
/// dalle classi *attuali* verificherebbe che il codice di oggi è d'accordo con
/// sé stesso.
const List<String> _schemaV1 = <String>[
  '''
  CREATE TABLE orders (
    id TEXT NOT NULL,
    table_number INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    status TEXT NOT NULL,
    PRIMARY KEY (id)
  )''',
  '''
  CREATE TABLE order_lines (
    order_id TEXT NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    product_id TEXT NOT NULL,
    description TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price_cents INTEGER NOT NULL,
    PRIMARY KEY (order_id, position)
  )''',
  '''
  CREATE TABLE outbox (
    id TEXT NOT NULL,
    order_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at INTEGER NULL,
    last_error TEXT NULL,
    PRIMARY KEY (id)
  )''',
];

void main() {
  final DateTime t0 = DateTime(2026, 7, 27, 12, 30);

  late Directory directory;
  late File file;
  late AppDatabase db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_sync_migrazione');
    file = File('${directory.path}/pos_sync.db');

    // `setup` gira all'apertura della connessione, prima che drift guardi la
    // versione dello schema: quando la logica di migrazione entra in scena
    // trova una base dati che sembra scritta dalla versione 1.
    db = AppDatabase(NativeDatabase(file, setup: (Database raw) {
      for (final String ddl in _schemaV1) {
        raw.execute(ddl);
      }
      raw.execute(
        "INSERT INTO orders VALUES ('o-1', 7, ${t0.microsecondsSinceEpoch}, "
        "'pending')",
      );
      raw.execute(
        "INSERT INTO order_lines VALUES ('o-1', 0, 'p-01', 'Caffè', 2, 120)",
      );
      raw.execute(
        "INSERT INTO order_lines VALUES ('o-1', 1, 'p-02', 'Cornetto', 1, 150)",
      );
      raw.execute(
        "INSERT INTO outbox VALUES ('q-1', 'o-1', "
        '${t0.microsecondsSinceEpoch}, 0, NULL, NULL)',
      );
      raw.execute('PRAGMA user_version = 1');
    }));
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('un ordine scritto dalla versione 1 si legge ancora', () async {
    final Order order = (await DriftOrderStore(db).allOrders()).single;

    expect(order.id, 'o-1');
    expect(order.tableNumber, 7);
    expect(order.createdAt, t0);
    expect(order.status, SyncStatus.pending);
    expect(order.lines.map((OrderLine l) => l.description),
        <String>['Caffè', 'Cornetto']);
    expect(order.totalCents, 390);
  });

  test('lo schema arriva alla versione 2', () async {
    await DriftOrderStore(db).allOrders(); // forza la migrazione
    final List<QueryRow> rows =
        await db.customSelect('PRAGMA user_version').get();
    expect(rows.single.data['user_version'], 2);
  });

  test('gli ordini vecchi nascono aperti e senza revisione', () async {
    // Il valore di default non è una comodità: SQLite non sa aggiungere una
    // colonna `NOT NULL` senza, e `open` è la scelta prudente — un tavolo che
    // resta aperto per errore si nota, uno che risulta pagato per errore no.
    final Order order = (await DriftOrderStore(db).allOrders()).single;

    expect(order.state, OrderState.open);
    expect(order.stateRevision, const Revision.initial());
  });

  test('le righe vecchie ricevono un identificativo, e sono distinte',
      () async {
    // Con l'id vuoto l'unione tratterebbe tutte le righe preesistenti come la
    // stessa riga, e alla prima sincronizzazione ne resterebbe una sola.
    final Order order = (await DriftOrderStore(db).allOrders()).single;
    final Set<String> ids = order.lines.map((OrderLine l) => l.id).toSet();

    expect(ids, hasLength(2), reason: 'due righe, due identificativi');
    expect(ids.any((String id) => id.isEmpty), isFalse);
    expect(ids, <String>{'o-1:0', 'o-1:1'});
  });

  test('la coda di uscita sopravvive: niente ordini persi', () async {
    // È la ragione per cui la migrazione è una migrazione e non una
    // ricreazione: qui dentro c'è un ordine che il server non ha ancora visto.
    final List<OutboxEntry> queue = await DriftOrderStore(db).pendingOutbox();

    expect(queue, hasLength(1));
    expect(queue.single.id, 'q-1');
    expect(queue.single.orderId, 'o-1');
    expect(queue.single.attempts, 0);
  });

  test('le tabelle nuove esistono e si usano', () async {
    final DriftOrderStore store = DriftOrderStore(db);
    final Order order = (await store.allOrders()).single;

    await store.recordConflict(OrderConflict(
      id: 'c-1',
      mine: order,
      theirs: order.copyWith(state: OrderState.paid),
      reason: 'prova',
      detectedAt: t0,
    ));
    expect((await store.openConflicts()).single.id, 'c-1');

    final DriftDeviceStore device = DriftDeviceStore(db);
    expect(await device.loadDeviceId(), isNotEmpty);
    expect(await device.loadCounter(), 0);
  });

  test("l'identificativo del dispositivo non cambia fra due letture", () async {
    // È metà della revisione: un dispositivo che cambia nome a ogni avvio
    // renderebbe l'ordine totale una finzione.
    final DriftDeviceStore device = DriftDeviceStore(db);

    final String first = await device.loadDeviceId();
    await device.saveCounter(12);
    final String second = await DriftDeviceStore(db).loadDeviceId();

    expect(second, first);
    expect(await DriftDeviceStore(db).loadCounter(), 12);
  });
}
