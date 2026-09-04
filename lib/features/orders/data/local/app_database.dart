import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Base dati locale su SQLite.
///
/// Il costruttore accetta un [QueryExecutor] invece di aprire il file da sé:
/// l'applicazione le passa il file vero, i test una base dati in memoria o un
/// file temporaneo. È la stessa ragione per cui l'orologio è iniettato —
/// decidere *dove* si scrive non è compito di chi sa *come* si scrive.
@DriftDatabase(tables: <Type>[Orders, OrderLines, Outbox])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
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
