/// La dimostrazione, verificata.
///
/// `SecondDevice` esiste per far comparire sullo schermo una cosa che prima
/// viveva solo nei test: nell'app in esecuzione c'è un dispositivo solo, quindi
/// il rientro non trovava mai niente e il conflitto non poteva nascere.
///
/// Un aiuto alla dimostrazione che non fosse verificato sarebbe però la cosa
/// peggiore di tutte: si mostrerebbe in colloquio una schermata che nessuno ha
/// messo alla prova. Questo file verifica la sequenza esatta che si esegue col
/// dito — incassa, aggiungi, sincronizza — e soprattutto verifica **quando il
/// conflitto non deve comparire**, che è la metà difficile.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/second_device.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_conflict.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';

import 'helpers/fixtures.dart';

void main() {
  late TestEnv tablet;
  late SecondDevice altro;

  setUp(() {
    tablet = TestEnv();
    altro = SecondDevice(server: tablet.api.server);
  });

  tearDown(() => tablet.dispose());

  /// L'ordine com'è adesso nel deposito locale.
  Future<Order> locale(String id) async => (await tablet.store.orderById(id))!;

  /// Crea un tavolo e lo porta al server, che è il punto di partenza di ogni
  /// dimostrazione: prima che l'altro tablet possa incassare qualcosa, quel
  /// qualcosa deve esistere per entrambi.
  Future<Order> tavoloSincronizzato({int numero = 7}) async {
    final Order ordine = await tablet.repository.createOrder(
      tableNumber: numero,
      lines: sampleLines,
    );
    await tablet.worker.drain();
    return locale(ordine.id);
  }

  test('incassare e basta non è un conflitto: il pagamento si fonde', () async {
    // È la metà che conta di più. Se il solo fatto che l'altro dispositivo
    // abbia chiuso il conto bastasse a interrompere qualcuno, il sistema
    // chiederebbe conferma nel caso normale — e una richiesta che arriva
    // sempre si smette di leggere.
    final Order ordine = await tavoloSincronizzato();

    altro.pays(ordine);
    await tablet.worker.drain();

    expect(await tablet.store.openConflicts(), isEmpty);
    expect((await locale(ordine.id)).state, OrderState.pagato,
        reason: 'il pagamento altrui vince il last-write-wins e arriva qui');
  });

  test('la comanda che arriva dopo il pagamento fa nascere il conflitto',
      () async {
    // La sequenza esatta che si esegue col dito.
    final Order ordine = await tavoloSincronizzato();

    altro.pays(ordine); // l'altro tablet chiude il conto
    await tablet.repository
        .addLines(orderId: ordine.id, lines: sampleLines); // comanda tardiva
    await tablet.worker.drain();

    final List<OrderConflict> conflitti = await tablet.store.openConflicts();
    expect(conflitti, hasLength(1));
    expect(conflitti.single.tableNumber, 7);
    expect(conflitti.single.reason, contains('non erano nel conto'));
    expect(conflitti.single.mine.lines, hasLength(2));
    expect(conflitti.single.theirs.state, OrderState.pagato);
  });

  test('sincronizzare ancora non duplica la scheda', () async {
    // Finché nessuno decide, il server continua a restituire la stessa
    // versione altrui: senza il controllo sui conflitti già aperti la
    // schermata si riempirebbe di schede identiche.
    final Order ordine = await tavoloSincronizzato();
    altro.pays(ordine);
    await tablet.repository.addLines(orderId: ordine.id, lines: sampleLines);

    await tablet.worker.drain();
    await tablet.worker.drain();
    await tablet.worker.drain();

    expect(await tablet.store.openConflicts(), hasLength(1));
  });

  test('decidere chiude la questione, e non si riapre da sola', () async {
    final Order ordine = await tavoloSincronizzato();
    altro.pays(ordine);
    await tablet.repository.addLines(orderId: ordine.id, lines: sampleLines);
    await tablet.worker.drain();

    final OrderConflict conflitto = (await tablet.store.openConflicts()).single;
    await tablet.repository.resolveConflict(conflitto.id, ConflictChoice.mine);

    // La versione decisa nasce con una revisione nuova, quindi batte quella
    // dell'altro dispositivo: la fusione successiva riesce da sola e nessuno
    // si ritrova a decidere due volte la stessa cosa.
    await tablet.worker.drain();
    await tablet.worker.drain();

    expect(await tablet.store.openConflicts(), isEmpty);
    expect((await locale(ordine.id)).lines, hasLength(2),
        reason: 'qualunque sia la scelta, nessuna comanda sparisce');
  });

  test('il secondo dispositivo si distingue dal primo', () async {
    // Se i due condividessero l'identificativo, il server considererebbe la
    // versione «già nostra» e non la restituirebbe: non nascerebbe nessun
    // conflitto, e la dimostrazione fallirebbe in silenzio.
    final Order ordine = await tavoloSincronizzato();
    altro.pays(ordine);

    expect(altro.deviceId, isNot(tablet.deviceId));
    expect(await tablet.api.fetchOrders(), hasLength(1),
        reason: 'il rientro deve vedere la versione dell\'altro tablet');
  });
}
