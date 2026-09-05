import '../../../core/clock.dart';
import '../../../core/logger.dart';
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
  })  : _orders = orderStore,
        _outbox = outboxStore,
        _api = api,
        _inbound = inbound,
        _retryPolicy = retryPolicy ?? BackoffRetryPolicy(),
        _clock = clock,
        _logger = logger;

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

  bool _running = false;

  /// Un ciclo completo: prima spinge la coda, poi tira quello che hanno fatto
  /// gli altri.
  ///
  /// L'ordine non è casuale. Spingere per primi fa sì che la fusione avvenga
  /// contro un server che conosce già le modifiche locali: al contrario, ogni
  /// giro produrrebbe una fusione basata su una versione del server più
  /// vecchia di quella che stiamo per mandarle.
  ///
  /// Le chiamate concorrenti vengono ignorate: due drenaggi in parallelo
  /// invierebbero le stesse voci due volte.
  Future<SyncResult> drain() async {
    if (_running) return const SyncResult();
    _running = true;
    try {
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
    } finally {
      _running = false;
    }
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
