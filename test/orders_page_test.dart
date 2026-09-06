import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_conflict.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/presentation/conflict_card.dart';
import 'package:pos_sync/features/orders/domain/sync_status.dart';
import 'package:pos_sync/features/orders/presentation/order_tile.dart';
import 'package:pos_sync/features/orders/presentation/orders_cubit.dart';
import 'package:pos_sync/features/orders/presentation/orders_page.dart';
import 'package:pos_sync/features/orders/presentation/orders_state.dart';

import 'helpers/preset_cubit.dart';

void main() {
  Order order(
    int table, {
    SyncStatus state = SyncStatus.pending,
    OrderState tableState = OrderState.open,
  }) =>
      Order(
        id: 'id-$table',
        tableNumber: table,
        createdAt: DateTime(2026, 7, 27, 12),
        status: state,
        state: tableState,
        lines: const <OrderLine>[
          OrderLine(
            id: 'r-01',
            productId: 'p-01',
            description: 'Caffè',
            quantity: 2,
            unitPriceCents: 120,
          ),
        ],
      );

  /// Monta la pagina sullo stato dato e restituisce il cubit, per poterci
  /// asserire sopra dopo aver toccato l'interfaccia.
  Future<PresetCubit> show(
    WidgetTester tester,
    OrdersState state, {
    void Function(int tableNumber)? onAddOrder,
    void Function(Order order)? onAddLine,
    void Function(Order order)? onOtherDevicePays,
  }) async {
    final PresetCubit cubit = PresetCubit(state);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: BlocProvider<OrdersCubit>.value(
          value: cubit,
          // Il valore predefinito non fa niente: i test che non riguardano la
          // creazione non devono decidere cosa succede quando si crea.
          child: OrdersPage(
            onAddOrder: onAddOrder ?? (int _) {},
            onAddLine: onAddLine ?? (Order _) {},
            onOtherDevicePays: onOtherDevicePays,
          ),
        ),
      ),
    );
    return cubit;
  }

  group('OrdersPage · i tre stati', () {
    testWidgets('in caricamento mostra l indicatore e nessuna lista',
        (WidgetTester tester) async {
      await show(tester, const OrdersState());

      expect(find.byKey(const Key('loading-indicator')), findsOneWidget);
      expect(find.byType(OrderTile), findsNothing);
      expect(find.byKey(const Key('empty-text')), findsNothing);
    });

    testWidgets('senza ordini dice che non ce ne sono',
        (WidgetTester tester) async {
      await show(tester, const OrdersState(status: OrdersStatus.ready));

      expect(find.byKey(const Key('empty-text')), findsOneWidget);
      expect(find.text('Nessun ordine'), findsOneWidget);
      expect(find.byType(OrderTile), findsNothing);
      // Il pulsante di creazione resta: è l'unica via d'uscita dallo stato
      // vuoto, nasconderlo lo renderebbe un vicolo cieco.
      expect(find.byKey(const Key('add-order')), findsOneWidget);
    });

    testWidgets('con ordini li elenca con totale e numero di articoli',
        (WidgetTester tester) async {
      await show(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[order(1), order(2), order(3)],
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
      await show(
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
      await show(tester, const OrdersState(status: OrdersStatus.error));

      expect(find.text('Errore'), findsOneWidget);
    });
  });

  group('OrdersPage · la barra superiore', () {
    testWidgets('il contatore appare solo se c è qualcosa da inviare',
        (WidgetTester tester) async {
      await show(tester, const OrdersState(status: OrdersStatus.ready));
      expect(find.byKey(const Key('pending-badge')), findsNothing);

      await show(
        tester,
        const OrdersState(status: OrdersStatus.ready, pending: 3),
      );
      expect(find.byKey(const Key('pending-badge')), findsOneWidget);
      expect(find.text('3 da inviare'), findsOneWidget);
    });

    testWidgets('il pulsante di sincronizzazione arriva al cubit',
        (WidgetTester tester) async {
      final PresetCubit cubit =
          await show(tester, const OrdersState(status: OrdersStatus.ready));

      await tester.tap(find.byKey(const Key('sync-button')));
      await tester.pump();

      expect(cubit.syncs, 1);
    });

    testWidgets('il pulsante di creazione propone il tavolo successivo',
        (WidgetTester tester) async {
      final List<int> requested = <int>[];
      await show(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[order(1), order(2)],
        ),
        onAddOrder: requested.add,
      );

      await tester.tap(find.byKey(const Key('add-order')));
      await tester.pump();

      expect(requested, <int>[3]);
    });
  });

  group('OrdersPage · gli stati di sincronizzazione', () {
    testWidgets('ogni ordine mostra l icona del proprio stato',
        (WidgetTester tester) async {
      await show(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[
            order(1),
            order(2, state: SyncStatus.sending),
            order(3, state: SyncStatus.synced),
            order(4, state: SyncStatus.failed),
          ],
        ),
      );

      for (final SyncStatus state in SyncStatus.values) {
        expect(
          find.byKey(Key('status-${state.name}')),
          findsOneWidget,
          reason: 'manca l indicatore per ${state.name}',
        );
      }
    });

    testWidgets('ogni stato ha un etichetta per il lettore di schermo',
        (WidgetTester tester) async {
      // L'albero semantico non viene costruito nei test se nessuno lo chiede.
      // Va rilasciato dentro il corpo del test: i tearDown girano dopo il
      // controllo che verifica che non ne sia rimasto nessuno attivo.
      final SemanticsHandle handle = tester.ensureSemantics();

      await show(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[
            order(1),
            order(2, state: SyncStatus.sending),
            order(3, state: SyncStatus.synced),
            order(4, state: SyncStatus.failed),
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
      for (final String label in <String>[
        'Da inviare',
        'Invio in corso',
        'Sincronizzato',
        'Invio fallito',
      ]) {
        expect(
          find.bySemanticsLabel(RegExp(label)),
          findsOneWidget,
          reason: 'nessuna riga annuncia "$label"',
        );
      }

      handle.dispose();
    });
  });

  group('OrdersPage · i conflitti', () {
    OrderConflict conflict(String id, {int table = 7}) => OrderConflict(
          id: id,
          mine: order(table).copyWith(state: OrderState.paid),
          theirs: order(table),
          reason: 'Il tavolo $table risulta pagato, ma 1 articolo non era '
              'nel conto',
          detectedAt: DateTime(2026, 9, 5, 20),
        );

    OrdersState withConflicts(List<OrderConflict> conflicts) => OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[order(7)],
          conflicts: conflicts,
        );

    testWidgets('senza conflitti non c è nessun avviso',
        (WidgetTester tester) async {
      await show(
        tester,
        OrdersState(status: OrdersStatus.ready, orders: <Order>[order(7)]),
      );

      expect(find.byKey(const Key('conflict-badge')), findsNothing);
      expect(find.byType(ConflictCard), findsNothing);
    });

    testWidgets('il contatore compare accanto a quello delle pendenze',
        (WidgetTester tester) async {
      await show(tester, withConflicts(<OrderConflict>[conflict('c-1')]));

      expect(find.byKey(const Key('conflict-badge')), findsOneWidget);
    });

    testWidgets('la scheda spiega il problema e mostra le due versioni',
        (WidgetTester tester) async {
      await show(tester, withConflicts(<OrderConflict>[conflict('c-1')]));

      expect(find.byKey(const Key('conflict-c-1')), findsOneWidget);
      expect(
        find.textContaining('non era nel conto'),
        findsOneWidget,
        reason: "chi decide deve sapere perché gli si sta chiedendo",
      );
      expect(find.textContaining('Qui: pagato'), findsOneWidget);
      expect(find.textContaining("Sull'altro dispositivo: aperto"),
          findsOneWidget);
    });

    testWidgets('i conflitti stanno sopra gli ordini',
        (WidgetTester tester) async {
      // In fondo alla lista non li vedrebbe nessuno, ed è l'unica cosa in
      // questa schermata che chiede di fare qualcosa.
      await show(tester, withConflicts(<OrderConflict>[conflict('c-1')]));

      final double cardY = tester.getTopLeft(find.byType(ConflictCard)).dy;
      final double tileY = tester.getTopLeft(find.byType(OrderTile)).dy;
      expect(cardY, lessThan(tileY));
    });

    testWidgets('i due pulsanti arrivano al cubit con la scelta giusta',
        (WidgetTester tester) async {
      final PresetCubit cubit = await show(
        tester,
        withConflicts(<OrderConflict>[conflict('c-1')]),
      );

      await tester.tap(find.byKey(const Key('conflict-mine-c-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('conflict-theirs-c-1')));
      await tester.pump();

      expect(cubit.resolvedConflicts, <(String, ConflictChoice)>[
        ('c-1', ConflictChoice.mine),
        ('c-1', ConflictChoice.theirs),
      ]);
    });

    testWidgets('i pulsanti dicono cosa fanno, non da dove viene la versione',
        (WidgetTester tester) async {
      // «Tieni la mia» costringe chi decide a ricostruire quale sia la propria
      // e cosa comporti; qui la conseguenza è scritta sul pulsante.
      await show(tester, withConflicts(<OrderConflict>[conflict('c-1')]));

      expect(find.text('Tieni il pagamento'), findsOneWidget);
      expect(find.text('Tieni il tavolo aperto'), findsOneWidget);
    });

    testWidgets('un conflitto si vede anche senza ordini in lista',
        (WidgetTester tester) async {
      await show(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          conflicts: <OrderConflict>[conflict('c-1')],
        ),
      );

      expect(find.byKey(const Key('empty-text')), findsNothing);
      expect(find.byType(ConflictCard), findsOneWidget);
    });
  });

  group('OrdersPage · le azioni su un tavolo', () {
    OrdersState withTable(OrderState state) => OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[order(7, tableState: state)],
        );

    Future<PresetCubit> openSheet(
      WidgetTester tester,
      OrdersState state, {
      void Function(Order order)? onAddLine,
      void Function(Order order)? onOtherDevicePays,
    }) async {
      final PresetCubit cubit = await show(
        tester,
        state,
        onAddLine: onAddLine,
        onOtherDevicePays: onOtherDevicePays,
      );
      await tester.tap(find.byType(OrderTile));
      await tester.pumpAndSettle();
      return cubit;
    }

    testWidgets('lo stato del tavolo si legge solo quando non è aperto',
        (WidgetTester tester) async {
      // `open` è la normalità: scriverlo su ogni riga riempirebbe la lista
      // di una parola che non distingue niente.
      await show(tester, withTable(OrderState.open));
      expect(find.text('2 articoli'), findsOneWidget);

      await show(tester, withTable(OrderState.paid));
      expect(find.text('2 articoli · pagato'), findsOneWidget);
    });

    testWidgets('toccare la riga apre le azioni sul tavolo',
        (WidgetTester tester) async {
      await openSheet(tester, withTable(OrderState.open));

      expect(find.byKey(const Key('action-served')), findsOneWidget);
      expect(find.byKey(const Key('action-paid')), findsOneWidget);
      expect(find.byKey(const Key('action-add-line')), findsOneWidget);
    });

    testWidgets('lo stato in cui il tavolo già si trova non viene proposto',
        (WidgetTester tester) async {
      // Una voce che non farebbe niente occupa spazio e va letta per
      // scoprirlo.
      await openSheet(tester, withTable(OrderState.paid));

      expect(find.byKey(const Key('action-paid')), findsNothing);
      expect(find.byKey(const Key('action-open')), findsOneWidget);
      expect(find.text('Riapri il tavolo'), findsOneWidget);
    });

    testWidgets('le voci dicono cosa succede, non quale campo cambia',
        (WidgetTester tester) async {
      await openSheet(tester, withTable(OrderState.open));

      expect(find.text('Segna servito'), findsOneWidget);
      expect(find.text('Segna pagato'), findsOneWidget);
    });

    testWidgets('cambiare stato arriva al cubit e chiude il foglio',
        (WidgetTester tester) async {
      final PresetCubit cubit =
          await openSheet(tester, withTable(OrderState.open));

      await tester.tap(find.byKey(const Key('action-paid')));
      await tester.pumpAndSettle();

      expect(cubit.changedStates,
          <(String, OrderState)>[('id-7', OrderState.paid)]);
      expect(find.byKey(const Key('action-paid')), findsNothing,
          reason: 'il foglio deve chiudersi dopo la scelta');
    });

    testWidgets('la comanda arriva a chi la sa comporre, non al cubit',
        (WidgetTester tester) async {
      // La pagina offre l'azione ma non decide cosa ci sia dentro una
      // comanda, esattamente come per la creazione di un ordine.
      final List<String> requests = <String>[];
      await openSheet(
        tester,
        withTable(OrderState.open),
        onAddLine: (Order o) => requests.add(o.id),
      );

      await tester.tap(find.byKey(const Key('action-add-line')));
      await tester.pumpAndSettle();

      expect(requests, <String>['id-7']);
    });

    testWidgets('senza secondo dispositivo la voce dimostrativa non c\'è',
        (WidgetTester tester) async {
      // Una build collegata a un backend vero passa `null` e la voce sparisce,
      // senza che la pagina debba sapere il perché.
      await openSheet(tester, withTable(OrderState.open));

      expect(find.byKey(const Key('action-other-device')), findsNothing);
    });

    testWidgets('con il secondo dispositivo la voce c\'è e avverte del seguito',
        (WidgetTester tester) async {
      final List<String> paidTables = <String>[];
      await openSheet(
        tester,
        withTable(OrderState.open),
        onOtherDevicePays: (Order o) => paidTables.add(o.id),
      );

      expect(find.byKey(const Key('action-other-device')), findsOneWidget);
      await tester.tap(find.byKey(const Key('action-other-device')));
      await tester.pumpAndSettle();

      expect(paidTables, <String>['id-7']);
      // Da sola l'azione non mostra niente: il conflitto nasce alla comanda
      // successiva, e chi sta dimostrando deve sapere che manca un passo.
      expect(find.textContaining('Aggiungi una comanda'), findsOneWidget);
    });
  });
}
