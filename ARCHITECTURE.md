# Architettura e scelte di progetto

## Struttura

```
core/
  clock.dart                   il tempo come dipendenza
  id_generator.dart            gli identificativi come dipendenza
  logger.dart                  la registrazione come dipendenza
  logical_clock.dart           il tempo *logico* come dipendenza
  feature_flags.dart           cosa si può spegnere da remoto
  product_metrics.dart         cosa il sistema fa per chi lo usa
  observability.dart           log, flag e metriche: arrivano insieme o per niente
  firebase/                    l'unico posto che conosce Firebase
    firebase_observability.dart   lo accende, se può
    crashlytics_logger.dart       Logger → Crashlytics
    remote_config_flags.dart      FeatureFlags ← Remote Config
    analytics_metrics.dart        ProductMetrics → Analytics
  di.dart                      composition root
  background_sync.dart         secondo ingresso: il lavoro di WorkManager
features/orders/
  domain/                      nessuna dipendenza esterna, nemmeno da Flutter
    order.dart  order_line.dart  outbox_entry.dart  sync_status.dart
    order_line_draft.dart      una riga come la scrive chi prende l'ordine
    order_state.dart           stato del tavolo, condiviso fra i dispositivi
    revision.dart              quando, in tempo logico
    order_conflict.dart        due versioni e la decisione da prendere
    orders_snapshot.dart       modello di lettura
    orders_repository.dart     contratto
  data/
    order_store.dart           OrderStore · OutboxStore · OrderOutboxTransaction · OrdersWatcher · ConflictStore
    in_memory_order_store.dart implementa i cinque contratti
    local/
      tables.dart              orders · order_lines · outbox · conflicts · device_identity
      app_database.dart        schema v3, migrazioni, PRAGMA
      drift_order_store.dart   implementa gli stessi cinque contratti su SQLite
      drift_device_store.dart  identità del dispositivo e contatore logico
      drift_peer_settings.dart ruolo e indirizzo, sulla stessa riga dell'identità
    dto/order_dto.dart         rappresentazione di rete + mapper
    remote_api.dart            contratto + gerarchia sealed degli errori
    order_registry.dart        cosa il punto di raccolta sa, e di chi
    second_device.dart         un altro tablet, simulato, per poterlo mostrare
    connectivity_plus_monitor.dart  adattatore sul plugin di rete
    outbox_scheduler.dart      creazione della voce di coda
    orders_repository_impl.dart
  lan/
    lan_protocol.dart          porta, percorsi, servizio mDNS: il poco condiviso
    order_server.dart          la cassa vista dagli altri tablet
    http_remote_api.dart       il tablet in sala che le parla
    local_registry_api.dart    la cassa che parla con sé stessa
    lan_coordinator.dart       sceglie il backend in base al ruolo, a caldo
    peer_settings.dart         ruolo e indirizzo + contratto del deposito
    peer_discovery.dart        contratto della scoperta + doppio inerte
    nsd_discovery.dart         la scoperta vera, su mDNS — senza decisioni
    primary_election.dart      chi prende il registro se la cassa sparisce
    peer_retry_policy.dart     budget di ritentativi diverso in sala
    local_address.dart         il proprio indirizzo, da mostrare a chi configura
  sync/
    backoff.dart               esponenziale con jitter
    retry_policy.dart          strategia: se e quando riprovare
    sync_worker.dart           orchestrazione: prima spinge, poi tira
    conflict_policy.dart       strategia: come si fondono due versioni
    inbound_merger.dart        il verso di rientro
    connectivity_monitor.dart  contratto sulla rete + monitor controllabile
    auto_sync.dart             collega il ritorno della rete al drenaggio
    order_republisher.dart     riaccoda tutto quando la cassa cambia identità
    drain_on_flag_change.dart  un flag cambiato fa girare subito la coda
  presentation/
    orders_cubit.dart  orders_state.dart  orders_page.dart
    order_tile.dart            la riga della lista + l'indicatore di stato
    conflict_card.dart         le due versioni e i due pulsanti
    table_number_dialog.dart   il numero del tavolo, ripetibile
    order_state_label.dart     come si scrive uno stato in sala
    peer_settings_sheet.dart   dove si sceglie che parte fa questo dispositivo
```

## Due lingue, e non è un caso

**Gli identificatori sono in inglese, la prosa è in italiano.** Nomi di classi,
metodi, variabili e costanti si leggono come in qualunque altro progetto Dart;
commenti, dartdoc, descrizioni dei test e testo dell'interfaccia restano nella
lingua di chi lavora in sala — e di chi ha scritto questo file.

La separazione ha avuto un costo che vale la pena raccontare, perché è il tipo di
accoppiamento che si nota solo quando si prova a scioglierlo. `OrderState` aveva
le costanti `aperto`, `servito` e `pagato`, e `state.name` faceva **tre** mestieri
insieme: il nome nel codice, la parola letta dall'operatore e il valore scritto
su SQLite. Rinominare le costanti — una modifica interna — avrebbe quindi
cambiato la lingua dell'interfaccia *e* invalidato i dati già salvati. Da qui due
aggiunte: `order_state_label.dart`, che traduce esplicitamente per lo schermo, e
un `parseOrderState` che accetta ancora i nomi vecchi, così un dispositivo
aggiornato non si ritrova i tavoli riaperti in silenzio.

## MVVM, in concreto

Il `Cubit` è il ViewModel: espone `OrdersState`, la View lo osserva e non lo
interroga. Il cubit non conosce né la rete né il database — parla con il repository e
con il worker, entrambi dietro astrazioni.

Dopo il refactoring **osserva un flusso** invece di ricaricare: prima ogni creazione
di ordine produceva due letture complete della lista, una dopo il salvataggio e una
dopo la sincronizzazione. Ora la sorgente notifica i cambiamenti.

### Perché Cubit e non Bloc

In questo progetto non c'è un Bloc, e aggiungerne uno dove non serve sarebbe una classe
scritta per far tornare una parola del curriculum, non per il codice.

**Perché basta un Cubit.** Il cubit ha un solo ingresso che scorre nel tempo, il flusso del
repository, e lo trasforma in stato dentro un listener sincrono. Tutto il resto sono
comandi: la schermata chiama `addOrder`, `addLines`, `changeState`, `resolveConflict` e
`sync`, e ognuno è una chiamata diretta che delega. Con un Bloc ciascuno diventerebbe una
classe evento con gli stessi argomenti del metodo, più un gestore che la spacchetta: cinque
classi che non aggiungono informazione, e test in cui `bloc.add(AddOrder(...))` sostituisce
`await cubit.addOrder(...)` perdendo proprio l'`await`.

