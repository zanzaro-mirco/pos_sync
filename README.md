# pos_sync

App Flutter **offline-first** per la raccolta ordini in sala: gli ordini si creano e si
consultano anche senza rete, e vengono sincronizzati quando la connettività torna —
senza mai generare duplicati.

[![CI](https://github.com/zanzaro-mirco/pos_sync/actions/workflows/ci.yml/badge.svg)](https://github.com/zanzaro-mirco/pos_sync/actions/workflows/ci.yml)

## Il problema

In un ristorante il Wi-Fi cade. In un negozio il terminale perde la rete a metà di una
transazione. L'approccio abituale — la UI chiama l'API e mostra uno spinner — in queste
condizioni produce un'app inutilizzabile e, peggio, ordini duplicati quando l'utente
riprova.

Questo progetto implementa l'alternativa: **il database locale è la sorgente di verità,
la rete è un dettaglio di sincronizzazione**.

## Come funziona

```
   UI (Cubit)  ◄── osserva OrdersSnapshot (ordini + pendenze + conflitti, coerenti)
       │  scrive solo in locale, non sa se c'è rete
       ▼
  OrdersRepository ──► OrderOutboxTransaction ──► SQLite (Drift)
       │   timbra le modifiche  (ordine + outbox, atomico)   ▲
       │   con LogicalClock                                  │
       ▼                                                     │
   OutboxStore ──► SyncWorker ──► RetryPolicy ──► Backoff    │
                       ▲  drain(): 1. spinge  2. tira        │
                       │                                     │
                       ├── AutoSync   ◄── ConnectivityMonitor (offline ➜ online)
                       └── WorkManager (Android, ad app chiusa)
                       │
                       ├──► RemoteApi (DTO) ──► backend idempotente su order.id
                       │
                       └──► InboundMerger ──► ConflictPolicy ──┬─► fonde
                              tira le versioni degli altri     └─► o chiede
```

### Le decisioni che contano

**1. L'id dell'ordine è generato dal client.**
Non dal server. È la chiave che rende l'invio idempotente: se il server registra l'ordine
ma la risposta si perde, il ritentativo usa lo stesso id e il server riconosce il duplicato.
Senza questo, ogni timeout diventa un ordine doppio — che in un locale è un danno contabile,
non un fastidio.

**2. Ordine e voce di outbox si scrivono insieme.**
O vengono salvati entrambi o nessuno dei due. È l'invariante che impedisce di avere un
ordine in locale che il server non vedrà mai.

**3. Il backoff ha il jitter.**
Senza jitter, un parco di dispositivi che perde la rete nello stesso momento la ritrova
nello stesso momento e riprova tutto insieme, mettendo giù il backend proprio quando torna
disponibile. Il jitter distribuisce i tentativi nel tempo.

**4. Errori temporanei ed errori definitivi sono trattati in modo diverso.**
Un timeout si ritenta; un payload rifiutato no — ritentarlo all'infinito significa solo
consumare batteria e riempire i log.

**5. La coda riparte sulla *transizione* di rete, non sull'evento.**
Passare da Wi-Fi a dati mobili è un cambiamento di rete, non di stato: agire su ogni evento
farebbe ripartire la coda a ogni sobbalzo del segnale. E lo stato all'avvio conta come una
transizione, altrimenti un'app riaperta sotto rete non riceverebbe mai un cambiamento e la
coda del giorno prima resterebbe ferma per sempre.

**6. Chi ha modificato per ultimo lo decide un contatore logico, non l'orologio.**
L'ora di sistema è un dato che l'utente può cambiare dalle impostazioni: basta un tablet
indietro di due minuti perché le sue modifiche non vincano mai. Ogni modifica porta una
`Revision` — un contatore di Lamport più l'identificativo del dispositivo a rompere la
parità — e il risultato è un ordine **totale**, uguale su tutti i dispositivi.

**7. Ogni tipo di dato ha la sua politica di fusione.**
Le righe dell'ordine sono append-only e si uniscono: due camerieri che aggiungono piatti
non sono in conflitto, e l'unione è commutativa, quindi il risultato non guarda l'ordine di
arrivo. Lo stato del tavolo invece è last-write-wins, perché un tavolo non può essere
insieme aperto e pagato.

**8. Dove fondere sarebbe sbagliato, il codice si ferma e chiede.**
Se il tavolo risulta pagato e l'altra versione porta righe che chi ha incassato non aveva
davanti, unione e last-write-wins darebbero un tavolo pagato con dentro roba non pagata:
plausibile, sbagliato, e silenzioso fino alla chiusura di cassa. Quel caso finisce in una
scheda con due pulsanti. Tutto il resto converge da solo — un sistema che chiede troppo
spesso viene ignorato.

## Architettura

Le scelte, i pattern applicati e i limiti dichiarati sono in
[ARCHITECTURE.md](ARCHITECTURE.md).

```
lib/
  core/
    clock.dart                   il tempo come dipendenza iniettabile
    di.dart                      registrazione con get_it
  features/orders/
    domain/                      modelli e contratti — nessuna dipendenza esterna
      order.dart
      order_line.dart
      outbox_entry.dart
      orders_repository.dart
      sync_status.dart
    data/
      order_store.dart           interfaccia della persistenza
      in_memory_order_store.dart implementazione usata da test e demo
      local/                     schema, database e deposito su SQLite (Drift)
      remote_api.dart            contratto + backend simulato controllabile
      connectivity_plus_monitor.dart  adattatore sul plugin di rete
      orders_repository_impl.dart
    sync/
      backoff.dart               esponenziale con jitter
      sync_worker.dart           drenaggio della coda
      connectivity_monitor.dart  contratto sulla rete + monitor controllabile
      auto_sync.dart             dalla rete che torna al drenaggio, con jitter
    presentation/
      orders_cubit.dart
      orders_state.dart
      orders_page.dart
      order_tile.dart            la riga della lista, con l'indicatore di stato
```

Le dipendenze puntano verso `domain`, mai il contrario: la logica di sincronizzazione si
testa senza Flutter, senza database e senza rete.

## Test

```bash
flutter pub get
flutter test
```

I test coprono i casi che contano, non le righe facili:

| Scenario | Cosa verifica |
|---|---|
| Rete assente | L'ordine resta in coda, lo stato resta `pending`, il tentativo viene riprogrammato |
| Backoff non trascorso | Il worker salta la voce invece di martellare il server |
| Tentativi esauriti | L'ordine viene marcato `failed` e tolto dalla coda |
| **Risposta persa** | Due invii, **un solo ordine distinto** lato server — l'idempotenza funziona |
| Errore permanente | Nessun ritentativo |
| Voce orfana | La coda si ripulisce da sola |
| Due `drain()` concorrenti | Un solo invio |
| JSON incompleto o malformato | Il record si scarta, l'app non crasha |
| Politica di ritentativo | Testata da sola, senza passare dal worker |
| **Contratto del deposito** | La stessa suite passa su `InMemoryOrderStore` e su `DriftOrderStore` |
| Scrittura interrotta a metà | La transazione annulla tutto: nessun ordine senza la sua voce di coda |
| Chiusura e riapertura | Ordini, righe, stato e coda si ritrovano identici |
| Stato sconosciuto nel file | Degrada a `pending` invece di far fallire la lettura |
| **Ritorno della rete** | Il monitor passa a online e **la coda si svuota da sola**, senza chiamate esplicite |
| Wi-Fi che diventa dati mobili | Un secondo evento `online` non fa ripartire la coda |
| Rete già presente all'avvio | La coda sopravvissuta alla sessione precedente viene drenata lo stesso |
| Rete che ricade durante l'attesa | Il drenaggio non parte: nessun tentativo sprecato |
| Jitter sul ritorno della rete | Il ritardo sta nei limiti e non è costante |
| Drenaggio automatico che esplode | Finisce nel log invece di far cadere la zona asincrona |
| I tre stati della schermata | Vuoto, con ordini ed errore — e "nessun ordine" non viene confuso con "non riesco a leggerli" |
| Comandi dell'interfaccia | Premere sincronizza *sincronizza*: il test conta le chiamate arrivate al cubit |
| Etichette per il lettore di schermo | Ogni stato si annuncia, il colore non è l'unico portatore dell'informazione |
| **Aspetto della riga** | Quattro golden: cambiare di **uno** il valore di un colore fa fallire il test (0,98%, 253 pixel) |
| **Due dispositivi, ordine invertito** | Le stesse modifiche applicate in sequenza opposta portano allo **stesso stato finale** |
| Tutte e sei le sequenze di tre modifiche | La convergenza è una proprietà, non un caso fortunato |
| Modifica fatta dopo aver visto quella altrui | Vince, anche se il contatore di chi la fa sarebbe più basso |
| **Pagato contro righe mai viste** | Non si fonde in silenzio: si apre un conflitto su entrambi i dispositivi |
| Decisione presa su un dispositivo | Chiude il conflitto anche sull'altro: nessuno decide due volte |
| Qualunque delle due scelte | Nessuna riga sparisce — è la ragione per cui è sicuro chiedere |
| Un dispositivo offline | Non blocca l'altro, e al rientro converge |
| **Migrazione dello schema v1 → v2** | Una base dati scritta dalla versione precedente, con dentro ordini non ancora inviati, arriva intatta |
| **Incassare e basta** | *Non* è un conflitto: le due versioni si fondono, il pagamento arriva — il caso normale non interrompe nessuno |
| La sequenza della dimostrazione | Incassa, aggiungi, sincronizza: il conflitto nasce, e la scheda dice quanti articoli non erano nel conto |
| Sincronizzare a conflitto aperto | Nessuna scheda duplicata, per quante volte si sincronizzi |
| Le azioni sul tavolo | Il foglio non propone lo stato in cui il tavolo già si trova, e la voce dimostrativa sparisce se non le si passa un secondo dispositivo |

Tempo, identificativi, log, politica di ritentativo, **contatore logico e politica di
fusione** sono tutti iniettati: i test sul backoff girano in millisecondi invece di
attendere minuti reali, gli id sono deterministici (`id-1`, `id-2`), si può asserire su
cosa è stato registrato nel log, e due `TestEnv` che condividono un `FakeServer` sono due
tablet nello stesso locale.

Due invarianti sono state verificate **al contrario**, rompendole apposta: sostituendo il
confronto delle revisioni con «vince chi arriva per ultimo», i due dispositivi divergono e
lo stesso tavolo risulta servito su uno e aperto sull'altro; togliendo il `witness`
dell'orologio logico, i due restano d'accordo ma scartano l'ultima decisione presa;
togliendo il controllo sui conflitti già aperti, tre sincronizzazioni producono tre schede
identiche per la stessa decisione.

## I quattro stati di un ordine

Sono le immagini di riferimento dei golden test, prese direttamente dalla suite:

| Stato | |
|---|---|
| Da inviare | ![in attesa](test/goldens/order_tile_pending.png) |
| Invio in corso | ![invio in corso](test/goldens/order_tile_sending.png) |
| Sincronizzato | ![sincronizzato](test/goldens/order_tile_synced.png) |
| Invio fallito | ![fallito](test/goldens/order_tile_failed.png) |

I colori non vengono dalla `ColorScheme`: il seme del tema è una decisione di marca e può
cambiare, mentre "riuscito" e "fallito" devono restare leggibili come stati. E il colore non
è l'unico portatore dell'informazione — le icone sono diverse fra loro e ognuna ha
un'etichetta per il lettore di schermo.

I riferimenti si generano e si verificano **su Linux**, la piattaforma della pipeline, e
altrove i test si saltano. Non è prudenza: gli stessi quattro riferimenti generati su Windows
e confrontati su Linux differiscono dal 3,27% al 3,91% dei pixel per il solo antialiasing dei
glifi, mentre il cambiamento da catturare ne vale lo 0,98%. Una soglia di tolleranza
dovrebbe accettare il rumore e ingoierebbe il segnale. Per rigenerarli c'è il workflow
[`goldens.yml`](.github/workflows/goldens.yml), che pubblica le immagini come artefatto
invece di committarle da solo.

## Provare la demo

L'app parte con un backend simulato, e in modalità demo **il finto server segue la rete vera
del dispositivo**. Il giro completo si prova così:

1. Attiva la modalità aereo.
2. Crea due ordini: restano in locale, il contatore "da inviare" sale.
3. Disattiva la modalità aereo e non toccare niente.
4. Entro pochi secondi gli ordini passano a sincronizzati da soli.

Il pulsante di sincronizzazione resta per forzare il giro a mano. Gli ordini finiscono in un
file SQLite: chiudendo l'app e riaprendola sono ancora lì, con il loro stato.

### Far nascere un conflitto

Toccando una riga si aprono le azioni sul tavolo. L'ultima simula un secondo tablet: senza
di essa il conflitto non potrebbe comparire, perché sul dispositivo c'è un client solo e il
rientro non troverebbe mai niente da fondere.

1. Crea un ordine — il numero del tavolo si può **ripetere**, ed è il punto.
2. Tocca la riga → **«L'altro tablet incassa il tavolo»**.
3. Tocca di nuovo la riga → **«Aggiungi una comanda»**.
4. Compare la scheda arancione: *il tavolo risulta pagato, ma 2 articoli non erano nel
   conto*. Il contatore nella barra sale.
5. Scegli: «tieni il pagamento» oppure «tieni il tavolo aperto». Qualunque sia la scelta,
   **la comanda resta** — è la ragione per cui è sicuro chiedere.

Il secondo passo da solo non produce niente, ed è corretto: se il pagamento arrivasse prima
della comanda le due versioni conterrebbero le stesse righe e si fonderebbero in silenzio.
Il conflitto nasce perché la versione pagata **non contiene** ciò che è arrivato dopo.

## Stato e prossimi passi

La logica di sincronizzazione è completa e testata, i dati sopravvivono alla chiusura
dell'app e la coda riparte da sola quando la rete torna. Cosa manca per un uso reale:

- [x] Persistenza su SQLite con Drift — `DriftOrderStore` implementa gli stessi quattro
      contratti dell'implementazione in memoria; fuori dal livello dati è cambiata solo
      la composition root
- [x] Ascolto dei cambi di connettività con `connectivity_plus` dietro `ConnectivityMonitor`:
      `drain()` riparte sulla transizione offline ➜ online, con jitter
- [x] `WorkManager` su Android per drenare la coda anche ad app chiusa — unico pezzo non
      verificabile in CI, si osserva con `adb shell dumpsys jobscheduler` e `logcat`
- [x] Widget test sulla `OrdersPage` e golden test sulla riga dell'ordine, in CI con la
      versione di Flutter fissata
- [ ] Client HTTP reale al posto di `FakeRemoteApi`
- [x] Gestione dei conflitti fra dispositivi — contatore logico di Lamport, righe
      append-only e stato del tavolo last-write-wins, con il caso ambiguo esposto
      all'operatore invece che risolto in silenzio
- [ ] Test end-to-end su emulatore con `integration_test`

## Licenza

MIT
