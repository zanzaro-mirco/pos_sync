import 'dart:convert';
import 'dart:io';

import '../../../core/logger.dart';
import '../data/dto/order_dto.dart';
import '../data/order_registry.dart';
import '../domain/order.dart';
import 'lan_protocol.dart';

/// Il dispositivo in cassa, visto dagli altri tablet.
///
/// Espone su HTTP lo stesso registro che in modalità dimostrativa vive in
/// processo: due verbi e un riconoscimento, niente di più. Non c'è un
/// framework perché non serve — `dart:io` porta un server HTTP completo, e
/// aggiungere una dipendenza per tre percorsi sarebbe peso senza guadagno.
///
/// **Non fonde e non decide.** Riceve versioni, le tiene distinte per
/// dispositivo e le restituisce. Tutta l'intelligenza — la politica di
/// fusione, il riconoscimento del conflitto, l'orologio logico — resta sui
/// dispositivi, dov'era già. È la ragione per cui questo file è corto: il
/// lavoro difficile era stato fatto prima, e in un posto che non è questo.
class OrderServer {
  OrderServer({
    required OrderRegistry registry,
    required String deviceId,
    Logger logger = const SilentLogger(),
  })  : _registry = registry,
        _deviceId = deviceId,
        _logger = logger;

  final OrderRegistry _registry;
  final String _deviceId;
  final Logger _logger;

  HttpServer? _server;

  /// Porta su cui si sta ascoltando, o `null` se il server non è avviato.
  int? get port => _server?.port;

  bool get isRunning => _server != null;

  /// Comincia ad ascoltare. Idempotente: chiamarla due volte non apre due
  /// server, perché la seconda porta fallirebbe e il ruolo di primario non è
  /// una cosa che si assume a metà.
  ///
  /// [port] è parametrizzabile per una ragione sola: nei test serve lo zero,
  /// che chiede al sistema una porta libera qualsiasi. In esercizio è sempre
  /// [lanPort].
  Future<void> start({int port = lanPort}) async {
    if (_server != null) return;

    // `anyIPv4` e non `loopbackIPv4`: un server raggiungibile solo da sé stesso
    // sarebbe esattamente ciò che questa voce esiste per evitare.
    final HttpServer server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _server = server;
    _logger.info('Nodo primario in ascolto sulla porta ${server.port}');

    // Non attesa: `listen` restituisce una sottoscrizione che vive quanto il
    // server, e attenderla qui bloccherebbe l'avvio per sempre.
    server.listen(_handle, onError: (Object e) => _logger.warning('$e'));
  }

  Future<void> stop() async {
    final HttpServer? server = _server;
    _server = null;
    // `force`: le connessioni aperte non devono trattenere lo spegnimento,
    // che nei test avviene fra un caso e l'altro.
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      switch ((request.method, request.uri.path)) {
        case ('GET', healthPath):
          _json(request, <String, dynamic>{
            'deviceId': _deviceId,
            'role': 'primary',
          });

        case ('GET', ordersPath):
          final String who = request.uri.queryParameters[deviceParam] ?? '';
          _json(
            request,
            _registry
                .versionsExcept(who)
                .map((Order o) => OrderDto.fromDomain(o).toJson())
                .toList(),
          );

        case ('POST', ordersPath):
          await _receive(request);

        default:
          request.response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      // Una richiesta malformata non deve poter fermare il nodo primario:
      // spegnere la cassa perché un tablet ha inviato spazzatura sarebbe un
      // modo elaborato di perdere il servizio.
      _logger.warning('Richiesta non gestita: $e');
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }

  Future<void> _receive(HttpRequest request) async {
    final String who = request.uri.queryParameters[deviceParam] ?? '';
    if (who.isEmpty) {
      // Senza mittente il registro non saprebbe da chi tenere distinta questa
      // versione, e la terrebbe per conto di nessuno. È un errore del
      // chiamante, quindi definitivo: 400, e il client non riprova.
      request.response.statusCode = HttpStatus.badRequest;
      return;
    }

    final String body = await utf8.decoder.bind(request).join();
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      request.response.statusCode = HttpStatus.badRequest;
      return;
    }

    final Order? order = OrderDto.fromJson(decoded).toDomain();
    if (order == null) {
      // `toDomain` restituisce null su un record inutilizzabile. Scartarlo con
      // un 400 è meglio che registrarlo: un ordine senza id o senza data
      // sporcherebbe il registro di tutti gli altri.
      request.response.statusCode = HttpStatus.badRequest;
      return;
    }

    _registry.store(order, who);
    request.response.statusCode = HttpStatus.noContent;
  }

  void _json(HttpRequest request, Object payload) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
  }
}
