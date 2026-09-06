import '../domain/order.dart';
import '../domain/order_state.dart';
import '../domain/revision.dart';
import 'remote_api.dart';

/// Un secondo tablet, simulato, perché i conflitti si possano vedere.
///
/// Nell'app in esecuzione c'è **un dispositivo solo**: `FakeRemoteApi` si
/// costruisce il proprio [FakeServer] e `fetchOrders` restituisce le versioni
/// *degli altri*, che non esistono. La conseguenza era che la parte più
/// interessante del sistema — riconoscere il caso ambiguo e chiedere invece di
/// fondere — non poteva comparire sullo schermo e viveva solo nei test.
///
/// Questa classe scrive nel finto server come se lo avesse fatto un altro
/// tablet. Non ha scorciatoie verso il deposito locale né verso la politica di
/// fusione: mette una versione sul server e si ferma lì. Tutto quello che
/// succede dopo — il rientro, la fusione, il conflitto — è il sistema vero che
/// fa il suo mestiere senza sapere che l'altro dispositivo è finto.
class SecondDevice {
  SecondDevice({required this.server, this.deviceId = 'dispositivo-2'});

  final FakeServer server;

  /// Deve essere diverso da quello del dispositivo locale, altrimenti il
  /// server considera questa versione «già nostra» e non la restituisce.
  final String deviceId;

  /// L'altro tablet incassa il tavolo così come lo vede adesso.
  ///
  /// Da sola non produce nessun conflitto, ed è corretto così: se il rientro
  /// avvenisse subito, le due versioni conterrebbero le stesse righe e il
  /// pagamento si fonderebbe in silenzio — che è il comportamento giusto.
  /// Il conflitto nasce alla comanda **successiva**, perché a quel punto la
  /// versione pagata non la contiene, ed è esattamente la domanda su cui la
  /// politica si ferma: chi ha incassato aveva questo davanti?
  ///
  /// La revisione è una più alta di quella locale, così il pagamento vince il
  /// last-write-wins. Non è una forzatura del test: è ciò che accadrebbe
  /// davvero, perché un dispositivo che agisce dopo aver visto lo stato altrui
  /// ne prende atto con `witness` e riparte da lì.
  void pays(Order order) => server.store(
        order.copyWith(
          state: OrderState.paid,
          stateRevision: Revision(
            counter: order.stateRevision.counter + 1,
            deviceId: deviceId,
          ),
        ),
        deviceId,
      );
}
