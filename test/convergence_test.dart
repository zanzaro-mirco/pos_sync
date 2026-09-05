/// Il criterio della voce 2.4: due dispositivi che modificano lo stesso tavolo
/// in ordine invertito convergono allo stesso stato finale.
///
/// Il criterio chiede **convergenza**, non "il conflitto viene gestito", ed è
/// la differenza che conta: o l'ordine di arrivo smette di contare, o il test
/// fallisce. Non lo si soddisfa con un `if`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/features/orders/data/remote_api.dart';
import 'package:pos_sync/features/orders/domain/order.dart';
import 'package:pos_sync/features/orders/domain/order_conflict.dart';
import 'package:pos_sync/features/orders/domain/order_line.dart';
import 'package:pos_sync/features/orders/domain/order_line_draft.dart';
import 'package:pos_sync/features/orders/domain/order_state.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';

import 'helpers/fixtures.dart';

const OrderLineDraft caffe = OrderLineDraft(
  productId: 'p-01',
  description: 'Caffè',
  quantity: 2,
  unitPriceCents: 120,
);

const OrderLineDraft cornetto = OrderLineDraft(
  productId: 'p-02',
  description: 'Cornetto',
  quantity: 1,
  unitPriceCents: 150,
);

/// Ciò che i due dispositivi devono avere identico.
///
/// `status` è escluso di proposito: dice se *questo* dispositivo è riuscito a
/// mandare l'ordine, ed è giusto che i due non siano d'accordo. Confrontare
/// l'ordine intero significherebbe pretendere che un fatto locale sia
/// condiviso, cioè misurare la cosa sbagliata.
///
/// Le righe sono una stringa e non una lista perché i record confrontano i
/// campi con `==`, e per una `List` `==` è l'identità: due liste con lo stesso
/// contenuto risulterebbero diverse e il test fallirebbe mostrando due valori
/// identici.
typedef StatoCondiviso = ({
  int tavolo,
  OrderState stato,
  Revision revisione,
  String righe,
  int totale,
});

/// Ciò che vedrebbe una persona guardando il tablet.
///
/// Serve a confrontare *storie diverse* fra loro. Il contatore logico e gli
/// identificativi delle righe dipendono da quante operazioni quel dispositivo
/// ha fatto prima: un cameriere che serve prima di aggiungere arriva allo
/// stesso tavolo con numeri diversi da uno che fa il contrario. Preterderli
/// uguali significherebbe pretendere che due storie diverse siano la stessa
/// storia, non che portino allo stesso risultato.
typedef StatoVisibile = ({
  int tavolo,
  OrderState stato,
  String piatti,
  int totale,
});

StatoVisibile visibile(Order o) => (
      tavolo: o.tableNumber,
      stato: o.state,
      piatti: (o.lines
              .map((OrderLine l) => '${l.description} x${l.quantity}')
              .toList()
            ..sort())
          .join(', '),
      totale: o.totalCents,
    );

StatoCondiviso condiviso(Order o) => (
      tavolo: o.tableNumber,
      stato: o.state,
      revisione: o.stateRevision,
      righe:
          o.lines.map((OrderLine l) => '${l.id}:${l.description}').join(', '),
      totale: o.totalCents,
    );

/// Due tablet nello stesso locale, con un ordine già condiviso fra i due.
class Sala {
  Sala._(this.a, this.b, this.ordineId);

  static Future<Sala> aperta() async {
    final FakeServer server = FakeServer();
    final TestEnv a =
        TestEnv(server: server, deviceId: 'tablet-a', idPrefix: 'a');
    final TestEnv b =
        TestEnv(server: server, deviceId: 'tablet-b', idPrefix: 'b');

    final Order ordine = await a.repository
        .createOrder(tableNumber: 7, lines: <OrderLineDraft>[caffe]);
    await a.worker.drain();
    await b.worker.drain(); // b lo riceve dal server

    return Sala._(a, b, ordine.id);
  }

  final TestEnv a;
  final TestEnv b;
  final String ordineId;

  /// Fa girare la sincronizzazione finché non cambia più niente.
  ///
  /// Non è un artificio del test: è quello che fanno i dispositivi veri, che
  /// sincronizzano a ogni ritorno della rete e ogni quarto d'ora. Il numero di
  /// giri è un limite superiore — se servissero più di così, il sistema non
  /// convergerebbe e il test lo direbbe.
  Future<void> stabilizza({int giri = 3}) async {
    for (int i = 0; i < giri; i++) {
      // L'orologio avanza fra un giro e l'altro: una voce che ha già fallito
      // porta un `nextAttemptAt` nel futuro, e con un orologio fermo resterebbe
      // in coda per sempre. Non è un dettaglio del test — è il backoff che
      // funziona, e senza questo avanzamento si starebbe verificando la
      // convergenza di un dispositivo che non riprova mai.
      a.clock.advance(const Duration(minutes: 5));
      b.clock.advance(const Duration(minutes: 5));
      await a.worker.drain();
      await b.worker.drain();
    }
  }

