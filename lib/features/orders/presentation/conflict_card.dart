import 'package:flutter/material.dart';

import '../domain/order.dart';
import '../domain/order_conflict.dart';
import '../domain/order_state.dart';
import 'order_state_label.dart';

/// Le due versioni di un ordine, con la decisione da prendere.
///
/// Sta in cima alla lista e non in una schermata a parte: un conflitto è
/// un'informazione **su un ordine**, e mandarla altrove significa che qualcuno
/// deve ricordarsi di andarla a cercare. Quello che si vede accanto ai tavoli
/// si risolve; quello che sta dietro a una voce di menu resta lì.
///
/// Le due scelte sono descritte per quello che fanno — «tieni il pagamento»,
/// «riapri il tavolo» — e non per la loro provenienza. «Tieni la mia» costringe
/// chi decide a ricostruire quale sia la propria e cosa comporti; qui la
/// conseguenza è scritta sul pulsante.
class ConflictCard extends StatelessWidget {
  const ConflictCard({
    super.key,
    required this.conflict,
    required this.onKeepMine,
    required this.onKeepTheirs,
  });

  static const Color _border = Color(0xFFB26A00);

  final OrderConflict conflict;
  final VoidCallback onKeepMine;
  final VoidCallback onKeepTheirs;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      key: Key('conflict-${conflict.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.warning_amber, color: _border),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tavolo ${conflict.tableNumber}',
                    style: text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(conflict.reason, key: const Key('conflict-reason')),
            const SizedBox(height: 12),
            _Version(label: 'Qui', order: conflict.mine),
            _Version(label: 'Sull\'altro dispositivo', order: conflict.theirs),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  key: Key('conflict-mine-${conflict.id}'),
                  onPressed: onKeepMine,
                  child: Text('Tieni ${_action(conflict.mine)}'),
                ),
                FilledButton(
                  key: Key('conflict-theirs-${conflict.id}'),
                  onPressed: onKeepTheirs,
                  child: Text('Tieni ${_action(conflict.theirs)}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Cosa si tiene scegliendo questa versione.
  ///
  /// Lo `switch` è sull'enumerazione e non su `state.name`: confrontare
  /// stringhe funzionava finché le costanti erano scritte in italiano, e
  /// sarebbe rimasto verde compilando anche dopo averle rinominate —
  /// restituendo in silenzio «il tavolo aperto» per un tavolo pagato.
  static String _action(Order order) => switch (order.state) {
        OrderState.paid => 'il pagamento',
        OrderState.served => 'servito',
        OrderState.open => 'il tavolo aperto',
      };
}

/// Una delle due versioni, ridotta a ciò che serve per decidere: com'è il
/// tavolo e quanta roba c'è dentro.
class _Version extends StatelessWidget {
  const _Version({required this.label, required this.order});

  final String label;
  final Order order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '$label: ${orderStateLabel(order.state)}, '
        '${order.lines.length} righe, '
        '${(order.totalCents / 100).toStringAsFixed(2)} €',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
