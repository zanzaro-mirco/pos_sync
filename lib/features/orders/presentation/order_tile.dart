import 'package:flutter/material.dart';

import '../domain/order.dart';
import '../domain/sync_status.dart';

/// Una riga della lista ordini.
///
/// Estratta dalla pagina per poterla rendere da sola in un golden test: un
/// golden sull'intera schermata cambierebbe a ogni ritocco della barra
/// superiore, e un test che fallisce per motivi che non interessano smette
/// presto di essere letto.
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SyncStatusIcon(status: order.status),
      title: Text('Tavolo ${order.tableNumber}'),
      subtitle: Text('${order.itemCount} articoli'),
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
  static const Color inAttesa = Color(0xFF757575);

  /// Verde: confermato dal server.
  static const Color sincronizzato = Color(0xFF2E7D32);

  /// Rosso: rifiutato in modo definitivo, richiede intervento.
  static const Color fallito = Color(0xFFC62828);

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _etichetta,
      child: switch (status) {
        SyncStatus.pending => const Icon(
            Icons.schedule,
            color: inAttesa,
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
            color: sincronizzato,
            key: Key('status-synced'),
          ),
        SyncStatus.failed => const Icon(
            Icons.error_outline,
            color: fallito,
            key: Key('status-failed'),
          ),
      },
    );
  }

  String get _etichetta => switch (status) {
        SyncStatus.pending => 'Da inviare',
        SyncStatus.sending => 'Invio in corso',
        SyncStatus.synced => 'Sincronizzato',
        SyncStatus.failed => 'Invio fallito',
      };
}
