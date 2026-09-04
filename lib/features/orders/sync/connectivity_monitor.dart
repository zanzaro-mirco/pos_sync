import 'dart:async';

/// Stato della connettività, ridotto a ciò che serve al drenaggio della coda.
///
/// È un booleano di proposito. Il plugin distingue Wi-Fi, dati mobili,
/// ethernet, VPN e bluetooth, ma al worker non serve sapere *come* si è
/// connessi: gli serve sapere se vale la pena tentare. Ridurre il tipo qui,
/// sul confine, tiene quella distinzione fuori dalla logica e permette di
/// sostituire domani il plugin con qualcosa che misura la raggiungibilità
/// vera senza toccare niente a valle.
///
/// Il contratto vive accanto a chi lo consuma, l'adattatore sul plugin sta in
/// `data/` insieme agli altri adattatori verso il mondo esterno. È anche ciò
/// che permette a `sync/` di restare Dart puro: la logica di sincronizzazione
/// continua a girare nei test senza Flutter.
abstract interface class ConnectivityMonitor {
  /// Stato corrente.
  Future<bool> isOnline();

  /// Emette a ogni cambiamento di rete.
  ///
  /// **I valori non si alternano necessariamente.** Il passaggio da Wi-Fi a
  /// dati mobili è un cambiamento di rete ma non di stato, e arriva qui come
  /// un secondo `true`. Riconoscere la transizione è compito di chi ascolta:
  /// filtrarlo qui nasconderebbe il problema invece di risolverlo, e un
  /// monitor scritto male tornerebbe a produrre drenaggi doppi.
  Stream<bool> get onOnlineChanged;
}

/// Monitor controllabile a mano.
///
/// Sta accanto al contratto come `FakeClock` accanto a `Clock`: serve ai test,
/// dove attendere una vera transizione di rete non è possibile, e alla
/// modalità demo, dove permette di riprodurre il ciclo offline/online senza
/// mettere davvero il telefono in modalità aereo.
class FakeConnectivityMonitor implements ConnectivityMonitor {
  FakeConnectivityMonitor({bool online = false}) : _online = online;

  bool _online;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  /// Simula un cambiamento di rete.
  ///
  /// Emette anche quando lo stato non cambia, perché è ciò che fa il plugin
  /// vero passando da Wi-Fi a dati mobili: è il caso che chi ascolta deve
  /// saper ignorare.
  void emit(bool online) {
    _online = online;
    _controller.add(online);
  }

  Future<void> dispose() => _controller.close();
}