**Quando servirebbe.** Quando conta *come* arrivano gli eventi, e non solo cosa fanno:
accodarli uno dopo l'altro, scartarli mentre uno è in corso, ritardarli finché l'utente
smette di scrivere, annullare il precedente quando arriva il successivo. Un Bloc lo esprime
con un trasformatore per tipo di evento (`sequential`, `droppable`, `restartable` di
`bloc_concurrency`); un Cubit non ha un posto dove scriverlo. Senza trasformatore, però, un
Bloc elabora gli eventi in parallelo, esattamente come i metodi di un cubit: passare a Bloc
senza sceglierne uno non cambia niente.

**Dove la soglia si è avvicinata.** Due punti, trovati con un test scritto apposta prima di
questo paragrafo e poi corretti, ciascuno con un test che falliva prima della correzione:

| Caso | Cosa succedeva | Dove sta la correzione, e perché non è un Bloc |
|---|---|---|
| Due tocchi rapidi su «tieni il mio» | La decisione si scriveva due volte: due tick dell'orologio logico, due voci in coda, due invii. Non si perdeva niente, perché il contenuto era identico e la seconda revisione batteva la prima, ma gli altri dispositivi ricevevano una modifica in più | Nel repository. `resolveConflict` era già idempotente in sequenza, perché un conflitto chiuso si ignora, ma non in parallelo: fra la lettura del conflitto e la sua rimozione ci sono delle `await`. Ora un insieme delle decisioni in corso fa uscire subito la seconda chiamata. Un `droppable` avrebbe protetto il pulsante; il repository protegge qualunque chiamante |
| Un ordine creato mentre un drenaggio è in corso | Il flag del worker scartava il drenaggio lanciato dal nuovo ordine, e l'ordine restava in coda finché qualcosa non ne faceva partire un altro: un comando, il pulsante, un cambio di rete, o il lavoro di sistema entro quindici minuti. Con ogni probabilità è ciò che ha fatto fallire una volta in pipeline il test di integrazione della cassa: la sequenza è compatibile, ma non l'ho riprodotta sull'emulatore | Nel worker. Una chiamata a metà giro non avvia un drenaggio parallelo e non viene scartata: il giro in corso ne fa uno in più, e chi ha chiamato aspetta anche quello. Nessun trasformatore di `bloc_concurrency` lo esprime: `droppable` era il difetto, `sequential` accoderebbe un giro per ogni comando. E `drain()` lo chiamano anche `AutoSync` e il lavoro in background, quindi la politica deve stare sotto tutti i chiamanti |

In entrambi i casi il problema di concorrenza esisteva davvero, ma stava sotto l'interfaccia.

**Il punto in cui un Bloc si guadagnerebbe il posto** è un campo di ricerca che interroga il
database a ogni lettera. Aspettare che l'utente smetta di scrivere e annullare la ricerca
precedente quando arriva la nuova (`restartable`, con un ritardo) è un'intenzione
dell'interfaccia, e non c'è nessun altro chiamante a cui spostarla.

## Pattern usati

| Pattern | Dove | Perché |
|---|---|---|
| **Repository** | `OrdersRepository` | Contratto nel dominio: la parola "rete" non compare mai |
| **Outbox** | `OutboxEntry` + `SyncWorker` | Operazione e dato si salvano insieme: nessun ordine può restare invisibile al server |
| **Unit of Work** | `OrderOutboxTransaction` | La scrittura atomica è un contratto esplicito, non un metodo nascosto fra gli altri |
| **Strategy** | `RetryPolicy`, `Backoff`, `ConflictPolicy` | Se e quando riprovare, e come si fondono due versioni dello stesso dato, sono politiche sostituibili |
| **Orologio logico** | `Revision`, `LamportClock` | L'ordine fra dispositivi non può dipendere dall'ora di sistema: sta nel dato |
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

I widget test montano `OrdersPage` su un `PresetCubit`, che è un
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
  binario in più da versionare. Il prezzo è che devono *esserci*: gli artefatti
  dell'SDK si scaricano su richiesta e `flutter test` da solo non li chiede, così
  la pipeline esegue `flutter precache` prima dei test. È il tipo di dipendenza
  dall'ambiente che si scopre solo facendo girare la suite altrove — qui l'ha
  scoperta la CI al primo tentativo.
- **I riferimenti valgono per una piattaforma sola, e il numero lo dimostra.**
  Avevo generato i quattro riferimenti su Windows dando per scontato che il
  motore, portandosi dietro il proprio stack di font, producesse gli stessi
  pixel ovunque. La pipeline ha risposto: **dal 3,27% al 3,91% di pixel
  diversi**, tutti sull'antialiasing dei glifi, invisibili a occhio nudo. Il
  cambiamento che questi test devono catturare — il verde spostato di *una*
  unità — vale lo **0,98%**. Una soglia di tolleranza dovrebbe accettare il
  3,91% e ingoierebbe il colore: il rumore di piattaforma è più grande del
  segnale, e nessun numero separa i due. Quindi i riferimenti si generano e si
  verificano su Linux, la piattaforma della pipeline, e altrove i test si
  saltano.
- **La versione di Flutter è fissata in CI.** Stesso motivo, su un altro asse:
  il motore che disegna cambia fra le versioni, e senza il pin i golden
  fallirebbero da soli il giorno di un aggiornamento — il modo più rapido per
  farli disattivare. Aggiornare la versione diventa una decisione deliberata, da
  prendere insieme alla rigenerazione dei riferimenti.
- **Rigenerare è un lavoro della pipeline, non della macchina di chi sviluppa.**
  Il workflow `goldens.yml` si lancia a mano, riesegue i golden con
  `--update-goldens` e pubblica le immagini come artefatto. Non le committa: un
  aggiornamento automatico promuoverebbe a riferimento qualunque cosa la
  pipeline abbia disegnato, regressioni comprese.

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

## I conflitti

Fino a ieri qui c'era scritto che la gestione dei conflitti non c'era, e che era
il primo limite dichiarato quando presentavo il progetto. La ragione per cui non
c'era è più interessante della mancanza: `RemoteApi` aveva un solo metodo,
`submitOrder`. Era un percorso di sola andata, e **un conflitto non poteva
proprio nascere** — niente tornava mai indietro. Aggiungere la gestione dei
conflitti ha significato prima di tutto aggiungere il verso di rientro.

### L'ordine sta nel dato, non nell'arrivo

Il primo istinto è ordinare le modifiche per `createdAt`. Non funziona: l'ora di
sistema è un dato che l'utente può cambiare dalle impostazioni, e basta un tablet
indietro di due minuti perché le sue modifiche non vincano mai. Al suo posto c'è
un **contatore logico di Lamport**: cresce di uno a ogni modifica locale
(`tick`), e sale ad almeno quello visto ogni volta che arriva una revisione da
fuori (`witness`).

