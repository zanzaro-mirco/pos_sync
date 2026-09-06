import '../../../core/logger.dart';
import '../domain/order.dart';
import '../domain/order_conflict.dart';
import '../domain/outbox_entry.dart';
import 'order_registry.dart';
import 'order_store.dart';

/// Riporta il dispositivo allo stato di appena installato, ordini a parte.
///
/// Serve a rifare una dimostrazione. Senza, l'unico modo di ripartire da una
/// lista vuota è disinstallare l'app: gli ordini stanno in un file SQLite che
/// sopravvive per costruzione, ed è il comportamento giusto in sala e scomodo
/// su una scrivania.
///
/// **Svuota anche il registro locale**, ed è la parte che rende il gesto
/// efficace. Le proprie versioni non tornerebbero comunque indietro — il
/// registro esclude sempre chi chiede — ma quelle *altrui* sì: su un
/// dispositivo che fa la cassa, il registro è il posto da cui gli ordini di
/// tutti possono ricomparire alla prima sincronizzazione.
///
/// Da qui una regola che va detta a chi prova: **si svuota su entrambi i
/// dispositivi**. Farlo solo in sala lascia alla cassa le proprie versioni, che
/// al giro dopo tornano — e sembra che il pulsante non abbia funzionato.
///
/// **Il contatore logico non si azzera**, di proposito. È l'unica cosa che qui
/// non è "dato di prova": farlo tornare indietro romperebbe l'ordine totale su
/// cui si regge la convergenza, e una modifica futura risulterebbe più vecchia
/// di una passata. Costa un numero che cresce; toglierlo costerebbe la
/// correttezza.
class DemoReset {
  const DemoReset({
    required OrderStore orders,
    required OutboxStore outbox,
    required ConflictStore conflicts,
    required OrderRegistry registry,
    Logger logger = const SilentLogger(),
  })  : _orders = orders,
        _outbox = outbox,
        _conflicts = conflicts,
        _registry = registry,
        _logger = logger;

  final OrderStore _orders;
  final OutboxStore _outbox;
  final ConflictStore _conflicts;
  final OrderRegistry _registry;
  final Logger _logger;

  /// Cancella ordini, coda, conflitti e registro locale.
  ///
  /// Restituisce quanti ordini ha tolto, che è il solo numero utile a chi
  /// guarda: gli altri sono conseguenze.
  Future<int> clearEverything() async {
    // Prima la coda, poi gli ordini: una voce di coda che sopravvive al proprio
    // ordine è la voce orfana che il worker sa già ripulire, ma lasciarla
    // significherebbe fidarsi di quella pulizia invece di non crearla.
    for (final OutboxEntry entry in await _outbox.pendingOutbox()) {
      await _outbox.removeOutboxEntry(entry.id);
    }
    for (final OrderConflict conflict in await _conflicts.openConflicts()) {
      await _conflicts.removeConflict(conflict.id);
    }

    final List<Order> orders = await _orders.allOrders();
    for (final Order order in orders) {
      await _orders.deleteOrder(order.id);
    }

    _registry.clear();
    _logger.info('Svuotati ${orders.length} ordini e il registro locale');
    return orders.length;
  }
}
