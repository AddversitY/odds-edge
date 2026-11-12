import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/odds.dart';

import '../backend/line_history.dart';
import '../backend/llm.dart';
import '../backend/prop_odds.dart';
import '../backend/providers.dart';
import '../backend/server.dart';
import '../backend/service.dart';

void main() {
  test(
    'a game keeps each fetched number, in order, and ignores a torn line',
    () async {
      final dir = await Directory.systemTemp.createTemp('line-history');
      addTearDown(() => dir.delete(recursive: true));
      final history = LineHistory(
        File('${dir.path}/lines.jsonl'),
        compactEvery: 100,
      );
      final earlier = DateTime.utc(2026, 11, 10, 15);
      final later = DateTime.utc(2026, 11, 12, 15);
      await history.record(
        _board(
          id: 'bufkc',
          at: earlier,
          point: -3.5,
          home: 'Kansas City Chiefs',
        ),
        kind: 'lines',
      );
      await history.record(
        _board(id: 'bufkc', at: later, point: -6, home: 'Kansas City Chiefs'),
        kind: 'lines',
      );
      await history.record(
        _board(id: 'other', at: later, point: -1, home: 'Green Bay Packers'),
        kind: 'lines',
      );
      await history.record(_propBoard(later), kind: 'props');
      await history.file.writeAsString('{"at":', mode: FileMode.append);

      final shots = await history.forEvent('bufkc');
      expect(shots, hasLength(2));
      expect(shots.first['prices'], hasLength(1));
      expect(shots.first['at'], earlier.toIso8601String());
      expect(shots.first['kind'], 'lines');
      expect(shots.first['home'], 'Kansas City Chiefs');
      expect(shots.first['away'], 'Buffalo Bills');
      expect(_point(shots.first, 'spreads'), -3.5);
      expect(_point(shots.last, 'spreads'), -6);
      expect(_book(shots.first), 'fanduel');

      final props = await history.forEvent('prop-game');
      expect(props, hasLength(1));
      expect(props.single['kind'], 'props');
      final price = (props.single['prices'] as List).single as Map;
      expect(price['player'], 'Josh Allen');
      expect(price['market'], 'player_pass_yds');
      expect(price['outcome'], 'Over');
      expect(price['point'], 249.5);

      expect(await history.forEvent('missing'), isEmpty);
    },
  );

  test('compaction drops old snapshots and stays within the caps', () async {
    final dir = await Directory.systemTemp.createTemp('line-history-cap');
    addTearDown(() => dir.delete(recursive: true));
    final now = DateTime.utc(2026, 11, 12, 18);
    final history = LineHistory(
      File('${dir.path}/lines.jsonl'),
      retain: const Duration(days: 10),
      maxPerEvent: 2,
      maxLines: 3,
      maxBytes: 2 * 1024 * 1024,
      compactEvery: 1,
      clock: () => now,
    );
    await history.record(
      _board(id: 'old', at: now.subtract(const Duration(days: 30)), point: -2),
      kind: 'lines',
    );
    expect(await history.forEvent('old'), isEmpty);

    final points = [-3.0, -3.5, -4.0, -4.5];
    for (var i = 0; i < points.length; i++) {
      await history.record(
        _board(
          id: 'capped',
          at: now.subtract(Duration(hours: 8 - i)),
          point: points[i],
        ),
        kind: 'lines',
      );
    }
    final capped = await history.forEvent('capped');
    expect(capped, hasLength(2));
    expect(_point(capped.first, 'spreads'), -4);
    expect(_point(capped.last, 'spreads'), -4.5);

    await history.record(
      _board(id: 'other', at: now.subtract(const Duration(hours: 1)), point: 1),
      kind: 'lines',
    );
    await history.record(
      _board(id: 'other', at: now, point: 2),
      kind: 'lines',
    );
    final lines = await history.file.readAsLines();
    expect(lines.where((line) => line.isNotEmpty), hasLength(3));
    expect(await history.forEvent('capped'), hasLength(1));
    expect(await history.forEvent('other'), hasLength(2));

    final byteFile = File('${dir.path}/byte.jsonl');
    final loose = LineHistory(byteFile, compactEvery: 100, clock: () => now);
    await loose.record(
      _board(id: 'byte', at: now.subtract(const Duration(hours: 2)), point: -3),
      kind: 'lines',
    );
    final oneLine = await byteFile.length();
    final tight = LineHistory(
      byteFile,
      maxBytes: oneLine + 8,
      maxLines: 50,
      maxPerEvent: 50,
      compactEvery: 100,
      clock: () => now,
    );
    await tight.record(
      _board(id: 'byte', at: now, point: -7),
      kind: 'lines',
    );
    expect(await byteFile.length(), lessThanOrEqualTo(oneLine + 8));
    final kept = await tight.forEvent('byte');
    expect(kept, hasLength(1));
    expect(_point(kept.single, 'spreads'), -7);
  });

  test('the odds service journals a fetch and not a later cache hit', () async {
    final dir = await Directory.systemTemp.createTemp('line-history-service');
    addTearDown(() => dir.delete(recursive: true));
    final history = LineHistory(
      File('${dir.path}/lines.jsonl'),
      compactEvery: 100,
    );
    final provider = _CountingProvider();
    final service = OddsService(
      [provider],
      SnapshotStore(File('${dir.path}/snapshots.jsonl')),
      lines: history,
      refreshInterval: const Duration(hours: 1),
    );
    await service.getBoard();
    await service.getBoard();
    expect(provider.calls, 1);
    final shots = await history.forEvent('game');
    expect(shots, hasLength(1));
    expect(shots.single['kind'], 'lines');
    expect(_point(shots.single, 'h2h'), isNull);
    expect((shots.single['prices'] as List).single['decimal'], 2);
  });

  test(
    'a prop fetch is journaled once and a cached read does not fetch again',
    () async {
      final dir = await Directory.systemTemp.createTemp('line-history-props');
      addTearDown(() => dir.delete(recursive: true));
      final history = LineHistory(
        File('${dir.path}/lines.jsonl'),
        compactEvery: 100,
      );
      var calls = 0;
      final now = DateTime.utc(2026, 11, 12, 15);
      final kick = now.add(const Duration(days: 1));
      final transport = _ScriptedTransport((uri) {
        calls++;
        if (uri.path.endsWith('/odds')) {
          return OddsApiResponse(
            statusCode: 200,
            body: jsonEncode({
              'bookmakers': [
                {
                  'key': 'fanduel',
                  'title': 'FanDuel',
                  'markets': [
                    {
                      'key': 'player_pass_yds',
                      'last_update': now.toIso8601String(),
                      'outcomes': [
                        {
                          'name': 'Over',
                          'description': 'Josh Allen',
                          'point': 249.5,
                          'price': 1.91,
                        },
                      ],
                    },
                  ],
                },
              ],
            }),
            headers: {'x-requests-last': '2'},
          );
        }
        return OddsApiResponse(
          statusCode: 200,
          body: jsonEncode([
            {
              'id': 'propgame1',
              'away_team': 'Buffalo Bills',
              'home_team': 'Kansas City Chiefs',
              'commence_time': kick.toIso8601String(),
            },
          ]),
          headers: {'x-requests-last': '0'},
        );
      });
      final props = PropCoordinator(
        apiKey: 'test-key-not-real',
        bookmakers: const ['fanduel'],
        transport: transport,
        cache: PropCache(File('${dir.path}/props.json')),
        lines: history,
        creditsRemaining: () => 500,
      );
      final board = await props.board(now, refresh: true);
      expect(board.quotes, isNotEmpty);
      final again = await props.board(now.add(const Duration(minutes: 5)));
      expect(again.quotes, isNotEmpty);
      expect(calls, 2);
      final shots = await history.forEvent(
        'nfl:BUF:KC:${kick.toIso8601String()}',
      );
      expect(shots, hasLength(1));
      expect(shots.single['kind'], 'props');
      expect((shots.single['prices'] as List).single['player'], 'Josh Allen');
      expect(shots.single.toString().contains('test-key-not-real'), isFalse);
    },
  );

  test('GET /v1/lines reads the journal and does not fetch odds', () async {
    final dir = await Directory.systemTemp.createTemp('line-history-route');
    addTearDown(() => dir.delete(recursive: true));
    final history = LineHistory(
      File('${dir.path}/lines.jsonl'),
      compactEvery: 100,
    );
    await history.record(
      _board(id: 'game', at: DateTime.utc(2026, 11, 12, 15), point: -3.5),
      kind: 'lines',
    );
    final provider = _CountingProvider();
    final service = OddsService([
      provider,
    ], SnapshotStore(File('${dir.path}/snapshots.jsonl')));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      handleRequest(
        request,
        providerMode: 'demo',
        service: service,
        assistant: XaiAssistant(apiKey: ''),
        lines: history,
      ).whenComplete(() => request.response.close());
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final missing = await _get(base.replace(path: '/v1/lines'));
    expect(missing.status, 400);
    final found = await _get(
      base.replace(path: '/v1/lines', queryParameters: {'event': 'game'}),
    );
    expect(found.status, 200);
    final body = jsonDecode(found.body) as Map<String, dynamic>;
    expect(body['event'], 'game');
    expect(body['notice'].toString().contains('does not call'), isTrue);
    final snapshots = body['snapshots'] as List;
    expect(snapshots, hasLength(1));
    expect(_point(snapshots.single as Map, 'spreads'), -3.5);
    expect(provider.calls, 0);

    final slate = await _get(
      base.replace(path: '/v1/lines', queryParameters: {'all': '1'}),
    );
    expect(slate.status, 200);
    final slateBody = jsonDecode(slate.body) as Map<String, dynamic>;
    final events = slateBody['events'] as List;
    expect(events, hasLength(1));
    expect(events.single['id'], 'game');
    expect(provider.calls, 0);

    final splits = await _get(base.replace(path: '/v1/public-splits'));
    expect(splits.status, 200);
    final splitsBody = jsonDecode(splits.body) as Map<String, dynamic>;
    expect(splitsBody['available'], isFalse);
    expect(splitsBody['games'], isEmpty);
    expect(splitsBody['notice'].toString(), contains('not available'));
    expect(splitsBody.toString(), isNot(contains('% of bets')));
    expect(provider.calls, 0);
  });

  test('the same snapshot is not written twice', () async {
    final dir = await Directory.systemTemp.createTemp('line-history-dedupe');
    addTearDown(() => dir.delete(recursive: true));
    final history = LineHistory(
      File('${dir.path}/lines.jsonl'),
      compactEvery: 100,
    );
    final at = DateTime.utc(2026, 11, 12, 15);
    final board = _board(id: 'game', at: at, point: -3);
    await history.record(board, kind: 'lines');
    await history.record(board, kind: 'lines');
    expect(await history.forEvent('game'), hasLength(1));
  });
}