`Revision` è la coppia *(contatore, dispositivo)*. Il secondo campo non ha
significato di merito: rompe la parità, e serve solo a garantire che una risposta
ci sia e che sia **la stessa ovunque**. Senza, due modifiche allo stesso contatore
sarebbero inordinabili e due dispositivi che le ricevono in ordine diverso
sceglierebbero vincitori diversi — cioè esattamente la divergenza che tutto
questo esiste per evitare.

Il `witness` è il passo che non ha effetti visibili finché non è troppo tardi, ed
è per questo che ha un test dedicato: se il tablet A ha lavorato molto e B poco,
la decisione presa da B *dopo aver visto* quella di A deve batterla, anche se il
contatore di B contato per conto proprio sarebbe più basso. Togliendo il
`witness`, la convergenza continua a valere — i due dispositivi restano
d'accordo — ma sono d'accordo sulla risposta sbagliata. È il motivo per cui la
convergenza da sola non basta a dire che un sistema distribuito è corretto.

### Una politica per tipo di dato

Il criterio giusto dipende dal dato, non dal sistema. Due camerieri che aggiungono
piatti allo stesso tavolo non sono in conflitto; due che lo chiudono sì.

| Dato | Politica | Perché |
|---|---|---|
| Righe dell'ordine | **Append-only**: unione per id | L'unione è commutativa e idempotente, quindi il risultato non guarda l'ordine di arrivo. È da qui che discende la convergenza |
| Stato del tavolo | **Last-write-wins** sulla revisione | Un tavolo non può essere insieme aperto e pagato: uno dei due deve perdere, e a decidere è il contatore logico |

Le righe portano un `id` proprio perché l'unione sia idempotente: senza,
sincronizzare due volte le duplicherebbe. E portano una `addedAt` perché serve
sapere *quando* sono entrate.

### Dove il codice si ferma e chiede

C'è un caso in cui le due politiche prese alla lettera danno un risultato
plausibile e sbagliato: **il tavolo risulta pagato, e l'altra versione porta
righe che chi ha incassato non aveva davanti**. Unione più last-write-wins
produrrebbe un tavolo pagato con dentro roba non pagata — un esito che non fa
rumore da nessuna parte, tranne che in cassa a fine serata. Non è il codice a
poter decidere se quelle righe vanno incassate a parte o se il pagamento va
rifatto: lo decide chi è lì.

Il riconoscimento **non passa dai contatori**, e questa è la parte non ovvia. Con
un orologio di Lamport una riga aggiunta da un dispositivo che non aveva ancora
visto il pagamento porta un contatore *più basso*, e un controllo del tipo "la
riga è successiva al pagamento?" la lascerebbe passare in silenzio. La domanda
giusta è un'altra e non dipende dai numeri: *chi ha incassato aveva questa riga
davanti?* Si risponde con una differenza fra insiemi.

Vale la pena dire anche cosa **non** è un conflitto: due dispositivi che
aggiungono piatti, due che portano il tavolo a servito, uno che serve mentre
l'altro aggiunge. Tutto questo converge da solo e non interrompe nessuno. Un
sistema che chiede conferma troppo spesso viene ignorato, ed è un modo più lento
di non avere gestione dei conflitti.

### Chiedere è sicuro perché non si perde niente

La decisione dell'operatore riguarda **solo lo stato del tavolo**: le righe
restano unite in ogni caso. Non esiste una risposta che faccia sparire una
comanda, ed è la ragione per cui i due pulsanti si possono mettere davanti a
qualcuno di fretta. Sui pulsanti è scritta la conseguenza — «tieni il pagamento»,
«tieni il tavolo aperto» — e non la provenienza: «tieni la mia» costringerebbe
chi decide a ricostruire quale sia la propria e cosa comporti.

La versione risolta nasce con una revisione **nuova**, non con quella della
versione scelta: la decisione è essa stessa una modifica e deve battere entrambe
le versioni che l'hanno provocata, anche sull'altro dispositivo. Senza, l'altro
rifonderebbe le stesse due e ricadrebbe nello stesso conflitto. E quando una
fusione torna a riuscire, l'eventuale conflitto ancora aperto su quell'ordine
viene chiuso: nessuno deve decidere due volte la stessa cosa.

### Il server non fonde

`fetchOrders` restituisce **una versione per dispositivo**, non una sola versione
fusa. Fondere sul server sembrerebbe più efficiente e distruggerebbe la
provenienza: la versione di un dispositivo è ciò che *quel* dispositivo credeva, e
senza non si può più rispondere alla domanda da cui dipende il riconoscimento del
conflitto — la versione fusa contiene tutte le righe per costruzione. È anche la
scelta che tiene la porta aperta al passo successivo della roadmap: fra due tablet
in rete locale, un server che fonde non c'è.

### Perché si può mostrare, e non solo raccontare

Per un po' questa parte è esistita solo nei test. La ragione è la stessa che
spiegava l'assenza dei conflitti: sul dispositivo c'è **un solo** client, che si
costruisce il proprio finto server, e `fetchOrders` restituisce le versioni degli
*altri* — che non ci sono. Il rientro girava a vuoto, la scheda di risoluzione
era codice irraggiungibile, e in colloquio si sarebbe potuto aprire un file di
test ma non lo schermo.

`SecondDevice` scrive nel finto server come farebbe un altro tablet: mette lì una
versione e si ferma. Non conosce il deposito locale, non chiama la politica di
fusione, non ha una via privilegiata verso la schermata. Tutto ciò che segue —
il rientro, la fusione, il conflitto — è il sistema vero che fa il suo mestiere
senza sapere che l'altro dispositivo è finto. È l'unica dipendenza registrata
sotto condizione in `di.dart`, e la pagina la riceve come callback opzionale:
una build collegata a un backend reale passa `null` e la voce sparisce dal menu.

La sequenza che si esegue col dito è di tre passi, e il secondo non è un
dettaglio: **incassare non basta**. Se il pagamento altrui arrivasse subito, le
due versioni conterrebbero le stesse righe e si fonderebbero in silenzio — che è
il comportamento giusto. Il conflitto nasce alla comanda successiva, perché è
allora che la versione pagata non la contiene. `second_device_test.dart` verifica
entrambe le metà, e la seconda — *quando il conflitto non deve comparire* — è
quella che conta di più: un sistema che chiede sempre viene ignorato.

Da qui una regola che senza uno schermo davanti non si sarebbe notata: **su un
ordine con un conflitto già aperto non se ne registra un secondo.** Finché
nessuno decide, ogni sincronizzazione ripesca la stessa versione altrui e arriva
di nuovo al punto in cui ci si ferma; ai test non dava fastidio, perché
sincronizzavano una volta sola. Nell'app la schermata si riempiva di schede
identiche — e una richiesta di decisione ripetuta all'infinito si smette di
leggere, che è il modo più rapido per rendere inutile l'unica cosa che il sistema
chiede.

## La rete locale

