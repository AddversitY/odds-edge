import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'providers.dart';
import 'quota.dart';
import 'service.dart';

Future<void> main() async {
  final OddsBackendConfig config;
  try {
    config = OddsBackendConfig.fromEnvironment(Platform.environment);
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
  final service = OddsService(
    providers,
    SnapshotStore(File(snapshotJournalPath(providers.single.id))),
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
  if (live != null) {
    await service.restore();
    // The timer keeps the shared snapshot current even when nobody has the
    // app open. It only calls The Odds API when a planned slot is due.
    unawaited(service.maintain());
    Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(service.maintain());
    });
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8787);
  stdout.writeln(
    'Odds Edge backend: http://127.0.0.1:8787 (${config.mode}). Loopback development server only.',
  );
  await for (final request in server) {
    try {
      if (request.method != 'GET') {
        request.response.statusCode = 405;
      } else {
        Object result;
        switch (request.uri.path) {
          case '/health':
            result = {'status': 'ok', 'mode': config.mode, ...service.status()};
          case '/v1/odds':
            result = (await service.getBoard(
              onDemand: request.uri.queryParameters['refresh'] == '1',
            )).toJson();
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
