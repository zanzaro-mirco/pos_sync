import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/order_conflict.dart';
import '../domain/order_line_draft.dart';
import '../domain/order_state.dart';
import '../domain/orders_repository.dart';
import '../domain/orders_snapshot.dart';
import '../sync/sync_worker.dart';
import 'orders_state.dart';

/// Stato della schermata ordini.
///
/// Il cubit non conosce la rete né il database: parla solo con il repository e
/// con il worker. È questo che permette di testarlo senza far partire nulla.
///
/// Osserva il flusso degli ordini invece di ricaricare la lista dopo ogni
/// operazione. Prima ogni creazione faceva due letture complete: una dopo il
/// salvataggio e una dopo la sincronizzazione. Ora la sorgente notifica i
/// cambiamenti e la UI si aggiorna una volta sola, per il cambiamento che è
/// avvenuto davvero.
class OrdersCubit extends Cubit<OrdersState> {
  OrdersCubit({
    required OrdersRepository repository,
    required SyncWorker syncWorker,
  })  : _repository = repository,
        _syncWorker = syncWorker,
        super(const OrdersState());

  final OrdersRepository _repository;
  final SyncWorker _syncWorker;
  StreamSubscription<OrdersSnapshot>? _subscription;

  /// Avvia l'osservazione. Idempotente.
  ///
  /// Il listener è sincrono di proposito: se dovesse attendere un'altra
  /// chiamata prima di emettere, due cambiamenti ravvicinati potrebbero
  /// arrivare alla UI nell'ordine sbagliato. Lo snapshot porta già tutto ciò
  /// che serve.
  void start() {
    if (_subscription != null) return;
    emit(state.copyWith(status: OrdersStatus.loading));
    _subscription = _repository.watch().listen(
          (OrdersSnapshot snapshot) => emit(
            state.copyWith(
              status: OrdersStatus.ready,
              orders: snapshot.orders,
              pending: snapshot.pending,
              conflicts: snapshot.conflicts,
            ),
          ),
          onError: (Object e) =>
              emit(state.copyWith(status: OrdersStatus.error, message: '$e')),
        );
  }

  /// Crea un ordine. Funziona identicamente online e offline: è il punto
  /// dell'architettura.
  Future<void> addOrder({
    required int tableNumber,
    required List<OrderLineDraft> lines,
  }) async {
    try {
      await _repository.createOrder(tableNumber: tableNumber, lines: lines);
      unawaited(sync());
    } catch (e) {
      emit(state.copyWith(status: OrdersStatus.error, message: '$e'));
    }
  }

  /// Cambia lo stato del tavolo. Come tutto il resto, funziona anche offline:
  /// la modifica è locale e porta con sé la revisione che la data.
  Future<void> changeState({
    required String orderId,
    required OrderState state,
  }) async {
    try {
      await _repository.changeState(orderId: orderId, state: state);
      unawaited(sync());
    } catch (e) {
      emit(this.state.copyWith(status: OrdersStatus.error, message: '$e'));
    }
  }

  /// Chiude un conflitto con la decisione dell'operatore.
  Future<void> resolveConflict(
    OrderConflict conflict,
    ConflictChoice choice,
  ) async {
    try {
      await _repository.resolveConflict(conflict.id, choice);
      unawaited(sync());
    } catch (e) {
      emit(state.copyWith(status: OrdersStatus.error, message: '$e'));
    }
  }

  Future<SyncResult> sync() => _syncWorker.drain();

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
