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
          // SQLite disattiva i vincoli di integrità per connessione: senza
          // questa riga la cascata sulle righe d'ordine sarebbe decorativa.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
