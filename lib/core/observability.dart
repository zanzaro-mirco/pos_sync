import 'feature_flags.dart';
import 'logger.dart';
import 'product_metrics.dart';

/// Cosa il sistema racconta di sé, e cosa gli si può dire da fuori.
///
/// Tre pezzi che arrivano insieme perché nascono insieme: o c'è un progetto
/// Firebase configurato, e allora ci sono tutti e tre, o non c'è, e allora non
/// c'è nessuno. Passarli uno a uno alla composition root lascerebbe possibile
/// una combinazione che non esiste.
class Observability {
  const Observability({
    required this.logger,
    required this.flags,
    required this.metrics,
  });

  /// Nessun servizio remoto: chi clona il repository, la pipeline, i test,
  /// e la build per Windows.
  ///
  /// È l'app com'era prima dell'osservabilità, ed è voluto: l'assenza di
  /// Firebase non deve cambiare cosa fa l'app, solo cosa se ne sa.
  static const Observability off = Observability(
    logger: SilentLogger(),
    flags: FixedFeatureFlags(),
    metrics: NoProductMetrics(),
  );

  final Logger logger;
  final FeatureFlags flags;
  final ProductMetrics metrics;
}
