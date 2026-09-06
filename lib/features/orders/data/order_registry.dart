import '../domain/order.dart';

/// Cosa il punto di raccolta sa, e di chi.
///
/// È la forma che `FakeServer` aveva già preso da sé nella voce sui conflitti:
/// per ogni ordine, **l'ultima versione ricevuta da ciascun dispositivo**. Qui
/// diventa un contratto perché in rete locale quel punto di raccolta non è più
/// un oggetto di prova — è il tablet in cassa.
///
/// **Non fonde.** Restituisce una voce per dispositivo e non una versione sola,
/// e la ragione è la stessa per cui `RemoteApi.fetchOrders` fa lo stesso: la
/// versione di un dispositivo è ciò che *quel* dispositivo credeva, e fonderla
/// qui distruggerebbe la provenienza su cui si regge il riconoscimento di un
/// conflitto — una versione fusa contiene tutte le righe per costruzione.
/// Fondere è lavoro di chi riceve, non di chi custodisce.
abstract interface class OrderRegistry {
  /// Registra la versione di [order] così come la vede [deviceId].
  ///
  /// Idempotente rispetto alla coppia *(ordine, dispositivo)*: ricevere due
  /// volte lo stesso invio sovrascrive, non accumula. È la proprietà su cui si
  /// regge il ritentativo dopo una risposta persa.
  void store(Order order, String deviceId);

  /// Le versioni degli *altri* dispositivi.
  ///
  /// L'esclusione guarda chi ha inviato, non cosa contiene la versione: è il
  /// registro a saperlo, ed è l'unico posto in cui l'informazione esiste.
  List<Order> versionsExcept(String deviceId);

  /// Tutte le versioni conosciute, appiattite.
  List<Order> allVersions();
}
