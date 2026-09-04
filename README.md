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
   UI (Cubit)  ◄── osserva OrdersSnapshot (ordini + pendenze, coerenti)
       │  scrive solo in locale, non sa se c'è rete
       ▼
  OrdersRepository ──► OrderOutboxTransaction ──► SQLite (Drift)
       │                  (ordine + outbox, atomico)      ▲
       ▼                                                  │
   OutboxStore ──► SyncWorker ──► RetryPolicy ──► Backoff │
                       ▲  drain(): invia le voci scadute  │
                       │                                  │
                       ├── AutoSync   ◄── ConnectivityMonitor (offline ➜ online)
                       └── WorkManager (Android, ad app chiusa)
                       │
                       ▼
                   RemoteApi (DTO) ──► backend idempotente su order.id
```

### Le quattro decisioni che contano

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

Tempo, identificativi, log e politica di ritentativo sono tutti iniettati: i test sul
backoff girano in millisecondi invece di attendere minuti reali, gli id sono
deterministici (`id-1`, `id-2`) e si può asserire su cosa è stato registrato nel log.

## Provare la demo

L'app parte con un backend simulato, e in modalità demo **il finto server segue la rete vera
del dispositivo**. Il giro completo si prova così:

1. Attiva la modalità aereo.
2. Crea due ordini: restano in locale, il contatore "da inviare" sale.
3. Disattiva la modalità aereo e non toccare niente.
4. Entro pochi secondi gli ordini passano a sincronizzati da soli.

Il pulsante di sincronizzazione resta per forzare il giro a mano. Gli ordini finiscono in un
file SQLite: chiudendo l'app e riaprendola sono ancora lì, con il loro stato.

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
- [ ] Client HTTP reale al posto di `FakeRemoteApi`
- [ ] Widget test sulla `OrdersPage` (le `Key` sono già in posizione)
- [ ] Gestione dei conflitti fra dispositivi

## Licenza

MIT
