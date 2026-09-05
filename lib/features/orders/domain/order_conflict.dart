import 'package:equatable/equatable.dart';

import 'order.dart';

/// Quale delle due versioni tenere, quando decide l'operatore.
///
/// La scelta riguarda **solo lo stato del tavolo**: le righe sono append-only e
/// restano unite in ogni caso. Non è una limitazione, è la ragione per cui è
/// sicuro chiedere — qualunque cosa l'operatore risponda, nessuna comanda
/// sparisce.
enum ConflictChoice { mine, theirs }

/// Due versioni dello stesso ordine che il codice non se l'è sentita di fondere.
///
/// Sopravvive nel deposito locale finché qualcuno non decide: un conflitto che
/// esiste solo in memoria si perde alla prima chiusura dell'app, ed è il modo
/// più rapido per fondere in silenzio dopo aver dichiarato di non volerlo fare.
class OrderConflict extends Equatable {
  const OrderConflict({
    required this.id,
    required this.mine,
    required this.theirs,
    required this.reason,
    required this.detectedAt,
  });

  final String id;

  /// La versione di questo dispositivo.
  final Order mine;

  /// La versione arrivata dall'altro.
  final Order theirs;

  /// Perché il codice si è fermato, in una frase leggibile dall'operatore.
  final String reason;

  final DateTime detectedAt;

  String get orderId => mine.id;
  int get tableNumber => mine.tableNumber;

  @override
  List<Object?> get props => <Object?>[id, mine, theirs, reason, detectedAt];
}
