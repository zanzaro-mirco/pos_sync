import '../../../core/clock.dart';
import '../../../core/id_generator.dart';
import '../../../core/logger.dart';
import '../../../core/logical_clock.dart';
import '../data/order_store.dart';
import '../data/remote_api.dart';
import '../domain/order.dart';
import '../domain/order_conflict.dart';
import '../domain/order_line.dart';
import '../domain/sync_status.dart';
import 'conflict_policy.dart';

/// Esito di un ciclo di rientro.
class MergeResult {
  const MergeResult({this.merged = 0, this.conflicted = 0, this.arrived = 0});

  /// Ordini aggiornati con quello che arrivava da fuori.
  final int merged;

  /// Fusioni che si sono fermate e aspettano una decisione.
  final int conflicted;

  /// Ordini che questo dispositivo non aveva mai visto.
  final int arrived;

  bool get isIdle => merged == 0 && conflicted == 0 && arrived == 0;

  MergeResult operator +(MergeResult o) => MergeResult(
        merged: merged + o.merged,
        conflicted: conflicted + o.conflicted,
        arrived: arrived + o.arrived,
      );

  @override
  String toString() =>
      'MergeResult(merged: $merged, conflicted: $conflicted, arrived: $arrived)';
}

/// Porta dentro quello che hanno fatto gli altri dispositivi.
///
/// È il verso che al progetto mancava del tutto: fino a ieri `RemoteApi` aveva
/// il solo `submitOrder` e niente tornava mai indietro, il che spiega perché
/// non ci fosse gestione dei conflitti — non potevano nascere.
///
/// Classe a sé e non un metodo in più del `SyncWorker`: il worker dichiara di
/// avere come unica responsabilità l'orchestrazione, e tirare, fondere e
/// registrare i conflitti sono tre cose che non gli appartengono. Il worker la
/// chiama, come chiama la politica di ritentativo.
class InboundMerger {
  InboundMerger({
    required OrderStore orderStore,
    required ConflictStore conflictStore,
    required RemoteApi api,
    required LogicalClock logicalClock,
    ConflictPolicy<Order> policy = const OrderConflictPolicy(),
    Clock clock = const SystemClock(),
    IdGenerator idGenerator = const UuidGenerator(),
    Logger logger = const SilentLogger(),
  })  : _orders = orderStore,
        _conflicts = conflictStore,
        _api = api,
        _logical = logicalClock,
        _policy = policy,
        _clock = clock,
        _ids = idGenerator,
        _logger = logger;

  final OrderStore _orders;
  final ConflictStore _conflicts;
  final RemoteApi _api;
  final LogicalClock _logical;
  final ConflictPolicy<Order> _policy;
  final Clock _clock;
  final IdGenerator _ids;
  final Logger _logger;

  /// Legge le versioni degli altri dispositivi e le fonde in locale.
  ///
  /// Un errore di rete qui non è un fallimento del ciclo: la coda è già stata
  /// drenata e i dati locali restano quelli che sono. Si registra e si riprova
  /// al giro dopo.
  Future<MergeResult> pull() async {
    final List<Order> remote;
    try {
      remote = await _api.fetchOrders();
    } on ApiFailure catch (failure) {
      _logger.info('Rientro saltato: ${failure.message}');
      return const MergeResult();
    }

    MergeResult result = const MergeResult();
    for (final Order theirs in remote) {
      result = result + await _mergeOne(theirs);
    }
    return result;
  }

  Future<bool> _hasOpenConflictOn(String orderId) async =>
      (await _conflicts.openConflicts())
          .any((OrderConflict c) => c.orderId == orderId);

  Future<void> _closeConflictsOn(String orderId) async {
    for (final OrderConflict aperto in await _conflicts.openConflicts()) {
      if (aperto.orderId == orderId) {
        await _conflicts.removeConflict(aperto.id);
      }
    }
  }

  Future<MergeResult> _mergeOne(Order theirs) async {
    // Prima di tutto: prendere atto del tempo logico altrui. Se lo si
    // dimenticasse, la prossima modifica locale nascerebbe con un contatore
    // più basso di quello che ha appena visto, e risulterebbe più vecchia di
    // ciò che l'ha preceduta. È il passo che fa funzionare Lamport, e l'unico
    // che non ha un effetto visibile finché non è troppo tardi.
    await _logical.witness(theirs.stateRevision);
    for (final OrderLine line in theirs.lines) {
      await _logical.witness(line.addedAt);
    }

    final Order? mine = await _orders.orderById(theirs.id);
    if (mine == null) {
      // Ordine di un altro tavolo, o di un altro cameriere: non c'è niente da
      // fondere. Arriva già sincronizzato, perché il server ce l'ha per
      // definizione.
      await _orders.updateOrder(theirs.copyWith(status: SyncStatus.synced));
      return const MergeResult(arrived: 1);
    }

    switch (_policy.merge(mine, theirs)) {
      case Resolved<Order>(:final Order value):
        // Se le due versioni ora si fondono, un eventuale conflitto aperto su
        // questo ordine non esiste più: l'ha chiuso l'altro dispositivo, e
        // lasciarlo lì chiederebbe due volte la stessa decisione — la seconda
        // a chi non l'ha presa.
        await _closeConflictsOn(theirs.id);
        if (value == mine) return const MergeResult();
        await _orders.updateOrder(value);
        return const MergeResult(merged: 1);

      case NeedsDecision<Order>(:final String reason):
        // Su un ordine che ha già un conflitto aperto non se ne registra un
        // secondo. Finché nessuno decide, ogni sincronizzazione ripesca la
        // stessa versione altrui e arriva di nuovo qui: senza questo controllo
        // la schermata si riempirebbe di schede identiche, e una richiesta di
        // decisione ripetuta all'infinito si smette di leggere — che è il modo
        // più rapido per rendere inutile l'unica cosa che il sistema chiede.
        if (await _hasOpenConflictOn(theirs.id)) return const MergeResult();

        await _conflicts.recordConflict(
          OrderConflict(
            id: _ids.next(),
            mine: mine,
            theirs: theirs,
            reason: reason,
            detectedAt: _clock.now(),
          ),
        );
        _logger.warning('Conflitto sul tavolo ${mine.tableNumber}: $reason');
        return const MergeResult(conflicted: 1);
    }
  }
}
