import '../domain/order_state.dart';

/// Come si scrive uno stato del tavolo nell'interfaccia.
///
/// Finché le costanti dell'enumerazione erano italiane, `state.name` faceva due
/// mestieri: era il nome del valore nel codice **e** la parola che l'operatore
/// leggeva sullo schermo. Comodo, e sbagliato: rinominare una costante — cioè
/// una modifica interna — cambiava ciò che si legge in sala. La traduzione
/// adesso è esplicita e sta qui, dove stanno le altre parole dell'interfaccia.
///
/// Lo `switch` è sull'enumerazione e non sulla stringa: se domani si aggiunge
/// uno stato, il compilatore lo segnala qui invece di lasciar comparire una
/// parola inglese in mezzo alla schermata.
String orderStateLabel(OrderState state) => switch (state) {
      OrderState.open => 'aperto',
      OrderState.served => 'servito',
      OrderState.paid => 'pagato',
    };
