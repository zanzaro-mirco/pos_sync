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

  /// Stato di sincronizzazione, locale a questo dispositivo.
  TextColumn get status => text()();

  /// Stato del tavolo, condiviso fra i dispositivi.
  TextColumn get state =>
      text().withDefault(const Constant<String>('aperto'))();

  /// Revisione dell'ultimo cambio di stato, in due colonne piatte.
  ///
  /// Un valore composto scritto in una colonna sola — `"7@tablet-a"` — sarebbe
  /// più compatto e impossibile da ordinare in SQL. Separate si possono
  /// confrontare e indicizzare.
  IntColumn get stateRevisionCounter => integer()
      .named('state_revision_counter')
      .withDefault(const Constant<int>(0))();
  TextColumn get stateRevisionDevice => text()
      .named('state_revision_device')
      .withDefault(const Constant<String>(''))();

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

  /// Identificativo della riga, stabile fra i dispositivi.
  ///
  /// Non è la chiave primaria e non lo diventa: la posizione dipende
  /// dall'ordine locale e cambia a ogni fusione, l'id no. Serve all'unione
  /// append-only, che senza di esso duplicherebbe la stessa riga a ogni
  /// sincronizzazione.
  TextColumn get lineId =>
      text().named('line_id').withDefault(const Constant<String>(''))();

  /// Revisione a cui la riga è stata aggiunta.
  IntColumn get addedAtCounter =>
      integer().named('added_at_counter').withDefault(const Constant<int>(0))();
  TextColumn get addedAtDevice =>
      text().named('added_at_device').withDefault(const Constant<String>(''))();

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

/// Conflitti aperti, in attesa che qualcuno decida.
///
/// Le due versioni sono conservate come JSON, con lo stesso DTO che le manda in
/// rete. Normalizzarle in tabelle significherebbe reggere due ordini "ombra"
/// accanto a quello vero, con le loro righe e le loro cascate, per un dato che
/// nessuno interroga: di un conflitto si legge tutto o niente. È anche il
/// secondo impiego del DTO, che smette di esistere solo per il trasporto.
///
/// Nessuna chiave esterna verso `orders`, per la stessa ragione della coda: se
/// l'ordine sparisce, il conflitto resta e va chiuso a mano.
@DataClassName('ConflictRow')
class Conflicts extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().named('order_id')();

  /// La versione locale, serializzata.
  TextColumn get mine => text()();

  /// La versione arrivata dall'altro dispositivo, serializzata.
  TextColumn get theirs => text()();

  TextColumn get reason => text()();
  IntColumn get detectedAt => integer().named('detected_at')();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Chi è questo dispositivo e a che punto è il suo contatore logico.
///
/// Una riga sola, con chiave fissa: non è una tabella, è una cassetta. Ma vive
/// qui e non fra le preferenze perché deve stare nella **stessa transazione**
/// dei dati che numera — un contatore salvato altrove può disallinearsi da ciò
/// che ha numerato, e un contatore che torna indietro rompe l'ordine totale su
/// cui si regge tutta la convergenza.
@DataClassName('DeviceRow')
class DeviceIdentity extends Table {
  /// Sempre 1: la riga è una sola e questo lo rende impossibile da sbagliare.
  IntColumn get id => integer()();

  TextColumn get deviceId => text().named('device_id')();
  IntColumn get counter => integer().withDefault(const Constant<int>(0))();

  /// Che parte fa questo dispositivo in rete locale.
  ///
  /// Sta qui e non in una tabella sua per la stessa ragione del contatore: è
  /// una cassetta a riga singola, e una tabella in più per tre colonne
  /// sarebbe cerimonia. Il valore predefinito non è una comodità — un'app
  /// appena installata deve funzionare senza che nessuno abbia configurato
  /// niente.
  TextColumn get role =>
      text().withDefault(const Constant<String>('standalone'))();

  /// Indirizzo del primario, significativo solo per un follower.
  TextColumn get primaryHost =>
      text().named('primary_host').withDefault(const Constant<String>(''))();

  /// Deve valere quanto `lanPort` in `lan/lan_protocol.dart`.
  ///
  /// Scritto a mano invece di importare la costante perché drift **ricopia
  /// questa espressione nel codice generato**, che non ha quell'import e non
  /// compilerebbe. I due valori sono tenuti allineati da un test, che è il
  /// solo modo per accorgersene se uno dei due cambia.
  IntColumn get primaryPort =>
      integer().named('primary_port').withDefault(const Constant<int>(53170))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
