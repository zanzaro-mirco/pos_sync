/// Ripartire da una lista vuota senza disinstallare l'app.
///
/// Gli ordini stanno in un file SQLite che sopravvive per costruzione — è il
/// punto dell'architettura — e questo rende scomodo rifare una dimostrazione.
/// Lo svuotamento è l'unica azione dell'app che *toglie* qualcosa, quindi i
/// test guardano soprattutto che tolga esattamente ciò che dice.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/demo_reset.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_conflict.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';

import 'helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late FakeServer registry;
  late DemoReset reset;

  setUp(() {
    env = TestEnv();
    registry = FakeServer();
    reset = DemoReset(
      orders: env.store,
      outbox: env.store,
      conflicts: env.store,
      registry: registry,
      logger: env.logger,
    );
  });

  tearDown(() => env.dispose());

  test('toglie ordini, coda e registro, e dice quanti', () async {
    await env.repository.createOrder(tableNumber: 7, lines: sampleLines);
    await env.repository.createOrder(tableNumber: 9, lines: sampleLines);
    for (final Order order in await env.store.allOrders()) {
      registry.store(order, 'un-altro-tablet');
    }

    expect(await reset.clearEverything(), 2);

    expect(await env.store.allOrders(), isEmpty);
    expect(await env.store.pendingCount(), 0);
    expect(registry.storedOrderIds, isEmpty);
  });

  test('toglie anche i conflitti aperti', () async {
    // Un conflitto che sopravvive ai suoi ordini resterebbe sullo schermo a
    // chiedere una decisione su due versioni che non esistono più.
    final Order order = await env.repository.createOrder(
      tableNumber: 7,
      lines: sampleLines,
    );
    await env.store.recordConflict(
      OrderConflict(
        id: 'c-1',
        mine: order,
        theirs: order,
        reason: 'per finta',
        detectedAt: env.clock.now(),
      ),
    );

    await reset.clearEverything();

    expect(await env.store.openConflicts(), isEmpty);
  });

  test('su un deposito già vuoto non fa niente e lo dice', () async {
    // Il numero restituito serve proprio a questo: «fatto» non distingue
    // «ne ho cancellati dodici» da «non c'era niente».
    expect(await reset.clearEverything(), 0);
  });

  test('il contatore logico non torna indietro', () async {
    // È l'unica cosa che qui non è dato di prova. Farlo tornare indietro
    // romperebbe l'ordine totale su cui si regge la convergenza: una modifica
    // futura risulterebbe più vecchia di una passata.
    await env.repository.createOrder(tableNumber: 7, lines: sampleLines);
    final int before = (await env.logical.tick()).counter;

    await reset.clearEverything();

    final Revision after = await env.logical.tick();
    expect(after.counter, greaterThan(before));
  });

  test('svuotare non cancella le versioni altrui già ricevute', () async {
    // Distinzione che conta per chi prova in due: qui si svuota *questo*
    // dispositivo. Il registro dell'altro non lo tocca nessuno, ed è la ragione
    // per cui la conferma dice di farlo su entrambi.
    final FakeServer altrove = FakeServer();
    final Order order = await env.repository.createOrder(
      tableNumber: 7,
      lines: sampleLines,
    );
    altrove.store(order, 'un-altro-tablet');

    await reset.clearEverything();

    expect(altrove.storedOrderIds, hasLength(1));
  });
}
