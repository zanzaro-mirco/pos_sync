import '../../../core/clock.dart';
import '../../../core/id_generator.dart';
import '../domain/order.dart';
import '../domain/outbox_entry.dart';

/// Costruisce la voce di coda associata a un'operazione.
///
/// Estratto dal repository, che prima generava identificativi, creava l'ordine
/// *e* creava la voce di outbox. Sono responsabilità diverse: se domani la
/// coda dovrà supportare priorità o scadenze, si cambia qui e il repository
/// resta intatto.
class OutboxScheduler {
  const OutboxScheduler({
    required IdGenerator idGenerator,
    required Clock clock,
  })  : _ids = idGenerator,
        _clock = clock;

  final IdGenerator _ids;
  final Clock _clock;

  OutboxEntry scheduleFor(Order order) => OutboxEntry(
        id: _ids.next(),
        orderId: order.id,
        createdAt: _clock.now(),
      );
}
