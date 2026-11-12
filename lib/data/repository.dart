import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/assistant.dart';
import '../domain/odds.dart';

class BackendRepository {
  BackendRepository(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

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
    final request = http.Request('GET', _endpoint(path))
      ..followRedirects = false;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 12));
    final text = await response.stream.bytesToString().timeout(
      const Duration(seconds: 12),
    );
    if (response.statusCode != 200) {
      throw StateError('Backend unavailable (${response.statusCode}).');
    }
    return jsonDecode(text);
  }

  Future<dynamic> _post(String path, Object body) async {
    final request = http.Request('POST', _endpoint(path))
      ..followRedirects = false
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(body);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 150));
    final text = await response.stream.bytesToString().timeout(
      const Duration(seconds: 150),
    );
    if (response.statusCode != 200) {
      throw StateError('Backend unavailable (${response.statusCode}).');
    }
    return jsonDecode(text);
  }

  void close() => _client.close();

  Future<OddsBoard> board({bool refresh = false}) async =>
      OddsBoard.fromJson(await _get('/v1/odds${refresh ? '?refresh=1' : ''}'));

  /// Cached player-prop prices. Refresh may spend a few free-tier credits
  /// and is refused once the daily prop budget is used.
  Future<OddsBoard> props({bool refresh = false}) async =>
      OddsBoard.fromJson(await _get('/v1/props${refresh ? '?refresh=1' : ''}'));

  /// Cached Pinnacle spreads and totals. Refresh may spend 2 credits and
  /// is refused once the daily or monthly Pinnacle budget is used.
  Future<OddsBoard> sharp({bool refresh = false}) async =>
      OddsBoard.fromJson(await _get('/v1/sharp${refresh ? '?refresh=1' : ''}'));

  /// The Coach's Line file. This route does not call The Odds API.
  Future<Map<String, dynamic>> coachModel() async {
    final decoded = await _get('/v1/model');
    if (decoded is! Map) throw StateError('Backend unavailable.');
    return Map<String, dynamic>.from(decoded);
  }

  /// Every saved line snapshot. Reading this does not call The Odds API.
  Future<Object?> lineSlate() => _get('/v1/lines?all=1');

  /// Public ticket and money percentages, or an explicit unavailable report.
  Future<Object?> publicSplits() => _get('/v1/public-splits');

  Future<List<OddsQuote>> history(Selection selection, {DateTime? at}) async {
    final query = <String, String>{'selection': selection.key};
    if (at != null) query['at'] = at.toUtc().toIso8601String();
    final decoded = await _get(
      Uri(path: '/v1/history', queryParameters: query).toString(),
    );
    return (decoded['quotes'] as List)
        .map((quote) => OddsQuote.fromJson(quote))
        .toList();
  }

  Future<AssistantReply> assistant(AssistantRequest request) async {
    final decoded = await _post('/v1/assistant', request.toJson());
    if (decoded is! Map) throw StateError('Backend unavailable.');
    return AssistantReply.fromJson(Map<String, dynamic>.from(decoded));
  }
}
