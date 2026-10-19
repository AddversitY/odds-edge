import 'dart:convert';
import 'dart:io';

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
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8787);
  stdout.writeln(
    'Odds Edge backend: http://127.0.0.1:8787 ($mode). Loopback development server only.',
  );
  await for (final request in server) {
    try {
      if (request.method != 'GET') {
        request.response.statusCode = 405;
      } else {
        Object result;
        switch (request.uri.path) {
          case '/health':
            result = {'status': 'ok', 'mode': mode};
          case '/v1/odds':
            result = (await service.getBoard()).toJson();
          case '/v1/history':
            final selection = request.uri.queryParameters['selection'];
            if (selection == null) {
              throw const FormatException('selection required');
            }
            final atString = request.uri.queryParameters['at'];
            final at = atString == null
                ? null
                : DateTime.parse(atString).toUtc();
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
      }
    } on FormatException {
      request.response.statusCode = 400;
      request.response.write('{"error":"Invalid request"}');
    } catch (_) {
      request.response.statusCode = 503;
      request.response.write(
        '{"error":"Odds service unavailable; no fallback prices supplied"}',
      );
    } finally {
      await request.response.close();
    }
  }
}
