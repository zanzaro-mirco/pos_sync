import 'package:flutter/material.dart';

import '../domain/order.dart';
import '../domain/order_state.dart';
import '../domain/sync_status.dart';
import 'order_state_label.dart';

/// Una riga della lista ordini.
///
/// Estratta dalla pagina per poterla rendere da sola in un golden test: un
/// golden sull'intera schermata cambierebbe a ogni ritocco della barra
/// superiore, e un test che fallisce per motivi che non interessano smette
/// presto di essere letto.
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, this.onTap});

  final Order order;

  /// Cosa fare toccando la riga. Nullable: nei golden la riga si ritrae da
  /// sola, senza che nessuno debba inventarsi un'azione per poterla disegnare.
  final VoidCallback? onTap;

  /// `open` non si scrive.
  ///
  /// È lo stato normale di un tavolo, e ripeterlo su ogni riga riempirebbe la
  /// lista di una parola che non distingue niente: si nota ciò che è raro, non
  /// ciò che c'è ovunque. Ha anche l'effetto di lasciare intatti i quattro
  /// riferimenti golden, che ritraggono tavoli aperti.
  String get _subtitle => order.state == OrderState.open
      ? '${order.itemCount} articoli'
      : '${order.itemCount} articoli · ${orderStateLabel(order.state)}';

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: SyncStatusIcon(status: order.status),
      title: Text('Tavolo ${order.tableNumber}'),
      subtitle: Text(_subtitle),
      trailing: Text('${(order.totalCents / 100).toStringAsFixed(2)} €'),
    );
  }
}

/// L'indicatore di stato di un ordine.
///
/// **I colori non vengono dalla `ColorScheme`.** Il seme del tema è una
/// decisione di marca e può cambiare; "in attesa", "riuscito" e "fallito"
/// devono invece restare leggibili come stati. Derivarli dal seme
/// significherebbe che un cambio di colore aziendale può rendere il successo e
/// l'errore due sfumature della stessa tinta.
///
/// Il colore non è comunque l'unico portatore dell'informazione: le quattro
/// icone sono diverse fra loro e ognuna ha un'etichetta per il lettore di
/// schermo. Un utente che non distingue il rosso dal verde legge lo stato
/// dall'icona, non dalla tinta.
class SyncStatusIcon extends StatelessWidget {
  const SyncStatusIcon({super.key, required this.status});

  /// Grigio: salvato, in attesa del suo turno. Non è un problema.
  static const Color pending = Color(0xFF757575);

  /// Verde: confermato dal server.
  static const Color synced = Color(0xFF2E7D32);

  /// Rosso: rifiutato in modo definitivo, richiede intervento.
  static const Color failed = Color(0xFFC62828);

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _label,
      child: switch (status) {
        SyncStatus.pending => const Icon(
            Icons.schedule,
            color: pending,
            key: Key('status-pending'),
          ),
        // L'invio è l'unico stato in movimento, ed è l'unico che segue il
        // tema: non è un esito, è un'attesa in corso.
        SyncStatus.sending => const SizedBox(
            key: Key('status-sending'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        SyncStatus.synced => const Icon(
            Icons.cloud_done,
            color: synced,
            key: Key('status-synced'),
          ),
        SyncStatus.failed => const Icon(
            Icons.error_outline,
            color: failed,
            key: Key('status-failed'),
          ),
      },
    );
  }

  String get _label => switch (status) {
        SyncStatus.pending => 'Da inviare',
        SyncStatus.sending => 'Invio in corso',
        SyncStatus.synced => 'Sincronizzato',
        SyncStatus.failed => 'Invio fallito',
      };
}