OddsBoard _board({
  required String id,
  required DateTime at,
  required double point,
  String away = 'Buffalo Bills',
  String home = 'Kansas City Chiefs',
}) {
  return OddsBoard(
    events: [SportEvent(id, away, home, at.add(const Duration(days: 2)))],
    quotes: [
      _quote(id: id, market: 'spreads', outcome: home, point: point, at: at),
      _quote(id: id, market: 'spreads', outcome: home, point: point, at: at),
    ],
    fetchedAt: at,
  );
}

OddsBoard _propBoard(DateTime at) {
  return OddsBoard(
    events: [
      SportEvent(
        'prop-game',
        'Buffalo Bills',
        'Kansas City Chiefs',
        at.add(const Duration(days: 1)),
      ),
    ],
    quotes: [
      OddsQuote(
        selection: const Selection(
          eventId: 'prop-game',
          market: 'player_pass_yds',
          outcome: 'Over',
          point: 249.5,
          participant: 'Josh Allen',
        ),
        bookId: 'fanduel',
        book: 'FanDuel',
        provider: 'the-odds-api',
        decimal: 1.91,
        sourceAt: at,
        collectedAt: at,
      ),
    ],
    fetchedAt: at,
  );
}

OddsQuote _quote({
  required String id,
  required String market,
  required String outcome,
  required double? point,
  required DateTime at,
}) {
  return OddsQuote(
    selection: Selection(
      eventId: id,
      market: market,
      outcome: outcome,
      point: point,
    ),
    bookId: 'fanduel',
    book: 'FanDuel',
    provider: 'demonstration',
    decimal: 1.91,
    sourceAt: at,
    collectedAt: at,
  );
}

