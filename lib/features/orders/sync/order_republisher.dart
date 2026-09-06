import '../../../core/logger.dart';
import '../data/order_store.dart';
import '../data/outbox_scheduler.dart';
import '../domain/order.dart';
import '../domain/outbox_entry.dart';

/// Rimette in coda tutti gli ordini locali.
///
/// Serve dopo un'elezione, e nasce da un errore nel piano di questa voce.
/// Ci avevo scritto che dopo il cambio di cassa «i dispositivi ripubblicano le
/// proprie versioni al giro successivo»: **è falso**. La coda si svuota quando
/// l'invio riesce, quindi un ordine già consegnato alla vecchia cassa non
/// viene mai rispedito. Il registro della nuova nascerebbe vuoto e resterebbe
/// tale, e i tablet smetterebbero di vedersi gli ordini pur essendo tutti
/// connessi — il guasto peggiore, perché nessuno segnala niente.
///
/// Chi ha già una voce in coda viene saltato: rimetterlo produrrebbe due invii
/// dello stesso ordine. Non sarebbe un danno — il registro è idempotente sulla
/// coppia *(ordine, dispositivo)* — ma sarebbe lavoro raddoppiato proprio nel
/// momento in cui la rete è già in difficoltà.
class OrderRepublisher {
  const OrderRepublisher({
    required OrderStore orders,
    required OutboxStore outbox,
    required OrderOutboxTransaction transaction,
    required OutboxScheduler scheduler,
    Logger logger = const SilentLogger(),
  })  : _orders = orders,
        _outbox = outbox,
        _transaction = transaction,
        _scheduler = scheduler,
        _logger = logger;

  final OrderStore _orders;
  final OutboxStore _outbox;
  final OrderOutboxTransaction _transaction;
  final OutboxScheduler _scheduler;
  final Logger _logger;

  /// Riaccoda ciò che non è già in coda. Restituisce quanti ne ha aggiunti.
  Future<int> republishAll() async {
    final List<Order> orders = await _orders.allOrders();
    final Set<String> queued = <String>{
      for (final OutboxEntry e in await _outbox.pendingOutbox()) e.orderId,
    };

    int added = 0;
    for (final Order order in orders) {
      if (queued.contains(order.id)) continue;
      await _transaction.saveOrderWithOutbox(
          order, _scheduler.scheduleFor(order));
      added++;
    }

    if (added > 0) _logger.info('Riaccodati $added ordini per la nuova cassa');
    return added;
  }
}
