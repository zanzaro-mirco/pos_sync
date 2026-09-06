import 'package:flutter/material.dart';

/// Chiede il numero del tavolo, proponendo quello suggerito.
///
/// Prima il numero veniva incrementato d'ufficio, e la conseguenza era che
/// **due ordini sullo stesso tavolo non si potevano creare** — cioè proprio lo
/// scenario per cui esistono la fusione e i conflitti. Poterlo ripetere non è
/// una comodità: è ciò che rende dimostrabile il resto.
///
/// Restituisce `null` se non c'è niente da creare: finestra annullata, o campo
/// lasciato vuoto.
///
/// **Niente `TextEditingController`.** Il campo vive quanto la finestra, e un
/// controller creato qui andrebbe liberato *dopo* che la finestra ha finito di
/// chiudersi: `whenComplete` sul futuro di `showDialog` scatta alla `pop`,
/// mentre l'animazione di uscita sta ancora ridisegnando il campo — e ridisegnare
/// un campo il cui controller è già stato liberato fa cadere la build. Con
/// `initialValue` e `onChanged` non c'è niente da liberare, quindi non c'è
/// nessun momento in cui liberarlo può essere sbagliato.
///
/// Sta qui e non in `main.dart` perché è presentazione, e perché lì dentro non
/// sarebbe raggiungibile da un test: questo bug è arrivato sul dispositivo
/// esattamente per quel motivo.
Future<int?> askTableNumber(BuildContext context, int suggested) {
  int? chosen = suggested;

  return showDialog<int>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      title: const Text('Numero del tavolo'),
      content: TextFormField(
        key: const Key('table-number-field'),
        initialValue: '$suggested',
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          helperText: 'Si può ripetere un tavolo già aperto',
        ),
        onChanged: (String v) => chosen = int.tryParse(v.trim()),
        onFieldSubmitted: (String _) => Navigator.pop(dialog, chosen),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('table-number-cancel'),
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Annulla'),
        ),
        FilledButton(
          key: const Key('table-number-confirm'),
          onPressed: () => Navigator.pop(dialog, chosen),
          child: const Text('Crea'),
        ),
      ],
    ),
  );
}
