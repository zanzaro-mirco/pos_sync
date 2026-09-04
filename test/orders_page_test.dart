import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';
import 'package:pos_sync/features/orders/presentation/order_tile.dart';
import 'package:pos_sync/features/orders/presentation/orders_cubit.dart';
import 'package:pos_sync/features/orders/presentation/orders_page.dart';
import 'package:pos_sync/features/orders/presentation/orders_state.dart';

import 'helpers/cubit_preimpostato.dart';

void main() {
  Order ordine(int tavolo, {SyncStatus stato = SyncStatus.pending}) => Order(
        id: 'id-$tavolo',
        tableNumber: tavolo,
        createdAt: DateTime(2026, 7, 27, 12),
        status: stato,
        lines: const <OrderLine>[
          OrderLine(
            productId: 'p-01',
            description: 'Caffè',
            quantity: 2,
            unitPriceCents: 120,
          ),
        ],
      );

  /// Monta la pagina sullo stato dato e restituisce il cubit, per poterci
  /// asserire sopra dopo aver toccato l'interfaccia.
  Future<CubitPreimpostato> mostra(
    WidgetTester tester,
    OrdersState stato, {
    void Function(int tableNumber)? onAddOrder,
  }) async {
    final CubitPreimpostato cubit = CubitPreimpostato(stato);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: BlocProvider<OrdersCubit>.value(
          value: cubit,
          // Il valore predefinito non fa niente: i test che non riguardano la
          // creazione non devono decidere cosa succede quando si crea.
          child: OrdersPage(onAddOrder: onAddOrder ?? (int _) {}),
        ),
      ),
    );
    return cubit;
  }

  group('OrdersPage · i tre stati', () {
    testWidgets('in caricamento mostra l indicatore e nessuna lista',
        (WidgetTester tester) async {
      await mostra(tester, const OrdersState());

      expect(find.byKey(const Key('loading-indicator')), findsOneWidget);
      expect(find.byType(OrderTile), findsNothing);
      expect(find.byKey(const Key('empty-text')), findsNothing);
    });

    testWidgets('senza ordini dice che non ce ne sono',
        (WidgetTester tester) async {
      await mostra(tester, const OrdersState(status: OrdersStatus.ready));

      expect(find.byKey(const Key('empty-text')), findsOneWidget);
      expect(find.text('Nessun ordine'), findsOneWidget);
      expect(find.byType(OrderTile), findsNothing);
      // Il pulsante di creazione resta: è l'unica via d'uscita dallo stato
      // vuoto, nasconderlo lo renderebbe un vicolo cieco.
      expect(find.byKey(const Key('add-order')), findsOneWidget);
    });

    testWidgets('con ordini li elenca con totale e numero di articoli',
        (WidgetTester tester) async {
      await mostra(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[ordine(1), ordine(2), ordine(3)],
        ),
      );

      expect(find.byType(OrderTile), findsNWidgets(3));
      expect(find.text('Tavolo 2'), findsOneWidget);
      expect(find.text('2 articoli'), findsNWidgets(3));
      expect(find.text('2.40 €'), findsNWidgets(3));
      expect(find.byKey(const Key('empty-text')), findsNothing);
    });

    testWidgets('in errore mostra il messaggio, non una lista vuota',
        (WidgetTester tester) async {
      await mostra(
        tester,
        const OrdersState(
          status: OrdersStatus.error,
          message: 'Database non leggibile',
        ),
      );

      expect(find.byKey(const Key('error-text')), findsOneWidget);
      expect(find.text('Database non leggibile'), findsOneWidget);
      // La distinzione che conta: "non ci sono ordini" e "non riesco a
      // leggerli" sono due cose diverse, e confonderle nasconde il guasto.
      expect(find.byKey(const Key('empty-text')), findsNothing);
    });

    testWidgets('in errore senza messaggio non lascia la schermata muta',
        (WidgetTester tester) async {
      await mostra(tester, const OrdersState(status: OrdersStatus.error));

      expect(find.text('Errore'), findsOneWidget);
    });
  });

  group('OrdersPage · la barra superiore', () {
    testWidgets('il contatore appare solo se c è qualcosa da inviare',
        (WidgetTester tester) async {
      await mostra(tester, const OrdersState(status: OrdersStatus.ready));
      expect(find.byKey(const Key('pending-badge')), findsNothing);

      await mostra(
        tester,
        const OrdersState(status: OrdersStatus.ready, pending: 3),
      );
      expect(find.byKey(const Key('pending-badge')), findsOneWidget);
      expect(find.text('3 da inviare'), findsOneWidget);
    });

    testWidgets('il pulsante di sincronizzazione arriva al cubit',
        (WidgetTester tester) async {
      final CubitPreimpostato cubit =
          await mostra(tester, const OrdersState(status: OrdersStatus.ready));

      await tester.tap(find.byKey(const Key('sync-button')));
      await tester.pump();

      expect(cubit.sincronizzazioni, 1);
    });

    testWidgets('il pulsante di creazione propone il tavolo successivo',
        (WidgetTester tester) async {
      final List<int> richiesti = <int>[];
      await mostra(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[ordine(1), ordine(2)],
        ),
        onAddOrder: richiesti.add,
      );

      await tester.tap(find.byKey(const Key('add-order')));
      await tester.pump();

      expect(richiesti, <int>[3]);
    });
  });

  group('OrdersPage · gli stati di sincronizzazione', () {
    testWidgets('ogni ordine mostra l icona del proprio stato',
        (WidgetTester tester) async {
      await mostra(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[
            ordine(1),
            ordine(2, stato: SyncStatus.sending),
            ordine(3, stato: SyncStatus.synced),
            ordine(4, stato: SyncStatus.failed),
          ],
        ),
      );

      for (final SyncStatus stato in SyncStatus.values) {
        expect(
          find.byKey(Key('status-${stato.name}')),
          findsOneWidget,
          reason: 'manca l indicatore per ${stato.name}',
        );
      }
    });

    testWidgets('ogni stato ha un etichetta per il lettore di schermo',
        (WidgetTester tester) async {
      // L'albero semantico non viene costruito nei test se nessuno lo chiede.
      // Va rilasciato dentro il corpo del test: i tearDown girano dopo il
      // controllo che verifica che non ne sia rimasto nessuno attivo.
      final SemanticsHandle handle = tester.ensureSemantics();

      await mostra(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[
            ordine(1),
            ordine(2, stato: SyncStatus.sending),
            ordine(3, stato: SyncStatus.synced),
            ordine(4, stato: SyncStatus.failed),
          ],
        ),
      );

      // Il colore non è l'unico portatore dell'informazione: chi non lo
      // percepisce deve poter comunque sapere in che stato è un ordine.
      //
      // Il confronto è su una parte dell'etichetta perché `ListTile` fonde i
      // nodi dei suoi figli: il lettore annuncia la riga intera — "Da
      // inviare, Tavolo 1, 2 articoli, 2.40 €" — ed è il comportamento
      // giusto, quattro nodi separati per riga sarebbero più lenti da
      // navigare, non più chiari.
      for (final String etichetta in <String>[
        'Da inviare',
        'Invio in corso',
        'Sincronizzato',
        'Invio fallito',
      ]) {
        expect(
          find.bySemanticsLabel(RegExp(etichetta)),
          findsOneWidget,
          reason: 'nessuna riga annuncia "$etichetta"',
        );
      }

      handle.dispose();
    });
  });
}
