import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/dto/order_dto.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';

void main() {
  final Order order = Order(
    id: 'o-1',
    tableNumber: 7,
    lines: const <OrderLine>[
      OrderLine(
        id: 'r-01',
        productId: 'p-01',
        description: 'Caffè',
        quantity: 2,
        unitPriceCents: 120,
      ),
    ],
    createdAt: DateTime.utc(2026, 7, 27, 12, 30),
  );

  test('andata e ritorno dal dominio al JSON e viceversa', () {
    final Map<String, dynamic> json = OrderDto.fromDomain(order).toJson();
    final Order? back = OrderDto.fromJson(json).toDomain();

    expect(back, isNotNull);
    expect(back!.id, order.id);
    expect(back.tableNumber, order.tableNumber);
    expect(back.lines, order.lines);
    expect(back.createdAt, order.createdAt);
  });

  test('un campo mancante non fa crashare il parsing', () {
    // Il backend omette le righe e il numero del tavolo.
    final Order? back = OrderDto.fromJson(<String, dynamic>{
      'id': 'o-2',
      'createdAt': '2026-07-27T12:00:00.000Z',
    }).toDomain();

    expect(back, isNotNull);
    expect(back!.lines, isEmpty);
    expect(back.tableNumber, 0);
  });

  test('un record inutilizzabile viene scartato invece che propagato', () {
    expect(OrderDto.fromJson(<String, dynamic>{}).toDomain(), isNull);
    expect(
      OrderDto.fromJson(<String, dynamic>{'id': 'o-3', 'createdAt': 'boh'})
          .toDomain(),
      isNull,
    );
  });

  test('il dominio non conosce il formato di trasporto', () {
    // Se un giorno qualcuno aggiungesse toJson al modello di dominio, questo
    // test non basterebbe a impedirlo, ma la sua esistenza documenta l intento.
    expect(order.lines.first, isA<OrderLine>());
    expect(OrderLineDto.fromDomain(order.lines.first).toJson()['productId'],
        'p-01');
  });
}
