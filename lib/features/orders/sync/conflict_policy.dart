import '../domain/order.dart';
import '../domain/order_line.dart';
import '../domain/order_state.dart';

/// Esito di una fusione.
///
/// Gerarchia chiusa come [RetryDecision] in `retry_policy.dart`: le due
/// risposte possibili sono note, e il compilatore segnala ogni `switch` che ne
/// dimentica una.
sealed class Resolution<T> {
  const Resolution();
}

/// Le due versioni si sono fuse da sole.
class Resolved<T> extends Resolution<T> {
  const Resolved(this.value);

  final T value;
}

/// Le due versioni non si fondono senza decidere qualcosa che il codice non
/// può decidere.
///
/// Non è un errore ed è il punto: fondere in silenzio produrrebbe un risultato
/// plausibile e sbagliato. Meglio fermarsi e chiedere.
class NeedsDecision<T> extends Resolution<T> {
  const NeedsDecision({
    required this.mine,
    required this.theirs,
    required this.reason,
  });

  final T mine;
  final T theirs;

  /// Perché il codice si è fermato, in una frase leggibile dall'operatore.
  final String reason;
}

/// Fonde due versioni dello stesso dato.
///
/// Una per tipo di dato, perché il criterio giusto dipende dal dato e non dal
/// sistema: due camerieri che aggiungono piatti non sono in conflitto, due che
/// chiudono lo stesso tavolo sì. Un'unica politica per tutto costringerebbe a
/// scegliere quale dei due casi trattare male.
abstract interface class ConflictPolicy<T> {
  Resolution<T> merge(T mine, T theirs);
}

/// Righe d'ordine: unione dei due insiemi.
///
/// Le righe si aggiungono e non si modificano, quindi la fusione è l'unione ed
/// è **commutativa**: `merge(a, b)` e `merge(b, a)` danno lo stesso risultato.
/// È da questa proprietà che discende la convergenza — l'ordine di arrivo
/// smette di contare perché il risultato non lo guarda.
///
/// L'ordinamento finale è per revisione, con l'id a rompere la parità: serve a
/// far sì che i due dispositivi non ottengano solo lo stesso *insieme* ma la
/// stessa *lista*, altrimenti confrontarli campo per campo fallirebbe per una
/// differenza che non significa niente.
class AppendOnlyLines implements ConflictPolicy<List<OrderLine>> {
  const AppendOnlyLines();

  @override
  Resolution<List<OrderLine>> merge(
    List<OrderLine> mine,
    List<OrderLine> theirs,
  ) {
    final Map<String, OrderLine> byId = <String, OrderLine>{
      for (final OrderLine line in mine) line.id: line,
      for (final OrderLine line in theirs) line.id: line,
    };

    final List<OrderLine> merged = byId.values.toList()
      ..sort((OrderLine a, OrderLine b) {
        final int byRevision = a.addedAt.compareTo(b.addedAt);
        return byRevision != 0 ? byRevision : a.id.compareTo(b.id);
      });

    return Resolved<List<OrderLine>>(List<OrderLine>.unmodifiable(merged));
  }
}

/// Stato del tavolo: vince la revisione più alta.
///
/// Qui l'unione non ha senso — un tavolo non può essere insieme aperto e
/// pagato — quindi uno dei due deve perdere. Che a perdere sia sempre lo stesso
/// su tutti i dispositivi dipende dall'ordine totale di `Revision`: sul
/// contatore logico, non sull'orologio di sistema e non sull'ordine di arrivo.
class LastWriteWinsState implements ConflictPolicy<StampedState> {
  const LastWriteWinsState();

  @override
  Resolution<StampedState> merge(StampedState mine, StampedState theirs) =>
      Resolved<StampedState>(mine.revision >= theirs.revision ? mine : theirs);
}

