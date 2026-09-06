import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/dto/order_dto.dart';
import '../data/remote_api.dart';
import '../domain/order.dart';
import 'lan_protocol.dart';

/// Il backend, quando è il tablet in cassa invece del cloud.
///
/// Implementa lo stesso [RemoteApi] di `FakeRemoteApi`, ed è tutto ciò che
/// serve perché il resto del sistema funzioni in rete locale: la coda, il
/// backoff, il rientro e la fusione non sanno — e non devono sapere — se
/// dall'altra parte del filo c'è un server o il tablet di un collega.
///
/// **La sola logica vera qui è la traduzione degli errori.** La gerarchia
/// sealed di `ApiFailure` esiste da prima, e la politica di ritentativo decide
/// su quella: sbagliare la traduzione significa una coda che ritenta per
/// sempre un errore definitivo, o che butta via un ordine per una disconnessione
/// momentanea. Il resto del file è trasporto.
class HttpRemoteApi implements RemoteApi {
  HttpRemoteApi({
    required this.host,
    required this.deviceId,
    this.port = lanPort,
    Duration timeout = const Duration(seconds: 4),
    HttpClient? client,
  })  : _timeout = timeout,
        _client = client ?? HttpClient() {
    // Più corto del timeout complessivo: un tablet spento non risponde al
    // SYN, e senza questo si aspetterebbe il timeout di sistema — decine di
    // secondi in cui la sala guarda una rotellina.
    _client.connectionTimeout = const Duration(seconds: 2);
  }

  /// Indirizzo del dispositivo primario, come IPv4 sulla rete locale.
  final String host;
  final int port;

  /// Chi sta parlando. Serve al registro per escludere le nostre versioni da
  /// ciò che ci restituisce.
  final String deviceId;

  final Duration _timeout;
  final HttpClient _client;

  Uri _uri(String path) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path,
        queryParameters: <String, String>{deviceParam: deviceId},
      );

  @override
  Future<void> submitOrder(Order order) async {
    await _send(() async {
      final HttpClientRequest request = await _client.postUrl(_uri(ordersPath));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(OrderDto.fromDomain(order).toJson()));
      return request.close();
    });
  }

  @override
  Future<List<Order>> fetchOrders() async {
    final String body = await _send(() async {
      final HttpClientRequest request = await _client.getUrl(_uri(ordersPath));
      return request.close();
    });

    final Object? decoded = jsonDecode(body);
    if (decoded is! List<dynamic>) {
      // Il primario ha risposto qualcosa che non è una lista di ordini: è un
      // guasto di protocollo, non di rete, e riprovare non lo aggiusta.
      throw const PermanentApiFailure('Risposta non riconosciuta dal primario');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> j) => OrderDto.fromJson(j).toDomain())
        .whereType<Order>()
        .toList();
  }

  /// Esegue la richiesta e traduce ogni modo di fallire.
  ///
  /// Le tre famiglie che contano, e perché stanno da parti diverse:
  ///
  /// - **rete** (socket chiuso, host irraggiungibile, timeout): il primario
  ///   può essere in un'altra stanza o riavviato. Recuperabile.
  /// - **4xx**: abbiamo mandato qualcosa che non va bene, e rimandarlo identico
  ///   darà lo stesso esito. Definitivo — è l'unico caso in cui un ordine può
  ///   uscire dalla coda senza essere arrivato, ed è per questo che il server
  ///   risponde 400 solo su richieste davvero inutilizzabili.
  /// - **5xx**: il primario è in difficoltà, non noi. Recuperabile.
  Future<String> _send(Future<HttpClientResponse> Function() call) async {
    final HttpClientResponse response;
    try {
      response = await call().timeout(_timeout);
    } on TimeoutException {
      throw const TransientApiFailure('Il primario non ha risposto in tempo');
    } on SocketException catch (e) {
      throw TransientApiFailure('Primario irraggiungibile: ${e.message}');
    } on HttpException catch (e) {
      throw TransientApiFailure('Connessione interrotta: ${e.message}');
    }

    final String body = await utf8.decoder.bind(response).join();

    if (response.statusCode >= 500) {
      throw TransientApiFailure(
          'Il primario ha risposto ${response.statusCode}');
    }
    if (response.statusCode >= 400) {
      throw PermanentApiFailure('Richiesta rifiutata (${response.statusCode})');
    }
    return body;
  }

  /// Chi è dall'altra parte, o `null` se non risponde.
  ///
  /// Restituisce l'identificativo invece di un booleano perché la domanda utile
  /// non è «c'è qualcuno?» ma «c'è **ancora quello di prima**?»: dopo
  /// un'elezione all'indirizzo noto può rispondere un dispositivo diverso, e
  /// una connessione riuscita da sola non lo direbbe.
  Future<String?> primaryDeviceId() async {
    try {
      final String body = await _send(() async {
        final HttpClientRequest request =
            await _client.getUrl(_uri(healthPath));
        return request.close();
      });
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded['deviceId'] as String?;
      }
      return null;
    } on ApiFailure {
      return null;
    }
  }

  void close() => _client.close(force: true);
}
