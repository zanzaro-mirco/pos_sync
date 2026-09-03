# Architettura e scelte di progetto

## Struttura

```
core/
  clock.dart                   il tempo come dipendenza
  id_generator.dart            gli identificativi come dipendenza
  logger.dart                  la registrazione come dipendenza
  di.dart                      composition root
features/orders/
  domain/                      nessuna dipendenza esterna, nemmeno da Flutter
    order.dart  order_line.dart  outbox_entry.dart  sync_status.dart
    orders_snapshot.dart       modello di lettura
    orders_repository.dart     contratto
  data/
    order_store.dart           OrderStore · OutboxStore · OrderOutboxTransaction · OrdersWatcher
    in_memory_order_store.dart implementa i quattro contratti
    local/
      tables.dart              orders · order_lines · outbox
      app_database.dart        schema, versione, PRAGMA
      drift_order_store.dart   implementa gli stessi quattro contratti su SQLite
    dto/order_dto.dart         rappresentazione di rete + mapper
    remote_api.dart            contratto + gerarchia sealed degli errori
    outbox_scheduler.dart      creazione della voce di coda
    orders_repository_impl.dart
  sync/
    backoff.dart               esponenziale con jitter
    retry_policy.dart          strategia: se e quando riprovare
    sync_worker.dart           orchestrazione
  presentation/
    orders_cubit.dart  orders_state.dart  orders_page.dart
```

## MVVM, in concreto

Il `Cubit` è il ViewModel: espone `OrdersState`, la View lo osserva e non lo
interroga. Il cubit non conosce né la rete né il database — parla con il repository e
con il worker, entrambi dietro astrazioni.

Dopo il refactoring **osserva un flusso** invece di ricaricare: prima ogni creazione
di ordine produceva due letture complete della lista, una dopo il salvataggio e una
dopo la sincronizzazione. Ora la sorgente notifica i cambiamenti.

## Pattern usati

| Pattern | Dove | Perché |
|---|---|---|
| **Repository** | `OrdersRepository` | Contratto nel dominio: la parola "rete" non compare mai |
| **Outbox** | `OutboxEntry` + `SyncWorker` | Operazione e dato si salvano insieme: nessun ordine può restare invisibile al server |
| **Unit of Work** | `OrderOutboxTransaction` | La scrittura atomica è un contratto esplicito, non un metodo nascosto fra gli altri |
| **Strategy** | `RetryPolicy`, `Backoff` | Se e quando riprovare è una politica sostituibile |
| **DTO + Mapper** | `OrderDto` | Il dominio non conosce il formato di trasporto |
| **Sealed hierarchy** | `ApiFailure`, `RetryDecision` | Categorie di errore e decisioni chiuse ed esaustive |
| **Observer** | `OrdersWatcher` | La UI reagisce ai cambiamenti invece di richiedere i dati |
| **Read model (CQRS in piccolo)** | `OrdersSnapshot` | Lista e contatore delle pendenze arrivano insieme e non possono disallinearsi |
| **Null Object** | `SilentLogger` | Nessun `if (logger != null)` sparso nel codice |
| **Composition root** | `core/di.dart` | Unico punto che conosce le classi concrete |
| **Idempotency key** | `Order.id` generato dal client | Il ritentativo dopo una risposta persa non crea duplicati |

## La persistenza

### Perché Drift

`sqflite` è SQLite grezzo: query come stringhe, nessun controllo a compilazione, nessuna
reattività. `Isar` e `ObjectBox` sono più veloci ma non sono SQL e legano i dati al loro
formato. Drift è l'unico che dà **SQL tipizzato** e **query osservabili**, e la seconda
cosa è quella che serve qui: `watch()` è un `Stream` che riemette quando le tabelle
lette cambiano. Senza, la sorgente unica di verità si trasforma in "ricarica tutto dopo
ogni scrittura" — che è esattamente ciò da cui il progetto era già scappato.

Il costo è un passo di generazione del codice e un `.g.dart` accanto alle tabelle. Il
file generato è versionato, così `flutter test` funziona subito dopo un clone, e la CI
rigenera e fallisce se qualcuno modifica le tabelle senza rigenerare.

### Cosa incapsula `drift_flutter`

Una riga — `driftDatabase(name: 'pos_sync')` — al posto di tre cose: il percorso del file
nella cartella dei documenti dell'applicazione (`path_provider`), le librerie native di
SQLite impacchettate con l'app (`sqlite3_flutter_libs`) e l'apertura su un isolate di
background, che tiene le interrogazioni fuori dal thread della UI. Apre pigramente, alla
prima query, e per questo la composition root resta sincrona.

### Tre decisioni nello schema

**Le righe d'ordine hanno una colonna `position`.** `Order.lines` è una lista *ordinata*;
le righe di una tabella SQL non hanno ordine. Senza quella colonna l'ordine dipenderebbe
da come il motore decide di restituirle — e i test in memoria non se ne accorgerebbero
mai.

**Gli istanti sono salvati in microsecondi.** `DateTime` in Dart ha precisione al
microsecondo; il formato storico di Drift salva secondi. Due depositi che troncano in
modo diverso non possono superare lo stesso test.

