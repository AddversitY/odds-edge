import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/odds.dart';

import '../backend/prop_odds.dart';
import '../backend/quota.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 15);
  final chiefs = DateTime.utc(2026, 10, 27, 0, 20);
  final packers = DateTime.utc(2026, 10, 28, 0, 15);
  final later = DateTime.utc(2026, 11, 2, 18);

  UpstreamEvent event(String id, String away, String home, DateTime start) =>
      UpstreamEvent(
        id: id,
        away: away,
        home: home,
        awayName: away,
        homeName: home,
        startsAt: start,
      );

  List<UpstreamEvent> upcoming() => [
    event('later', 'BAL', 'PIT', later),
    event('soon', 'BUF', 'KC', chiefs),
    event('next', 'DET', 'GB', packers),
  ];

  test('prop markets stay inside the two-market free plan', () {
    expect(resolvePropMarkets(null), defaultPropMarkets);
    expect(
      resolvePropMarkets(['player_rush_yds', 'player_receptions']),
      ['player_rush_yds', 'player_receptions'],
    );
    expect(
      () => resolvePropMarkets([
        'player_pass_yds',
        'player_receptions',
        'player_rush_yds',
      ]),
      throwsFormatException,
    );
    expect(() => resolvePropMarkets(['player_assists']), throwsFormatException);
    expect(
      oddsRequestCost(markets: defaultPropMarkets.length, bookmakers: true),
      2,
    );
  });

  test('a refresh is refused when the cache, the day, the month, or the hold says no', () {
    final fresh = decidePropRefresh(
      now: now,
      cacheFetchedAt: now.subtract(const Duration(hours: 2)),
      creditsSpentToday: 0,
      creditsSpentThisMonth: 0,
      creditsRemaining: 400,
      scheduledHold: 50,
      upcoming: upcoming(),
    );
    expect(fresh.allowed, isFalse);
    expect(fresh.reason, contains('kept'));
    expect(fresh.credits, 4);

    final forcedOverDay = decidePropRefresh(
      now: now,
      cacheFetchedAt: now.subtract(const Duration(hours: 2)),
      creditsSpentToday: 4,
      creditsSpentThisMonth: 4,
      creditsRemaining: 400,
      scheduledHold: 50,
      upcoming: upcoming(),
      force: true,
    );
    expect(forcedOverDay.allowed, isFalse);
    expect(forcedOverDay.reason, contains('4 credits'));

    final overMonth = decidePropRefresh(
      now: now,
      cacheFetchedAt: null,
      creditsSpentToday: 0,
      creditsSpentThisMonth: 58,
      creditsRemaining: 400,
      scheduledHold: 50,
      upcoming: upcoming(),
    );
    expect(overMonth.allowed, isFalse);
    expect(overMonth.reason, contains('month'));

    final intoTheHold = decidePropRefresh(
      now: now,
      cacheFetchedAt: null,
      creditsSpentToday: 0,
      creditsSpentThisMonth: 0,
      creditsRemaining: 53,
      scheduledHold: 50,
      upcoming: upcoming(),
    );
    expect(intoTheHold.allowed, isFalse);
    expect(intoTheHold.reason, contains('regular moneyline'));

    final noGames = decidePropRefresh(
      now: now,
      cacheFetchedAt: null,
      creditsSpentToday: 0,
      creditsSpentThisMonth: 0,
      creditsRemaining: 400,
      scheduledHold: 50,
      upcoming: const [],
    );
    expect(noGames.allowed, isFalse);
    expect(noGames.credits, 0);

    final allowed = decidePropRefresh(
      now: now,
      cacheFetchedAt: now.subtract(const Duration(hours: 19)),
      creditsSpentToday: 0,
      creditsSpentThisMonth: 20,
      creditsRemaining: null,
      scheduledHold: 50,
      upcoming: upcoming(),
    );
    expect(allowed.allowed, isTrue);
    expect(allowed.credits, 4);
    expect(allowed.events.map((item) => item.id), ['soon', 'next']);
  });

  test('event ids and prop rows that cannot be read are dropped', () {
    final parsed = parsePropEvents([
      {
        'id': 'abc123',
        'away_team': 'Buffalo Bills',
        'home_team': 'Kansas City Chiefs',
        'commence_time': '2026-10-27T00:20:00Z',
      },
      {
        'id': 'has-a-dash',
        'away_team': 'Detroit Lions',
        'home_team': 'Green Bay Packers',
        'commence_time': '2026-10-28T00:15:00Z',
      },
      {
        'id': 'notateam',
        'away_team': 'Some Club',
        'home_team': 'Other Club',
        'commence_time': '2026-10-28T00:15:00Z',
      },
      {'id': 12},
    ]);
    expect(parsed, hasLength(1));
    expect(parsed.single.away, 'BUF');
    expect(parsed.single.home, 'KC');
    expect(
      parsed.single.eventId,
      'nfl:BUF:KC:2026-10-27T00:20:00.000Z',
    );

    final game = parsed.single;
    final rows = parsePropEvent(
      {
        'bookmakers': [
          {
            'key': 'draftkings',
            'title': 'DraftKings',
            'markets': [
              {
                'key': 'player_pass_yds',
                'last_update': '2026-10-26T14:00:00Z',
                'outcomes': [
                  {
                    'name': 'Over',
                    'description': 'Josh Allen',
                    'price': 1.91,
                    'point': 249.5,
                  },
                  {
                    'name': 'Under',
                    'description': 'Josh Allen',
                    'price': 1.91,
                    'point': 249.5,
                  },
                  {
                    'name': 'Over',
                    'description': ' ',
                    'price': 1.9,
                    'point': 10,
                  },
                  {
                    'name': 'Yes',
                    'description': 'Josh Allen',
                    'price': 1.5,
                    'point': 0.5,
                  },
                ],
              },
              {
                'key': 'player_assists',
                'last_update': '2026-10-26T14:00:00Z',
                'outcomes': [
                  {
                    'name': 'Over',
                    'description': 'Josh Allen',
                    'price': 1.8,
                    'point': 1.5,
                  },
                ],
              },
            ],
          },
          'not-a-book',
        ],
      },
      game,
      now,
      providerId: 'the-odds-api',
    );
    expect(rows.quotes, hasLength(2));
    expect(rows.rejected, greaterThan(0));
    final over = rows.quotes.first;
    expect(over.selection.participant, 'Josh Allen');
    expect(over.selection.outcome, 'Over');
    expect(over.selection.point, 249.5);
    expect(over.selection.eventId, game.eventId);
    expect(over.selection.rules, 'player_prop_unverified');
    expect(over.status, 'unverified');
    expect(over.bookId, 'draftkings');
    expect(over.sourceAt, DateTime.utc(2026, 10, 26, 14));
    expect(rows.quotes.every((quote) => quote.decimal == 1.91), isTrue);
  });

  test('the prop cache remembers the spend and ignores a damaged file', () async {
    final dir = await Directory.systemTemp.createTemp('prop-cache');
    addTearDown(() => dir.delete(recursive: true));
    final cache = PropCache(File('${dir.path}/props-snapshot.json'));
    final board = OddsBoard(
      events: const [],
      quotes: const [],
      fetchedAt: now,
      notices: const ['fixture'],
    );
    await cache.save(
      PropCacheRecord(
        fetchedAt: now,
        dayKey: '2026-10-26',
        daySpent: 4,
        monthKey: '2026-10',
        monthSpent: 12,
        board: board,
        notice: 'fixture',
      ),
    );
    final loaded = await cache.load();
    expect(loaded.spentToday(now), 4);
    expect(loaded.spentThisMonth(now), 12);
    expect(loaded.spentToday(now.add(const Duration(days: 1))), 0);
    expect(loaded.board!.notices, ['fixture']);
    final next = loaded.spending(now, 0);
    expect(next.daySpent, 4);

    await File('${dir.path}/props-snapshot.json').writeAsString('{nope');
    final damaged = await PropCache(File('${dir.path}/props-snapshot.json')).load();
    expect(damaged.board, isNull);
    expect(damaged.daySpent, 0);
  });

  test('ODDS_API_KEY is accepted when THE_ODDS_API_KEY is empty', () {
    final config = OddsBackendConfig.fromEnvironment({
      'ODDS_PROVIDER': 'the-odds-api',
      'ODDS_API_KEY': 'alias-key',
    });
    expect(config.apiKey, 'alias-key');
    expect(config.live, isTrue);
    final named = OddsBackendConfig.fromEnvironment({
      'ODDS_PROVIDER': 'the-odds-api',
      'THE_ODDS_API_KEY': 'named-key',
      'ODDS_API_KEY': 'alias-key',
    });
    expect(named.apiKey, 'named-key');
  });
}
