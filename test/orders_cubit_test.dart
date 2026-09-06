import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/domain/order_line_draft.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';
import 'package:pos_sync/features/orders/presentation/orders_cubit.dart';
import 'package:pos_sync/features/orders/presentation/orders_state.dart';

import 'helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  OrdersCubit build() =>
      OrdersCubit(repository: env.repository, syncWorker: env.worker);

  blocTest<OrdersCubit, OrdersState>(
    'start passa da loading a ready osservando il flusso',
    build: build,
    act: (OrdersCubit cubit) => cubit.start(),
    expect: () => <Matcher>[
      isA<OrdersState>()
          .having((OrdersState s) => s.status, 'status', OrdersStatus.loading),
      isA<OrdersState>()
          .having((OrdersState s) => s.status, 'status', OrdersStatus.ready),
    ],
  );

  blocTest<OrdersCubit, OrdersState>(
    'start è idempotente: due chiamate non raddoppiano le emissioni',
    build: build,
    act: (OrdersCubit cubit) {
      cubit.start();
      cubit.start();
    },
    expect: () => <Matcher>[
      isA<OrdersState>()
          .having((OrdersState s) => s.status, 'status', OrdersStatus.loading),
      isA<OrdersState>()
          .having((OrdersState s) => s.status, 'status', OrdersStatus.ready),
    ],
  );

  blocTest<OrdersCubit, OrdersState>(
    'aggiungere un ordine offline lo mostra comunque nella lista',
    build: () {
      env.fake.online = false;
      return build();
    },
    act: (OrdersCubit cubit) async {
      cubit.start();
      await cubit.addOrder(tableNumber: 3, lines: sampleLines);
    },
    verify: (OrdersCubit cubit) {
      expect(cubit.state.orders.length, 1);
      expect(cubit.state.hasPending, isTrue);
      expect(cubit.state.orders.single.status, SyncStatus.pending);
    },
  );

  blocTest<OrdersCubit, OrdersState>(
    'dopo la sincronizzazione le pendenze tornano a zero',
    build: build,
    act: (OrdersCubit cubit) async {
      cubit.start();
      await cubit.addOrder(tableNumber: 1, lines: sampleLines);
      await cubit.sync();
    },
    verify: (OrdersCubit cubit) {
      expect(cubit.state.pending, 0);
      expect(cubit.state.orders.single.status, SyncStatus.synced);
    },
  );

  blocTest<OrdersCubit, OrdersState>(
    'un ordine senza righe porta lo stato in errore',
    build: build,
    act: (OrdersCubit cubit) async {
      cubit.start();
      await cubit.addOrder(tableNumber: 1, lines: const <OrderLineDraft>[]);
    },
    verify: (OrdersCubit cubit) {
      expect(cubit.state.status, OrdersStatus.error);
      expect(cubit.state.message, isNotNull);
    },
  );

  test('lo snapshot porta ordini e pendenze insieme', () async {
    // Verifica del motivo per cui esiste OrdersSnapshot: la lista e il
    // contatore non possono mai essere disallineati.
    final OrdersCubit cubit = build();
    cubit.start();
    await env.repository.createOrder(tableNumber: 1, lines: sampleLines);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.orders.length, 1);
    expect(cubit.state.pending, 1);
    await cubit.close();
  });
}
