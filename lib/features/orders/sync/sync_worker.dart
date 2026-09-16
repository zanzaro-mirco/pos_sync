import '../../../core/clock.dart';
import '../../../core/logger.dart';
import '../../../core/product_metrics.dart';
import '../data/order_store.dart';
import '../data/remote_api.dart';
import '../domain/order.dart';
import '../domain/outbox_entry.dart';
import '../domain/sync_status.dart';
import 'inbound_merger.dart';
import 'retry_policy.dart';

/// Esito di un ciclo di drenaggio della coda.
class SyncResult {
  const SyncResult({
    this.sent = 0,
    this.retried = 0,
    this.failed = 0,
    this.skipped = 0,
    this.inbound = const MergeResult(),
  });

  /// Inviati con successo e rimossi dalla coda.
  final int sent;

  /// Falliti con errore recuperabile, riprogrammati.
  final int retried;

  /// Falliti in modo definitivo.
  final int failed;

  /// Non ancora scaduti: il backoff non è trascorso.
  final int skipped;

  /// Cosa è arrivato dagli altri dispositivi.
  final MergeResult inbound;

  bool get isIdle => sent == 0 && retried == 0 && failed == 0 && inbound.isIdle;

  SyncResult operator +(SyncResult o) => SyncResult(
        sent: sent + o.sent,
        retried: retried + o.retried,
        failed: failed + o.failed,
        skipped: skipped + o.skipped,
        inbound: inbound + o.inbound,
      );

  @override
  String toString() => 'SyncResult(sent: $sent, retried: $retried, '
      'failed: $failed, skipped: $skipped, inbound: $inbound)';
}

/// Drena la coda di uscita verso il backend.
///
/// Unica responsabilità: orchestrare. *Quando* riprovare lo decide la
/// [RetryPolicy], *quanto* aspettare lo decide il backoff dentro la politica,
/// *dove* finiscono i messaggi lo decide il [Logger]. Il worker si limita a
/// mettere in fila i passi.
///
/// Non ha timer propri: espone `drain()` e qualcuno lo chiama — un timer, un
/// cambio di stato della rete, un pull-to-refresh. Così la logica resta
/// interamente testabile senza attese reali.
class SyncWorker {
  SyncWorker({
    required OrderStore orderStore,
    required OutboxStore outboxStore,
    required RemoteApi api,
    RetryPolicy? retryPolicy,
    InboundMerger? inbound,
    Clock clock = const SystemClock(),
    Logger logger = const SilentLogger(),
    ProductMetrics metrics = const NoProductMetrics(),
  })  : _orders = orderStore,
        _outbox = outboxStore,
        _api = api,
        _inbound = inbound,
        _retryPolicy = retryPolicy ?? BackoffRetryPolicy(),
        _clock = clock,
        _logger = logger,
        _metrics = metrics;

  final OrderStore _orders;
  final OutboxStore _outbox;
  final RemoteApi _api;
  final RetryPolicy _retryPolicy;

  /// Il verso di rientro. Opzionale: un dispositivo che non deve fondere
  /// niente — la modalità demo a un solo dispositivo, o un test che guarda
  /// solo la coda — non paga il costo di un giro di rete in più.
  final InboundMerger? _inbound;
  final Clock _clock;
  final Logger _logger;

  /// Dove finisce il conto degli invii riusciti.
  ///
  /// Qui e non in chi chiama `drain()`: i chiamanti sono tre — la rete che
  /// torna, un comando, il lavoro di sistema — e contare in uno solo di loro
  /// perderebbe gli altri due senza che niente lo segnali.
  final ProductMetrics _metrics;

  /// Il drenaggio in corso, se ce n'è uno.
  Future<SyncResult>? _running;

  /// Se qualcuno ha chiesto un drenaggio mentre ne girava già uno.
  bool _requestedAgain = false;