*«In un ristorante il server cloud è irraggiungibile ma i tablet si vedono fra loro.»*
È l'ultima voce della roadmap, ed è quella che mette alla prova tutte le scelte
prese prima: se il livello di sincronizzazione è davvero disaccoppiato dal
trasporto, sostituire il trasporto non deve toccare nient'altro.

### Tre backend, un contratto

`RemoteApi` ha due metodi e tre implementazioni, una per situazione:

| Situazione | Implementazione | Dove sta il registro |
|---|---|---|
| Demo in processo | `FakeRemoteApi` | in memoria, stesso processo |
| Dispositivo in cassa | `LocalRegistryApi` | qui, senza rete |
| Dispositivo in sala | `HttpRemoteApi` | sulla cassa, via HTTP |

`LanCoordinator` è a sua volta un `RemoteApi` che sceglie fra le tre in base al
ruolo configurato, e rilegge il ruolo a ogni chiamata invece di osservarlo: le
chiamate sono due e arrivano quando la coda gira, mentre il ruolo cambia una
volta all'anno. Senza questo indirizzamento dinamico, cambiare ruolo
richiederebbe di riavviare l'app — accettabile in un test, imbarazzante davanti
a qualcuno che guarda.

**Il worker non è stato toccato**, ed era il criterio vero di questa voce. Due
decisioni prese per i conflitti lo hanno reso possibile: `fetchOrders`
restituisce una versione per dispositivo e non una fusa, e gli errori sono una
gerarchia sealed. `HttpRemoteApi` deve solo tradurre — timeout e socket in
`TransientApiFailure`, `4xx` in `PermanentApiFailure`, `5xx` in transitorio — e
coda, backoff e ritentativi funzionano da soli senza sapere che dall'altra parte
c'è un tablet.

### Il protocollo è asimmetrico, e questo semplifica tutto

**Solo chi è in sala apre connessioni. La cassa risponde e basta.** Non c'è uno
scambio fra pari, non c'è un canale aperto, nessuno "trasmette" agli altri: c'è
un tablet che fa da lavagna e altri che ci vanno a scrivere e a leggere.

Tre percorsi su `dart:io`, nessun framework aggiunto per tre rotte:

| Verbo | Significato | Risposta |
|---|---|---|
| `POST /orders?device=X` | «questa è la mia versione» | `204` |
| `GET /orders?device=X` | «dammi quelle degli altri» | lista di `OrderDto` |
| `GET /health` | «chi sei?» | `{deviceId, role}` |

Il formato è `OrderDto`, lo stesso con cui l'ordine sta nel database: non c'è un
modello di trasporto separato da tenere allineato.

La cassa **non fonde e non decide**. Tiene *(ordine, dispositivo) → versione* e
restituisce le versioni altrui; la politica di fusione, il riconoscimento del
conflitto e l'orologio logico restano sui dispositivi, dov'erano già. È la
ragione per cui `order_server.dart` è corto: il lavoro difficile era stato fatto
prima, e in un posto che non è quello.

La cassa passa comunque dal proprio `RemoteApi`, solo senza filo. Non è "il
server": è un dispositivo con la sua coda e il suo rientro che si trova il
registro sotto le dita. Se avesse un percorso tutto suo, i suoi ordini non
entrerebbero mai nel registro e nessuno li vedrebbe.

### La porta non si chiede

`53170`, sopra 49152, dove sta l'intervallo effimero: nessun servizio noto la
rivendica. Vale su entrambi i lati, come la 80 di HTTP, e nessuno deve
impararla dall'altro.

Per un po' il foglio impostazioni l'ha chiesta, e solo a chi è in sala — mentre
la cassa non poteva cambiare quella su cui ascolta. Quel campo poteva soltanto
far puntare un tablet dove non risponde nessuno, con un sintomo — «non arriva
niente» — che non suggerisce di andare a guardare le impostazioni. Resta un
parametro nel codice per i test, che chiedono la porta `0` per farsene assegnare
una libera.

### Scoperta: mDNS, con l'indirizzo manuale che resta

Chi fa la cassa si annuncia come `_possync._tcp`; chi è in sala la cerca. Un
indirizzo vuoto non significa più «configurazione a metà» ma **«cercala»**, ed è
il valore da preferire, perché sopravvive a un cambio di indirizzo della cassa.

**L'indirizzo digitato ha la precedenza**, e non è un ripiego di serie B: nei
locali il Wi-Fi ospiti filtra spesso il multicast, ed è l'unica configurazione
che si può sempre far funzionare. Per la stessa ragione un annuncio non riuscito
non impedisce alla cassa di fare la cassa.

Un indirizzo **scoperto** viene dimenticato quando smette di rispondere, uno
**digitato** no. Senza quella distinzione, la cassa che riavvia con un indirizzo
nuovo dal router resterebbe irraggiungibile fino al riavvio dell'app: la
scoperta automatica funzionerebbe una volta sola.

`NsdDiscovery` non ha test, ed è dichiarato nel file. Parla con i canali di
piattaforma, che in `flutter test` non esistono: qualunque prova lì
verificherebbe un simulacro. Il file è quindi sottile fino alla noia — nessuna
decisione, solo traduzione — e tutto ciò che si può sbagliare sta dietro
l'interfaccia `PeerDiscovery`, dove un doppio lo raggiunge.

### L'elezione, e perché lo split-brain è sopravvivibile

Se la cassa non risponde, si promuove **il dispositivo con l'identificativo più
basso fra quelli che si annunciano**. È lo stesso confronto che rompe la parità
fra due `Revision`, riusato — e non per economia: è ciò che permette a tutti di
calcolare lo stesso risultato senza mettersi d'accordo, che è l'unica cosa che
rende possibile un'elezione senza coordinatore.

Due condizioni, ed entrambe servono. **Tre giri falliti di seguito**, perché un
errore isolato è una rete che fa il suo mestiere e promuoversi al primo intoppo
cambierebbe cassa a ogni pacchetto perso. E **nessuno che si annunci come
cassa**: se c'è e si dichiara, non raggiungerla è un problema di questo tablet, e
affiancargliene una seconda sposterebbe il guasto su tutti gli altri.

Perché la regola sia applicabile, **anche chi è in sala si annuncia**, con il
ruolo in un record TXT: un tablet che tace non è contabile. Il servizio che un
follower pubblica non ascolta finché non viene promosso — dichiara una presenza,
non un servizio pronto — e nessuno ci si collega, perché la ricerca della cassa
filtra per ruolo.

Lo **split-brain resta possibile**: una rete che si spezza in due tronconi
produce due casse, una per metà, perché ciascuna vede solo sé stessa. È
sopravvivibile grazie alla politica di fusione — le righe si uniscono perché
l'unione è commutativa, lo stato lo decide la revisione più alta — e quando i
tronconi si ritrovano gli ordini convergono. Si perde l'ordine di arrivo, non il
contenuto.

