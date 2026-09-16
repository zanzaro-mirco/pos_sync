/// Le metriche di prodotto: cosa fa il sistema per chi lo usa, non come sta.
///
/// Un crash dice che qualcosa si è rotto. Non dice se, dopo un rilascio, gli
/// ordini hanno smesso di arrivare in cassa senza che niente si rompesse — ed è
/// il guasto più costoso per un locale, perché nessuno lo segnala.
abstract interface class ProductMetrics {
  /// Ordini consegnati al backend, o alla cassa, in un giro della coda.
  ///
  /// Contati da chi li manda e non da chi li riceve: il dispositivo che li ha
  /// presi è l'unico che sa quando è riuscito a consegnarli. Sommati sul parco
  /// e divisi per ora danno la metrica: ordini sincronizzati per ora.
  void ordersSynced(int count);
}

/// Non misura niente. Predefinito finché non c'è dove mandare i numeri.
class NoProductMetrics implements ProductMetrics {
  const NoProductMetrics();

  @override
  void ordersSynced(int count) {}
}