  /// Svuota la coda, e la risvuota finché qualcuno continua a chiederlo.
  ///
  /// Una chiamata che arriva a metà giro non avvia un secondo drenaggio in
  /// parallelo, che invierebbe le stesse voci due volte. Ma non viene nemmeno
  /// scartata, come succedeva prima: il giro in corso, finito, ne fa un altro,
  /// e chi ha chiamato aspetta anche quello. Scartarla lasciava in coda un
  /// ordine creato durante il drenaggio finché qualcos'altro non faceva
  /// ripartire la coda — un comando, un cambio di rete, o il lavoro di sistema
  /// dopo un quarto d'ora.
  ///
  /// Più chiamate durante lo stesso giro ne producono uno solo in più: il
  /// secondo giro legge la coda intera, quindi vede tutto ciò che è arrivato.
  Future<SyncResult> drain() {
    final Future<SyncResult>? running = _running;
    if (running != null) {
      _requestedAgain = true;
      return running;
    }
    return _running = _drainUntilQuiet();
  }

  Future<SyncResult> _drainUntilQuiet() async {
    try {
      SyncResult result = const SyncResult();
      do {
        _requestedAgain = false;
        result = result + await _drainOnce();
      } while (_requestedAgain);
      // Un invio riuscito conta uno, quindi un ordine a cui si aggiunge una
      // riga ne conta due. È la misura del lavoro della coda, non dei coperti.
      if (result.sent > 0) _metrics.ordersSynced(result.sent);
      return result;
    } finally {
      // Fra il controllo del ciclo e questa riga non c'è nessuna attesa: una
      // chiamata non può infilarsi in mezzo, trovare il drenaggio ancora
      // registrato e restare senza il suo giro.
      _running = null;
    }
  }

  /// Un ciclo completo: prima spinge la coda, poi tira quello che hanno fatto
  /// gli altri.
  ///
  /// L'ordine non è casuale. Spingere per primi fa sì che la fusione avvenga
  /// contro un server che conosce già le modifiche locali: al contrario, ogni
  /// giro produrrebbe una fusione basata su una versione del server più
  /// vecchia di quella che stiamo per mandarle.
  Future<SyncResult> _drainOnce() async {
    SyncResult result = const SyncResult();
    final DateTime now = _clock.now();

    for (final OutboxEntry entry in await _outbox.pendingOutbox()) {
      result = result + await _process(entry, now);
    }

    final InboundMerger? inbound = _inbound;
    if (inbound != null) {
      result = result + SyncResult(inbound: await inbound.pull());
    }
    return result;
  }

  Future<SyncResult> _process(OutboxEntry entry, DateTime now) async {
    if (!entry.isDueAt(now)) return const SyncResult(skipped: 1);

    final Order? order = await _orders.orderById(entry.orderId);
    if (order == null) {
      // Voce orfana: l'ordine non esiste più.
      await _outbox.removeOutboxEntry(entry.id);
      _logger.info('Rimossa voce orfana ${entry.id}');
      return const SyncResult();
    }

    await _orders.updateOrder(order.copyWith(status: SyncStatus.sending));

    try {
      await _api.submitOrder(order);
      await _orders.updateOrder(order.copyWith(status: SyncStatus.synced));
      await _outbox.removeOutboxEntry(entry.id);
      return const SyncResult(sent: 1);
    } on ApiFailure catch (failure) {
      return _handleFailure(entry, order, failure, now);
    }
  }

  Future<SyncResult> _handleFailure(
    OutboxEntry entry,
    Order order,
    ApiFailure failure,
    DateTime now,
  ) async {
    final RetryDecision decision =
        _retryPolicy.decide(failure: failure, attempts: entry.attempts);

    switch (decision) {
      case GiveUp(:final String reason):
        await _orders.updateOrder(order.copyWith(status: SyncStatus.failed));
        await _outbox.removeOutboxEntry(entry.id);
        _logger.warning('Ordine ${order.id} abbandonato: $reason', failure);
        return const SyncResult(failed: 1);

      case RetryAfter(:final Duration delay):
        await _outbox.updateOutboxEntry(
          entry.withFailure(
            nextAttemptAt: now.add(delay),
            error: failure.toString(),
          ),
        );
        await _orders.updateOrder(order.copyWith(status: SyncStatus.pending));
        return const SyncResult(retried: 1);
    }
  }
}
