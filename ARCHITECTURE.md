# Architettura e scelte di progetto

## Struttura

```
core/
  clock.dart                   il tempo come dipendenza
  id_generator.dart            gli identificativi come dipendenza
  logger.dart                  la registrazione come dipendenza
  di.dart                      composition root
  background_sync.dart         secondo ingresso: il lavoro di WorkManager
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
    connectivity_plus_monitor.dart  adattatore sul plugin di rete
    outbox_scheduler.dart      creazione della voce di coda
    orders_repository_impl.dart
  sync/
    backoff.dart               esponenziale con jitter
    retry_policy.dart          strategia: se e quando riprovare
    sync_worker.dart           orchestrazione
    connectivity_monitor.dart  contratto sulla rete + monitor controllabile
    auto_sync.dart             collega il ritorno della rete al drenaggio
  presentation/
    orders_cubit.dart  orders_state.dart  orders_page.dart
    order_tile.dart            la riga della lista + l'indicatore di stato
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
| **Adapter** | `ConnectivityPlusMonitor` | Il plugin di rete compare in un file solo, e mai nel livello di sincronizzazione |

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

## La connettività

`SyncWorker.drain()` è sempre stato pubblico e senza timer, di proposito: sapere *cosa*
mandare e sapere *quando* mandarlo cambiano per ragioni diverse. Mancava però chi lo
chiamasse, e finché è mancato l'app era offline-first solo a metà — i dati sopravvivevano
alla chiusura, la coda restava ferma.

### Un booleano, non un elenco di interfacce

`connectivity_plus` distingue Wi-Fi, dati mobili, ethernet, VPN e bluetooth. Il contratto
`ConnectivityMonitor` espone un booleano, e la riduzione avviene nell'adattatore: al worker
non serve sapere *come* si è connessi, gli serve sapere se vale la pena tentare.

Il segnale resta grossolano — il plugin riporta l'interfaccia di rete, non se il backend
risponde, e dietro un portale captivo dirà "online". È accettabile **grazie alla coda**: un
invio che fallisce non perde niente, torna in coda e riparte con il backoff. Una verifica di
raggiungibilità vera costerebbe una richiesta a ogni cambio di rete per anticipare un errore
che il sistema già gestisce.

### Il contratto sta con chi lo consuma, l'adattatore con gli altri adattatori

`ConnectivityMonitor` vive in `sync/`, `ConnectivityPlusMonitor` in `data/`. Non è simmetria
per il gusto della simmetria: è ciò che tiene `sync/` in Dart puro. La logica di
sincronizzazione continua a girare nei test senza Flutter, senza database e senza rete, che
è la proprietà su cui poggia tutto il resto della suite.

### Due errori facili, entrambi chiusi da un test

**Agire sull'evento invece che sulla transizione.** Passare da Wi-Fi a dati mobili produce un
secondo `true`: cambia la rete, non lo stato. Senza il confronto con lo stato precedente ogni
cambio di rete farebbe ripartire la coda. Il monitor *non* filtra i duplicati, ed è
deliberato: nasconderli nell'adattatore vorrebbe dire che un monitor scritto male tornerebbe
a produrre drenaggi doppi senza che nessun test se ne accorga.

**Ignorare lo stato iniziale.** Un'app chiusa in una sala senza campo e riaperta sotto rete
non riceve nessun *cambiamento*: la rete c'era già all'avvio. Trattare lo stato di partenza
come una transizione è ciò che impedisce a una coda sopravvissuta alla sessione precedente di
restare ferma per sempre.

### Lo stesso jitter del backoff, su una scala diversa

Il drenaggio parte dopo un ritardo casuale fino a cinque secondi. Quando il router di un
locale torna su, tutti i dispositivi vedono la rete nello stesso istante: senza il ritardo
partirebbero insieme, e il backend riceverebbe l'intero parco in una volta proprio nel momento
in cui è appena tornato disponibile. È l'argomento del jitter nel backoff, applicato
all'evento invece che al ritentativo.

L'attesa è iniettata (`Sleeper`) per la stessa ragione per cui lo è l'orologio: un test che
verifica il jitter non deve subirlo. Il doppio registra le durate richieste, e la suite
asserisce che stiano nei limiti e che non siano tutte uguali.

### Ad app chiusa: WorkManager

`AutoSync` copre il caso in cui l'app è aperta. L'altro — chiusa in un posto senza campo,
riaperta il giorno dopo — è un lavoro periodico di sistema vincolato alla presenza di rete:
Android non sveglia il processo finché non c'è connettività, quindi non si paga un risveglio
per scoprire di non poter fare niente.

Il lavoro gira in un **motore Flutter separato**, dove non esiste niente di ciò che `main()`
ha costruito: il grafo va montato da capo e il database richiuso alla fine. Da qui due
conseguenze concrete:

- `shareAcrossIsolates` di `drift_flutter` non aiuta, perché funziona solo dentro lo stesso
  motore. La mutua esclusione torna a essere un problema di SQLite, ed è il motivo di
  `journal_mode = WAL` e `busy_timeout` accanto a `foreign_keys` in `beforeOpen`.
- Quando l'app è viva il lavoro può essere eseguito nel suo stesso processo. Il codice se ne
  accorge, e non rimonta il grafo né chiude un database che non è suo.

È il pezzo che **non è verificabile in CI**: gira solo su Android, solo se il sistema decide
di eseguirlo, e non prima di quindici minuti. Ciò che è verificabile — che il lavoro venga
pianificato e poi eseguito — si legge da `adb shell dumpsys jobscheduler` e da `logcat`. Il
drenaggio che esegue è lo stesso testato dal resto della suite: il lavoro in background non
contiene logica propria, e anche questo è deliberato.

## L'interfaccia sotto test

Era il buco più visibile della suite: undici file di test e nessuno che aprisse
la schermata. Le `Key` erano in posizione dal primo giorno, il che rendeva
l'assenza ancora meno giustificabile.

### Un cubit preimpostato, non il grafo vero

I widget test montano `OrdersPage` su un `CubitPreimpostato`, che è un
`Cubit<OrdersState>` e niente altro: nessun repository, nessun worker, nessun
database. Un test che monta il grafo vero per vedere una lista vuota sta
testando il grafo, non la pagina — e fallisce per motivi che con la pagina non
c'entrano.

Il doppio conta anche le chiamate ricevute, così i test verificano che i comandi
**arrivino a destinazione** invece di limitarsi a controllare che i pulsanti
esistano. È la differenza fra "c'è un pulsante di sincronizzazione" e "premerlo
sincronizza".

I tre stati che contano sono vuoto, con ordini ed errore, e la distinzione fra i
primi due e il terzo è quella che un test protegge davvero: *"non ci sono
ordini"* e *"non riesco a leggerli"* sono due cose diverse, e confonderle
nasconde il guasto proprio nel momento in cui va visto.

### Perché i golden, e su cosa

Un test che cerca `find.byIcon(Icons.cloud_done)` passa anche se quell'icona è
diventata invisibile, grigia o larga il doppio. Il golden no: confronta i pixel.

Il soggetto è la **riga**, non la schermata. Un golden sull'intera pagina
cambierebbe a ogni ritocco della barra superiore, e un test che fallisce per
motivi che non interessano smette presto di essere letto — poi disattivato.
`OrderTile` è stato estratto dalla pagina esattamente per poterlo rendere da
solo.

Tre dettagli che nella pratica fanno la differenza fra un golden utile e uno
inservibile:

- **Il `RepaintBoundary` non è decorativo.** `matchesGoldenFile` non ritaglia il
  widget che gli si indica: risale al primo confine di ridisegno sopra di esso.
  Senza, l'immagine è l'intera finestra con la riga persa in mezzo — e cambia a
  ogni ritocco dello sfondo.
- **I font vanno registrati.** Senza, Flutter ripiega su un carattere segnaposto
  e il riferimento diventa una fila di rettangoli: deterministico, e illeggibile
  per chiunque debba decidere se un cambiamento è quello voluto. `flutter_test_config.dart`
  carica Roboto e MaterialIcons dall'SDK — gli stessi che usa l'app, e nessun
  binario in più da versionare.
- **La versione di Flutter è fissata in CI.** Il motore porta con sé il proprio
  stack di disegno e di font, quindi la stessa versione dà gli stessi pixel su
  sistemi diversi; una versione diversa no. Senza il pin i golden fallirebbero
  da soli il giorno di un aggiornamento, che è il modo più rapido per farli
  disattivare. Aggiornare la versione diventa una decisione deliberata, da
  prendere insieme alla rigenerazione dei riferimenti.

Quando un golden fallisce la pipeline pubblica `test/failures/`: immagine
ottenuta, attesa e differenza. Un log che dice `0.98%, 253px diff` è vero e
inutile.

### I colori di stato non vengono dalla ColorScheme

Il seme del tema è una decisione di marca e può cambiare; "in attesa",
"riuscito" e "fallito" devono restare leggibili come stati. Derivarli dal seme
significherebbe che un cambio di colore aziendale può rendere il successo e
l'errore due sfumature della stessa tinta.

Il colore non è comunque l'unico portatore dell'informazione: le quattro icone
sono diverse fra loro e ognuna porta un'etichetta per il lettore di schermo, che
un test verifica. Chi non distingue il rosso dal verde legge lo stato
dall'icona.

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
| La connettività sarebbe stata verificabile solo mettendo il telefono in modalità aereo | `FakeConnectivityMonitor` e `Sleeper` iniettato: transizioni e jitter verificati in millisecondi |
| La schermata non era coperta da nessun test | `orders_page_test.dart`: i tre stati, i comandi che arrivano al cubit, le etichette per il lettore di schermo |
| L'aspetto era verificabile solo guardando l'app | Quattro golden sulla riga dell'ordine: cambiare di uno il valore di un colore fa fallire il test |

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
- **Concorrenza gestita con un flag booleano** nel worker. Basta finché i drenaggi partono
  dallo stesso isolate. Con il lavoro in background ce ne sono due e i due flag non si
  vedono: se coincidessero, lo stesso ordine partirebbe due volte. Non produce duplicati —
  l'idempotenza sull'id serve esattamente a questo — ma è una richiesta di rete sprecata, e
  un lock vero starebbe in una riga di tabella invece che in un campo in memoria.
- **Nessun ridrenaggio periodico ad app aperta.** Se un drenaggio riprogramma delle voci con
  backoff, quelle restano ferme finché la rete non cambia di nuovo o finché non interviene il
  lavoro di sistema. Un timer risolverebbe, al prezzo di risvegli inutili nel caso normale in
  cui non c'è niente in coda.
- **Il lavoro in background è solo Android.** Su iOS il modello è diverso — BGTaskScheduler
  decide *se* eseguire, non *quando* — e prometterlo senza averlo verificato su un dispositivo
  Apple sarebbe una dichiarazione non sostenuta.
- **I golden coprono la riga, non la schermata.** Un riferimento sull'intera pagina
  fallirebbe a ogni ritocco della barra superiore. Il prezzo è che una regressione nella
  disposizione della pagina non viene vista da nessun golden: la coprono i widget test, che
  però guardano la struttura e non i pixel.
- **Nessun test end-to-end su un dispositivo.** Widget test e golden girano sul motore di
  Flutter, non su Android: il canale della piattaforma, i permessi e il ciclo di vita reale
  non sono coperti. Servirebbe `integration_test` e un emulatore in pipeline.
- **La gestione dei conflitti non c'è.** Funziona finché i dispositivi lavorano su
  dati disgiunti — ed è il primo limite che dichiaro quando presento il progetto.
