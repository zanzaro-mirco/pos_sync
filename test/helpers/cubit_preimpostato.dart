import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_sync/features/orders/domain/order_conflict.dart';
import 'package:pos_sync/features/orders/domain/order_line_draft.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/presentation/orders_cubit.dart';
import 'package:pos_sync/features/orders/presentation/orders_state.dart';
import 'package:pos_sync/features/orders/sync/sync_worker.dart';

/// Cubit con lo stato deciso dal test.
///
/// `OrdersCubit` è un `Cubit<OrdersState>`, quindi per la pagina basta
/// implementarne il contratto: niente repository, niente worker, niente
/// database. Un widget test che dovesse montare il grafo vero per vedere una
/// lista vuota starebbe testando il grafo, non la pagina.
///
/// Conta anche le chiamate ricevute, così si può verificare che i comandi
/// dell'interfaccia arrivino a destinazione invece di limitarsi a verificare
/// che i pulsanti esistano.
class CubitPreimpostato extends Cubit<OrdersState> implements OrdersCubit {
  CubitPreimpostato(super.initialState);

  int avvii = 0;
  int sincronizzazioni = 0;
  final List<int> tavoliAggiunti = <int>[];
  final List<String> comandeAggiunte = <String>[];
  final List<(String, OrderState)> statiCambiati = <(String, OrderState)>[];
  final List<(String, ConflictChoice)> conflittiRisolti =
      <(String, ConflictChoice)>[];

  @override
  void start() => avvii++;

  @override
  Future<void> addOrder({
    required int tableNumber,
    required List<OrderLineDraft> lines,
  }) async {
    tavoliAggiunti.add(tableNumber);
  }

  @override
  Future<void> addLines({
    required String orderId,
    required List<OrderLineDraft> lines,
  }) async {
    comandeAggiunte.add(orderId);
  }

  @override
  Future<void> changeState({
    required String orderId,
    required OrderState state,
  }) async {
    statiCambiati.add((orderId, state));
  }

  @override
  Future<void> resolveConflict(
    OrderConflict conflict,
    ConflictChoice choice,
  ) async {
    conflittiRisolti.add((conflict.id, choice));
  }

  @override
  Future<SyncResult> sync() async {
    sincronizzazioni++;
    return const SyncResult();
  }
}
