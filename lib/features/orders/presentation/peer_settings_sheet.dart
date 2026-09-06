import 'package:flutter/material.dart';

import '../lan/lan_check.dart';
import '../lan/peer_settings.dart';

/// Dove si decide che parte fa questo dispositivo in sala.
///
/// Le tre scelte sono descritte per **cosa comportano**, non per il nome del
/// ruolo: «questo dispositivo è la cassa» dice a chi installa l'app dove deve
/// stare il tablet, mentre «primario» richiede di sapere già come funziona il
/// sistema. È la stessa regola dei pulsanti della scheda di conflitto.
///
/// L'indirizzo della cassa compare solo quando serve, ed è **facoltativo**:
/// lasciarlo vuoto significa cercarla sulla rete. Un campo sempre presente e
/// quasi sempre da ignorare è un invito a compilarlo per sbaglio.
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
    this.onCheck,
  });

  final PeerSettings initial;
  final ValueChanged<PeerSettings> onSave;

  /// Prova la configurazione mostrata e dice com'è andata.
  ///
  /// Nullable come le azioni della pagina: una build senza rete locale non ha
  /// niente da provare. Riceve le impostazioni **correnti del foglio** e non
  /// quelle salvate, perché chi sta configurando vuole sapere se funziona ciò
  /// che ha appena scritto.
  final Future<LanCheck> Function(PeerSettings settings)? onCheck;

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

  /// L'esito dell'ultima prova, o `null` se non se ne sono ancora fatte.
  LanCheck? _check;
  bool _checking = false;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _runCheck() async {
    final Future<LanCheck> Function(PeerSettings)? check = widget.onCheck;
    if (check == null || _checking) return;

    setState(() {
      _checking = true;
      // L'esito vecchio sparisce subito: lasciarlo mentre si prova di nuovo
      // farebbe leggere come risposta alla domanda di adesso una risposta alla
      // domanda di prima.
      _check = null;
    });
    final LanCheck result = await check(_chosen);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _check = result;
    });
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
                    labelText: 'Indirizzo della cassa (facoltativo)',
                    hintText: '192.168.1.7',
                    helperText: 'Vuoto: la cerca da sola sulla rete',
                    helperMaxLines: 2,
                  ),
                ),
              ),
            if (widget.onCheck != null) ...<Widget>[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('peer-check'),
                    onPressed: _checking ? null : _runCheck,
                    icon: const Icon(Icons.network_check),
                    label: Text(
                      _checking ? 'Provo...' : 'Prova il collegamento',
                    ),
                  ),
                ),
              ),
            ],
            if (_check != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _checkMessage(_check!),
                  key: const Key('peer-check-result'),
                  style: text.bodyMedium?.copyWith(
                    color: _check!.ok
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
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

  /// Come si racconta un esito.
  ///
  /// Le due domande sono diverse a seconda del ruolo, e la risposta lo rispetta.
  /// In sala interessa **chi risponde**; in cassa interessa **chi ha scritto**,
  /// perché una porta aperta dice che il servizio c'è, non che qualcuno lo
  /// stia usando.
  String _checkMessage(LanCheck check) {
    if (!check.ok) return check.problem!;

    if (_role == PeerRole.primary) {
      if (check.senders.isEmpty) {
        return 'Registro attivo. Nessun altro dispositivo ha ancora inviato '
            'ordini qui.';
      }
      return 'Registro attivo. Hanno inviato ordini: '
          '${check.senders.join(', ')}.';
    }

    final String where = check.address == null ? '' : ' a ${check.address}';
    return 'Risponde la cassa ${check.primary}$where.';
  }

  static String _title(PeerRole role) => switch (role) {
        PeerRole.standalone => 'Nessuna rete locale',
        PeerRole.primary => 'Questo dispositivo è la cassa',
        PeerRole.follower => 'Questo dispositivo è in sala',
      };

  static String _subtitle(PeerRole role) => switch (role) {
        PeerRole.standalone => 'Si parla solo con il backend, come prima',
        PeerRole.primary => 'Tiene il registro e risponde agli altri tablet',
        PeerRole.follower => 'Cerca la cassa in rete e si sincronizza',
      };
}
