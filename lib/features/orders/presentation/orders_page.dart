import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/order.dart';
import '../domain/order_conflict.dart';
import '../domain/order_state.dart';
import 'conflict_card.dart';
import 'order_tile.dart';
import 'order_state_label.dart';
import 'orders_cubit.dart';
import 'orders_state.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({
    super.key,
    required this.onAddOrder,
    required this.onAddLine,
    this.onOtherDevicePays,
    this.onOpenSettings,
    this.onResetOrders,
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

  /// Apre le impostazioni di rete locale, se questa build le ha.
  ///
  /// Nullable come [onOtherDevicePays] e per la stessa ragione: la pagina non
  /// deve sapere se questo dispositivo può fare parte di una rete di sala.
  final VoidCallback? onOpenSettings;

  /// Svuota gli ordini di questo dispositivo, se questa build lo permette.
  ///
  /// Nullable, e in un locale vero è `null`: cancellare il servizio di una
  /// serata non è un'azione che si offre a chi prende le comande. Restituisce
  /// quanti ordini ha tolto, perché un'azione distruttiva deve dire cosa ha
  /// fatto — «fatto» non distingue «ne ho cancellati dodici» da «non c'era
  /// niente».
  final Future<int> Function()? onResetOrders;

  /// Le azioni su un tavolo, in un foglio che sale dal basso.
  ///
  /// In un foglio e non in un menu compatto: le voci sono poche ma una ha una
  /// conseguenza che va spiegata, e in un menu di scorciatoie non ci sarebbe
  /// spazio per dirlo. Come sui pulsanti della scheda di conflitto, ogni voce
  /// dice **cosa succede**, non quale campo cambia.
  void _showActions(BuildContext context, Order order) {
    final OrdersCubit cubit = context.read<OrdersCubit>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                'Tavolo ${order.tableNumber}',
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
              subtitle: Text('${orderStateLabel(order.state)} · '
                  '${order.itemCount} articoli'),
            ),
            const Divider(height: 1),
            // Lo stato in cui il tavolo già si trova non compare: una voce che
            // non farebbe niente occupa spazio e va letta per scoprirlo.
            for (final OrderState state in OrderState.values)
              if (state != order.state)
                ListTile(
                  key: Key('action-${state.name}'),
                  leading: Icon(_actionIcon(state)),
                  title: Text(_actionLabel(state)),
                  onTap: () {
                    Navigator.pop(sheet);
                    cubit.changeState(orderId: order.id, state: state);
                  },
                ),
            ListTile(
              key: const Key('action-add-line'),
              leading: const Icon(Icons.add_shopping_cart),
              title: const Text('Aggiungi una comanda'),
              onTap: () {
                Navigator.pop(sheet);
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
                  Navigator.pop(sheet);
                  onOtherDevicePays!(order);
                  messenger.showSnackBar(
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

  /// Chiede conferma, poi svuota.
  ///
  /// La conferma non è cerimonia: è l'unica azione dell'app che **toglie**
  /// qualcosa, e il testo dice cosa succede davvero — compreso il fatto che
  /// farlo su un dispositivo solo non basta, perché il registro dell'altro
  /// rimanda indietro le proprie versioni al primo giro.
  Future<void> _confirmReset(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('Svuotare gli ordini?'),
        content: const Text(
          'Cancella gli ordini di questo dispositivo, la coda di invio e i '
          'conflitti aperti. Se stai provando in due, fallo su entrambi: '
          "altrimenti gli ordini dell'altro tornano alla prima "
          'sincronizzazione.',
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('reset-cancel'),
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const Key('reset-confirm'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Svuota'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    final int removed = await onResetOrders!();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? 'Non c\'era niente da svuotare.'
              : 'Svuotati $removed ordini.',
        ),
      ),
    );
  }

  static IconData _actionIcon(OrderState state) => switch (state) {
        OrderState.open => Icons.lock_open,
        OrderState.served => Icons.room_service,
        OrderState.paid => Icons.euro,
      };

  static String _actionLabel(OrderState state) => switch (state) {
        OrderState.open => 'Riapri il tavolo',
        OrderState.served => 'Segna servito',
        OrderState.paid => 'Segna pagato',
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
              if (onOpenSettings != null)
                IconButton(
                  key: const Key('settings-button'),
                  icon: const Icon(Icons.lan),
                  tooltip: 'Rete locale',
                  onPressed: onOpenSettings,
                ),
              // In un menu e non come icona a sé: è l'unica azione che toglie
              // qualcosa, e in barra starebbe a un dito di distanza da
              // «sincronizza».
              if (onResetOrders != null)
                PopupMenuButton<void>(
                  key: const Key('overflow-menu'),
                  itemBuilder: (BuildContext menu) => <PopupMenuEntry<void>>[
                    PopupMenuItem<void>(
                      key: const Key('reset-orders'),
                      onTap: () => _confirmReset(context),
                      child: const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_sweep),
                        title: Text('Svuota gli ordini'),
                      ),
                    ),
                  ],
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
                        onTap: () => _showActions(context, order),
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
