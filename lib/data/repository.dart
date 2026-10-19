import 'dart:convert';
import 'dart:io';

import '../domain/assistant.dart';
import '../domain/odds.dart';

class BackendRepository {
  BackendRepository(this.baseUrl);
  final String baseUrl;

  Uri _endpoint(String path) {
    final base = Uri.parse(baseUrl);
    final host = base.host.toLowerCase();
    // The model host is never a valid Odds Edge backend.
    if (host == 'x.ai' || host.endsWith('.x.ai')) {
      throw StateError(
        'Use the Odds Edge backend. This app does not call the model host.',
      );
    }
    final remoteHttps = base.scheme == 'https';
    final localHttp =
        base.scheme == 'http' && (host == '127.0.0.1' || host == 'localhost');
    if (!remoteHttps && !localHttp) {
      throw StateError('Use HTTPS for a remote backend.');
    }
    final target = base.resolve(path);
    if (target.scheme != base.scheme || target.host.toLowerCase() != host) {
      throw StateError(
        'Use the Odds Edge backend. This app does not call the model host.',
      );
    }
    return target;
  }

  Future<dynamic> _get(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(_endpoint(path))
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != 200) {
        throw StateError('Backend unavailable (${response.statusCode}).');
      }
      return jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 12)),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<dynamic> _post(String path, Object body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(_endpoint(path))
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 150),
      );
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 150));
      if (response.statusCode != 200) {
        throw StateError('Backend unavailable (${response.statusCode}).');
      }
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  Future<OddsBoard> board() async => OddsBoard.fromJson(await _get('/v1/odds'));
  Future<List<OddsQuote>> history(Selection s) async =>
      ((await _get(
                '/v1/history?selection=${Uri.encodeComponent(s.key)}',
              ))['quotes']
              as List)
          .map((j) => OddsQuote.fromJson(j))
          .toList();

  /// Posts research context to this app's backend. The model key stays there.
  Future<AssistantReply> assistant(AssistantRequest request) async {
    final decoded = await _post('/v1/assistant', request.toJson());
    if (decoded is! Map) throw StateError('Backend unavailable.');
    return AssistantReply.fromJson(Map<String, dynamic>.from(decoded));
  }
}
