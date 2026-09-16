import 'dart:async';

import 'package:pos_sync/core/feature_flags.dart';

/// Flag che il test cambia a mano, come farebbe la console di Firebase.
class SwitchableFlags implements FeatureFlags {
  SwitchableFlags({this.peerSyncEnabled = true});

  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  bool peerSyncEnabled;

  @override
  Stream<void> get changes => _changes.stream;

  /// Cambia il valore e lo annuncia, nello stesso ordine di Remote Config:
  /// prima si attiva il valore nuovo, poi si avvisa chi ascolta.
  void setPeerSync(bool enabled) {
    peerSyncEnabled = enabled;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
