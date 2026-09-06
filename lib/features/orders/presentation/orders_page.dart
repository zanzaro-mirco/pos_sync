import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/order.dart';
import '../domain/order_conflict.dart';
import '../domain/order_state.dart';
import 'conflict_card.dart';
import 'order_tile.dart';
import 'orders_cubit.dart';
import 'orders_state.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({
    super.key,
    required this.onAddOrder,
    required this.onAddLine,
    this.onOtherDevicePays,
  });

  /// Cosa fare quando si crea un ordine.
  ///
  /// Passato dall'esterno invece di essere cablato: la pagina non decide né
  /// cosa contiene un ordine di prova né chi lo gestisce, quindi si può
  /// riusare e mettere in anteprima senza dipendenze. Il numero è una
  /// **proposta** — il tavolo successivo — e chi la riceve è libero di
  /// chiederne un altro.
  final void Function(int tableNumber) onAddOrder;

  /// Cosa fare quando si aggiunge una comanda a un tavolo già aperto.
  ///
  /// Stessa ragione di [onAddOrder]: la pagina offre l'azione, non decide cosa
  /// ci sia dentro una comanda.
  final void Function(Order order) onAddLine;

  /// L'azione dimostrativa, se questa build ne ha una.
  ///
  /// Nullable perché è l'unica voce di questo menu che in un locale vero non
  /// esisterebbe: una build collegata a un backend reale passa `null` e la voce
  /// sparisce, senza che la pagina debba sapere il perché.
  final void Function(Order order)? onOtherDevicePays;

  /// Le azioni su un tavolo, in un foglio che sale dal basso.
  ///
  /// In un foglio e non in un menu compatto: le voci sono poche ma una ha una
  /// conseguenza che va spiegata, e in un menu di scorciatoie non ci sarebbe
  /// spazio per dirlo. Come sui pulsanti della scheda di conflitto, ogni voce
  /// dice **cosa succede**, non quale campo cambia.
  void _mostraAzioni(BuildContext context, Order order) {
    final OrdersCubit cubit = context.read<OrdersCubit>();
    final ScaffoldMessengerState messaggi = ScaffoldMessenger.of(context);

    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext foglio) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                'Tavolo ${order.tableNumber}',
                style: Theme.of(foglio).textTheme.titleMedium,
              ),
              subtitle:
                  Text('${order.state.name} · ${order.itemCount} articoli'),
            ),
            const Divider(height: 1),
            // Lo stato in cui il tavolo già si trova non compare: una voce che
            // non farebbe niente occupa spazio e va letta per scoprirlo.
            for (final OrderState stato in OrderState.values)
              if (stato != order.state)
                ListTile(
                  key: Key('action-${stato.name}'),
                  leading: Icon(_icona(stato)),
                  title: Text(_verbo(stato)),
                  onTap: () {
                    Navigator.pop(foglio);
                    cubit.changeState(orderId: order.id, state: stato);
                  },
                ),
            ListTile(
              key: const Key('action-add-line'),
              leading: const Icon(Icons.add_shopping_cart),
              title: const Text('Aggiungi una comanda'),
              onTap: () {
                Navigator.pop(foglio);
                onAddLine(order);
              },
            ),
            if (onOtherDevicePays != null) ...<Widget>[
              const Divider(height: 1),
              ListTile(
                key: const Key('action-other-device'),
                leading: const Icon(Icons.tablet_android),
                title: const Text("L'altro tablet incassa il tavolo"),
                subtitle: const Text(
                  'Poi aggiungi una comanda: alla sincronizzazione il conto '
                  'risulterà già chiuso senza di essa, e nasce il conflitto.',
                ),
                isThreeLine: true,
                onTap: () {
                  Navigator.pop(foglio);
                  onOtherDevicePays!(order);
                  messaggi.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Il tavolo ${order.tableNumber} risulta incassato '
                        "sull'altro dispositivo. Aggiungi una comanda per "
                        'vedere il conflitto.',
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _icona(OrderState stato) => switch (stato) {
        OrderState.aperto => Icons.lock_open,
        OrderState.servito => Icons.room_service,
        OrderState.pagato => Icons.euro,
      };

  static String _verbo(OrderState stato) => switch (stato) {
        OrderState.aperto => 'Riapri il tavolo',
        OrderState.servito => 'Segna servito',
        OrderState.pagato => 'Segna pagato',
      };

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
                      final Order order =
                          state.orders[index - state.conflicts.length];
                      return OrderTile(
                        order: order,
                        onTap: () => _mostraAzioni(context, order),
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
