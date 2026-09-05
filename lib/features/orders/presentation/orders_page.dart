import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/order_conflict.dart';
import 'conflict_card.dart';
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
              if (state.hasConflicts)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: Chip(
                      key: const Key('conflict-badge'),
                      avatar: const Icon(Icons.warning_amber, size: 18),
                      label: Text('${state.conflicts.length}'),
                    ),
                  ),
                ),
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
            OrdersStatus.ready => state.orders.isEmpty && !state.hasConflicts
                ? const Center(
                    child: Text('Nessun ordine', key: Key('empty-text')))
                // I conflitti stanno in cima, prima degli ordini: sono
                // l'unica cosa in questa schermata che chiede di fare
                // qualcosa, e in fondo alla lista non la vedrebbe nessuno.
                : ListView.builder(
                    itemCount: state.conflicts.length + state.orders.length,
                    itemBuilder: (BuildContext context, int index) {
                      if (index < state.conflicts.length) {
                        final OrderConflict conflict = state.conflicts[index];
                        final OrdersCubit cubit = context.read<OrdersCubit>();
                        return ConflictCard(
                          conflict: conflict,
                          onKeepMine: () => cubit.resolveConflict(
                              conflict, ConflictChoice.mine),
                          onKeepTheirs: () => cubit.resolveConflict(
                              conflict, ConflictChoice.theirs),
                        );
                      }
                      return OrderTile(
                        order: state.orders[index - state.conflicts.length],
                      );
                    },
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