**La coda non ha una chiave esterna verso gli ordini.** È deliberato: una voce deve poter
sopravvivere al suo ordine, perché il worker gestisce esplicitamente quel caso. Una
cascata renderebbe quel ramo codice morto invece che una difesa.

### La transazione, finalmente vera

`saveOrderWithOutbox` in memoria era due assegnazioni a due mappe: atomica per
costruzione, e quindi incapace di dimostrare alcunché. Su SQLite è una transazione con
rollback, e c'è un test che la interrompe a metà — dopo l'inserimento della testata,
prima delle righe — e verifica che non resti niente.

## SOLID, punto per punto

**Single Responsibility.** Il `SyncWorker` faceva cinque cose: orchestrare la coda,
classificare gli errori, calcolare il backoff, aggiornare gli stati e registrare i
messaggi. Ora orchestra e basta: *se* riprovare lo decide `RetryPolicy`, *quanto*
aspettare il `Backoff` dentro la politica, *dove* finiscono i messaggi il `Logger`.
Allo stesso modo il repository non crea più le voci di coda: lo fa `OutboxScheduler`.

**Open/Closed.** Gli errori dell'API erano due classi non imparentate intercettate da
due `catch` distinti nel worker: aggiungere una terza categoria significava
*modificare* il worker. Ora sono una gerarchia `sealed` e la decisione sta nella
politica. Il test `retry_policy_test.dart` definisce una `_NeverRetryPolicy`
alternativa senza toccare nulla.

**Liskov.** `InMemoryOrderStore` implementa quattro contratti e li rispetta tutti; la
futura implementazione su SQLite deve rispettare gli stessi, incluso il fatto che
`saveOrderWithOutbox` sia atomica.

**Interface Segregation.** Il punto corretto principale. C'era un unico `OrderStore`
con sette metodi, e nessun collaboratore li usava tutti — il repository ne usava
quattro, il worker cinque. Ora ci sono quattro contratti stretti e ognuno vede solo
il proprio. Una classe può implementarli tutti: è esattamente l'idea del principio.

**Dependency Inversion.** Tempo, identificativi, persistenza, rete, politica di
ritentativo e log sono tutti iniettati dietro astrazioni. Il grafo si compone in un
punto solo.

## Effetti sulla testabilità

| Prima | Dopo |
|---|---|
| Gli id erano UUID casuali: impossibile asserire su un valore | `IdGenerator` sostituibile, gli id nei test sono `id-1`, `id-2` |
| `print` dentro il worker: output sporco, nessuna verifica possibile | `InMemoryLogger`: si asserisce su cosa è stato registrato |
| `clearOrdersOnly()`, metodo di test su una classe di produzione | `deleteOrder()`, operazione legittima del dominio |
| Un doppio dello store doveva implementare sette metodi | Ne implementa solo quelli del contratto che serve |
| Nessun test su mappatura e serializzazione | `order_dto_test.dart`: JSON incompleto, record inutilizzabili, andata e ritorno |
| Politica di ritentativo verificabile solo passando dal worker | `retry_policy_test.dart` la testa da sola |
| I contratti del deposito erano verificati solo di riflesso, attraverso repository e worker | `store_contract.dart`: una suite sola, girata su entrambe le implementazioni |

### La suite di contratto

Un test che gira su un'implementazione verifica *quella*. Lo stesso test su due verifica
il **contratto** — e il contratto è ciò su cui repository e worker fanno affidamento.
`store_contract.dart` è scritto una volta e invocato da
`in_memory_order_store_test.dart` e `drift_order_store_test.dart`: ordinamenti, posizione
delle righe, sostituzione invece di accumulo, coerenza fra lista e contatore. Sono tutte
promesse che i tipi non sanno esprimere.

Al di là del contratto restano le prove che solo un deposito vero può dare: il rollback,
i vincoli di integrità effettivamente accesi, e i dati che si ritrovano dopo aver chiuso
e riaperto il file.

## Dove ho consapevolmente semplificato

- **Nessuno use case fra cubit e repository.** Le operazioni sono due e dirette.
  Diventerebbero utili con logica composta fra più feature.
- **Una sola versione dello schema.** C'è `schemaVersion` e c'è il punto in cui scrivere
  le migrazioni, ma non essendoci ancora una versione 2 non c'è niente da migrare.
- **Il fuso orario non sopravvive al deposito.** Gli istanti sono salvati come punto
  assoluto nel tempo e riletti come ora locale: il flag `isUtc` si perde. Per un
  applicativo che gira su un dispositivo solo non cambia niente; in un sistema con
  dispositivi in fusi diversi andrebbe salvato anche l'offset.
- **Il file non è cifrato.** Su un dispositivo di sala perso, gli ordini sono leggibili.
  Drift supporta SQLCipher e sarebbe un cambio di esecutore, non di codice.
- **Concorrenza gestita con un flag booleano** nel worker. Sufficiente per un singolo
  isolate; con più isolate servirebbe un lock vero.
- **La gestione dei conflitti non c'è.** Funziona finché i dispositivi lavorano su
  dati disgiunti — ed è il primo limite che dichiaro quando presento il progetto.