double? _point(Map snapshot, String market) {
  final prices = snapshot['prices'] as List;
  final match = prices.cast<Map>().where((price) => price['market'] == market);
  if (match.isEmpty) return null;
  final point = match.first['point'];
  return point is num ? point.toDouble() : null;
}

String _book(Map snapshot) =>
    ((snapshot['prices'] as List).first as Map)['bookId'] as String;

class _CountingProvider implements OddsProvider {
  int calls = 0;

  @override
  String get id => 'count';

  @override
  Future<OddsBoard> fetch(DateTime time) async {
    calls++;
    return OddsBoard(
      events: [SportEvent('game', 'Buffalo Bills', 'Kansas City Chiefs', time)],
      quotes: [
        OddsQuote(
          selection: const Selection(
            eventId: 'game',
            market: 'h2h',
            outcome: 'Kansas City Chiefs',
          ),
          bookId: 'a',
          book: 'A',
          provider: id,
          decimal: 2,
          sourceAt: time,
          collectedAt: time,
        ),
      ],
      fetchedAt: time,
    );
  }
}

class _ScriptedTransport implements OddsApiTransport {
  _ScriptedTransport(this.onGet);
  final OddsApiResponse Function(Uri uri) onGet;

  @override
  Future<OddsApiResponse> get(Uri uri) async => onGet(uri);
}

Future<({int status, String body})> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}
