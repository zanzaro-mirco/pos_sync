import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';
import 'package:pos_sync/features/orders/presentation/order_tile.dart';

/// Golden test sulla riga dell'ordine, uno per stato di sincronizzazione.
///
/// È l'unico test della suite che verifica *l'aspetto* invece del
/// comportamento, ed è il motivo per cui esiste: un test che cerca
/// `find.byIcon(Icons.cloud_done)` passa anche se quell'icona è diventata
/// invisibile, o grigia, o larga il doppio. Il golden no.
///
/// Il soggetto è la riga, non la schermata: un golden sull'intera pagina
/// cambierebbe a ogni ritocco della barra superiore, e un test che fallisce
/// per motivi che non interessano smette presto di essere letto.
///
/// **Le immagini di riferimento dipendono dalla versione di Flutter.** Il
/// motore porta con sé il proprio stack di font e di disegno, quindi la stessa
/// versione produce gli stessi pixel su sistemi diversi — ma una versione
/// diversa no. Per questo la pipeline fissa la versione invece di seguire il
/// canale stabile: senza, i golden fallirebbero da soli il giorno di un
/// aggiornamento, che è il modo più rapido per far disattivare un test.
void main() {
  Order ordine(SyncStatus stato) => Order(
        id: 'id-1',
        tableNumber: 12,
        createdAt: DateTime(2026, 7, 27, 12),
        status: stato,
        lines: const <OrderLine>[
          OrderLine(
            productId: 'p-01',
            description: 'Caffè',
            quantity: 2,
            unitPriceCents: 120,
          ),
          OrderLine(
            productId: 'p-02',
            description: 'Cornetto',
            quantity: 1,
            unitPriceCents: 150,
          ),
        ],
      );

  Widget cornice(Order order) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: Scaffold(
          body: Center(
            // Il RepaintBoundary non è decorativo: `matchesGoldenFile` non
            // ritaglia il widget che gli si indica, risale al primo confine di
            // ridisegno sopra di esso. Senza, l'immagine sarebbe l'intera
            // finestra con la riga persa in mezzo — e cambierebbe a ogni
            // ritocco dello sfondo.
            child: RepaintBoundary(
              // Larghezza fissa: la riga si adatta allo spazio, e un golden
              // preso a larghezza variabile cambierebbe con la finestra di chi
              // lo esegue.
              child: SizedBox(width: 360, child: OrderTile(order: order)),
            ),
          ),
        ),
      );

  for (final SyncStatus stato in SyncStatus.values) {
    testWidgets('la riga nello stato ${stato.name}',
        (WidgetTester tester) async {
      // Un pixel logico per pixel dell'immagine, e una finestra della misura
      // del soggetto: i riferimenti restano piccoli e leggibili in una
      // revisione invece di essere ritagli da 3x dentro una pagina vuota.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 200);
      addTearDown(tester.view.reset);

      // Niente pumpAndSettle: nello stato `sending` c'è un indicatore che gira
      // all'infinito e non si assesterebbe mai. Il primo fotogramma è comunque
      // deterministico, perché nei test l'orologio delle animazioni parte da
      // zero.
      await tester.pumpWidget(cornice(ordine(stato)));

      await expectLater(
        find.byType(OrderTile),
        matchesGoldenFile('goldens/order_tile_${stato.name}.png'),
      );
    });
  }
}
