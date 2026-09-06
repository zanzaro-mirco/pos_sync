import 'package:flutter_test/flutter_test.dart';
import 'package:pos_sync/core/logical_clock.dart';
import 'package:pos_sync/features/orders/domain/revision.dart';

Revision rev(int counter, String device) =>
    Revision(counter: counter, deviceId: device);

void main() {
  group('Revision · ordine totale', () {
    test('vince il contatore più alto', () {
      expect(rev(2, 'a') > rev(1, 'z'), isTrue);
      expect(rev(1, 'z') < rev(2, 'a'), isTrue);
    });

    test('a parità di contatore decide il dispositivo', () {
      // Il criterio non ha significato di merito: serve solo a garantire che
      // una risposta ci sia e che sia la stessa ovunque. Senza, due modifiche
      // concorrenti sarebbero inordinabili e due dispositivi che le ricevono
      // in ordine diverso sceglierebbero vincitori diversi.
      expect(rev(3, 'tablet-b') > rev(3, 'tablet-a'), isTrue);
      expect(rev(3, 'tablet-a') < rev(3, 'tablet-b'), isTrue);
    });

    test('è un ordine totale: fra due revisioni qualsiasi una viene prima', () {
      final List<Revision> all = <Revision>[
        for (int c = 0; c <= 4; c++)
          for (final String d in <String>['a', 'b', 'c']) rev(c, d),
      ];

      for (final Revision x in all) {
        for (final Revision y in all) {
          final bool comparable = x == y || x > y || x < y;
          expect(comparable, isTrue, reason: '$x e $y non sono confrontabili');
          // Antisimmetria: se x batte y, y non può battere x.
          if (x > y) {
            expect(y > x, isFalse, reason: '$x e $y si battono a vicenda');
          }
        }
      }
    });

    test('la revisione iniziale precede qualunque modifica', () {
      const Revision initial = Revision.initial();
      expect(initial < rev(1, 'a'), isTrue);
      expect(initial < rev(1, ''), isTrue);
    });

    test('ordinare una lista dà lo stesso risultato da qualunque mescolata',
        () {
      final List<Revision> sorted = <Revision>[
        rev(1, 'a'),
        rev(1, 'b'),
        rev(2, 'a'),
        rev(9, 'a'),
      ];
      final List<Revision> shuffled = <Revision>[
        rev(9, 'a'),
        rev(1, 'b'),
        rev(2, 'a'),
        rev(1, 'a'),
      ]..sort();
      expect(shuffled, sorted);
    });
  });

  group('LamportClock', () {
    test('tick avanza di uno e porta il dispositivo', () async {
      final LamportClock clock =
          LamportClock(InMemoryLogicalClockStore(deviceId: 'tablet-a'));

      expect(await clock.tick(), rev(1, 'tablet-a'));
      expect(await clock.tick(), rev(2, 'tablet-a'));
    });

    test('witness porta il contatore almeno a quello visto', () async {
      // È il passo che fa funzionare Lamport. Senza, due dispositivi
      // conterebbero per conto proprio e chi ha lavorato di più vincerebbe
      // sempre, a prescindere da chi ha modificato per ultimo.
      final LamportClock clock =
          LamportClock(InMemoryLogicalClockStore(deviceId: 'tablet-a'));
      await clock.tick();

      await clock.witness(rev(41, 'tablet-b'));

      expect(await clock.tick(), rev(42, 'tablet-a'),
          reason: 'la modifica successiva deve battere quella vista');
    });

    test('witness di una revisione vecchia non fa tornare indietro', () async {
      final LamportClock clock =
          LamportClock(InMemoryLogicalClockStore(deviceId: 'tablet-a'));
      await clock.witness(rev(10, 'tablet-b'));

      await clock.witness(rev(3, 'tablet-c'));

      expect(await clock.tick(), rev(11, 'tablet-a'));
    });

    test('il contatore riparte da dove era dopo un riavvio', () async {
      // Un contatore che riparte da zero riuserebbe revisioni già usate: due
      // modifiche diverse dello stesso dispositivo porterebbero la stessa
      // revisione e l'ordine totale smetterebbe di essere tale.
      final InMemoryLogicalClockStore store =
          InMemoryLogicalClockStore(deviceId: 'tablet-a');

      final LamportClock before = LamportClock(store);
      await before.tick();
      await before.tick();
      await before.tick();

      final LamportClock afterRestart = LamportClock(store);
      expect(await afterRestart.tick(), rev(4, 'tablet-a'));
    });

    test('il contatore è persistito prima di essere usato', () async {
      final InMemoryLogicalClockStore store =
          InMemoryLogicalClockStore(deviceId: 'tablet-a');
      final LamportClock clock = LamportClock(store);

      final Revision issued = await clock.tick();

      expect(store.counter, issued.counter,
          reason: 'una revisione emessa e non salvata si può riusare');
    });
  });
}
