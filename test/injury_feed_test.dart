import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/odds.dart';

import '../backend/injury_feed.dart';
import '../backend/llm.dart';
import '../backend/providers.dart';
import '../backend/server.dart';
import '../backend/service.dart';

void main() {
  const espn = '''
{"injuries":[{"displayName":"Buffalo Bills","injuries":[
  {"status":"Out","date":"2026-11-12T17:00:00Z","athlete":{
    "displayName":"Star Receiver","position":{"abbreviation":"WR"},
    "team":{"abbreviation":"BUF"}},"details":{"type":"Ankle"}}
]}]}
''';
  const nfl = '''
<h1>WEEK 10</h1>
<div class="d3-o-section-sub-title"><span>Bills</span></div>
<table><tr><td>Star Receiver</td><td>WR</td><td>Ankle</td><td>DNP</td><td>Out</td></tr></table>
''';
  const verse = '''
season,season_type,week,team,position,full_name,report_status,report_primary_injury
2026,REG,10,BUF,WR,Star Receiver,Out,Ankle
''';

  test('the injury check never calls the odds host', () async {
    await expectLater(
      fetchInjuryBytes(Uri.parse('https://api.the-odds-api.com/v4/sports')),
      throwsA(isA<StateError>()),
    );
  });

  test('a fresh cache is not downloaded again', () async {
    final dir = await Directory.systemTemp.createTemp('injury-feed');
    addTearDown(() => dir.delete(recursive: true));
    final calls = <Uri>[];
    var now = DateTime.utc(2026, 11, 12, 15);
    Future<InjuryBytes> transport(Uri uri) async {
      calls.add(uri);
      final body = switch (uri.host) {
        'site.api.espn.com' => espn,
        'www.nfl.com' => nfl,
        'github.com' => verse,
        _ => throw StateError('Unexpected host ${uri.host}'),
      };
      return InjuryBytes(status: 200, body: body);
    }

    final feed = InjuryFeed(
      transport: transport,
      cacheFile: File('${dir.path}/injuries.json'),
      clock: () => now,
    );
    await feed.refresh();
    expect(calls, hasLength(3));
    expect(calls.map((uri) => uri.host).toSet(), injurySourceHosts);
    expect(feed.report!.entries.single.player, 'Star Receiver');
    expect(feed.report!.entries.single.agrees, contains('NFL.com'));
    expect(feed.report!.live, isTrue);

    final before = calls.length;
    await feed.refresh();
    expect(calls, hasLength(before));

    now = now.add(const Duration(minutes: 3));
    await feed.refresh(kickoffs: [now.add(const Duration(hours: 1))]);
    expect(calls, hasLength(before + 1));
    expect(calls.last.host, 'site.api.espn.com');

    final again = InjuryFeed(
      transport: transport,
      cacheFile: File('${dir.path}/injuries.json'),
      clock: () => now,
    );
    await again.refresh(kickoffs: [now.add(const Duration(hours: 1))]);
    expect(again.report!.entries.single.player, 'Star Receiver');
    expect(calls, hasLength(before + 1));
  });

  test('a failed check keeps the last good list', () async {
    final dir = await Directory.systemTemp.createTemp('injury-feed-fail');
    addTearDown(() => dir.delete(recursive: true));
    var fail = false;
    var now = DateTime.utc(2026, 11, 12, 15);
    final feed = InjuryFeed(
      transport: (uri) async {
        if (fail && uri.host == 'site.api.espn.com') {
          return const InjuryBytes(status: 500, body: '');
        }
        final body = switch (uri.host) {
          'site.api.espn.com' => espn,
          'www.nfl.com' => nfl,
          'github.com' => verse,
          _ => throw StateError(uri.host),
        };
        return InjuryBytes(status: 200, body: body);
      },
      cacheFile: File('${dir.path}/injuries.json'),
      clock: () => now,
    );
    await feed.refresh();
    fail = true;
    now = now.add(const Duration(minutes: 10));
    await feed.refresh();
    expect(feed.report!.entries.single.player, 'Star Receiver');
    expect(feed.report!.notice, contains('ESPN answered 500'));
  });

  test('GET /v1/injuries does not ask the odds provider', () async {
    final dir = await Directory.systemTemp.createTemp('injury-route');
    addTearDown(() => dir.delete(recursive: true));
    final service = OddsService([
      _OddsGuard(),
    ], SnapshotStore(File('${dir.path}/snapshots.jsonl')));
    final feed = InjuryFeed(
      transport: (uri) async => InjuryBytes(
        status: 200,
        body: switch (uri.host) {
          'site.api.espn.com' => espn,
          'www.nfl.com' => nfl,
          'github.com' => verse,
          _ => throw StateError(uri.host),
        },
      ),
      cacheFile: File('${dir.path}/injuries.json'),
      clock: () => DateTime.utc(2026, 11, 12, 15),
    );
    await feed.refresh();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      handleRequest(
        request,
        providerMode: 'demo',
        service: service,
        assistant: XaiAssistant(apiKey: ''),
        injuries: feed,
      ).whenComplete(() => request.response.close());
    });
    final response = await HttpClient()
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/v1/injuries'))
        .then((request) => request.close());
    final body = jsonDecode(await utf8.decoder.bind(response).join());
    expect(response.statusCode, 200);
    expect(body['live'], isTrue);
    expect(body['entries'], hasLength(1));
    expect(body['entries'][0]['sourceLabel'], 'ESPN, unofficial');
  });
}

class _OddsGuard implements OddsProvider {
  @override
  String get id => 'guard';

  @override
  Future<OddsBoard> fetch(DateTime now) {
    throw StateError('The injury route called the odds provider.');
  }
}