### Ripubblicare dopo un'elezione, e un errore che avevo scritto nel piano

Nel piano di questa voce avevo scritto che dopo un cambio di cassa «i dispositivi
ripubblicano le proprie versioni al giro successivo». **È falso**: la coda si
svuota quando l'invio riesce, quindi un ordine già consegnato alla cassa vecchia
non verrebbe mai rispedito. Il registro della nuova sarebbe nato vuoto e ci
sarebbe rimasto, con tutti i tablet connessi e nessun errore da mostrare — il
guasto peggiore, perché non si presenta.

Serve un meccanismo vero, e `/health` lo permetteva già: restituisce
l'identificativo e non un sì/no, perché la domanda utile non è «c'è qualcuno?» ma
«c'è ancora quello di prima?». Quando l'identità della cassa cambia,
`OrderRepublisher` rimette in coda gli ordini locali che non ci sono già. Sta
fuori dal coordinatore di proposito: quello sa riconoscere il momento, non cosa
sia una coda.

### Un budget di ritentativi diverso in rete locale

`PeerAwareRetryPolicy` sceglie la politica in base al ruolo. Verso il cloud il
budget è otto tentativi con un tetto di cinque minuti — una decina di minuti in
tutto, tarati su un servizio remoto che se tace un quarto d'ora è rotto. In sala
sono sessanta tentativi, perché **la cassa spenta per venti minuti non è un
guasto**: è qualcuno che l'ha riavviata o messa in carica di là, e rinunciare
marcherebbe come falliti ordini di tavoli ancora occupati.

Il tetto per singola attesa va invece nella direzione opposta, da cinque minuti a
uno: con il tetto alto, la cassa che torna resterebbe inutilizzata fino a cinque
minuti per un'attesa maturata mentre era spenta.

Non è servito toccare il worker: la politica era già una strategia sostituibile.

### Cosa serviva fuori dal codice Dart

Due dichiarazioni nel manifest Android che, se mancano, si manifestano come
guasti che non suggeriscono dove guardare:

- **`INTERNET` anche in release.** Il template Flutter lo dichiara solo nei
  manifest di debug e profile. Finché il backend era simulato in processo non
  serviva; ora un APK di release funzionerebbe sulla macchina di chi sviluppa e
  non su quella del cliente.
- **`CHANGE_WIFI_MULTICAST_STATE`**, senza cui `NsdManager` non riceve le
  risposte mDNS e ogni ricerca scade a vuoto.

E `usesCleartextTraffic`, perché da Android 9 il traffico in chiaro è vietato per
impostazione predefinita. Vorrebbe essere ristretto ai soli indirizzi privati, ma
la configurazione di sicurezza di rete di Android accetta domini e non
intervalli: non si può scrivere `192.168.0.0/16`.

### Sapere se i due dispositivi si parlano davvero

Finito il passo 7, il sistema funzionava e non sapeva dirlo. L'unico segnale era
indiretto — il contatore «da inviare» che sale — e non distingue **«la cassa non
risponde»** da **«la cassa risponde ma non le ho ancora mandato niente»**. Chi
prova due tablet resta a indovinare, e indovinare su una rete è il modo più
rapido per dare la colpa alla cosa sbagliata.

`LanChecker` risponde, e la risposta è diversa sui due lati perché la domanda lo
è:

- **In sala**: «qualcuno risponde, e chi?». Si chiede a `/health`, che
  restituisce l'identificativo e non un sì/no — dopo un'elezione all'indirizzo
  noto può rispondere un dispositivo diverso, e saperlo è metà della diagnosi.
- **In cassa**: «qualcuno mi ha scritto?». La risposta sta nel registro, nei
  dispositivi che vi hanno depositato una versione. **Una porta aperta dice che
  il servizio c'è, non che qualcuno l'abbia usata**, ed è la differenza fra un
  collegamento che esiste e uno che serve.

Quando fallisce, il messaggio porta con sé il rimedio: «nessuna cassa trovata»
suggerisce di scrivere l'indirizzo a mano, perché il caso più frequente è il
multicast filtrato. Un messaggio che dice solo «errore» lascia chi legge senza
mosse.

### Svuotare, e cosa non si svuota

Gli ordini stanno in un file SQLite che sopravvive alla chiusura — è il punto
dell'architettura — e questo rende scomodo rifare una dimostrazione: l'unico
modo di ripartire da una lista vuota era disinstallare l'app.

`DemoReset` toglie ordini, coda e conflitti, e **svuota anche il registro
locale**. È quest'ultima la parte che rende il gesto efficace: le proprie
versioni non tornerebbero comunque indietro, perché il registro esclude sempre
chi chiede, ma su un dispositivo che fa la cassa il registro è il posto da cui
gli ordini di *tutti* possono ricomparire alla prima sincronizzazione. Da qui la
regola scritta nella conferma: **si svuota su entrambi i dispositivi**.

**Il contatore logico non si azzera**, di proposito. È l'unica cosa che lì non è
dato di prova: farlo tornare indietro romperebbe l'ordine totale su cui si regge
la convergenza, e una modifica futura risulterebbe più vecchia di una passata.
Costa un numero che cresce; toglierlo costerebbe la correttezza.

È registrato solo in modalità dimostrativa, come il secondo dispositivo
simulato, e la pagina lo riceve come callback opzionale: in un locale vero
cancellare il servizio di una serata non è un'azione da offrire a chi prende le
comande.

### La piattaforma Windows

Il progetto ha `windows/` per una ragione pratica: la prova a due dispositivi
richiede due dispositivi, e il PC fa il secondo senza chiedere in prestito un
altro telefono. I due pacchetti con una parte nativa reggono il passaggio —
sqlite3 arriva come DLL accanto all'eseguibile, `connectivity_plus` ha la sua
implementazione Windows — verificato ad app avviata e non solo compilata.

In CI c'è un lavoro `build-windows` che compila e basta: i test girano già su
Linux e ripeterli direbbe la stessa cosa, mentre un errore di MSVC o un pacchetto
senza implementazione Windows lì non si vedrebbe mai.

### L'app vera, su un sistema operativo vero

Widget test e golden girano sul **motore di Flutter**, non su Android: i canali di
piattaforma non ci sono, il file su disco nemmeno, e nessuna porta viene mai aperta
davvero. Resta scoperto tutto ciò che sta sotto al livello Dart — `path_provider` che
restituisce una cartella scrivibile, sqlite3 caricato dal sistema, un socket che si lega,
il permesso `INTERNET` dichiarato nel manifest — e sono precisamente le cose che
funzionano sulla macchina di chi sviluppa e falliscono su quella di qualcun altro.

