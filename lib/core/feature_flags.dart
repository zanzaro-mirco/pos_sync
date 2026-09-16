/// Le funzionalità che si possono spegnere senza pubblicare una nuova versione.
///
/// È la risposta a «hai rilasciato un bug grave, cosa fai»: un'app già
/// installata su trenta tablet non si aggiorna in dieci minuti, un valore letto
/// dal cloud sì. Chi legge un flag non sa da dove arrivi, come il worker non sa
/// se dietro `RemoteApi` c'è il cloud o un altro tablet.
abstract interface class FeatureFlags {
  /// La sincronizzazione peer-to-peer in rete locale.
  ///
  /// Spenta, ogni dispositivo torna a parlare solo con il backend, e la cassa
  /// smette di rispondere agli altri tablet. Le impostazioni di rete restano
  /// salvate: riaccesa, ognuno riprende il ruolo che aveva.
  bool get peerSyncEnabled;

  /// Emette quando un valore è cambiato mentre l'app era aperta.
  ///
  /// Senza, un flag spento avrebbe effetto solo al prossimo giro della coda,
  /// cioè quando qualcuno prende un ordine: la cassa continuerebbe a
  /// rispondere agli altri tablet proprio mentre la si vuole fermare.
  Stream<void> get changes;
}

/// Valori fissi: in chi compila senza Firebase, e nei test.
///
/// I valori predefiniti sono quelli con cui l'app si comporta come prima che i
/// flag esistessero. Un'osservabilità che manca non deve spegnere niente.
class FixedFeatureFlags implements FeatureFlags {
  const FixedFeatureFlags({this.peerSyncEnabled = true});

  @override
  final bool peerSyncEnabled;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}
