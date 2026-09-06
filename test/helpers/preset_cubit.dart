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
class PresetCubit extends Cubit<OrdersState> implements OrdersCubit {
  PresetCubit(super.initialState);

  int starts = 0;
  int syncs = 0;
  final List<int> addedTables = <int>[];
  final List<String> addedLines = <String>[];
  final List<(String, OrderState)> changedStates = <(String, OrderState)>[];
  final List<(String, ConflictChoice)> resolvedConflicts =
      <(String, ConflictChoice)>[];

  @override
  void start() => starts++;

  @override
  Future<void> addOrder({
    required int tableNumber,
    required List<OrderLineDraft> lines,
  }) async {
    addedTables.add(tableNumber);
  }

  @override
  Future<void> addLines({
    required String orderId,
    required List<OrderLineDraft> lines,
  }) async {
    addedLines.add(orderId);
  }

  @override
  Future<void> changeState({
    required String orderId,
    required OrderState state,
  }) async {
    changedStates.add((orderId, state));
  }

  @override
  Future<void> resolveConflict(
    OrderConflict conflict,
    ConflictChoice choice,
  ) async {
    resolvedConflicts.add((conflict.id, choice));
  }

  @override
  Future<SyncResult> sync() async {
    syncs++;
    return const SyncResult();
  }
}
