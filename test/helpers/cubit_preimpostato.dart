import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
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

  @override
  void start() => avvii++;

  @override
  Future<void> addOrder({
    required int tableNumber,
    required List<OrderLine> lines,
  }) async {
    tavoliAggiunti.add(tableNumber);
  }

  @override
  Future<SyncResult> sync() async {
    sincronizzazioni++;
    return const SyncResult();
  }
}
