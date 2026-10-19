import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:odds_edge/domain/assistant.dart';

import 'llm.dart';
import 'providers.dart';
import 'service.dart';

Future<void> main() async {
  final env = Platform.environment;
  final mode = env['ODDS_PROVIDER'] ?? 'demo';
  final key = env['THE_ODDS_API_KEY'] ?? '';
  if (!['demo', 'the-odds-api'].contains(mode) ||
      (mode != 'demo' && key.isEmpty)) {
    stderr.writeln(
      'Set ODDS_PROVIDER to demo or the-odds-api. Real mode needs THE_ODDS_API_KEY on the server.',
    );
    exitCode = 64;
    return;
  }
  final providers = <OddsProvider>[
    mode == 'demo'
        ? DemoProvider()
        : TheOddsApiProvider(
            key,
            verifiedRuleBooks: (env['VERIFIED_NFL_RULE_BOOKS'] ?? '')
                .split(',')
                .where((s) => s.isNotEmpty)
                .toSet(),
          ),
  ];
  final seconds = int.tryParse(env['ODDS_REFRESH_SECONDS'] ?? '') ?? 60;
  final service = OddsService(
    providers,
    SnapshotStore(File('backend/data/snapshots.jsonl')),
    refreshInterval: Duration(seconds: seconds.clamp(30, 3600)),
  );
  final assistant = XaiAssistant(
    apiKey: env['XAI_API_KEY'] ?? '',
    model: xaiModel(env['XAI_MODEL']),
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8787);
  stdout.writeln(
    'Odds Edge backend: http://127.0.0.1:8787 ($mode). Loopback development server only.',
  );
  stdout.writeln(
    assistant.configured
        ? 'Research assistant: configured with model ${assistant.model}. The key stays on this server.'
        : 'Research assistant: assistant unavailable until XAI_API_KEY is set on the server.',
  );
  await for (final request in server) {
    try {
      await handleRequest(
        request,
        providerMode: mode,
        service: service,
        assistant: assistant,
      );
    } finally {
      await request.response.close();
    }
  }
}

Future<void> handleRequest(
  HttpRequest request, {
  required String providerMode,
  required OddsService service,
  required XaiAssistant assistant,
}) async {
  try {
    if (request.method == 'POST' && request.uri.path == '/v1/assistant') {
      await _writeAssistant(request, assistant);
      return;
    }
    if (request.method != 'GET') {
      request.response.statusCode = 405;
      return;
    }
    Object result;
    switch (request.uri.path) {
      case '/health':
        result = {'status': 'ok', 'mode': providerMode};
      case '/v1/odds':
        result = (await service.getBoard()).toJson();
      case '/v1/history':
        final selection = request.uri.queryParameters['selection'];
        if (selection == null) {
          throw const FormatException('selection required');
        }
        final atString = request.uri.queryParameters['at'];
        final at = atString == null ? null : DateTime.parse(atString).toUtc();
        result = {
          'origin': 'collected_since_installation',
          'quotes': (await service.store.history(
            selection,
            at: at,
          )).map((q) => q.toJson()).toList(),
        };
      default:
        request.response.statusCode = 404;
        result = {'error': 'Not found'};
    }
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.write(jsonEncode(result));
  } on FormatException {
    request.response.statusCode = 400;
    request.response.write('{"error":"Invalid request"}');
  } catch (_) {
    request.response.statusCode = 503;
    request.response.write(
      '{"error":"Odds service unavailable; no fallback prices supplied"}',
    );
  }
}

Future<void> _writeAssistant(
  HttpRequest request,
  XaiAssistant assistant,
) async {
  try {
    final payload = await _readJsonObject(request);
    final reply = await assistant.answer(payload);
    _writeJson(request, 200, reply.toJson());
  } on FormatException {
    request.response.statusCode = 400;
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"error":"Invalid request"}');
  } catch (_) {
    _writeJson(request, 200, AssistantReply.unavailable.toJson());
  }
}

Future<Map<String, dynamic>> _readJsonObject(HttpRequest request) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.timeout(const Duration(seconds: 8))) {
    bytes.add(chunk);
    if (bytes.length > 48000) throw const FormatException('Invalid request');
  }
  Object decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
  } on FormatException {
    throw const FormatException('Invalid request');
  }
  if (decoded is! Map) throw const FormatException('Invalid request');
  return Map<String, dynamic>.from(decoded);
}

void _writeJson(HttpRequest request, int status, Object body) {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.headers.set('Cache-Control', 'no-store');
  request.response.write(jsonEncode(body));
}
