import 'revision.dart';

/// Stato del tavolo, condiviso fra i dispositivi.
///
/// Da non confondere con `SyncStatus`, che è tutt'altro: quello dice se *questo*
/// dispositivo è riuscito a mandare l'ordine al server, ed è un fatto locale che
/// non interessa a nessun altro. Questo dice cosa sta succedendo al tavolo, ed è
/// il dato che due camerieri possono cambiare nello stesso momento da due
/// dispositivi diversi — cioè l'unico posto dove un conflitto può nascere.
enum OrderState {
  /// Ordinato, non ancora servito.
  aperto,

  /// Portato al tavolo.
  servito,

  /// Conto saldato.
  pagato,
}

/// Lo stato del tavolo insieme alla revisione che lo data.
///
/// Stanno insieme perché non hanno senso separati: uno stato senza la sua
/// revisione non si può confrontare con quello di un altro dispositivo, ed è
/// proprio il confronto la sola cosa che serve farne.
class StampedState {
  const StampedState(this.value, this.revision);

  final OrderState value;
  final Revision revision;

  @override
  bool operator ==(Object other) =>
      other is StampedState &&
      other.value == value &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(value, revision);

  @override
  String toString() => 'StampedState(${value.name} @ $revision)';
}
