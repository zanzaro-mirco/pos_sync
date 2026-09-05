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

import 'helpers/cubit_preimpostato.dart';

void main() {
  Order ordine(int tavolo, {SyncStatus stato = SyncStatus.pending}) => Order(
        id: 'id-$tavolo',
        tableNumber: tavolo,
        createdAt: DateTime(2026, 7, 27, 12),
        status: stato,
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

  group('OrdersPage · i conflitti', () {
    OrderConflict conflitto(String id, {int tavolo = 7}) => OrderConflict(
          id: id,
          mine: ordine(tavolo).copyWith(state: OrderState.pagato),
          theirs: ordine(tavolo),
          reason: 'Il tavolo $tavolo risulta pagato, ma 1 articolo non era '
              'nel conto',
          detectedAt: DateTime(2026, 9, 5, 20),
        );

    OrdersState conConflitti(List<OrderConflict> conflitti) => OrdersState(
          status: OrdersStatus.ready,
          orders: <Order>[ordine(7)],
          conflicts: conflitti,
        );

    testWidgets('senza conflitti non c è nessun avviso',
        (WidgetTester tester) async {
      await mostra(
        tester,
        OrdersState(status: OrdersStatus.ready, orders: <Order>[ordine(7)]),
      );

      expect(find.byKey(const Key('conflict-badge')), findsNothing);
      expect(find.byType(ConflictCard), findsNothing);
    });

    testWidgets('il contatore compare accanto a quello delle pendenze',
        (WidgetTester tester) async {
      await mostra(tester, conConflitti(<OrderConflict>[conflitto('c-1')]));

      expect(find.byKey(const Key('conflict-badge')), findsOneWidget);
    });

    testWidgets('la scheda spiega il problema e mostra le due versioni',
        (WidgetTester tester) async {
      await mostra(tester, conConflitti(<OrderConflict>[conflitto('c-1')]));

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
      await mostra(tester, conConflitti(<OrderConflict>[conflitto('c-1')]));

      final double schedaY = tester.getTopLeft(find.byType(ConflictCard)).dy;
      final double ordineY = tester.getTopLeft(find.byType(OrderTile)).dy;
      expect(schedaY, lessThan(ordineY));
    });

    testWidgets('i due pulsanti arrivano al cubit con la scelta giusta',
        (WidgetTester tester) async {
      final CubitPreimpostato cubit = await mostra(
        tester,
        conConflitti(<OrderConflict>[conflitto('c-1')]),
      );

      await tester.tap(find.byKey(const Key('conflict-mine-c-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('conflict-theirs-c-1')));
      await tester.pump();

      expect(cubit.conflittiRisolti, <(String, ConflictChoice)>[
        ('c-1', ConflictChoice.mine),
        ('c-1', ConflictChoice.theirs),
      ]);
    });

    testWidgets('i pulsanti dicono cosa fanno, non da dove viene la versione',
        (WidgetTester tester) async {
      // «Tieni la mia» costringe chi decide a ricostruire quale sia la propria
      // e cosa comporti; qui la conseguenza è scritta sul pulsante.
      await mostra(tester, conConflitti(<OrderConflict>[conflitto('c-1')]));

      expect(find.text('Tieni il pagamento'), findsOneWidget);
      expect(find.text('Tieni il tavolo aperto'), findsOneWidget);
    });

    testWidgets('un conflitto si vede anche senza ordini in lista',
        (WidgetTester tester) async {
      await mostra(
        tester,
        OrdersState(
          status: OrdersStatus.ready,
          conflicts: <OrderConflict>[conflitto('c-1')],
        ),
      );

      expect(find.byKey(const Key('empty-text')), findsNothing);
      expect(find.byType(ConflictCard), findsOneWidget);
    });
  });
}
