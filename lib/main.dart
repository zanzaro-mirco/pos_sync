import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di.dart';
import 'features/orders/data/second_device.dart';
import 'features/orders/domain/order.dart';
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
        child: const _Home(),
      ),
    );
  }
}

/// Collega la schermata a ciò che sta sotto.
///
/// Widget a sé e non un `Builder` annidato perché ormai decide tre cose — cosa
/// contiene una comanda, quale tavolo, e se questa build sa fingere un secondo
/// dispositivo — e ognuna è una scelta di questo strato, non della pagina.
class _Home extends StatelessWidget {
  const _Home();

  /// Cosa arriva al tavolo quando si tocca «aggiungi».
  ///
  /// Una sola voce e sempre la stessa: qui non si sta costruendo un menu, si
  /// sta dando modo di mettere qualcosa su un tavolo per vedere cosa fa il
  /// sistema quando due dispositivi lo fanno insieme.
  static const List<OrderLineDraft> _comanda = <OrderLineDraft>[
    OrderLineDraft(
      productId: 'p-01',
      description: 'Caffè',
      quantity: 2,
      unitPriceCents: 120,
    ),
  ];

  /// Chiede il numero del tavolo, proponendo il successivo.
  ///
  /// Prima il numero veniva incrementato d'ufficio, e la conseguenza era che
  /// **due ordini sullo stesso tavolo non si potevano creare** — cioè proprio
  /// lo scenario per cui esistono la fusione e i conflitti. Poterlo ripetere
  /// non è una comodità: è ciò che rende dimostrabile il resto.
  Future<int?> _chiediTavolo(BuildContext context, int proposto) {
    final TextEditingController campo =
        TextEditingController(text: '$proposto');

    return showDialog<int>(
      context: context,
      builder: (BuildContext finestra) => AlertDialog(
        title: const Text('Numero del tavolo'),
        content: TextField(
          key: const Key('table-number-field'),
          controller: campo,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            helperText: 'Si può ripetere un tavolo già aperto',
          ),
          onSubmitted: (String v) =>
              Navigator.pop(finestra, int.tryParse(v.trim())),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(finestra),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const Key('table-number-confirm'),
            onPressed: () =>
                Navigator.pop(finestra, int.tryParse(campo.text.trim())),
            child: const Text('Crea'),
          ),
        ],
      ),
    ).whenComplete(campo.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final OrdersCubit cubit = context.read<OrdersCubit>();

    return OrdersPage(
      onAddOrder: (int proposto) async {
        final int? tavolo = await _chiediTavolo(context, proposto);
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
