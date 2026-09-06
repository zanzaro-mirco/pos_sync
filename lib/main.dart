import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di.dart';
import 'features/orders/data/second_device.dart';
import 'features/orders/domain/order.dart';
import 'features/orders/domain/order_line_draft.dart';
import 'features/orders/domain/orders_repository.dart';
import 'features/orders/presentation/orders_cubit.dart';
import 'features/orders/presentation/orders_page.dart';
import 'features/orders/presentation/table_number_dialog.dart';
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
        child: const _Home(),
      ),
    );
  }
}

/// Collega la schermata a ciò che sta sotto.
///
/// Widget a sé e non un `Builder` annidato perché ormai decide tre cose — cosa
/// contiene una comanda, a chi chiedere il numero del tavolo, e se questa build
/// sa fingere un secondo dispositivo — e ognuna è una scelta di questo strato,
/// non della pagina.
///
/// Qui dentro non c'è nessun widget: `main.dart` non è raggiungibile dai test,
/// quindi tutto ciò che si disegna vive in `presentation/` e qui resta solo il
/// cablaggio.
class _Home extends StatelessWidget {
  const _Home();

  /// Cosa arriva al tavolo quando si tocca «aggiungi».
  ///
  /// Una sola voce e sempre la stessa: qui non si sta costruendo un menu, si sta
  /// dando modo di mettere qualcosa su un tavolo per vedere cosa fa il sistema
  /// quando due dispositivi lo fanno insieme.
  static const List<OrderLineDraft> _comanda = <OrderLineDraft>[
    OrderLineDraft(
      productId: 'p-01',
      description: 'Caffè',
      quantity: 2,
      unitPriceCents: 120,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final OrdersCubit cubit = context.read<OrdersCubit>();

    return OrdersPage(
      onAddOrder: (int proposto) async {
        final int? tavolo = await chiediNumeroTavolo(context, proposto);
        if (tavolo != null) {
          await cubit.addOrder(tableNumber: tavolo, lines: _comanda);
        }
      },
      onAddLine: (Order order) =>
          cubit.addLines(orderId: order.id, lines: _comanda),
      // In una build non dimostrativa il secondo dispositivo non è registrato,
      // la voce non compare, e la pagina non deve saperne niente.
      onOtherDevicePays:
          sl.isRegistered<SecondDevice>() ? sl<SecondDevice>().pays : null,
    );
  }
}
