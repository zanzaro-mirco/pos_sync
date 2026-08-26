import '../../domain/order.dart';
import '../../domain/order_line.dart';

/// Rappresentazione di rete di una riga d'ordine.
class OrderLineDto {
  const OrderLineDto({
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
  });

  factory OrderLineDto.fromDomain(OrderLine line) => OrderLineDto(
        productId: line.productId,
        description: line.description,
        quantity: line.quantity,
        unitPriceCents: line.unitPriceCents,
      );

  factory OrderLineDto.fromJson(Map<String, dynamic> json) => OrderLineDto(
        productId: json['productId'] as String? ?? '',
        description: json['description'] as String? ?? '',
        quantity: json['quantity'] as int? ?? 0,
        unitPriceCents: json['unitPriceCents'] as int? ?? 0,
      );

  final String productId;
  final String description;
  final int quantity;
  final int unitPriceCents;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'description': description,
        'quantity': quantity,
        'unitPriceCents': unitPriceCents,
      };

  OrderLine toDomain() => OrderLine(
        productId: productId,
        description: description,
        quantity: quantity,
        unitPriceCents: unitPriceCents,
      );
}

/// Rappresentazione di rete di un ordine.
///
/// Volutamente più permissiva del modello di dominio: i campi arrivano
/// nullable perché un backend può omettere o rinominare qualcosa, e questo non
/// deve far crashare l'app. Qui si assorbono le imperfezioni del contratto, in
/// un punto solo.
class OrderDto {
  const OrderDto({
    required this.id,
    required this.tableNumber,
    required this.createdAtIso,
    required this.lines,
  });

  factory OrderDto.fromDomain(Order order) => OrderDto(
        id: order.id,
        tableNumber: order.tableNumber,
        createdAtIso: order.createdAt.toIso8601String(),
        lines: order.lines.map(OrderLineDto.fromDomain).toList(),
      );

  factory OrderDto.fromJson(Map<String, dynamic> json) => OrderDto(
        id: json['id'] as String? ?? '',
        tableNumber: json['tableNumber'] as int? ?? 0,
        createdAtIso: json['createdAt'] as String? ?? '',
        lines: (json['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(OrderLineDto.fromJson)
            .toList(),
      );

  final String id;
  final int tableNumber;
  final String createdAtIso;
  final List<OrderLineDto> lines;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'tableNumber': tableNumber,
        'createdAt': createdAtIso,
        'lines': lines.map((OrderLineDto l) => l.toJson()).toList(),
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
    );
  }
}