`integration_test/app_test.dart` monta il grafo di produzione senza sostituzioni: nessun
doppio, nemmeno per il tempo. Quattro prove, scelte perché **nessun altro test le può
fare**: l'app che parte su un file nuovo e ci ritrova un ordine dopo un riavvio, lo
svuotamento che sopravvive allo stesso riavvio, il nodo primario che apre davvero una
porta e risponde a chi bussa, e la diagnostica che riferisce chi ha scritto nel registro.

**Il primo tentativo era vacuo, e l'ha detto la falsificazione.** Sostituendo la base dati
con una in memoria, i test restavano verdi: ripompando lo stesso widget radice Flutter lo
riconosce e riusa gli elementi, quindi `BlocProvider.create` non viene richiamato e il
cubit vecchio sopravvive con dentro il repository di prima. Smontavo le registrazioni e
lasciavo in piedi chi le usava, e il test misurava la memoria invece del file. Smontare
l'albero prima di chiudere non è pulizia: è la sostanza del riavvio.

I test usano una porta propria, la 53171. `HttpServer.bind` è chiamato con `shared: true`,
quindi legare una porta già presa **riesce** e le richieste si dividono fra i due
ascoltatori: con l'app vera aperta in modalità cassa sulla stessa macchina, i test
avrebbero potuto parlare con lei e passare per la ragione sbagliata.

In pipeline girano su un emulatore Android con KVM abilitato — senza, l'emulatore parte in
emulazione software e impiega minuti invece di secondi.

## Osservabilità e interruttore remoto

La domanda da cui nasce è una da colloquio: *hai rilasciato un bug grave, cosa fai?* Un'app
già installata su trenta tablet non si aggiorna in dieci minuti. Le risposte possibili sono
tre, e servono tutte: **saperlo** (Crashlytics), **vedere se ha fatto danni** anche senza
crash (una metrica di prodotto), **spegnere la parte rotta** senza pubblicare niente (Remote
Config).

### Tre contratti, e uno aspettava da sempre

`Logger` esisteva dalla prima voce, e il suo commento diceva già perché: `print` non si può
reindirizzare a Crashlytics. `CrashlyticsLogger` lo implementa, e nessuna delle classi che
registrano qualcosa è cambiata. Accanto sono arrivati `FeatureFlags` e `ProductMetrics`, con lo
stesso schema: il contratto in `core/`, l'implementazione Firebase in `core/firebase/`, che è
l'unica cartella a importare un pacchetto di Firebase.

I tre pezzi viaggiano dentro `Observability`, e non separati, perché nascono insieme: o c'è
un progetto Firebase configurato e ci sono tutti e tre, o non c'è e non c'è nessuno.
`Observability.off` è l'app com'era prima: logger muto, flag ai valori di sempre, metriche
che non vanno da nessuna parte. **L'assenza di Firebase cambia cosa si sa dell'app, non cosa
fa l'app.**

### Il segreto che non è una password

`google-services.json` non è nel repository. Non è una password: Google scrive che le chiavi
limitate ai servizi Firebase non vanno trattate come segreti, perché a proteggere i dati sono
altre regole. Ma il file identifica il progetto, e chi lo ha può mandargli crash e metriche
finti. La gestione sta in tre posti, con tre regole diverse:

| Dove | Il file | Cosa succede |
|---|---|---|
| Sul computer di chi sviluppa | in `.gitignore`, si rigenera con `firebase apps:sdkconfig` | Firebase acceso |
| Chi clona, e la pipeline dei test | assente | Gradle **non applica** i due plugin di Firebase e compila lo stesso; l'app parte con l'osservabilità spenta |
| La pipeline di rilascio | ricostruito dal segreto `GOOGLE_SERVICES_JSON` | si **ferma** se il segreto manca o non è JSON valido, e dopo la compilazione controlla che nell'APK ci sia `google_app_id` |

Il ripiego silenzioso della seconda riga è voluto, ed è lo stesso della firma: chi clona deve
poter compilare. Nella terza non è accettabile, perché un rilascio senza crash registrati e
senza interruttore è esattamente quello in cui un bug grave non si vede e non si ferma. Il
controllo guarda l'APK e non la configurazione: `google_app_id` lo scrive solo il plugin dei
servizi Google, quindi se manca l'osservabilità è spenta, qualunque cosa dicano i file.

**Verificato togliendo il file.** La compilazione riesce e nell'APK `google_app_id` non c'è.
Installata sul telefono, l'app parte, mostra i suoi ordini e scrive nel log *Firebase non
configurato, osservabilità spenta*. E dall'altra parte, con la `v0.2.0`: la pipeline di
rilascio ha ricostruito il file dal segreto, ha trovato `google_app_id` nell'APK, e l'app con
Firebase acceso è partita sull'emulatore senza Play Services.

### L'interruttore: dove sta, e perché vale subito

Il flag è `peer_sync_enabled`, e spegne la sincronizzazione in rete locale, cioè la parte più
recente e più complicata del sistema. È un solo punto: `LanCoordinator`, da cui passano
tutte le strade verso la rete locale. Spento, il coordinatore si comporta come se nessuno
avesse configurato niente:

- niente server, quindi la cassa smette di rispondere agli altri tablet;
- niente annunci mDNS;
- niente elezione, che parte solo da chi è in sala.

**Le impostazioni non si toccano.** Il flag è una decisione di chi gestisce il parco, il ruolo
è una decisione di chi ha installato il tablet: riaccendere deve restituire a ognuno quello
che aveva, e lo fa. Chi apre il foglio della rete locale a flag spento legge che è sospesa da
remoto, altrimenti imposterebbe la cassa, non vedrebbe arrivare niente e cercherebbe il guasto
nel posto sbagliato.

Il coordinatore rilegge il flag a ogni giro della coda, ma un giro parte solo da un ordine
preso, da un comando o dalla rete che torna. Per questo `drainOnFlagChange` fa girare la coda
appena il flag cambia: senza, la cassa spenta da remoto continuerebbe a rispondere fino al
prossimo ordine, cioè proprio mentre la si vuole fermare. Il valore arriva con
l'aggiornamento in tempo reale di Remote Config, che non rispetta l'intervallo minimo fra una
lettura e l'altra: quello, un'ora, vale solo per la lettura all'avvio.

`remote_kill_switch_test.dart` lo prova con una porta vera: «smette di rispondere» vuol dire
che una connessione viene rifiutata. **Falsificato due volte:** facendo ignorare il flag al
coordinatore falliscono quattro test su cinque; togliendo il giro della coda al cambio del
flag, falliscono i due che lo riguardano.

### La prova sul telefono

Il criterio della voce è *spegnere una funzionalità da remoto senza pubblicare una nuova
versione*, e si prova solo con un progetto vero e un telefono vero. Samsung Galaxy S20,
Android 13, APK di rilascio, 16 settembre 2026. Dal PC sulla stessa Wi-Fi un controllo prova
la porta della cassa più volte al secondo, e l'ora della pubblicazione è quella registrata da
Firebase nella cronologia delle versioni.