  Future<Order> ordineDi(TestEnv env) async =>
      (await env.store.orderById(ordineId))!;

  Future<void> chiudi() async {
    await a.dispose();
    await b.dispose();
  }
}

void main() {
  group('Il criterio', () {
    test('due dispositivi, ordine invertito, stesso stato finale', () async {
      // Andata: prima aggiunge A, poi serve B.
      final Sala andata = await Sala.aperta();
      await andata.a.repository.addLines(
          orderId: andata.ordineId, lines: <OrderLineDraft>[cornetto]);
      await andata.a.worker.drain();
      await andata.b.repository
          .changeState(orderId: andata.ordineId, state: OrderState.servito);
      await andata.b.worker.drain();
      await andata.stabilizza();

      // Ritorno: le stesse due modifiche, nell'ordine opposto.
      final Sala ritorno = await Sala.aperta();
      await ritorno.b.repository
          .changeState(orderId: ritorno.ordineId, state: OrderState.servito);
      await ritorno.b.worker.drain();
      await ritorno.a.repository.addLines(
          orderId: ritorno.ordineId, lines: <OrderLineDraft>[cornetto]);
      await ritorno.a.worker.drain();
      await ritorno.stabilizza();

      // I due dispositivi della stessa sala sono d'accordo fra loro...
      expect(
        condiviso(await andata.ordineDi(andata.a)),
        condiviso(await andata.ordineDi(andata.b)),
        reason: 'i due tablet della prima sala non convergono',
      );
      expect(
        condiviso(await ritorno.ordineDi(ritorno.a)),
        condiviso(await ritorno.ordineDi(ritorno.b)),
        reason: 'i due tablet della seconda sala non convergono',
      );

      // ...e le due sale sono arrivate allo stesso posto, pur avendo visto le
      // stesse modifiche in ordine opposto.
      expect(
        condiviso(await andata.ordineDi(andata.a)),
        condiviso(await ritorno.ordineDi(ritorno.a)),
        reason: "l'ordine delle modifiche ha cambiato il risultato",
      );

      final Order finale = await andata.ordineDi(andata.a);
      expect(finale.state, OrderState.servito);
      expect(finale.lines.length, 2, reason: 'nessuna riga si perde');
      expect(finale.totalCents, 240 + 150);

      await andata.chiudi();
      await ritorno.chiudi();
    });

    test('tre modifiche, tutte e sei le sequenze, un solo risultato', () async {
      // La convergenza è una proprietà, non un caso fortunato: qui si prova su
      // ogni ordine possibile invece che su quello che è venuto in mente.
      final List<StatoVisibile> esiti = <StatoVisibile>[];

      for (final List<int> sequenza in <List<int>>[
        <int>[0, 1, 2],
        <int>[0, 2, 1],
        <int>[1, 0, 2],
        <int>[1, 2, 0],
        <int>[2, 0, 1],
        <int>[2, 1, 0],
      ]) {
        final Sala sala = await Sala.aperta();

        for (final int mossa in sequenza) {
          switch (mossa) {
            case 0:
              await sala.a.repository.addLines(
                  orderId: sala.ordineId, lines: <OrderLineDraft>[cornetto]);
              await sala.a.worker.drain();
            case 1:
              await sala.b.repository.addLines(
                  orderId: sala.ordineId, lines: <OrderLineDraft>[caffe]);
              await sala.b.worker.drain();
            case 2:
              await sala.b.repository.changeState(
                  orderId: sala.ordineId, state: OrderState.servito);
              await sala.b.worker.drain();
          }
        }
        await sala.stabilizza();

        expect(
          condiviso(await sala.ordineDi(sala.a)),
          condiviso(await sala.ordineDi(sala.b)),
          reason: 'sequenza $sequenza: i due dispositivi non convergono',
        );
        esiti.add(visibile(await sala.ordineDi(sala.a)));
        await sala.chiudi();
      }

      for (final StatoVisibile esito in esiti) {
        expect(esito, esiti.first,
            reason: 'sequenze diverse hanno prodotto tavoli diversi');
      }
      expect(esiti.first.piatti.split(', '), hasLength(3));
    });
  });

  group('Il tempo logico', () {
    test('chi modifica dopo aver visto la modifica altrui la batte', () async {
      // La convergenza da sola non basta a dire che il sistema è corretto: due
      // dispositivi possono essere perfettamente d'accordo sulla risposta
      // sbagliata. Questa è la proprietà che tiene in piedi il `witness`.
      //
      // Il tablet A lavora molto e il suo contatore sale; B non ha ancora
      // fatto niente. Quando B vede il tavolo servito e decide di incassare,
      // la sua decisione è la più recente e deve vincere — anche se il suo
      // contatore, contato per conto proprio, sarebbe più basso di quello di A.
      final Sala sala = await Sala.aperta();

      for (int i = 0; i < 4; i++) {
        await sala.a.repository.addLines(
            orderId: sala.ordineId, lines: <OrderLineDraft>[cornetto]);
      }
      await sala.a.repository
          .changeState(orderId: sala.ordineId, state: OrderState.servito);
      await sala.a.worker.drain();

      await sala.b.worker.drain(); // qui B prende atto del tempo di A
      await sala.b.repository
          .changeState(orderId: sala.ordineId, state: OrderState.pagato);
      await sala.b.worker.drain();
      await sala.stabilizza();

      expect((await sala.ordineDi(sala.b)).state, OrderState.pagato);
      expect(
        (await sala.ordineDi(sala.a)).state,
        OrderState.pagato,
        reason: "l'ultima decisione presa è stata scartata: senza `witness` il "
            'contatore di B nasce più basso di quello di A e perde',
      );

      await sala.chiudi();
    });
  });

  group('Quando invece serve una persona', () {
    test('pagare mentre l altro aggiunge apre un conflitto su entrambi',
        () async {
      final Sala sala = await Sala.aperta();

      // La cassa incassa senza sapere che in sala stanno ancora ordinando.
      await sala.a.repository
          .changeState(orderId: sala.ordineId, state: OrderState.pagato);
      await sala.b.repository
          .addLines(orderId: sala.ordineId, lines: <OrderLineDraft>[cornetto]);

      await sala.a.worker.drain();
      await sala.b.worker.drain();
      await sala.a.worker.drain();

      final List<OrderConflict> suA = await sala.a.store.openConflicts();
      final List<OrderConflict> suB = await sala.b.store.openConflicts();

      expect(suA, hasLength(1),
          reason: 'la cassa deve sapere di quel cornetto');
      expect(suB, hasLength(1), reason: 'anche la sala deve saperlo');
      expect(suA.single.reason, contains('pagato'));
      expect(suA.single.reason, contains('1 articolo'));

      await sala.chiudi();
    });

    test('la decisione di uno chiude il conflitto anche sull altro', () async {
      final Sala sala = await Sala.aperta();
      await sala.a.repository
          .changeState(orderId: sala.ordineId, state: OrderState.pagato);
      await sala.b.repository
          .addLines(orderId: sala.ordineId, lines: <OrderLineDraft>[cornetto]);
      await sala.a.worker.drain();
      await sala.b.worker.drain();
      await sala.a.worker.drain();

      // In sala si decide: il tavolo si riapre, il cornetto va incassato.
      // `mine` è la versione di *questo* dispositivo, cioè quella della sala,
      // dove il tavolo è ancora aperto.
      final OrderConflict conflitto =
          (await sala.b.store.openConflicts()).single;
      await sala.b.repository
          .resolveConflict(conflitto.id, ConflictChoice.mine);
      await sala.stabilizza();

      expect(await sala.b.store.openConflicts(), isEmpty);
      expect(await sala.a.store.openConflicts(), isEmpty,
          reason: 'nessuno deve decidere due volte la stessa cosa');

      final Order suA = await sala.ordineDi(sala.a);
      expect(condiviso(suA), condiviso(await sala.ordineDi(sala.b)));
      expect(suA.state, OrderState.aperto);
      expect(suA.lines.length, 2,
          reason: 'il cornetto resta, comunque si scelga');

      await sala.chiudi();
    });

    test('tenere il pagamento non fa sparire le righe arrivate dopo', () async {
      // È la ragione per cui è sicuro chiedere: nessuna delle due risposte
      // cancella una comanda.
      final Sala sala = await Sala.aperta();
      await sala.a.repository
          .changeState(orderId: sala.ordineId, state: OrderState.pagato);
      await sala.b.repository
          .addLines(orderId: sala.ordineId, lines: <OrderLineDraft>[cornetto]);
      await sala.a.worker.drain();
      await sala.b.worker.drain();
      await sala.a.worker.drain();

      final OrderConflict conflitto =
          (await sala.a.store.openConflicts()).single;
      await sala.a.repository
          .resolveConflict(conflitto.id, ConflictChoice.mine);
      await sala.stabilizza();

      final Order suA = await sala.ordineDi(sala.a);
      expect(suA.state, OrderState.pagato);
      expect(suA.lines.length, 2);
      expect(condiviso(suA), condiviso(await sala.ordineDi(sala.b)));

      await sala.chiudi();
    });
  });

  group('Offline', () {
    test('un dispositivo scollegato non blocca l altro, e rientra dopo',
        () async {
      final Sala sala = await Sala.aperta();
      sala.b.api.online = false;

      await sala.a.repository
          .addLines(orderId: sala.ordineId, lines: <OrderLineDraft>[cornetto]);
      await sala.a.worker.drain();
      await sala.b.repository
          .changeState(orderId: sala.ordineId, state: OrderState.servito);
      await sala.b.worker.drain(); // non esce niente

      expect((await sala.ordineDi(sala.b)).lines.length, 1,
          reason: 'offline non si vede il cornetto');

      sala.b.api.online = true;
      await sala.stabilizza();

      expect(
        condiviso(await sala.ordineDi(sala.a)),
        condiviso(await sala.ordineDi(sala.b)),
      );
      expect((await sala.ordineDi(sala.b)).lines.length, 2);

      await sala.chiudi();
    });
  });
}
