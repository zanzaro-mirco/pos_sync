import '../data/order_registry.dart';
import '../data/remote_api.dart';
import '../domain/order.dart';

/// Il backend visto dal dispositivo **primario**: sé stesso.
///
/// Sul tablet in cassa il registro è in casa, quindi non c'è niente da mettere
/// in rete: si scrive e si legge direttamente. Serve comunque un `RemoteApi`,
/// perché il primario è un dispositivo come gli altri — ha la sua coda, i suoi
/// ritentativi e il suo rientro — e togliergli il concetto di «backend»
/// significherebbe scrivergli un percorso di sincronizzazione tutto suo.
///
/// Non fallisce mai per ragioni di rete, ed è corretto: non ce n'è. La coda si
/// svuota al primo giro, il che è esattamente ciò che deve succedere a chi il
/// registro ce l'ha sotto le dita.
class LocalRegistryApi implements RemoteApi {
  const LocalRegistryApi({required this.registry, required this.deviceId});

  final OrderRegistry registry;

  /// Identificativo di questo dispositivo, non del ruolo: il primario deposita
  /// la propria versione come chiunque altro, e deve restare distinguibile
  /// dalle versioni dei follower.
  final String deviceId;

  @override
  Future<void> submitOrder(Order order) async =>
      registry.store(order, deviceId);

  @override
  Future<List<Order>> fetchOrders() async => registry.versionsExcept(deviceId);
}
