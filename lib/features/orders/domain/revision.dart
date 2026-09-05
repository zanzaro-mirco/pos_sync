import 'package:equatable/equatable.dart';

/// Quando una modifica è avvenuta, secondo il tempo logico e non secondo
/// l'orologio del dispositivo.
///
/// Un `DateTime` non serve a ordinare modifiche fatte da dispositivi diversi:
/// basta un tablet con l'ora sbagliata di due minuti e le sue modifiche
/// vincono su tutto, o non vincono mai. L'ora di sistema è un dato che
/// l'utente può cambiare dalle impostazioni; l'ordinamento di un sistema
/// distribuito non può dipenderne.
///
/// Qui l'ordine sta nel dato: un contatore che cresce a ogni modifica
/// ([counter]) e l'identificativo di chi l'ha fatta ([deviceId]) a rompere la
/// parità. Il risultato è un ordine **totale** — fra due revisioni qualsiasi
/// una delle due viene prima, sempre, e tutti i dispositivi sono d'accordo su
/// quale. È la proprietà da cui dipende la convergenza: senza il tiebreak sul
/// dispositivo due modifiche allo stesso contatore sarebbero inordinabili, e
/// due dispositivi che le ricevono in ordine diverso sceglierebbero vincitori
/// diversi.
class Revision extends Equatable implements Comparable<Revision> {
  const Revision({required this.counter, required this.deviceId});

  /// Revisione che precede qualunque altra: il punto di partenza.
  const Revision.initial()
      : counter = 0,
        deviceId = '';

  /// Contatore logico di Lamport al momento della modifica.
  final int counter;

  /// Dispositivo che ha fatto la modifica.
  final String deviceId;

  @override
  int compareTo(Revision other) {
    final int byCounter = counter.compareTo(other.counter);
    // Il confronto sul dispositivo non ha significato di merito: serve solo a
    // garantire che una risposta ci sia e che sia la stessa ovunque.
    return byCounter != 0 ? byCounter : deviceId.compareTo(other.deviceId);
  }

  bool operator >(Revision other) => compareTo(other) > 0;
  bool operator <(Revision other) => compareTo(other) < 0;
  bool operator >=(Revision other) => compareTo(other) >= 0;
  bool operator <=(Revision other) => compareTo(other) <= 0;

  @override
  List<Object?> get props => <Object?>[counter, deviceId];

  @override
  String toString() => 'Revision($counter@$deviceId)';
}
