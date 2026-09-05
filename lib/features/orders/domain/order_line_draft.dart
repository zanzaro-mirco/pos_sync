/// Una riga come la scrive chi prende l'ordine: cosa e quanto, e basta.
///
/// L'identificativo e la revisione non ci sono perché non spettano a chi
/// compila la comanda: li assegna il repository, che è l'unico a sapere qual è
/// questo dispositivo e a che punto è il suo contatore logico. Un tipo separato
/// invece di un `OrderLine` con i campi lasciati vuoti rende la regola
/// strutturale — non c'è modo di inventarsi un id di riga dalla presentazione,
/// e due dispositivi non possono coniare lo stesso.
class OrderLineDraft {
  const OrderLineDraft({
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
  });

  final String productId;
  final String description;
  final int quantity;
  final int unitPriceCents;
}
