import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:odds_edge/domain/assistant.dart';

import 'injury_feed.dart';
import 'line_history.dart';
import 'llm.dart';
import 'prop_odds.dart';
import 'providers.dart';
import 'public_splits.dart';
import 'quota.dart';
import 'service.dart';
import 'sharp_odds.dart';

Future<void> main() async {
  final env = Platform.environment;
  final OddsBackendConfig config;
  try {
    config = OddsBackendConfig.fromEnvironment(env);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  final live = config.live
      ? TheOddsApiProvider(
          config.apiKey,
          verifiedRuleBooks: config.verifiedRuleBooks,
          bookmakers: config.bookmakers,
          markets: config.markets,
        )
      : null;
  final providers = <OddsProvider>[live ?? DemoProvider()];
  final ledger = CreditLedger(
    reserve: config.creditReserve,
    file: File('backend/data/credits.json'),
  );
  if (live != null) await ledger.load();
  final lines = LineHistory(File('backend/data/line-history.jsonl'));
  final service = OddsService(
    providers,
    SnapshotStore(File(snapshotJournalPath(providers.single.id))),
    lines: lines,
    refreshInterval: config.demoRefreshInterval,
    freeTier: live == null
        ? null
        : FreeTierPlan(
            schedule: OddsRefreshSchedule(
              dailyUtc: config.dailyUtc,
              leadTimes: config.leadTimes,
              grace: config.scheduleGrace,
              coalesce: config.coalesce,
            ),
            ledger: ledger,
            estimatedCost: live.estimatedCost,
            cooldown: config.onDemandCooldown,
            eventsMaxAge: config.eventsMaxAge,
            bookmakers: live.bookmakers,
            markets: live.markets,
            dailyOnDemandCap: config.onDemandDailyCap,
            billingResetDay: config.billingResetDay,
          ),
  );
  final assistant = XaiAssistant(
    apiKey: env['XAI_API_KEY'] ?? '',
    model: xaiModel(env['XAI_MODEL']),
    reasoningEffort: env['XAI_REASONING_EFFORT'],
  );
  final props = live == null
      ? null
      : PropCoordinator(
          apiKey: config.apiKey,
          bookmakers: live.bookmakers,
          transport: live.transport,
          cache: PropCache(File('backend/data/props-snapshot.json')),
          scheduledHold: config.creditReserve,
          creditsRemaining: () => ledger.remaining,
          onCredit: (observation, {required bool oddsCall}) {
            ledger.apply(
              observation,
              at: DateTime.now().toUtc(),
              updateLastCost: oddsCall,
            );
            unawaited(ledger.save());
          },
          lines: lines,
        );
  final sharp = live == null
      ? null
      : SharpCoordinator(
          apiKey: config.apiKey,
          transport: live.transport,
          cache: SharpCache(File('backend/data/sharp-snapshot.json')),
          scheduledHold: config.creditReserve,
          creditsRemaining: () => ledger.remaining,
          onCredit: (observation, {required bool oddsCall}) {
            ledger.apply(
              observation,
              at: DateTime.now().toUtc(),
              updateLastCost: oddsCall,
            );
            unawaited(ledger.save());
          },
          lines: lines,
        );
  final injuries = InjuryFeed(cacheFile: File('backend/data/injuries.json'));
  // Injury pages are free public files. This timer does not call The Odds API.
  unawaited(injuries.refresh(kickoffs: service.knownKickoffs));
  Timer.periodic(const Duration(minutes: 1), (_) {
    unawaited(injuries.refresh(kickoffs: service.knownKickoffs));
  });
  if (live != null) {
    await service.restore();
    // The timer keeps the shared snapshot current even when nobody has the
    // app open. It only calls The Odds API when a planned slot is due.
    // Prop prices are a separate, smaller budget and are not polled here.
    // Pinnacle uses its own cache. A fresh cache does not call the network.
    unawaited(service.maintain());
    Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(service.maintain());
      unawaited(sharp!.board(DateTime.now().toUtc()));
    });
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8787);
  stdout.writeln(
    'Odds Edge backend: http://127.0.0.1:8787 (${config.mode}). Loopback development server only.',
  );
  stdout.writeln(
    assistant.configured
        ? 'Research assistant: configured with model ${assistant.model}, reasoning ${assistant.reasoningEffort}. The key stays on this server.'
        : 'Research assistant: assistant unavailable until XAI_API_KEY is set on the server.',
  );
  await for (final request in server) {
    try {
      await handleRequest(
        request,
        providerMode: config.mode,
        service: service,
        assistant: assistant,
        props: props,
        lines: lines,
        sharp: sharp,
        injuries: injuries,
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
  PropCoordinator? props,
  LineHistory? lines,
  SharpCoordinator? sharp,
  InjuryFeed? injuries,
  String modelPath = 'assets/nfl-model.json',
}) async {
  _cors(request);
  if (request.method == 'OPTIONS') {
    request.response.statusCode = 204;
    return;
  }
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
        result = {'status': 'ok', 'mode': providerMode, ...service.status()};
      case '/v1/odds':
        result = (await service.getBoard(
          onDemand: request.uri.queryParameters['refresh'] == '1',
        )).toJson();
      case '/v1/props':
        result = props == null
            ? {
                'events': <Object>[],
                'quotes': <Object>[],
                'fetchedAt': DateTime.now().toUtc().toIso8601String(),
                'demo': true,
                'notices': [
                  'Player-prop prices are requested only when the server is using The Odds API. Sample props, when the app is in demonstration mode, are already on the main odds board.',
                ],
              }
            : (await props.board(
                DateTime.now().toUtc(),
                refresh: request.uri.queryParameters['refresh'] == '1',
              )).toJson();
      case '/v1/sharp':
        result = sharp == null
            ? {
                'events': <Object>[],
                'quotes': <Object>[],
                'fetchedAt': DateTime.now().toUtc().toIso8601String(),
                'demo': true,
                'notices': [
                  'Pinnacle spreads and totals are requested only when the server is using The Odds API. Sample mode already includes a Pinnacle price on the main board.',
                ],
              }
            : (await sharp.board(
                DateTime.now().toUtc(),
                refresh: request.uri.queryParameters['refresh'] == '1',
              )).toJson();
      case '/v1/model':
        final modelFile = File(modelPath);
        if (!modelFile.existsSync()) {
          request.response.statusCode = 404;
          result = {'error': "Coach's Line file is not on this server."};
        } else {
          try {
            final decoded = jsonDecode(modelFile.readAsStringSync());
            if (decoded is! Map) {
              request.response.statusCode = 500;
              result = {'error': "Coach's Line file could not be read."};
            } else {
              result = decoded;
            }
          } on FormatException {
            request.response.statusCode = 500;
            result = {'error': "Coach's Line file could not be read."};
          }
        }
      case '/v1/injuries':
        final feed = injuries;
        result = feed == null
            ? {
                'live': false,
                'entries': <Object>[],
                'changes': <Object>[],
                'sources': <Object>[],
                'fetchedAt': DateTime.now().toUtc().toIso8601String(),
                'notice': 'Injury checks are not running on this server.',
              }
            : (await feed.current(kickoffs: service.knownKickoffs)).toJson();
      case '/v1/lines':
        final history = lines;
        final all = request.uri.queryParameters['all'] == '1';
        if (all) {
          result = {
            'origin': 'collected_since_installation',
            'events': history == null ? <Object>[] : await history.slate(),
            'notice': 'Prices this server already fetched. Reading them does not call The Odds API.',
          };
          break;
        }
        final event = request.uri.queryParameters['event'];
        if (event == null || event.isEmpty) {
          throw const FormatException('event required');
        }
        result = {
          'origin': 'collected_since_installation',
          'event': event,
          'snapshots': history == null
              ? <Object>[]
              : await history.forEvent(event),
          'notice': 'Prices this server already fetched. Reading them does not call The Odds API.',
        };
      case '/v1/public-splits':
        result = publicSplitsPayload();
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

void _cors(HttpRequest request) {
  request.response.headers.set('Access-Control-Allow-Origin', '*');
  request.response.headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, OPTIONS',
  );
  request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
}

void _writeJson(HttpRequest request, int status, Object body) {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.headers.set('Cache-Control', 'no-store');
  request.response.write(jsonEncode(body));
}
