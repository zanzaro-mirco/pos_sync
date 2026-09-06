import 'dart:io';

/// Gli indirizzi IPv4 con cui questo dispositivo è raggiungibile.
///
/// Serve a una cosa sola, e pratica: il tablet in cassa deve poter **mostrare**
/// il proprio indirizzo, perché è quello che qualcuno deve digitare sugli
/// altri. Senza, la configurazione manuale richiederebbe di andarlo a cercare
/// nelle impostazioni di sistema — cioè di uscire dall'app proprio nel momento
/// in cui la si sta configurando.
///
/// Il loopback è escluso: è raggiungibile solo da sé stesso, e proporlo come
/// indirizzo della cassa manderebbe l'altro tablet a parlare con sé.
Future<List<String>> lanAddresses() async {
  try {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return <String>[
      for (final NetworkInterface interface in interfaces)
        for (final InternetAddress address in interface.addresses)
          address.address,
    ];
  } on SocketException {
    // Su alcune piattaforme enumerare le interfacce richiede permessi che
    // potremmo non avere. Non sapere il proprio indirizzo è una comodità in
    // meno, non un motivo per non aprire la schermata.
    return const <String>[];
  }
}
