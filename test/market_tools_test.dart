import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/data/research_store.dart';
import 'package:odds_edge/domain/bets.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/market_math.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/tools_page.dart';

final now = DateTime.utc(2026, 10, 18, 12);

OddsQuote quote({
  required String outcome,
  required String book,
  required double decimal,
  String event = 'g',
  String market = 'h2h',
  double? point,
  String participant = '',
  String? bookName,
  DateTime? collected,
  DateTime? source,
  String rules = 'includes_overtime_push_on_tie',
  String status = 'open',
}) => OddsQuote(
  selection: Selection(
    eventId: event,
    market: market,
    outcome: outcome,
    point: point,
    participant: participant,
    rules: rules,
  ),
  bookId: book,
  book: bookName ?? book,
  provider: 'test',
  decimal: decimal,
  sourceAt: source ?? collected ?? now,
  collectedAt: collected ?? now,
  status: status,
);

OddsBoard board(List<OddsQuote> quotes, {DateTime? start, DateTime? fetched}) =>
    OddsBoard(
      events: [
        SportEvent(
          'g',
          'Buffalo Bills',
          'Kansas City Chiefs',
          start ?? now.add(const Duration(days: 1)),
        ),
      ],
      quotes: quotes,
      fetchedAt: fetched ?? now,
    );

PlayerGame game({
  required int week,
  required num? yards,
  String opponent = 'MIA',
  int season = 2026,
}) => PlayerGame(
  playerId: 'ada',
  name: 'Ada Lovelace',
  position: 'WR',
  team: 'BUF',
  opponent: opponent,
  season: season,
  week: week,
  date: DateTime.utc(2026, 9, week),
  seasonType: 'REG',
  stats: {'receiving_yards': yards},
);

