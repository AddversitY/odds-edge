import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../backend/providers.dart';
import '../backend/sharp_odds.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 15);
  const secret = 'test-odds-key-do-not-print';

  test(
    'the budget blocks a pull that is fresh, over the caps, or into the hold',
    () {
      final fresh = decideSharpRefresh(
        now: now,
        cacheFetchedAt: now.subtract(const Duration(hours: 2)),
        creditsSpentToday: 0,
        creditsSpentThisMonth: 0,
        pullsToday: 0,
        pullsThisMonth: 0,
        creditsRemaining: 200,
        scheduledHold: 50,
      );
      expect(fresh.allowed, isFalse);
      expect(fresh.reason, contains('kept'));

      final day = decideSharpRefresh(
        now: now,
        cacheFetchedAt: now.subtract(const Duration(hours: 9)),
        creditsSpentToday: 6,
        creditsSpentThisMonth: 6,
        pullsToday: 3,
        pullsThisMonth: 3,
        creditsRemaining: 200,
        scheduledHold: 50,
        force: true,
      );
      expect(day.allowed, isFalse);
      expect(day.reason, contains('Today'));

      final month = decideSharpRefresh(
        now: now,
        cacheFetchedAt: null,
        creditsSpentToday: 0,
        creditsSpentThisMonth: 36,
        pullsToday: 0,
        pullsThisMonth: 18,
        creditsRemaining: 200,
        scheduledHold: 50,
      );
      expect(month.allowed, isFalse);
      expect(month.reason, contains('month'));

      final hold = decideSharpRefresh(
        now: now,
        cacheFetchedAt: null,
        creditsSpentToday: 0,
        creditsSpentThisMonth: 0,
        pullsToday: 0,
        pullsThisMonth: 0,
        creditsRemaining: 51,
        scheduledHold: 50,
      );
      expect(hold.allowed, isFalse);
      expect(hold.reason, contains('regular snapshots'));
    },
  );

  test('a missing charge still counts as a full two-credit pull', () {
    expect(sharpCreditsCharged(null), 2);
    expect(sharpCreditsCharged(0), 2);
    expect(sharpCreditsCharged(3), 3);
  });

  test('only pinnacle spreads and totals are kept', () {
    final parsed = parseSharpOdds([
      {
        'home_team': 'Kansas City Chiefs',
        'away_team': 'Buffalo Bills',
        'commence_time': '2026-11-13T00:20:00Z',
        'bookmakers': [
          {
            'key': 'pinnacle',
            'title': 'Pinnacle',
            'markets': [
              {
                'key': 'spreads',
                'last_update': '2026-11-12T15:00:00Z',
                'outcomes': [
                  {'name': 'Kansas City Chiefs', 'point': -3.5, 'price': 1.95},
                  {'name': 'Buffalo Bills', 'point': 3.5, 'price': 1.91},
                ],
              },
              {
                'key': 'h2h',
                'last_update': '2026-11-12T15:00:00Z',
                'outcomes': [
                  {'name': 'Kansas City Chiefs', 'price': 1.7},
                ],
              },
            ],
          },
          {
            'key': 'draftkings',
            'title': 'DraftKings',
            'markets': [
              {
                'key': 'spreads',
                'last_update': '2026-11-12T15:00:00Z',
                'outcomes': [
                  {'name': 'Kansas City Chiefs', 'point': -3.5, 'price': 1.91},
                ],
              },
            ],
          },
        ],
      },
    ], now);
    expect(parsed.quotes, hasLength(2));
    expect(parsed.quotes.every((quote) => quote.bookId == 'pinnacle'), isTrue);
    expect(
      parsed.quotes.every((quote) => quote.selection.market == 'spreads'),
      isTrue,
    );
    expect(
      parsed.quotes.first.selection.eventId,
      'nfl:BUF:KC:2026-11-13T00:20:00.000Z',
    );
    expect(parsed.rejected, greaterThan(0));
  });

  test(
    'the cache stops a second pull and the key stays out of the result',
    () async {
      final dir = await Directory.systemTemp.createTemp('sharp-odds');
      addTearDown(() => dir.delete(recursive: true));
      final transport = _Transport(
        statusCode: 200,
        body: jsonEncode(_body()),
        headers: {'x-requests-last': '0'},
      );
      final sharp = SharpCoordinator(
        apiKey: secret,
        transport: transport,
        cache: SharpCache(File('${dir.path}/sharp-snapshot.json')),
        creditsRemaining: () => 200,
        scheduledHold: 50,
      );
      final first = await sharp.board(now);
      expect(transport.calls, 1);
      expect(transport.last!.queryParameters['regions'], 'eu');
      expect(transport.last!.queryParameters['markets'], 'spreads,totals');
      expect(transport.last!.queryParameters['bookmakers'], 'pinnacle');
      expect(first.quotes, isNotEmpty);
      expect(jsonEncode(first.toJson()), isNot(contains(secret)));

      final second = await sharp.board(now.add(const Duration(minutes: 30)));
      expect(transport.calls, 1);
      expect(second.quotes, isNotEmpty);

      final saved = jsonDecode(
        await File('${dir.path}/sharp-snapshot.json').readAsString(),
      );
      expect(saved['daySpent'], 2);
      expect(saved.toString(), isNot(contains(secret)));
    },
  );

  test('a failed request does not print the key', () async {
    final dir = await Directory.systemTemp.createTemp('sharp-odds-fail');
    addTearDown(() => dir.delete(recursive: true));
    final transport = _Transport(throwWithKey: secret);
    final sharp = SharpCoordinator(
      apiKey: secret,
      transport: transport,
      cache: SharpCache(File('${dir.path}/sharp-snapshot.json')),
      creditsRemaining: () => 200,
      scheduledHold: 50,
    );
    final board = await sharp.board(now);
    expect(board.quotes, isEmpty);
    expect(board.notices.join(' '), isNot(contains(secret)));
    expect(transport.calls, 1);
  });
}

List<Map<String, Object>> _body() => [
  {
    'home_team': 'Kansas City Chiefs',
    'away_team': 'Buffalo Bills',
    'commence_time': '2026-11-13T00:20:00Z',
    'bookmakers': [
      {
        'key': 'pinnacle',
        'title': 'Pinnacle',
        'markets': [
          {
            'key': 'spreads',
            'last_update': '2026-11-12T15:00:00Z',
            'outcomes': [
              {'name': 'Kansas City Chiefs', 'point': -3.5, 'price': 1.91},
              {'name': 'Buffalo Bills', 'point': 3.5, 'price': 1.91},
            ],
          },
          {
            'key': 'totals',
            'last_update': '2026-11-12T15:00:00Z',
            'outcomes': [
              {'name': 'Over', 'point': 47.5, 'price': 1.90},
              {'name': 'Under', 'point': 47.5, 'price': 1.90},
            ],
          },
        ],
      },
    ],
  },
];

class _Transport implements OddsApiTransport {
  _Transport({
    this.statusCode = 200,
    this.body = '[]',
    this.headers = const {},
    this.throwWithKey,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final String? throwWithKey;
  int calls = 0;
  Uri? last;

  @override
  Future<OddsApiResponse> get(Uri uri) async {
    calls++;
    last = uri;
    final key = throwWithKey;
    if (key != null) {
      throw StateError('request failed for $key');
    }
    return OddsApiResponse(
      statusCode: statusCode,
      body: body,
      headers: headers,
    );
  }
}
