import 'package:drift/drift.dart';

/// Tabelle della base dati locale.
///
/// I nomi delle classi generate portano il suffisso `Row` (`@DataClassName`)
/// perché il dominio ha già un `Order` e un `OrderLine`: sono due cose diverse
/// e devono restare distinguibili a colpo d'occhio. La riga è il formato di
/// deposito, l'entità di dominio è il modello — la traduzione fra le due sta
/// in un solo posto, `DriftOrderStore`.

@DataClassName('OrderRow')
class Orders extends Table {
  TextColumn get id => text()();
  IntColumn get tableNumber => integer().named('table_number')();

  /// Istante di creazione in **microsecondi** dall'epoca.
  ///
  /// `DateTime` in Dart ha precisione al microsecondo. Salvare secondi — il
  /// formato storico di Drift — o millisecondi troncherebbe, e uno store che
  /// tronca non supera la stessa suite di uno che non tronca. Il fuso non
  /// viene conservato: si legge sempre come ora locale.
  IntColumn get createdAt => integer().named('created_at')();

  TextColumn get status => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('OrderLineRow')
class OrderLines extends Table {
  TextColumn get orderId => text()
      .named('order_id')
      .references(Orders, #id, onDelete: KeyAction.cascade)();

  /// Posizione della riga dentro l'ordine.
  ///
  /// `Order.lines` è una lista *ordinata*, le righe di una tabella SQL non
  /// hanno ordine. Senza questa colonna l'ordine delle righe dipenderebbe da
  /// come il motore decide di restituirle.
  IntColumn get position => integer()();

  TextColumn get productId => text().named('product_id')();
  TextColumn get description => text()();
  IntColumn get quantity => integer()();
  IntColumn get unitPriceCents => integer().named('unit_price_cents')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{orderId, position};
}

/// Coda di uscita.
///
/// Volutamente **senza** chiave esterna verso `orders`: la voce di coda deve
/// poter sopravvivere al suo ordine. Il worker gestisce già esplicitamente il
/// caso dell'ordine sparito, e una cascata renderebbe quel ramo codice morto
/// invece che una difesa.
@DataClassName('OutboxRow')
class Outbox extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().named('order_id')();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get attempts => integer().withDefault(const Constant<int>(0))();
  IntColumn get nextAttemptAt =>
      integer().named('next_attempt_at').nullable()();
  TextColumn get lastError => text().named('last_error').nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
