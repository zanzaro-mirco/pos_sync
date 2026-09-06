import 'package:flutter/material.dart';

import '../lan/peer_settings.dart';

/// Dove si decide che parte fa questo dispositivo in sala.
///
/// Le tre scelte sono descritte per **cosa comportano**, non per il nome del
/// ruolo: «questo dispositivo è la cassa» dice a chi installa l'app dove deve
/// stare il tablet, mentre «primario» richiede di sapere già come funziona il
/// sistema. È la stessa regola dei pulsanti della scheda di conflitto.
///
/// L'indirizzo della cassa compare solo quando serve. Un campo sempre presente
/// e quasi sempre da ignorare è un invito a compilarlo per sbaglio.
///
/// La porta non si chiede affatto: vale `lanPort` su entrambi i lati e nessuno
/// deve impararla dall'altro. Chiederla darebbe a chi installa l'app un modo
/// di rompere la sincronizzazione scrivendo un numero diverso su un tablet
/// solo — e il guasto si manifesterebbe come «non arriva niente», che è il
/// sintomo meno diagnosticabile di tutti.
class PeerSettingsSheet extends StatefulWidget {
  const PeerSettingsSheet({
    super.key,
    required this.initial,
    required this.onSave,
    this.localAddresses = const <String>[],
  });

  final PeerSettings initial;
  final ValueChanged<PeerSettings> onSave;

  /// Gli indirizzi con cui questo dispositivo è raggiungibile, da mostrare
  /// quando fa da cassa: sono quelli da digitare sugli altri tablet.
  final List<String> localAddresses;

  @override
  State<PeerSettingsSheet> createState() => _PeerSettingsSheetState();
}

class _PeerSettingsSheetState extends State<PeerSettingsSheet> {
  late PeerRole _role = widget.initial.role;

  // Qui il controller è corretto, a differenza della finestra del numero di
  // tavolo: vive quanto lo `State`, che Flutter smonta dopo l'animazione di
  // uscita, e `dispose()` è chiamato al momento giusto per costruzione.
  late final TextEditingController _host =
      TextEditingController(text: widget.initial.primaryHost);

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  // La porta si riporta com'era invece di essere ricalcolata: è un dato che
  // questo foglio non modifica, e riscriverlo con il valore predefinito
  // cancellerebbe in silenzio l'unico caso in cui è diverso — un test che
  // l'aveva impostata.
  PeerSettings get _chosen => PeerSettings(
        role: _role,
        primaryHost: _host.text.trim(),
        primaryPort: widget.initial.primaryPort,
      );

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Rete locale', style: text.titleMedium),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Con il cloud irraggiungibile i tablet possono sincronizzarsi '
                'fra loro, purché uno faccia da punto di raccolta.',
              ),
            ),
            const Divider(height: 1),
            // La scelta sta sul gruppo e non sulle singole voci: `groupValue` e
            // `onChanged` su `RadioListTile` sono deprecati, e la ragione è
            // buona — con il valore ripetuto su ogni voce niente impediva di
            // scriverne tre diversi.
            RadioGroup<PeerRole>(
              groupValue: _role,
              onChanged: (PeerRole? picked) =>
                  setState(() => _role = picked ?? _role),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final PeerRole role in PeerRole.values)
                    RadioListTile<PeerRole>(
                      key: Key('peer-role-${peerRoleName(role)}'),
                      value: role,
                      title: Text(_title(role)),
                      subtitle: Text(_subtitle(role)),
                    ),
                ],
              ),
            ),
            if (_role == PeerRole.primary && widget.localAddresses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Sugli altri tablet inserisci: '
                  '${widget.localAddresses.join(' oppure ')}',
                  key: const Key('peer-own-address'),
                  style: text.bodySmall,
                ),
              ),
            if (_role == PeerRole.follower)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  key: const Key('peer-host-field'),
                  controller: _host,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Indirizzo della cassa',
                    hintText: '192.168.1.7',
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    key: const Key('peer-cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('peer-save'),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onSave(_chosen);
                    },
                    child: const Text('Salva'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _title(PeerRole role) => switch (role) {
        PeerRole.standalone => 'Nessuna rete locale',
        PeerRole.primary => 'Questo dispositivo è la cassa',
        PeerRole.follower => 'Questo dispositivo è in sala',
      };

  static String _subtitle(PeerRole role) => switch (role) {
        PeerRole.standalone => 'Si parla solo con il backend, come prima',
        PeerRole.primary => 'Tiene il registro e risponde agli altri tablet',
        PeerRole.follower => 'Si sincronizza con la cassa',
      };
}
