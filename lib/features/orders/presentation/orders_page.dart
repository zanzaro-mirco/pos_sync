import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/order.dart';
import '../domain/sync_status.dart';
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
            OrdersStatus.initial ||
            OrdersStatus.loading =>
              const Center(child: CircularProgressIndicator()),
            OrdersStatus.error => Center(
                child: Text(state.message ?? 'Errore',
                    key: const Key('error-text')),
              ),
            OrdersStatus.ready => state.orders.isEmpty
                ? const Center(child: Text('Nessun ordine'))
                : ListView.builder(
                    itemCount: state.orders.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _OrderTile(order: state.orders[index]),
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

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _StatusIcon(status: order.status),
      title: Text('Tavolo ${order.tableNumber}'),
      subtitle: Text('${order.itemCount} articoli'),
      trailing: Text('${(order.totalCents / 100).toStringAsFixed(2)} €'),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        SyncStatus.pending => const Icon(Icons.schedule),
        SyncStatus.sending => const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        SyncStatus.synced => const Icon(Icons.cloud_done),
        SyncStatus.failed => const Icon(Icons.error_outline),
      };
}