| Cosa | Ora (UTC) |
|---|---|
| Sul telefono si sceglie «questo dispositivo è la cassa»: la porta si apre | 12:58:01 |
| Nella console si pubblica `peer_sync_enabled = false` | 12:58:36 |
| **La porta si chiude** | 13:00:19 |
| Nella console si ripubblica `true` | 13:02:14 |
| **La porta si riapre**, senza toccare il telefono | 13:03:56 |

Fra la pubblicazione e l'effetto passano **103 e 102 secondi**. Il processo dell'app è lo stesso
per tutta la prova: nessun riavvio, nessuna installazione, e il ruolo di cassa torna da solo
quando il flag si riaccende.

**Dove si perdano quei cento secondi non l'ho isolato.** Nei test il lato dell'app si muove
appena riceve il cambio, senza attese proprie. Due misure così vicine fanno pensare a un ritardo sistematico nella
consegna dell'aggiornamento più che a latenza di rete, ma non l'ho dimostrato. Per un
interruttore di emergenza meno di due minuti bastano: l'alternativa è un rilascio.

### Cosa arriva a Crashlytics, e cosa no

Due strade da cui un errore esce senza che nessuno lo prenda: `FlutterError.onError` per
quelli dentro il framework, `PlatformDispatcher.onError` per tutti gli altri, cioè il caso
tipico di un `Future` fallito in una sincronizzazione partita da un evento. Senza la seconda,
Crashlytics vedrebbe solo i crash dell'interfaccia.

Dal logger passano gli avvisi, con una regola: **un avviso diventa un errore registrato solo
se porta con sé un errore.** Un ordine abbandonato o un drenaggio fallito devono comparire in
un grafico anche se l'app non è caduta. Un conflitto sul tavolo o un annuncio mDNS non
riuscito sono il sistema che fa il suo lavoro in condizioni difficili: restano come contesto,
nel registro breve che Crashlytics allega al prossimo errore.

In debug la raccolta è spenta: i crash di chi scrive il codice finirebbero nel grafico dei
tablet in sala. **Verificato sul telefono** con un crash indotto da `adb shell am crash`: al
riavvio l'SDK ha inviato il rapporto e il servizio ha risposto `200`.

### La metrica: un evento per invio

`order_synced`, un evento per ogni invio riuscito. Il conto sta nel `SyncWorker` e non in chi
lo chiama, perché i chiamanti sono tre: la rete che torna, un comando e il lavoro di sistema.
Contare in uno solo perderebbe gli altri due senza che niente lo segnali. Anche il lavoro in
background accende Firebase, per la stessa ragione.

Un evento per invio e non uno per giro con il numero dentro: Analytics conta gli eventi da
sé, per ora e per giorno, mentre un numero dentro un parametro andrebbe prima registrato a
mano come metrica personalizzata nella console, un passo che nessun file del repository
ricorderebbe. **Verificato sul telefono**, in modalità debug di Analytics: l'evento parte al
primo ordine e il caricamento risponde `204`.

### Windows, e quanto costa

Sulla build Windows Firebase resta spento. Crashlytics e Analytics su Windows non esistono.
Remote Config sì, attraverso l'SDK C++ per desktop, che Google dichiara in beta e adatto solo
allo sviluppo, non al codice distribuito. Il Windows di questo progetto fa da cassa nella
prova a due dispositivi, e non vale un'eccezione a quella avvertenza.

Spento non vuol dire gratis. `firebase_core` ha un'implementazione Windows, e la sua
compilazione **scarica l'SDK C++ intero, 918 MB**, anche se nessuna riga lo usa. È il prezzo
di una dipendenza che non si può escludere per piattaforma. In pipeline il lavoro
`build-windows` durava fra 3 minuti e 38 secondi e 3 minuti e 52 secondi nelle ultime quattro
esecuzioni senza Firebase, e 5 minuti e 51 secondi nella prima con: **due minuti in più a ogni
push**, su una misura sola. Una cache dell'SDK potrebbe recuperarne una parte, al prezzo di un
passo in più da tenere allineato alla versione di `firebase_core`. Non l'ho provata.

Sul telefono, l'APK di rilascio passa da 59.120.261 a 60.367.130 byte: **1,2 MB in più**.

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
| Un secondo dispositivo esisteva solo come ipotesi | `FakeServer` condiviso fra due `TestEnv`: due tablet veri, con la propria rete e il proprio contatore |
| La migrazione dello schema era un ramo di codice mai eseguito | `migration_test.dart` apre una base dati in formato versione 1, con dentro degli ordini |
| I conflitti si potevano descrivere ma non mostrare | `SecondDevice` scrive nel finto server come un altro tablet, e la sequenza che si esegue col dito è verificata da `second_device_test.dart` |

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

- **La firma di rilascio ripiega su quella di debug quando la chiave non c'è.**
  L'alternativa era far fallire la compilazione, e avrebbe reso il repository compilabile
  in rilascio solo da me. Il prezzo del ripiego è che `BUILD SUCCESSFUL` non significa più
  «APK distribuibile»: lo paga la pipeline di rilascio, che legge il certificato dell'APK e
  si ferma su `CN=Android Debug`. Verificato togliendo la chiave e ricompilando — l'APK
  esce firmato di debug senza un avviso.
- **La chiave è autofirmata e vale per entrambi i progetti dimostrativi.** Non è una
  identità verificata da nessuno: dice solo che due APK con lo stesso nome di pacchetto
  vengono dalla stessa mano. Per il Play Store servirebbe altro, e non è dove questi
  progetti vanno.
- **Nessuno use case fra cubit e repository.** Le operazioni sono due e dirette.
  Diventerebbero utili con logica composta fra più feature.
- **Una sola migrazione, ma vera.** La versione 2 aggiunge colonne con `ALTER TABLE`
  invece di ricreare le tabelle, ed è verificata da `migration_test.dart` su una base
  dati scritta a mano nella forma della versione 1, con dentro degli ordini. Non è
  pignoleria: su un tablet di sala quella base dati contiene ordini che il server non
  ha ancora visto.
- **Il fuso orario non sopravvive al deposito.** Gli istanti sono salvati come punto
  assoluto nel tempo e riletti come ora locale: il flag `isUtc` si perde. Per un
  applicativo che gira su un dispositivo solo non cambia niente; in un sistema con
  dispositivi in fusi diversi andrebbe salvato anche l'offset.
- **Il file non è cifrato.** Su un dispositivo di sala perso, gli ordini sono leggibili.
  Drift supporta SQLCipher e sarebbe un cambio di esecutore, non di codice.
