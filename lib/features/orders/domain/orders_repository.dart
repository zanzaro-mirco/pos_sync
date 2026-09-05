import 'order.dart';
import 'order_conflict.dart';
import 'order_line_draft.dart';
import 'order_state.dart';
import 'orders_snapshot.dart';

/// Contratto del repository, visto dal dominio e dalla presentazione.
///
/// Non compare mai la parola "rete": chi legge gli ordini non deve sapere se
/// il dispositivo è online. È il cuore dell'approccio offline-first.
abstract interface class OrdersRepository {
  /// Flusso osservabile: emette una fotografia coerente a ogni cambiamento.
  Stream<OrdersSnapshot> watch();

  Future<List<Order>> loadOrders();

  /// Crea un ordine, lo persiste e lo accoda per l'invio.
  Future<Order> createOrder({
    required int tableNumber,
    required List<OrderLineDraft> lines,
  });

  /// Aggiunge righe a un ordine esistente.
  ///
  /// Le righe si aggiungono e non si modificano: è la scelta che permette a due
  /// camerieri di lavorare sullo stesso tavolo senza pestarsi i piedi, perché
  /// l'unione di due insiemi non dipende da chi arriva prima.
  Future<Order> addLines({
    required String orderId,
    required List<OrderLineDraft> lines,
  });

  /// Cambia lo stato del tavolo.
  ///
  /// Qui invece uno dei due deve perdere, e a decidere è la revisione: non
  /// l'ora di sistema, non l'ordine di arrivo.
  Future<Order> changeState({
    required String orderId,
    required OrderState state,
  });

  /// Chiude un conflitto tenendo lo stato di una delle due versioni.
  ///
  /// Le righe restano unite in ogni caso: la scelta non fa sparire niente.
  Future<void> resolveConflict(String conflictId, ConflictChoice choice);

  /// Numero di operazioni ancora da sincronizzare.
  Future<int> pendingCount();
}
