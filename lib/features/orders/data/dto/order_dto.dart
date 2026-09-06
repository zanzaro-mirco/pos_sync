import '../../domain/order.dart';
import '../../domain/order_line.dart';
import '../../domain/order_state.dart';
import '../../domain/revision.dart';

/// Rappresentazione di rete di una revisione.
///
/// Due campi piatti invece di un oggetto annidato: una revisione è una coppia
/// di valori primitivi e annidarla costerebbe un livello di parsing in più per
/// niente.
class RevisionDto {
  const RevisionDto({required this.counter, required this.deviceId});

  factory RevisionDto.fromDomain(Revision revision) =>
      RevisionDto(counter: revision.counter, deviceId: revision.deviceId);

  final int counter;
  final String deviceId;

  Revision toDomain() => Revision(counter: counter, deviceId: deviceId);
}

/// Rappresentazione di rete di una riga d'ordine.
class OrderLineDto {
  const OrderLineDto({
    required this.id,
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    required this.addedAtCounter,
    required this.addedAtDevice,
  });

  factory OrderLineDto.fromDomain(OrderLine line) => OrderLineDto(
        id: line.id,
        productId: line.productId,
        description: line.description,
        quantity: line.quantity,
        unitPriceCents: line.unitPriceCents,
        addedAtCounter: line.addedAt.counter,
        addedAtDevice: line.addedAt.deviceId,
      );

  factory OrderLineDto.fromJson(Map<String, dynamic> json) => OrderLineDto(
        id: json['id'] as String? ?? '',
        productId: json['productId'] as String? ?? '',
        description: json['description'] as String? ?? '',
        quantity: json['quantity'] as int? ?? 0,
        unitPriceCents: json['unitPriceCents'] as int? ?? 0,
        addedAtCounter: json['addedAtCounter'] as int? ?? 0,
        addedAtDevice: json['addedAtDevice'] as String? ?? '',
      );

  final String id;
  final String productId;
  final String description;
  final int quantity;
  final int unitPriceCents;
  final int addedAtCounter;
  final String addedAtDevice;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'productId': productId,
        'description': description,
        'quantity': quantity,
        'unitPriceCents': unitPriceCents,
        'addedAtCounter': addedAtCounter,
        'addedAtDevice': addedAtDevice,
      };

  OrderLine toDomain() => OrderLine(
        id: id,
        productId: productId,
        description: description,
        quantity: quantity,
        unitPriceCents: unitPriceCents,
        addedAt: Revision(counter: addedAtCounter, deviceId: addedAtDevice),
      );
}

/// Rappresentazione di rete di un ordine.
///
/// Volutamente più permissiva del modello di dominio: i campi arrivano
/// nullable perché un backend può omettere o rinominare qualcosa, e questo non
/// deve far crashare l'app. Qui si assorbono le imperfezioni del contratto, in
/// un punto solo.
///
/// Attraversa la rete lo stato **condiviso** del tavolo con la sua revisione.
/// Non lo attraversa `SyncStatus`, che dice se *questo* dispositivo è riuscito
/// a mandare l'ordine: è un fatto locale, e spedirlo significherebbe che il
/// giudizio di un dispositivo sulla propria connessione diventa quello di tutti.
class OrderDto {
  const OrderDto({
    required this.id,
    required this.tableNumber,
    required this.createdAtIso,
    required this.lines,
    this.state = 'open',
    this.stateRevisionCounter = 0,
    this.stateRevisionDevice = '',
  });

  factory OrderDto.fromDomain(Order order) => OrderDto(
        id: order.id,
        tableNumber: order.tableNumber,
        createdAtIso: order.createdAt.toIso8601String(),
        lines: order.lines.map(OrderLineDto.fromDomain).toList(),
        state: order.state.name,
        stateRevisionCounter: order.stateRevision.counter,
        stateRevisionDevice: order.stateRevision.deviceId,
      );

  factory OrderDto.fromJson(Map<String, dynamic> json) => OrderDto(
        id: json['id'] as String? ?? '',
        tableNumber: json['tableNumber'] as int? ?? 0,
        createdAtIso: json['createdAt'] as String? ?? '',
        lines: (json['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(OrderLineDto.fromJson)
            .toList(),
        state: json['state'] as String? ?? 'open',
        stateRevisionCounter: json['stateRevisionCounter'] as int? ?? 0,
        stateRevisionDevice: json['stateRevisionDevice'] as String? ?? '',
      );

  final String id;
  final int tableNumber;
  final String createdAtIso;
  final List<OrderLineDto> lines;
  final String state;
  final int stateRevisionCounter;
  final String stateRevisionDevice;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'tableNumber': tableNumber,
        'createdAt': createdAtIso,
        'lines': lines.map((OrderLineDto l) => l.toJson()).toList(),
        'state': state,
        'stateRevisionCounter': stateRevisionCounter,
        'stateRevisionDevice': stateRevisionDevice,
      };

  /// Traduzione verso il dominio. Restituisce `null` se il record non è
  /// utilizzabile: meglio scartare una riga che propagare un dato incoerente.
  Order? toDomain() {
    if (id.isEmpty) return null;
    final DateTime? createdAt = DateTime.tryParse(createdAtIso);
    if (createdAt == null) return null;
    return Order(
      id: id,
      tableNumber: tableNumber,
      lines: lines.map((OrderLineDto l) => l.toDomain()).toList(),
      createdAt: createdAt,
      state: parseOrderState(state),
      stateRevision: Revision(
        counter: stateRevisionCounter,
        deviceId: stateRevisionDevice,
      ),
    );
  }
}

/// Uno stato sconosciuto diventa `open` invece di far fallire il parsing.
///
/// Un backend più recente potrebbe introdurre uno stato che questa versione
/// dell'app non conosce; scartare l'intero ordine per quello sarebbe una
/// reazione sproporzionata, e `open` è la scelta prudente — un tavolo che
/// resta aperto per errore si nota, uno che risulta pagato per errore no.
/// **I nomi italiani si leggono ancora.** Le costanti dell'enumerazione si
/// chiamavano `aperto`, `servito` e `pagato`, e finivano su SQLite così com'erano:
/// un dispositivo aggiornato trova quei valori nella propria base dati. Un
/// confronto sui soli nomi nuovi li avrebbe fatti scivolare tutti nel caso
/// predefinito, cioè avrebbe riaperto in silenzio ogni tavolo servito o pagato —
/// la peggiore delle perdite di dati, quella che non fa rumore.
///
/// Non serve una migrazione: la corrispondenza sta qui, si scrive sempre e solo
/// il nome nuovo, e i valori vecchi si esauriscono da soli alla prima modifica
/// di ciascun ordine.
OrderState parseOrderState(String raw) => switch (raw) {
      'open' || 'aperto' => OrderState.open,
      'served' || 'servito' => OrderState.served,
      'paid' || 'pagato' => OrderState.paid,
      _ => OrderState.open,
    };
