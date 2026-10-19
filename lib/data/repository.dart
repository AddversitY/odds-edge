import 'dart:convert';
import 'dart:io';

import '../domain/odds.dart';

class BackendRepository {
  BackendRepository(this.baseUrl);
  final String baseUrl;
  Future<dynamic> _get(String path) async {
    final base = Uri.parse(baseUrl);
    if (base.scheme != 'https' &&
        !(base.scheme == 'http' &&
            ['127.0.0.1', 'localhost'].contains(base.host))) {
      throw StateError('Use HTTPS for a remote backend.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(base.resolve(path))
          .timeout(const Duration(seconds: 8));
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

  Future<OddsBoard> board() async => OddsBoard.fromJson(await _get('/v1/odds'));
  Future<List<OddsQuote>> history(Selection s) async =>
      ((await _get(
                '/v1/history?selection=${Uri.encodeComponent(s.key)}',
              ))['quotes']
              as List)
          .map((j) => OddsQuote.fromJson(j))
          .toList();
}