void main() {
  test('proportional no-vig splits a standard price into 50/50', () {
    final price = americanToDecimal(-110);
    final fair = removeVigProportional([
      impliedProbability(price),
      impliedProbability(price),
    ]);
    expect(fair.hold, closeTo(1 / 21, 1e-9));
    expect(fair.probabilities[0], closeTo(.5, 1e-9));
    expect(fair.probabilities[1], closeTo(.5, 1e-9));
    expect(fair.method, 'proportional');
    expect(() => removeVigProportional([.4]), throwsArgumentError);
  });

  test('additive removal disagrees on lopsided prices and fails closed on a longshot trio', () {
    final lopsided = removeVigAdditive([.9, .4])!;
    final proportional = removeVigProportional([.9, .4]);
    expect(
      (lopsided.probabilities[0] - proportional.probabilities[0]).abs(),
      greaterThan(.01),
    );
    expect(removeVigAdditive([.01, .5, .7]), isNull);
    expect(
      removeVigProportional([.01, .5, .7]).probabilities
          .reduce((a, b) => a + b),
      closeTo(1, 1e-9),
    );
  });

  test('market comparison, sharp reference, fee, and one-sided lines', () {
    final scan = scanMarkets(
      board([
        quote(outcome: 'Buffalo Bills', book: 'soft', decimal: 2.2),
        quote(outcome: 'Kansas City Chiefs', book: 'soft', decimal: 1.8),
        quote(
          outcome: 'Buffalo Bills',
          book: 'pinnacle',
          bookName: 'Pinnacle',
          decimal: americanToDecimal(-110),
        ),
        quote(
          outcome: 'Kansas City Chiefs',
          book: 'pinnacle',
          bookName: 'Pinnacle',
          decimal: americanToDecimal(-110),
        ),
        quote(
          outcome: 'Buffalo Bills',
          book: 'soft',
          decimal: 1.7,
          market: 'spreads',
          point: 2.5,
        ),
      ]),
      now,
    );
    final moneyline = scan.markets.firstWhere(
      (market) => market.market == 'h2h',
    );
    expect(moneyline.sharpLabel, 'Pinnacle');
    expect(moneyline.booksAveraged, 2);
    expect(moneyline.bestHold, isNotNull);
    final bills = moneyline.sides.firstWhere(
      (side) => side.selection.outcome == 'Buffalo Bills',
    );
    expect(bills.best!.decimal, 2.2);
    expect(bills.sharpProbability, closeTo(.5, 1e-9));
    expect(bills.marketEv, isNotNull);
    expect(bills.sharpEv, expectedValue(2.2, .5));
    final oneSide = scan.markets.firstWhere(
      (market) => market.market == 'spreads',
    );
    expect(oneSide.complete, isFalse);
    expect(oneSide.bestHold, isNull);
    expect(oneSide.sides.single.fairProbability, isNull);
    expect(oneSide.detail, 'Buffalo Bills +2.5');
    expect(moneyline.rulesUnverified, isFalse);
    expect(moneyline.detail, 'Moneyline');

    final noSharp = scanMarkets(
      board([
        quote(outcome: 'Buffalo Bills', book: 'soft', decimal: 1.91),
        quote(outcome: 'Kansas City Chiefs', book: 'soft', decimal: 1.91),
      ]),
      now,
    );
    expect(noSharp.markets.single.sharpLabel, isNull);
    expect(noSharp.arbitrage, isEmpty);
  });

  test('disagreement between fee-removal methods is reported', () {
    final scan = scanMarkets(
      board([
        quote(outcome: 'Buffalo Bills', book: 'soft', decimal: 1 / .9),
        quote(outcome: 'Kansas City Chiefs', book: 'soft', decimal: 1 / .4),
      ]),
      now,
    );
    expect(scan.markets.single.removalMethodsDisagree, isTrue);
  });

  test('arbitrage stakes equalize the payout and ignore a normal fee', () {
    final scan = scanMarkets(
      board([
        quote(outcome: 'Buffalo Bills', book: 'a', decimal: 2.1),
        quote(outcome: 'Kansas City Chiefs', book: 'b', decimal: 2.1),
        quote(
          outcome: 'Over',
          book: 'a',
          decimal: 1.91,
          market: 'totals',
          point: 47.5,
        ),
        quote(
          outcome: 'Under',
          book: 'b',
          decimal: 1.91,
          market: 'totals',
          point: 47.5,
        ),
      ]),
      now,
    );
    expect(scan.arbitrage, hasLength(1));
    final arb = scan.arbitrage.single;
    expect(arb.roi, closeTo(.05, 1e-9));
    expect(arb.sameBook, isFalse);
    expect(arb.legs.map((leg) => leg.share), everyElement(closeTo(.5, 1e-9)));
    expect(arb.tieNotPriced, isTrue);
  });

  test(
    'middles describe the window and skip mirrors, reverses, and empty gaps',
    () {
      final scan = scanMarkets(
        board([
          quote(
            outcome: 'Buffalo Bills',
            book: 'a',
            decimal: 1.91,
            market: 'spreads',
            point: 3.5,
          ),
          quote(
            outcome: 'Kansas City Chiefs',
            book: 'b',
            decimal: 1.91,
            market: 'spreads',
            point: -2.5,
          ),
          quote(
            outcome: 'Buffalo Bills',
            book: 'a',
            decimal: 1.91,
            market: 'spreads',
            point: -3.5,
          ),
          quote(
            outcome: 'Kansas City Chiefs',
            book: 'b',
            decimal: 1.91,
            market: 'spreads',
            point: 3.5,
          ),
          quote(
            outcome: 'Buffalo Bills',
            book: 'a',
            decimal: 1.87,
            market: 'spreads',
            point: 2.5,
          ),
          quote(
            outcome: 'Kansas City Chiefs',
            book: 'b',
            decimal: 1.95,
            market: 'spreads',
            point: -3.5,
          ),
          quote(
            outcome: 'Over',
            book: 'a',
            decimal: 1.91,
            market: 'totals',
            point: 47.5,
          ),
          quote(
            outcome: 'Under',
            book: 'b',
            decimal: 1.91,
            market: 'totals',
            point: 51.5,
          ),
          quote(
            outcome: 'Over',
            book: 'a',
            decimal: 1.91,
            market: 'totals',
            point: 47,
          ),
          quote(
            outcome: 'Under',
            book: 'b',
            decimal: 1.91,
            market: 'totals',
            point: 48,
          ),
        ]),
        now,
      );
      final windows = scan.middles.map((middle) => middle.window).toList();
      expect(
        windows,
        contains('Both bets win if Kansas City Chiefs win by 3.'),
      );
      final chiefsByThree = scan.middles.singleWhere(
        (middle) =>
            middle.window == 'Both bets win if Kansas City Chiefs win by 3.',
      );
      expect(chiefsByThree.pushPossible, isFalse);
      expect(
        middleWindowExplanation(chiefsByThree),
        contains('loses one side and wins the other'),
      );
      expect(
        windows,
        contains('Both bets win if the total is 48, 49, 50, or 51.'),
      );
      expect(windows.join('\n'), isNot(contains('win by 4')));
      expect(windows, isNot(contains('Both bets win if the total is 47.')));
      expect(
        scan.middles.where(
          (middle) => middle.market == 'Total' && middle.pushPossible,
        ),
        isNotEmpty,
      );
    },
  );

  test('whole-number totals can push and still show an interior window', () {
    final scan = scanMarkets(
      board([
        quote(
          outcome: 'Over',
          book: 'a',
          decimal: 1.91,
          market: 'totals',
          point: 47,
        ),
        quote(
          outcome: 'Under',
          book: 'b',
          decimal: 1.91,
          market: 'totals',
          point: 49,
        ),
      ]),
      now,
    );
    expect(scan.middles.single.window, 'Both bets win if the total is 48.');
    expect(scan.middles.single.pushPossible, isTrue);
    expect(scan.middles.single.payoff.hitProfit, closeTo(182, 1e-9));
    expect(scan.middles.single.payoff.missIfFirstWins, closeTo(-9, 1e-9));
    expect(scan.middles.single.payoff.missIfSecondWins, closeTo(-9, 1e-9));
    expect(scan.middles.single.payoff.breakEvenHitRate, closeTo(9 / 191, 1e-9));
    expect(
      middlePayoffSummary(scan.middles.single),
      '\$100 on each side. If the window hits, the profit is \$182.00. '
      'If the window misses and both bets are decided, the result is -\$9.00. '
      'The window has to hit 4.7% of the time to break even.',
    );
    final explanation = middleWindowExplanation(scan.middles.single);
    expect(explanation, contains('return the stake'));
    expect(explanation, isNot(contains('loses one side and wins the other')));
  });

  test(
    'demo snapshot exposes sample arbitrage and no sharp book or middle',
    () {
      final scan = scanMarkets(demoBoard(now), now);
      expect(scan.demo, isTrue);
      expect(scan.arbitrage, isNotEmpty);
      expect(scan.arbitrage.every((arb) => arb.sameBook), isTrue);
      expect(scan.middles, isEmpty);
      expect(scan.markets.every((market) => market.sharpLabel == null), isTrue);
      expect(
        scan.markets.any((market) => (market.bestMarketEv ?? 0) > 0),
        isTrue,
      );
    },
  );

  test('parlay fair price multiplies unrelated chances and refuses same-game multiplication', () {
    final unrelated = priceParlay(
      legs: const [
        ParlayLegInput(label: 'A', decimal: 2, winProbability: .5),
        ParlayLegInput(label: 'B', decimal: 2, winProbability: .5),
      ],
      sameGame: false,
    );
    expect(unrelated.multipliedDecimal, 4);
    expect(unrelated.fairProbability, .25);
    expect(unrelated.fairDecimal, 4);
    expect(unrelated.expectedValuePerUnit, closeTo(0, 1e-9));
    expect(unrelated.basis, 'unrelated-legs');

    final sameGame = priceParlay(
      legs: const [
        ParlayLegInput(label: 'A', decimal: 2, winProbability: .5),
        ParlayLegInput(label: 'B', decimal: 2, winProbability: .5),
      ],
      sameGame: true,
    );
    expect(sameGame.fairProbability, isNull);
    expect(sameGame.basis, 'unavailable');

    final assumed = priceParlay(
      legs: const [
        ParlayLegInput(label: 'A', decimal: 2, winProbability: .5),
        ParlayLegInput(label: 'B', decimal: 2, winProbability: .5),
      ],
      sameGame: true,
      jointWinProbability: .3,
    );
    expect(assumed.basis, 'your-assumption');
    expect(assumed.expectedValuePerUnit, closeTo(expectedValue(4, .3), 1e-9));
    expect(
      () => priceParlay(
        legs: const [ParlayLegInput(label: 'A', decimal: 2)],
        sameGame: false,
      ),
      throwsArgumentError,
    );
  });

  test('Kelly is zero without an edge and accounts for a push', () {
    final coin = kellyStake(decimal: 2, win: .5);
    expect(coin.fraction, 0);
    expect(coin.half, 0);
    expect(coin.edgeIsPositive, isFalse);

    final edge = kellyStake(decimal: 2, win: .6);
    expect(edge.fraction, closeTo(.2, 1e-9));
    expect(edge.half, closeTo(.1, 1e-9));
    expect(edge.quarter, closeTo(.05, 1e-9));
    expect(edge.expectedValuePerUnit, closeTo(.2, 1e-9));

    final pushed = kellyStake(decimal: 2, win: .55, push: .1);
    expect(pushed.fraction, closeTo(.2 / .9, 1e-9));
    expect(
      () => kellyStake(decimal: 2, win: .8, push: .3),
      throwsArgumentError,
    );
  });

  test('line movement keeps the earliest and latest saved price per book', () {
    final rows = lineMoves([
      quote(outcome: 'Buffalo Bills', book: 'fd', decimal: 2.5, collected: now),
      quote(
        outcome: 'Buffalo Bills',
        book: 'fd',
        decimal: 1.909,
        bookName: 'FanDuel',
        collected: now.add(const Duration(hours: 3)),
      ),
      quote(
        outcome: 'Buffalo Bills',
        book: 'dk',
        decimal: 2.1,
        bookName: 'DraftKings',
      ),
    ]);
    expect(rows, hasLength(2));
    final fanduel = rows.firstWhere((row) => row.bookId == 'fd');
    expect(fanduel.samples, 2);
    expect(fanduel.firstDecimal, 2.5);
    expect(fanduel.latestDecimal, closeTo(1.909, 1e-9));
    expect(fanduel.moved, isTrue);
    expect(rows.firstWhere((row) => row.bookId == 'dk').moved, isFalse);
  });

  test(
    'ROI excludes pending and void bets, and CLV uses only a typed close',
    () {
      final ledger = BetLedger([
        TrackedBet(
          id: '1',
          placedAt: now,
          description: 'Bills moneyline',
          book: 'FanDuel',
          decimal: 2,
          stake: 100,
          result: BetResult.won,
          closingDecimal: americanToDecimal(-110),
        ),
        TrackedBet(
          id: '2',
          placedAt: now,
          description: 'Chiefs moneyline',
          book: 'FanDuel',
          decimal: 2,
          stake: 50,
          result: BetResult.lost,
        ),
        TrackedBet(
          id: '3',
          placedAt: now,
          description: 'Total',
          book: 'FanDuel',
          decimal: 1.91,
          stake: 25,
          result: BetResult.push,
        ),
        TrackedBet(
          id: '4',
          placedAt: now,
          description: 'Later',
          book: 'FanDuel',
          decimal: 1.91,
          stake: 80,
          result: BetResult.pending,
          closingDecimal: 1.5,
        ),
        TrackedBet(
          id: '5',
          placedAt: now,
          description: 'Cancelled',
          book: 'FanDuel',
          decimal: 1.91,
          stake: 40,
          result: BetResult.voided,
        ),
      ]);
      expect(ledger.profit, closeTo(50, 1e-9));
      expect(ledger.staked, 175);
      expect(ledger.roi, closeTo(50 / 175, 1e-9));
      expect(ledger.pending, 1);
      expect(ledger.wins, 1);
      expect(ledger.closingLineValues, hasLength(2));
      final won = ledger.bets.first.closingLineValue!;
      expect(
        won,
        closeTo(impliedProbability(americanToDecimal(-110)) - .5, 1e-9),
      );
      expect(won, greaterThan(0));
      expect(ledger.beatClose, 2);
      expect(BetLedger(const []).roi, isNull);
      expect(BetLedger(const []).averageClosingLineValue, isNull);
    },
  );

  test(
    'bet log keeps the latest result and round-trips through export',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-bets');
      addTearDown(() => dir.delete(recursive: true));
      final store = ResearchStore(directory: dir);
      final bet = TrackedBet(
        id: 'bet-1',
        placedAt: now,
        description: 'Bills +3.5',
        book: 'DraftKings',
        decimal: 1.91,
        stake: 20,
        result: BetResult.pending,
      );
      await store.saveBet(bet);
      await store.saveBet(bet.copyWith(result: BetResult.won));
      expect((await store.loadBets()).single.result, BetResult.won);

      final otherDir = await Directory.systemTemp.createTemp('odds-bets-2');
      addTearDown(() => otherDir.delete(recursive: true));
      final other = ResearchStore(directory: otherDir);
      expect(await other.importJson(await store.exportJson()), 1);
      expect((await other.loadBets()).single.profit, closeTo(18.2, 1e-9));
      expect(
        await other.importJson(
          '{"format":"odds-edge-research-v2","records":[],"reviews":[]}',
        ),
        0,
      );
      expect((await other.loadBets()).single.id, 'bet-1');

      final changed =
          jsonDecode(await store.exportJson()) as Map<String, dynamic>;
      changed['bets'][0]['description'] = 'A different bet';
      expect(
        () => other.importJson(jsonEncode(changed)),
        throwsFormatException,
      );
    },
  );

  test('prop hit rate skips missing stats and separates last games, season, and opponent', () {
    final rows = [
      game(week: 1, yards: 80),
      game(week: 2, yards: 10),
      game(week: 3, yards: null),
      game(week: 4, yards: 70, opponent: 'KC'),
      game(week: 5, yards: 90, opponent: 'KC'),
      game(week: 6, yards: 40, season: 2025),
    ];
    final lastFive = hitRate(
      label: 'Last 5',
      games: propGames(rows, 'ada', limit: 5),
      metric: 'receiving_yards',
      line: 64.5,
      side: LineSide.over,
    );
    expect(lastFive.games, 5);
    expect(lastFive.hits, 2);
    expect(lastFive.misses, 2);
    expect(lastFive.missing, 1);
    expect(lastFive.clearRate, closeTo(.5, 1e-9));

    final season = hitRate(
      label: '2026',
      games: propGames(rows, 'ada', season: 2026),
      metric: 'receiving_yards',
      line: 64.5,
      side: LineSide.over,
    );
    expect(season.games, 5);
    expect(season.samples.any((sample) => sample.game.season == 2025), isFalse);

    final chiefs = hitRate(
      label: 'KC',
      games: propGames(rows, 'ada', opponent: 'kc'),
      metric: 'receiving_yards',
      line: 64.5,
      side: LineSide.under,
    );
    expect(chiefs.hits, 0);
    expect(chiefs.misses, 2);

    final tied = hitRate(
      label: 'push',
      games: [game(week: 7, yards: 64.5)],
      metric: 'receiving_yards',
      line: 64.5,
      side: LineSide.over,
    );
    expect(tied.pushes, 1);
    expect(tied.hits, 0);
    expect(tied.clearRate, 0);
  });

  test(
    'unverified books compare by market and number, with the rules called out',
    () {
      final scan = scanMarkets(
        board([
          quote(
            outcome: 'Buffalo Bills',
            book: 'draftkings',
            decimal: 2.2,
            rules: 'unverified:draftkings:h2h',
            status: 'unverified',
          ),
          quote(
            outcome: 'Kansas City Chiefs',
            book: 'draftkings',
            decimal: 1.7,
            rules: 'unverified:draftkings:h2h',
            status: 'unverified',
          ),
          quote(
            outcome: 'Buffalo Bills',
            book: 'fanduel',
            decimal: 2.05,
            rules: 'unverified:fanduel:h2h',
            status: 'unverified',
          ),
          quote(
            outcome: 'Kansas City Chiefs',
            book: 'fanduel',
            decimal: 1.8,
            rules: 'unverified:fanduel:h2h',
            status: 'unverified',
          ),
          quote(
            outcome: 'Buffalo Bills',
            book: 'draftkings',
            decimal: 1.95,
            market: 'spreads',
            point: 3.5,
            rules: 'unverified:draftkings:spreads',
            status: 'unverified',
          ),
          quote(
            outcome: 'Kansas City Chiefs',
            book: 'fanduel',
            decimal: 1.91,
            market: 'spreads',
            point: -3.5,
            rules: 'unverified:fanduel:spreads',
            status: 'unverified',
          ),
          quote(
            outcome: 'suspended',
            book: 'fliff',
            decimal: 3,
            status: 'suspended',
          ),
        ]),
        now,
      );
      final moneyline = scan.markets.singleWhere(
        (market) => market.market == 'h2h',
      );
      expect(scan.emptyReason, isNull);
      expect(moneyline.rulesUnverified, isTrue);
      expect(moneyline.booksAveraged, 2);
      expect(moneyline.complete, isTrue);
      final bills = moneyline.sides.singleWhere(
        (side) => side.selection.outcome == 'Buffalo Bills',
      );
      expect(bills.best!.bookId, 'draftkings');
      expect(bills.best!.decimal, 2.2);
      final spread = scan.markets.singleWhere(
        (market) => market.market == 'spreads',
      );
      expect(spread.detail, 'Buffalo Bills +3.5 · Kansas City Chiefs -3.5');
      expect(spread.rulesUnverified, isTrue);
      expect(spread.sides.map((side) => side.best!.bookId), [
        'draftkings',
        'fanduel',
      ]);
    },
  );

  test('a confirmed rule book is not mixed into the unverified group', () {
    final scan = scanMarkets(
      board([
        quote(outcome: 'Buffalo Bills', book: 'fanduel', decimal: 2.1),
        quote(outcome: 'Kansas City Chiefs', book: 'fanduel', decimal: 1.8),
        quote(
          outcome: 'Buffalo Bills',
          book: 'draftkings',
          decimal: 2.4,
          rules: 'unverified',
          status: 'unverified',
        ),
        quote(
          outcome: 'Kansas City Chiefs',
          book: 'draftkings',
          decimal: 1.6,
          rules: 'unverified',
          status: 'unverified',
        ),
      ]),
      now,
    );
    final moneylines = scan.markets.where((market) => market.market == 'h2h');
    expect(moneylines, hasLength(2));
    expect(
      moneylines.singleWhere((market) => market.rulesUnverified).booksAveraged,
      1,
    );
    expect(
      moneylines.singleWhere((market) => !market.rulesUnverified).booksAveraged,
      1,
    );
  });

  test('started games and stale prices cannot create a fake edge', () {
    final freshBills = quote(outcome: 'Buffalo Bills', book: 'a', decimal: 2.2);
    final freshChiefs = quote(
      outcome: 'Kansas City Chiefs',
      book: 'b',
      decimal: 2.2,
    );
    final started = scanMarkets(
      board([freshBills, freshChiefs], start: now),
      now,
    );
    expect(started.markets, isEmpty);
    expect(started.arbitrage, isEmpty);
    expect(started.middles, isEmpty);
    expect(started.emptyReason, contains('already started'));
    expect(started.emptyReason, isNot(contains('Suspended')));

    final kickingOff = scanMarkets(
      board([
        freshBills,
        freshChiefs,
      ], start: now.add(const Duration(seconds: 1))),
      now,
    );
    expect(kickingOff.markets, isNotEmpty);
    expect(kickingOff.arbitrage, isNotEmpty);

    final staleAt = now.subtract(const Duration(minutes: 31));
    final stale = scanMarkets(
      board([
        quote(
          outcome: 'Buffalo Bills',
          book: 'a',
          decimal: 2.2,
          source: staleAt,
        ),
        quote(
          outcome: 'Kansas City Chiefs',
          book: 'b',
          decimal: 2.2,
          source: staleAt,
        ),
      ]),
      now,
    );
    expect(stale.markets, isEmpty);
    expect(stale.emptyReason, contains('30 minutes'));

    final boundary = scanMarkets(
      board([
        quote(
          outcome: 'Buffalo Bills',
          book: 'a',
          decimal: 2.2,
          source: now.subtract(const Duration(minutes: 30)),
        ),
        quote(
          outcome: 'Kansas City Chiefs',
          book: 'b',
          decimal: 2.2,
          source: now.subtract(const Duration(minutes: 30)),
        ),
      ]),
      now,
    );
    expect(boundary.markets, isNotEmpty);

    final oneStaleSide = scanMarkets(
      board([
        quote(
          outcome: 'Buffalo Bills',
          book: 'a',
          decimal: 2.2,
          source: staleAt,
        ),
        freshChiefs,
      ]),
      now,
    );
    expect(oneStaleSide.arbitrage, isEmpty);
    expect(oneStaleSide.markets.single.complete, isFalse);

    final suspended = scanMarkets(
      board([
        quote(
          outcome: 'Buffalo Bills',
          book: 'a',
          decimal: 2.2,
          status: 'suspended',
        ),
        quote(
          outcome: 'Kansas City Chiefs',
          book: 'b',
          decimal: 2.2,
          status: 'suspended',
        ),
      ]),
      now,
    );
    expect(suspended.emptyReason, contains('Suspended'));
  });

  test(
    'a middle with uneven prices states both misses and the worse break-even',
    () {
      final scan = scanMarkets(
        board([
          quote(
            outcome: 'Buffalo Bills',
            book: 'a',
            decimal: 2,
            market: 'spreads',
            point: 3.5,
          ),
          quote(
            outcome: 'Kansas City Chiefs',
            book: 'b',
            decimal: 1.91,
            market: 'spreads',
            point: -2.5,
          ),
        ]),
        now,
      );
      final middle = scan.middles.single;
      expect(middle.payoff.hitProfit, closeTo(191, 1e-9));
      expect(middle.payoff.missIfFirstWins, closeTo(0, 1e-9));
      expect(middle.payoff.missIfSecondWins, closeTo(-9, 1e-9));
      expect(middle.payoff.breakEvenIfFirstCovers, 0);
      expect(middle.payoff.breakEvenHitRate, closeTo(0.045, 1e-9));
      final summary = middlePayoffSummary(middle);
      expect(summary, contains('\$191.00'));
      expect(summary, contains('\$0.00'));
      expect(summary, contains('-\$9.00'));
      expect(summary, contains('4.5%'));
      expect(summary, contains('larger loss'));
    },
  );

  test('lowest fee order is separate from the market-comparison order', () {
    PricedMarket row(String name, double ev, double hold) => PricedMarket(
      eventId: name,
      matchup: name,
      market: 'h2h',
      detail: 'Moneyline',
      sides: [
        PricedSide(
          selection: Selection(eventId: name, market: 'h2h', outcome: 'A'),
          best: null,
          fairProbability: null,
          marketEv: ev,
          sharpProbability: null,
          sharpEv: null,
        ),
      ],
      bestHold: hold,
      typicalHold: hold,
      booksAveraged: 2,
      sharpLabel: null,
      wholeNumberLine: false,
      tieNotPriced: true,
      removalMethodsDisagree: false,
      complete: true,
      rulesUnverified: false,
    );
    final markets = [row('High fee', 0.08, 0.08), row('Low fee', 0.01, -0.01)];
    expect(
      sortPricedMarkets(markets, MarketSort.comparison).first.matchup,
      'High fee',
    );
    expect(
      sortPricedMarkets(markets, MarketSort.lowestFee).first.matchup,
      'Low fee',
    );
  });

  test('a rounded zero EV is shown as 0.0 and a stake percent has no plus', () {
    expect(formatSignedPercent(-0.0004), '0.0%');
    expect(formatSignedPercent(0), '0.0%');
    expect(formatSignedPercent(0.001), '+0.1%');
    expect(formatSignedPercent(-0.001), '-0.1%');
    expect(formatPlainPercent(0.055), '5.5%');
    expect(formatPlainPercent(0.055).startsWith('+'), isFalse);
  });

  test('Kelly stays within the bankroll for a valid chance', () {
    final extreme = kellyStake(decimal: 50, win: .99);
    expect(extreme.fraction, greaterThan(0));
    expect(extreme.fraction, lessThanOrEqualTo(1));
    final certainLoss = kellyStake(decimal: 2, win: .1);
    expect(certainLoss.fraction, 0);
  });
}
