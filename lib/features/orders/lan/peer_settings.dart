import 'package:equatable/equatable.dart';

import 'lan_protocol.dart';

/// Che parte fa questo dispositivo in sala.
///
/// Non è uno stato che il codice deduce: lo decide chi installa l'app, perché
/// dipende da dove sta il tablet. Quello in cassa resta acceso e fermo, ed è
/// il candidato naturale a tenere il registro; quelli che girano fra i tavoli
/// no.
enum PeerRole {
  /// Nessuna rete locale: si parla con il backend come prima.
  ///
  /// È il valore predefinito, ed è l'unico che non richiede di sapere niente
  /// sulla rete del locale. Un'app appena installata deve funzionare senza che
  /// nessuno abbia configurato niente.
  standalone,

  /// Questo dispositivo tiene il registro e lo espone agli altri.
  primary,

  /// Questo dispositivo parla con il primario all'indirizzo configurato.
  follower,
}

/// Come questo dispositivo si colloca rispetto agli altri.
///
/// Persistite insieme all'identità del dispositivo, e per la stessa ragione:
/// un tablet che dimentica di essere la cassa a ogni riavvio smetterebbe di
/// esserlo proprio quando la sala si riempie.
class PeerSettings extends Equatable {
  const PeerSettings({
    this.role = PeerRole.standalone,
    this.primaryHost = '',
    this.primaryPort = lanPort,
  });

  final PeerRole role;

  /// Indirizzo IPv4 del primario. Significativo solo per [PeerRole.follower].
  final String primaryHost;

  final int primaryPort;

  /// Se questa configurazione è utilizzabile così com'è.
  ///
  /// Un follower senza indirizzo non è un errore da segnalare con un'eccezione:
  /// è semplicemente una configurazione a metà, e il dispositivo continua a
  /// comportarsi come se non fosse in rete locale finché non la si completa.
  bool get isUsable => switch (role) {
        PeerRole.standalone => true,
        PeerRole.primary => true,
        PeerRole.follower => primaryHost.isNotEmpty,
      };

  PeerSettings copyWith({
    PeerRole? role,
    String? primaryHost,
    int? primaryPort,
  }) =>
      PeerSettings(
        role: role ?? this.role,
        primaryHost: primaryHost ?? this.primaryHost,
        primaryPort: primaryPort ?? this.primaryPort,
      );

  @override
  List<Object?> get props => <Object?>[role, primaryHost, primaryPort];

  @override
  String toString() => switch (role) {
        PeerRole.standalone => 'PeerSettings(standalone)',
        PeerRole.primary => 'PeerSettings(primary)',
        PeerRole.follower =>
          'PeerSettings(follower -> $primaryHost:$primaryPort)',
      };
}

/// Dove il ruolo sopravvive alla chiusura dell'app.
abstract interface class PeerSettingsStore {
  Future<PeerSettings> load();
  Future<void> save(PeerSettings settings);
}

/// Impostazioni in memoria, per i test e per chi non ha una base dati.
class InMemoryPeerSettings implements PeerSettingsStore {
  InMemoryPeerSettings([this._settings = const PeerSettings()]);

  PeerSettings _settings;

  @override
  Future<PeerSettings> load() async => _settings;

  @override
  Future<void> save(PeerSettings settings) async => _settings = settings;
}

/// Nome del ruolo così come finisce su SQLite, e ritorno.
///
/// Esplicita e non `role.name`: le due cose coincidono oggi, e proprio per
/// questo è facile rinominare una costante dimenticando che quel nome è anche
/// un valore scritto su disco. È lo stesso inciampo già visto con lo stato del
/// tavolo, e qui la traduzione è scritta prima che capiti.
PeerRole parsePeerRole(String raw) => switch (raw) {
      'primary' => PeerRole.primary,
      'follower' => PeerRole.follower,
      _ => PeerRole.standalone,
    };

String peerRoleName(PeerRole role) => switch (role) {
      PeerRole.standalone => 'standalone',
      PeerRole.primary => 'primary',
      PeerRole.follower => 'follower',
    };
