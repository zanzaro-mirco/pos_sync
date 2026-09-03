import 'package:pos_sync/features/orders/data/in_memory_order_store.dart';

import 'store_contract.dart';

/// La stessa suite di `drift_order_store_test.dart`, sull'implementazione in
/// memoria. Non è una ripetizione: è il termine di paragone. Se un giorno le
/// due divergono, il fallimento dice quale delle due ha cambiato
/// comportamento.
void main() {
  runOrderStoreContract('InMemoryOrderStore', () async {
    final InMemoryOrderStore store = InMemoryOrderStore();
    return StoreHarness(
      orders: store,
      outbox: store,
      transaction: store,
      watcher: store,
      close: store.dispose,
    );
  });
}
