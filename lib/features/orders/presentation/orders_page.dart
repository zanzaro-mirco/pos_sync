import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'order_tile.dart';
import 'orders_cubit.dart';
import 'orders_state.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key, required this.onAddOrder});

  /// Cosa fare quando si crea un ordine.
  ///
  /// Passato dall'esterno invece di essere cablato: la pagina non decide né
  /// cosa contiene un ordine di prova né chi lo gestisce, quindi si può
  /// riusare e mettere in anteprima senza dipendenze.
  final void Function(int tableNumber) onAddOrder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersCubit, OrdersState>(
      builder: (BuildContext context, OrdersState state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ordini'),
            actions: <Widget>[
              if (state.hasPending)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: Chip(
                      key: const Key('pending-badge'),
                      label: Text('${state.pending} da inviare'),
                    ),
                  ),
                ),
              IconButton(
                key: const Key('sync-button'),
                icon: const Icon(Icons.sync),
                onPressed: () => context.read<OrdersCubit>().sync(),
              ),
            ],
          ),
          body: switch (state.status) {
            OrdersStatus.initial || OrdersStatus.loading => const Center(
                key: Key('loading-indicator'),
                child: CircularProgressIndicator(),
              ),
            OrdersStatus.error => Center(
                child: Text(state.message ?? 'Errore',
                    key: const Key('error-text')),
              ),
            OrdersStatus.ready => state.orders.isEmpty
                ? const Center(
                    child: Text('Nessun ordine', key: Key('empty-text')))
                : ListView.builder(
                    itemCount: state.orders.length,
                    itemBuilder: (BuildContext context, int index) =>
                        OrderTile(order: state.orders[index]),
                  ),
          },
          floatingActionButton: FloatingActionButton(
            key: const Key('add-order'),
            onPressed: () => onAddOrder(state.orders.length + 1),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