- **La guardia di concorrenza del worker vive in memoria.** Un drenaggio chiesto a metà
  giro ne produce uno in più invece di partire in parallelo, ma solo dentro lo stesso
  isolate. Con il lavoro in background gli isolate sono due e le due guardie non si
  vedono: se coincidessero, lo stesso ordine partirebbe due volte. Non produce duplicati —
  l'idempotenza sull'id serve esattamente a questo — ma è una richiesta di rete sprecata, e
  un lock vero starebbe in una riga di tabella invece che in un campo in memoria. La
  guardia sulle decisioni dei conflitti ha lo stesso limite, ma lì non pesa: una decisione
  parte solo dall'interfaccia, mai dal lavoro in background.
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
- **I test di integrazione coprono l'avvio, non il ciclo di vita.** Girano l'app vera su
  un emulatore, ma non mettono alla prova ciò che succede quando Android la sospende, la
  uccide in background o la ripristina: il «riavvio» dei test è un rimontaggio nello stesso
  processo. Per quello servirebbe pilotare il sistema da fuori, con `adb`, e la pipeline
  diventerebbe un'altra cosa.
- **I golden non danno riscontro fuori da Linux.** Su Windows si saltano, quindi una
  regressione grafica introdotta qui si scopre solo dopo il push. L'alternativa — un
  riferimento per piattaforma — raddoppia le immagini da tenere allineate, e quella che non
  gira in CI resterebbe vecchia senza che nessuno se ne accorga.
- **Lamport, non vector clock.** Un vector clock distingue *concorrente* da
  *causalmente ordinato*; Lamport no, e con Lamport due modifiche davvero simultanee
  vengono ordinate arbitrariamente. Qui non serve: l'unica ambiguità che il sistema
  espone si riconosce da un confronto fra insiemi di righe, non dai contatori. In
  cambio, la revisione resta due campi e non cresce con il numero di dispositivi.
- **`fetchOrders` porta tutto, senza delta né paginazione.** Va bene per il servizio
  di una sera; con lo storico di un anno servirebbe un `since` e delle pagine. La
  forma del contratto è già quella giusta per aggiungerli.
- **Nessuna cancellazione distribuita.** Un ordine eliminato in locale ricompare alla
  prima sincronizzazione, perché per il server esiste ancora. Servirebbero le
  *tombstone*, cioè una cancellazione che è essa stessa un dato che si propaga. Le
  righe non hanno il problema, perché non si cancellano per costruzione.
- **Il secondo dispositivo è simulato, e sta nel codice di produzione.** Non è
  dietro un flag di compilazione né in un sorgente separato: è registrato solo
  in modalità demo e la pagina lo riceve come callback opzionale, ma il file
  viene compilato comunque. Con un backend vero al posto di `FakeRemoteApi`
  sparirebbe insieme a lui.
- **La scheda mostra le due versioni di quando il conflitto è nato.** Se nel
  frattempo l'altro dispositivo cambia ancora idea, il confronto non si aggiorna:
  la decisione riguarda comunque solo lo stato del tavolo, e le righe si uniscono
  in ogni caso, quindi l'esito resta corretto anche se la scheda invecchia.
- **Il conflitto resta sul dispositivo che lo ha visto.** Se A e B se lo trovano
  entrambi, entrambi devono aprirlo — poi la prima decisione chiude anche l'altro,
  ma nell'intervallo in due potrebbero decidere in modo opposto. Vincerebbe la
  revisione più alta, quindi il sistema resta coerente: è l'operatore che ha lavorato
  per niente.
- **Lo stato del tavolo non ha transizioni vincolate.** Da `pagato` si può tornare ad
  `aperto`, ed è voluto: è esattamente la scelta che la scheda di risoluzione offre
  all'operatore. Una macchina a stati che lo vietasse renderebbe irrisolvibile
  proprio il caso per cui la scheda esiste.
- **In rete locale non c'è né TLS né autenticazione.** Chi è sul Wi-Fi del locale
  è considerato fidato. I dispositivi non hanno un certificato e non c'è
  un'autorità che glielo firmi, quindi TLS vorrebbe dire certificati
  autofirmati e verifica disattivata — la stessa esposizione con più cerimonia.
  È una scelta dichiarata anche nel manifest, dove si vede.
- **L'elezione è semplificata.** Soglia fissa a tre giri, nessun consenso fra i
  dispositivi, nessun mandato che scade: solo un confronto fra identificativi che
  tutti calcolano allo stesso modo. Basta perché il caso da coprire è «la cassa si
  è spenta», non «qualcuno mente sul proprio identificativo».
- **L'ultima cassa vista vive in memoria.** Un riavvio dell'app la dimentica,
  quindi un'elezione avvenuta mentre il tablet era spento non provoca la
  ripubblicazione. Persisterla costerebbe una migrazione per un caso in cui gli
  ordini nuovi ricostruiscono comunque il registro.
- **Il servizio annunciato da chi è in sala non ascolta.** Dichiara una presenza,
  perché l'elezione deve poter contare i dispositivi, e nessuno ci si collega
  perché la ricerca filtra per ruolo. Farlo ascoltare davvero sarebbe più pulito e
  richiederebbe a ogni tablet una porta propria da gestire.
- **`NsdDiscovery` non ha test.** Parla con i canali di piattaforma, che in
  `flutter test` non esistono. È la ragione per cui non contiene decisioni: tutto
  ciò che si può sbagliare sta dietro `PeerDiscovery`, dove un doppio lo raggiunge.
- **La rete locale non è trattata su iOS.** Il pacchetto `nsd` lo supporta, ma
  servirebbe la dichiarazione `NSBonjourServices` nell'Info.plist e una verifica su
  un dispositivo Apple: prometterlo senza averlo provato sarebbe una dichiarazione
  non sostenuta, come già per il lavoro in background.
- **L'interruttore non raggiunge un tablet che non vede internet.** Ed è il limite da dire per
  primo, perché la rete locale esiste proprio per quando il cloud non si vede. Remote Config
  conserva su disco l'ultimo valore attivato, quindi un tablet che il flag spento lo ha
  ricevuto dovrebbe restare spento anche offline e dopo un riavvio: lo dice la documentazione,
  qui non è verificato.
- **Dalla pubblicazione all'effetto passano cento secondi**, misurati due volte, e la causa non
  è isolata.
- **I crash Dart non sono provati sul telefono.** Lì è provato il percorso completo con un crash
  Java indotto da `adb`. I due gestori Dart sono quattro righe senza un test, perché in
  `flutter test` Crashlytics non esiste.
- **Gli adattatori Firebase non hanno test**, per la stessa ragione di `NsdDiscovery`: parlano con
  i canali di piattaforma. Tutto ciò che si può sbagliare sta dietro i tre contratti, dove un
  doppio lo raggiunge.
- **La metrica conta gli invii, non gli ordini.** Un ordine a cui si aggiunge una riga conta
  due: è la misura del lavoro della coda, non dei coperti.
- **Su Windows l'osservabilità è spenta**, ma la compilazione scarica lo stesso l'SDK C++ di
  Firebase.
