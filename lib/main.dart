import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di.dart';
import 'features/orders/domain/order_line_draft.dart';
import 'features/orders/domain/orders_repository.dart';
import 'features/orders/presentation/orders_cubit.dart';
import 'features/orders/presentation/orders_page.dart';
import 'features/orders/sync/sync_worker.dart';

void main() {
  // Serve prima di interrogare qualunque plugin: `startBackgroundServices`
  // chiede subito lo stato della rete, e `runApp` inizializzerebbe il binding
  // troppo tardi.
  WidgetsFlutterBinding.ensureInitialized();
  setUpDependencies();
  startBackgroundServices();
  runApp(const PosSyncApp());
}

class PosSyncApp extends StatelessWidget {
  const PosSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS Sync',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: BlocProvider<OrdersCubit>(
        create: (_) => OrdersCubit(
          repository: sl<OrdersRepository>(),
          syncWorker: sl<SyncWorker>(),
        )..start(),
        child: Builder(
          builder: (BuildContext context) => OrdersPage(
            onAddOrder: (int tableNumber) =>
                context.read<OrdersCubit>().addOrder(
              tableNumber: tableNumber,
              lines: const <OrderLineDraft>[
                OrderLineDraft(
                  productId: 'p-01',
                  description: 'Caffè',
                  quantity: 2,
                  unitPriceCents: 120,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
