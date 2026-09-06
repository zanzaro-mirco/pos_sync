import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Base dati locale su SQLite.
///
/// Il costruttore accetta un [QueryExecutor] invece di aprire il file da sé:
/// l'applicazione le passa il file vero, i test una base dati in memoria o un
/// file temporaneo. È la stessa ragione per cui l'orologio è iniettato —
/// decidere *dove* si scrive non è compito di chi sa *come* si scrive.
@DriftDatabase(
    tables: <Type>[Orders, OrderLines, Outbox, Conflicts, DeviceIdentity])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),

        /// Versione 2: la gestione dei conflitti.
        ///
        /// Una migrazione vera e non una ricreazione: su un tablet di sala la
        /// base dati contiene ordini che non sono ancora arrivati al server, e
        /// buttarla per aggiungere tre colonne significherebbe perderli. È
        /// anche la ragione per cui le colonne nuove hanno tutte un valore di
        /// default — SQLite non sa aggiungere una colonna `NOT NULL` senza.
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(orders, orders.state);
            await m.addColumn(orders, orders.stateRevisionCounter);
            await m.addColumn(orders, orders.stateRevisionDevice);
            await m.addColumn(orderLines, orderLines.lineId);
            await m.addColumn(orderLines, orderLines.addedAtCounter);
            await m.addColumn(orderLines, orderLines.addedAtDevice);
            await m.createTable(conflicts);
            await m.createTable(deviceIdentity);

            // Le righe già in tabella non hanno un identificativo, e con
            // l'id vuoto l'unione le tratterebbe tutte come la stessa riga.
            // Ordine più posizione è unico per costruzione — è la chiave
            // primaria — quindi ricostruirlo di qui è sicuro.
            await customStatement(
              "UPDATE order_lines SET line_id = order_id || ':' || position "
              "WHERE line_id = ''",
            );
          }

          /// Versione 3: la rete locale.
          ///
          /// Tre colonne sulla cassetta che tiene già l'identità del
          /// dispositivo. Non c'è niente da ricostruire: i valori predefiniti
          /// descrivono esattamente ciò che ogni installazione esistente è
          /// oggi — un dispositivo che non fa parte di nessuna rete locale.
          ///
          /// **`from >= 2` non è una svista.** `createTable` qui sopra usa la
          /// definizione *di oggi*, non quella che la tabella aveva alla
          /// versione 2: chi arriva dalla versione 1 riceve `device_identity`
          /// con le tre colonne già dentro, e aggiungerle di nuovo fallisce
          /// con «duplicate column name». Il salto v1 → v3 e il salto v2 → v3
          /// passano quindi da strade diverse, ed è la ragione per cui il test
          /// di migrazione li prova entrambi invece di fidarsi del più comune.
          if (from >= 2 && from < 3) {
            await m.addColumn(deviceIdentity, deviceIdentity.role);
            await m.addColumn(deviceIdentity, deviceIdentity.primaryHost);
            await m.addColumn(deviceIdentity, deviceIdentity.primaryPort);
          }
        },
        beforeOpen: (OpeningDetails details) async {
          // Tutto ciò che segue vale *per connessione*: SQLite non lo legge
          // dal file, va ripetuto ogni volta che si apre.

          // Senza questa riga la cascata sulle righe d'ordine sarebbe
          // decorativa: i vincoli di integrità nascono spenti.
          await customStatement('PRAGMA foreign_keys = ON');

          // Le due righe seguenti servono perché lo stesso file viene aperto
          // da due motori Flutter diversi — quello dell'app e quello del
          // lavoro in background di WorkManager. Non condividono l'isolate di
          // drift (`shareAcrossIsolates` funziona solo dentro lo stesso
          // motore), quindi la mutua esclusione torna a essere un problema di
          // SQLite.
          //
          // WAL fa convivere un lettore e uno scrittore invece di farli
          // escludere a vicenda; il timeout trasforma un "database is locked"
          // immediato in un'attesa. Un drenaggio dura millisecondi: aspettarlo
          // è preferibile a fallire.
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA busy_timeout = 5000');
        },
      );
}
