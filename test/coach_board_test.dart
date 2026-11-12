import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/data/research_store.dart';
import 'package:odds_edge/domain/bets.dart';
import 'package:odds_edge/domain/coach_board.dart';
import 'package:odds_edge/domain/market_math.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/saved_play.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 18);

  OddsQuote quote({
    required String eventId,
    required String market,
    required String outcome,
    required String bookId,
    required double decimal,
    double? point,
    String participant = '',
    String book = 'Book',
  }) => OddsQuote(
    selection: Selection(
      eventId: eventId,
      market: market,
      outcome: outcome,
      point: point,
      participant: participant,
    ),
    bookId: bookId,
    book: book,
    provider: 'fixture',
    decimal: decimal,
    sourceAt: now.subtract(const Duration(minutes: 12)),
    collectedAt: now,
  );

  test(
    'prop cards use the best open price and leave a one-sided edge blank',
    () {
      final board = demoBoard(now);
      final cards = propCards(board, now);
      final over = cards.singleWhere(
        (card) =>
            card.player == 'Josh Allen' &&
            card.lineSide.name == 'over' &&
            card.line == 249.5,
      );
      expect(over.marketLabel, 'Passing yards');
      expect(over.line, 249.5);
      expect(over.best!.bookId, 'hardrock');
      expect(over.implied, closeTo(1 / over.best!.decimal, 1e-12));
      expect(over.fairProbability, isNotNull);
      expect(over.expectedProfit, isNotNull);
      expect(over.bookRows.first.quote.decimal, over.best!.decimal);
      expect(
        over.bookRows.map((row) => row.quote.decimal).toList(),
        orderedEquals(
          [...over.bookRows.map((row) => row.quote.decimal)]
            ..sort((a, b) => b.compareTo(a)),
        ),
      );

      final oneSided = OddsBoard(
        events: [
          NflEvent(
            'g',
            'Buffalo Bills',
            'Kansas City Chiefs',
            now.add(const Duration(days: 1)),
          ),
        ],
        quotes: [
          quote(
            eventId: 'g',
            market: 'player_pass_yds',
            outcome: 'Over',
            bookId: 'draftkings',
            book: 'DraftKings',
            decimal: 1.91,
            point: 249.5,
            participant: 'Josh Allen',
          ),
        ],
        fetchedAt: now,
      );
      final lonely = propCards(oneSided, now).single;
      expect(lonely.best!.book, 'DraftKings');
      expect(lonely.fairProbability, isNull);
      expect(lonely.expectedProfit, isNull);
      expect(lonely.implied, closeTo(impliedProbability(1.91), 1e-12));
    },
  );

  test('a prop filter keeps a book and a longer price, and drops the rest', () {
    final cards = propCards(demoBoard(now), now);
    final longer = applyPropFilter(
      cards,
      const PropFilter(onlyLongerThanTheBooks: true, bookId: 'hardrock'),
    );
    expect(longer, isNotEmpty);
    expect(
      longer.every(
        (card) =>
            card.expectedProfit! > 0 &&
            card.bookRows.any((row) => row.quote.bookId == 'hardrock'),
      ),
      isTrue,
    );
    expect(
      applyPropFilter(cards, const PropFilter(market: 'player_rush_yds')),
      isEmpty,
    );
  });

  test('fee-free moneyline chances add to one and badges follow the scan', () {
    final board = demoBoard(now);
    final slate = summarizeSlate(board, now);
    for (final game in slate.games) {
      expect(game.awayChance, isNotNull);
      expect(game.homeChance! + game.awayChance!, closeTo(1, 1e-9));
      expect(game.chanceExplanation, contains('not a prediction'));
    }
    final scan = scanMarkets(board, now);
    final first = slate.games.first;
    final markets = scan.markets.where(
      (market) => market.eventId == first.event.id,
    );
    expect(
      first.positiveEvMarkets,
      markets.where((market) => (market.bestMarketEv ?? 0) > 0).length,
    );
    expect(
      first.arbitrageCount,
      scan.arbitrage
          .where(
            (item) =>
                item.matchup == '${first.event.away} at ${first.event.home}',
          )
          .length,
    );
  });

  test('a pre-built ticket explains the real chance and the house cut', () {
    final priced = priceParlay(
      legs: const [
        ParlayLegInput(label: 'A', decimal: 1.91, winProbability: 0.5),
        ParlayLegInput(label: 'B', decimal: 1.91, winProbability: 0.5),
      ],
      sameGame: false,
    );
    final text = explainParlay(priced);
    expect(text, contains('unrelated games'));
    expect(text, contains('25.0%'));
    expect(text, contains('house cut'));
    expect(text, isNot(contains('guaranteed')));

    final matched = explainParlay(
      priceParlay(
        legs: const [
          ParlayLegInput(label: 'A', decimal: 2, winProbability: 0.5),
          ParlayLegInput(label: 'B', decimal: 2, winProbability: 0.5),
        ],
        sameGame: false,
      ),
    );
    expect(matched, contains('matches that multiplied chance'));

    final suggestions = buildParlays(
      demoBoard(now),
      now,
      scan: scanMarkets(demoBoard(now), now),
    );
    expect(suggestions, isNotEmpty);
    expect(
      suggestions.first.legs.map((leg) => leg.eventId).toSet(),
      hasLength(2),
    );
    expect(suggestions.first.plainEnglish, contains('unrelated games'));
    expect(
      suggestions.every(
        (ticket) =>
            ticket.legs.map((leg) => leg.quote.bookId).toSet().length == 1,
      ),
      isTrue,
    );
  });

  test(
    'a slip without a chance for every leg leaves the real chance blank',
    () {
      final blank = checkSlip(const [
        SlipLeg(decimal: 2),
        SlipLeg(decimal: 1.91, winProbability: 0.5),
      ]);
      expect(blank.price.fairProbability, isNull);
      expect(blank.plainEnglish, contains('real chance is blank'));
      final told = checkSlip(const [
        SlipLeg(decimal: 2, winProbability: 0.5),
        SlipLeg(decimal: 2, winProbability: 0.4),
      ]);
      expect(told.price.fairProbability, closeTo(0.2, 1e-12));
      expect(told.plainEnglish, contains('unrelated games'));
    },
  );

  test(
    'the bet calendar sums a local day and leaves pending out of profit',
    () {
      final day = DateTime(2026, 10, 4, 15);
      final bets = [
        TrackedBet(
          id: 'w',
          placedAt: day,
          description: 'Bills moneyline',
          book: 'FanDuel',
          decimal: 2,
          stake: 10,
          result: BetResult.won,
        ),
        TrackedBet(
          id: 'l',
          placedAt: day.add(const Duration(hours: 2)),
          description: 'Under',
          book: 'FanDuel',
          decimal: 1.91,
          stake: 5,
          result: BetResult.lost,
        ),
        TrackedBet(
          id: 'p',
          placedAt: day,
          description: 'Still open',
          book: 'FanDuel',
          decimal: 1.91,
          stake: 20,
          result: BetResult.pending,
        ),
        TrackedBet(
          id: 'v',
          placedAt: day.add(const Duration(days: 1)),
          description: 'Voided',
          book: 'FanDuel',
          decimal: 1.91,
          stake: 8,
          result: BetResult.voided,
        ),
      ];
      final reports = betCalendar(bets);
      expect(reports, hasLength(2));
      expect(reports.first.day, calendarDay(day));
      expect(reports.first.settledProfit, closeTo(5, 1e-9));
      expect(reports.first.pendingStake, 20);
      expect(reports.first.settledCount, 2);
      expect(reports.last.settledCount, 0);
      expect(reports.last.settledProfit, 0);
      expect(pendingStake(bets), 20);
    },
  );

  test('saved plays round-trip and a removal is a later write', () async {
    final dir = await Directory.systemTemp.createTemp('saved-plays');
    addTearDown(() => dir.delete(recursive: true));
    final store = ResearchStore(directory: dir);
    final play = SavedPlay(
      id: 'play-1',
      savedAt: DateTime.utc(2026, 10, 26, 12),
      title: 'Josh Allen Passing yards Over 249.5',
      detail: 'Buffalo Bills at Kansas City Chiefs',
      book: 'DraftKings',
      decimal: 1.91,
      demo: true,
      priceNote: '12 minutes old',
    );
    await store.saveSavedPlay(play);
    expect((await store.loadSavedPlays()).single.title, play.title);
    final exported = await store.exportJson();
    expect(exported, contains('savedPlays'));
    await store.saveSavedPlay(play.copyWith(removed: true));
    expect(await store.loadSavedPlays(), isEmpty);

    final fresh = await Directory.systemTemp.createTemp('saved-plays-import');
    addTearDown(() => fresh.delete(recursive: true));
    final again = ResearchStore(directory: fresh);
    expect(
      await again.importJson(
        jsonEncode({
          'format': 'odds-edge-research-v2',
          'records': <Object>[],
          'savedPlays': [play.toJson()],
        }),
      ),
      1,
    );
    final restored = SavedPlay.fromJson(play.toJson());
    expect(restored.decimal, 1.91);
    expect(restored.demo, isTrue);
    expect((await again.loadSavedPlays()).single.id, 'play-1');
  });

  test('price age never calls a missing clock live', () {
    expect(
      priceAge(now.subtract(const Duration(seconds: 20)), now),
      'Under a minute old',
    );
    expect(
      priceAge(now.subtract(const Duration(minutes: 12)), now),
      '12 minutes old',
    );
    expect(
      priceAge(now.add(const Duration(minutes: 1)), now),
      contains('not used as current'),
    );
  });
}
