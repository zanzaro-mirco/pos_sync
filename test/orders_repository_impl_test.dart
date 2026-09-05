import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line_draft.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';

import 'helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  test('crea l ordine e la voce di outbox nella stessa operazione', () async {
    final Order order =
        await env.repository.createOrder(tableNumber: 4, lines: sampleLines);

    expect(order.status, SyncStatus.pending);
    expect((await env.store.allOrders()).length, 1);
    expect((await env.store.pendingOutbox()).single.orderId, order.id);
  });

  test('gli identificativi sono deterministici nei test', () async {
    // Con IdGenerator iniettato si può asserire sull'id, cosa impossibile
    // finché veniva generato un UUID casuale dentro il repository.
    final Order a =
        await env.repository.createOrder(tableNumber: 1, lines: sampleLines);
    final Order b =
        await env.repository.createOrder(tableNumber: 2, lines: sampleLines);
    // La sequenza è: ordine, riga, voce di coda. Le righe consumano un
    // identificativo per una ragione precisa — è la chiave con cui due
    // dispositivi riconoscono la stessa riga senza duplicarla.
    expect(a.id, 'id-1');
    expect(a.lines.single.id, 'id-2');
    expect(b.id, 'id-4');
  });

  test('rifiuta un ordine senza righe', () async {
    expect(
      () => env.repository
          .createOrder(tableNumber: 1, lines: const <OrderLineDraft>[]),
      throwsArgumentError,
    );
  });

  test('le righe dell ordine non sono modificabili dall esterno', () async {
    final List<OrderLineDraft> mutabili = <OrderLineDraft>[...sampleLines];
    final Order order =
        await env.repository.createOrder(tableNumber: 1, lines: mutabili);

    mutabili.clear(); // la lista originale cambia
    expect(order.lines.length, 1, reason: 'l ordine non deve risentirne');
    expect(
      () => order.lines.add(order.lines.first),
      throwsUnsupportedError,
    );
  });

  test('calcola totale e numero di articoli', () async {
    final Order order =
        await env.repository.createOrder(tableNumber: 1, lines: sampleLines);
    expect(order.totalCents, 240);
    expect(order.itemCount, 2);
  });

  test('gli ordini sono restituiti dal più recente', () async {
    await env.repository.createOrder(tableNumber: 1, lines: sampleLines);
    env.clock.advance(const Duration(minutes: 5));
    final Order recente =
        await env.repository.createOrder(tableNumber: 2, lines: sampleLines);

    expect((await env.repository.loadOrders()).first.id, recente.id);
  });

  test('pendingCount riflette la coda', () async {
    expect(await env.repository.pendingCount(), 0);
    await env.repository.createOrder(tableNumber: 1, lines: sampleLines);
    await env.repository.createOrder(tableNumber: 2, lines: sampleLines);
    expect(await env.repository.pendingCount(), 2);
  });
}
