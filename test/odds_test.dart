import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/market_math.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/data/demo.dart';

import '../backend/providers.dart';
import '../backend/service.dart';

final now = DateTime.utc(2026, 10, 18, 12);
const selection = Selection(eventId: 'game', market: 'h2h', outcome: 'Bills');
OddsQuote quote(
  double price, {
  String book = 'a',
  int age = 10,
  String status = 'open',
  Selection s = selection,
}) => OddsQuote(
  selection: s,
  bookId: book,
  book: book,
  provider: 'test',
  decimal: price,
  sourceAt: now.subtract(Duration(seconds: age)),
  collectedAt: now,
  status: status,
);

class FakeProvider implements OddsProvider {
  @override
  String get id => 'test';
  int calls = 0;
  bool fail = false;
  @override
  Future<OddsBoard> fetch(DateTime time) async {
    calls++;
    if (fail) throw StateError('offline');
    return OddsBoard(events: [], quotes: [quote(2)], fetchedAt: now);
  }
}

void main() {
  test('American conversions and invalid prices', () {
    expect(americanToDecimal(150), 2.5);
    expect(americanToDecimal(-200), 1.5);
    expect(americanToDecimal(-110), closeTo(1.9090909, .000001));
    expect(impliedProbability(2.5), .4);
    expect(americanLabel(2.5), '+150');
    expect(americanLabel(1.5), '-200');
    for (final value in [0, 50, -50, double.nan, double.infinity]) {
      expect(() => americanToDecimal(value), throwsArgumentError);
    }
    expect(() => impliedProbability(1), throwsArgumentError);
  });
  test('EV accounts for pushes and rejects invalid probabilities', () {
    expect(expectedValue(2, .55), closeTo(.1, 1e-10));
    expect(expectedValue(2, .45, push: .1), closeTo(0, 1e-10));
    expect(expectedValue(2, 0), -1);
    expect(() => expectedValue(2, .8, push: .3), throwsArgumentError);
    expect(() => expectedValue(2, double.nan), throwsArgumentError);
  });
  test(
    'Matching separates lines, periods, participants, rules, events and sides',
    () {
      const base = Selection(
        eventId: 'game',
        market: 'spreads',
        outcome: 'Bills',
        point: -2.5,
      );
      final variants = [
        const Selection(
          eventId: 'game',
          market: 'spreads',
          outcome: 'Bills',
          point: -3.5,
        ),
        const Selection(
          eventId: 'game',
          market: 'spreads',
          outcome: 'Bills',
          point: -2.5,
          period: 'half',
        ),
        const Selection(
          eventId: 'game',
          market: 'spreads',
          outcome: 'Bills',
          point: -2.5,
          rules: 'regulation',
        ),
        const Selection(
          eventId: 'other',
          market: 'spreads',
          outcome: 'Bills',
          point: -2.5,
        ),
        const Selection(
          eventId: 'game',
          market: 'spreads',
          outcome: 'Chiefs',
          point: -2.5,
        ),
        const Selection(
          eventId: 'game',
          market: 'spreads',
          outcome: 'Bills',
          point: -2.5,
          participant: 'player',
        ),
      ];
      for (final s in variants) {
        expect(comparableQuotes([quote(3, s: s)], base), isEmpty);
      }
    },
  );
  test(
    'Best excludes stale, suspended, future, unverified and filtered books',
    () {
      final quotes = [
        quote(2.1),
        quote(3, book: 'old', age: 121),
        quote(4, book: 'suspended', status: 'suspended'),
        quote(5, book: 'future', age: -60),
        quote(6, book: 'unknown', status: 'unverified'),
        quote(2.2, book: 'b'),
      ];
      expect(bestQuote(quotes, selection, now)?.bookId, 'b');
      expect(bestQuote(quotes, selection, now, books: {'a'})?.decimal, 2.1);
      expect(bestQuote(quotes, selection, now, books: {}), isNull);
      expect(
        bestQuote([quote(3, age: 21)], selection, now, inPlay: true),
        isNull,
      );
      expect(quote(2, age: 120).freshness(now), 'current');
      expect(quote(2, age: 20).freshness(now, inPlay: true), 'current');
    },
  );
  test('Latest observation wins; never cherry-pick an older higher price', () {
    expect(
      bestQuote([quote(3, age: 50), quote(2, age: 5)], selection, now)?.decimal,
      2,
    );
    expect(
      bestQuote(
        [quote(3, age: 50), quote(2, age: 1, status: 'suspended')],
        selection,
        now,
      ),
      isNull,
    );
    expect(
      bestQuote([quote(2), quote(2, book: 'b')], selection, now),
      isNotNull,
    );
  });
  test('Roundtrip preserves timestamps, identity and demo provenance', () {
    final board = demoBoard(now);
    final decoded = OddsBoard.fromJson(board.toJson());
    expect(decoded.quotes.length, board.quotes.length);
    expect(decoded.quotes.first.demo, isTrue);
    expect(decoded.quotes.first.sourceAt, board.quotes.first.sourceAt);
    expect(
      decoded.quotes.first.selection.key,
      board.quotes.first.selection.key,
    );
  });

  List<Map<String, dynamic>> fixture({String home = 'Kansas City Chiefs'}) => [
    {
      'home_team': home,
      'away_team': 'Buffalo Bills',
      'commence_time': '2026-10-19T17:00:00Z',
      'bookmakers': [
        {
          'key': 'fanduel',
          'title': 'FanDuel',
          'markets': [
            {
              'key': 'spreads',
              'last_update': '2026-10-18T11:59:50Z',
              'outcomes': [
                {'name': 'Buffalo Bills', 'price': 1.91, 'point': 3.5},
                {'name': home, 'price': 1.91, 'point': -3.5},
              ],
            },
          ],
        },
      ],
    },
  ];
  test('Adapter validates identity and settlement rules before comparing', () {
    final provider = TheOddsApiProvider('test', verifiedRuleBooks: {'fanduel'});
    final board = provider.parse(fixture(), now);
    expect(board.quotes.length, 2);
    expect(board.quotes.first.selection.point, 3.5);
    expect(board.quotes.first.freshness(now), 'current');
    expect(provider.parse(fixture(home: 'Unknown'), now).quotes, isEmpty);
    expect(board.quotes.first.status, 'open');
    expect(board.quotes.first.selection.rules, 'includes_overtime_push_on_tie');
    final unverified = TheOddsApiProvider('test').parse(fixture(), now);
    expect(unverified.quotes.first.status, 'unverified');
    expect(unverified.quotes.first.selection.rules, 'unverified');
    expect(
      bestQuote(unverified.quotes, unverified.quotes.first.selection, now),
      isNull,
    );
    expect(
      unverified.notices.join('\n'),
      contains('not independently verified'),
    );
    final priced = scanMarkets(unverified, now);
    expect(priced.markets, isNotEmpty);
    expect(priced.markets.single.rulesUnverified, isTrue);
    expect(priced.emptyReason, isNull);
    expect(canonicalTeam('BUF'), 'BUF');
    expect(canonicalTeam(' buffalo bills '), 'BUF');
    expect(
      provider.parse(fixture(home: 'KC'), now).events.first.id,
      board.events.first.id,
    );
    expect(
      provider.parse(fixture(home: 'KC'), now).quotes.last.selection.key,
      board.quotes.last.selection.key,
    );
  });
  test('Cache coalesces calls, history survives restart, replay excludes later collection', () async {
    final dir = await Directory.systemTemp.createTemp('odds-edge');
    addTearDown(() => dir.delete(recursive: true));
    final store = SnapshotStore(File('${dir.path}/history.jsonl'));
    final provider = FakeProvider();
    final service = OddsService([provider], store);
    final result = await Future.wait([service.getBoard(), service.getBoard()]);
    expect(provider.calls, 1);
    expect(result.first.quotes.length, 1);
    expect(
      await store.history(
        selection.key,
        at: now.subtract(const Duration(seconds: 1)),
      ),
      isEmpty,
    );
    expect(
      (await SnapshotStore(store.file).history(selection.key, at: now)).length,
      1,
    );
  });
  test('Outage preserves observations but removes eligibility', () async {
    final dir = await Directory.systemTemp.createTemp('odds-edge');
    addTearDown(() => dir.delete(recursive: true));
    final provider = FakeProvider();
    final service = OddsService(
      [provider],
      SnapshotStore(File('${dir.path}/history.jsonl')),
      refreshInterval: Duration.zero,
    );
    await service.getBoard();
    provider.fail = true;
    final result = await service.getBoard();
    expect(result.quotes.first.collectedAt, now);
    expect(result.quotes.first.status, 'provider unavailable');
    expect(bestQuote(result.quotes, selection, now), isNull);
    expect(result.notices.join(), contains('unavailable'));
  });
}
