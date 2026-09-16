import 'package:firebase_analytics/firebase_analytics.dart';

import '../product_metrics.dart';

/// Le metriche di prodotto, come eventi di Google Analytics.
class AnalyticsMetrics implements ProductMetrics {
  const AnalyticsMetrics(this._analytics);

  /// Il nome dell'evento. Una volta nei dati, cambiarlo spezza le serie: i
  /// giorni prima e quelli dopo diventano due metriche diverse.
  static const String orderSyncedEvent = 'order_synced';

  final FirebaseAnalytics _analytics;

  /// Un evento per invio, e non uno per giro con il numero dentro.
  ///
  /// Analytics conta gli eventi da solo, per ora e per giorno. Un numero dentro
  /// un parametro, invece, andrebbe prima registrato come metrica
  /// personalizzata nella console per poterlo sommare: un passo a mano in più,
  /// che nessun file del repository ricorderebbe. I volumi di un locale — le
  /// centinaia di ordini in una sera, non i milioni — lo permettono.
  @override
  void ordersSynced(int count) {
    for (int i = 0; i < count; i++) {
      // Non attesa: la metrica non deve rallentare la coda, né fermarla se
      // Analytics non risponde.
      _analytics.logEvent(name: orderSyncedEvent).ignore();
    }
  }
}