/// Fonde due versioni dello stesso ordine componendo le due politiche, e si
/// ferma dove il risultato automatico sarebbe plausibile ma sbagliato.
///
/// Il caso è uno solo, ed è concreto: **il tavolo risulta pagato, e l'altra
/// versione porta righe che chi ha incassato non aveva davanti**. Le due
/// politiche prese alla lettera produrrebbero un tavolo pagato con dentro roba
/// non pagata — un risultato che non fa rumore da nessuna parte tranne che in
/// cassa a fine serata. Non è il codice a poter decidere se quelle righe vanno
/// incassate a parte o se il pagamento va rifatto: lo decide chi è lì.
///
/// Da notare cosa **non** è un conflitto: due dispositivi che aggiungono piatti,
/// due che portano il tavolo a `served`, uno che serve mentre l'altro aggiunge.
/// Tutto questo converge da solo e non deve interrompere nessuno — un sistema
/// che chiede conferma troppo spesso viene ignorato, ed è un modo più lento di
/// non avere gestione dei conflitti.
class OrderConflictPolicy implements ConflictPolicy<Order> {
  const OrderConflictPolicy({
    ConflictPolicy<List<OrderLine>> lines = const AppendOnlyLines(),
    ConflictPolicy<StampedState> state = const LastWriteWinsState(),
  })  : _lines = lines,
        _state = state;

  final ConflictPolicy<List<OrderLine>> _lines;
  final ConflictPolicy<StampedState> _state;

  @override
  Resolution<Order> merge(Order mine, Order theirs) {
    // Le due politiche componenti possono a loro volta fermarsi: qui non
    // succede con quelle predefinite, ma sono sostituibili dall'esterno e
    // ignorarlo significherebbe fondere un dato che la politica aveva
    // dichiarato di non saper fondere.
    final Resolution<List<OrderLine>> lines =
        _lines.merge(mine.lines, theirs.lines);
    if (lines is NeedsDecision<List<OrderLine>>) {
      return NeedsDecision<Order>(
          mine: mine, theirs: theirs, reason: lines.reason);
    }
    final Resolution<StampedState> state =
        _state.merge(_stampOf(mine), _stampOf(theirs));
    if (state is NeedsDecision<StampedState>) {
      return NeedsDecision<Order>(
          mine: mine, theirs: theirs, reason: state.reason);
    }

    final List<OrderLine> mergedLines =
        (lines as Resolved<List<OrderLine>>).value;
    final StampedState winner = (state as Resolved<StampedState>).value;

    final Order merged = mine.copyWith(
      lines: mergedLines,
      state: winner.value,
      stateRevision: winner.revision,
    );

    final Order? paying = _payingSide(mine, theirs, winner);
    if (paying != null) {
      final List<OrderLine> unseen = _linesMissingFrom(paying, mergedLines);
      if (unseen.isNotEmpty) {
        return NeedsDecision<Order>(
          mine: mine,
          theirs: theirs,
          reason: 'Il tavolo ${mine.tableNumber} risulta pagato, ma '
              '${_itemsLabel(unseen)} non erano nel conto',
        );
      }
    }

    return Resolved<Order>(merged);
  }

  static StampedState _stampOf(Order order) =>
      StampedState(order.state, order.stateRevision);

  /// La versione che ha vinto, se ha vinto dichiarando il tavolo pagato.
  ///
  /// Il confronto è sulla revisione e non sul valore: due versioni possono
  /// essere entrambe `paid`, e in quel caso non c'è niente da chiedere.
  static Order? _payingSide(Order mine, Order theirs, StampedState winner) {
    if (winner.value != OrderState.paid) return null;
    if (mine.state == OrderState.paid && theirs.state == OrderState.paid) {
      return null;
    }
    return mine.stateRevision == winner.revision ? mine : theirs;
  }

  /// Righe della fusione che la versione [side] non aveva.
  ///
  /// Il confronto è sull'insieme delle righe e non sulle revisioni. Con un
  /// orologio di Lamport una riga aggiunta da un dispositivo che non aveva
  /// ancora visto il pagamento può portare un contatore più basso, e un
  /// controllo basato sui numeri la lascerebbe passare. Chiedersi invece "chi
  /// ha incassato aveva questa riga davanti?" non dipende dai contatori e
  /// risponde alla domanda vera.
  static List<OrderLine> _linesMissingFrom(Order side, List<OrderLine> merged) {
    final Set<String> known = side.lines.map((OrderLine l) => l.id).toSet();
    return merged
        .where((OrderLine l) => !known.contains(l.id))
        .toList(growable: false);
  }

  static String _itemsLabel(List<OrderLine> lines) {
    final int quantity =
        lines.fold<int>(0, (int acc, OrderLine l) => acc + l.quantity);
    return quantity == 1 ? '1 articolo' : '$quantity articoli';
  }
}
