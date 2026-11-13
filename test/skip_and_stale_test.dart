import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_board.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_history.dart';
import 'package:odds_edge/coach/prop_pricing.dart';
import 'package:odds_edge/domain/skip_list.dart';
import 'package:odds_edge/domain/stale_prices.dart';

PlayerGame allen(int week, num yards) => PlayerGame(
  playerId: 'allen',
  name: 'Josh Allen',
  position: 'QB',
  team: 'BUF',
  opponent: 'MIA',
  season: 2026,
  week: week,
  date: DateTime.utc(2026, 9, week),
  seasonType: 'REG',
  stats: {'passing_yards': yards, 'attempts': 30},
);

void main() {
  final now = DateTime.utc(2026, 11, 12);

  test('a short price that is worse than the fee-free consensus is a skip', () {
    final board = demoBoard(now);
    final cards = propCards(board, now);
    final directory = PlayerDirectory(
      PlayerStatsDataset(
        rows: [for (var week = 1; week <= 8; week++) allen(week, 280)],
      ),
    );
    final shown = showProps(
      cards: cards,
      directory: directory,
      context: null,
      board: board,
      now: now,
    );
    final skips = skipList(
      board: board,
      now: now,
      prices: [
        for (final prop in shown)
          RatedPrice(
            id: prop.card.id,
            title: '${prop.card.player} ${prop.card.lineLabel}',
            detail: prop.card.marketLabel,
            decimal: prop.card.best?.decimal,
            fair: prop.card.fairProbability,
            hits: prop.windows?.season?.hits,
            observed: prop.windows?.season?.observed,
          ),
      ],
    );
    expect(skips, isNotEmpty);
    expect(skips.every((item) => item.gap >= skipConsensusGap), isTrue);
    expect(
      skips.every((item) => item.breakEven >= skipShortPrice || item.likely),
      isTrue,
    );
    expect(skips.first.reason, contains('not a pick'));
    expect(skips.first.reason, contains('fee-free consensus'));
    expect(skips.first.brief, contains('pts too high'));
    expect(skips.any((item) => item.brief.contains('Hit 8 of 8')), isTrue);
    expect(skips.any((item) => item.title.contains('149.5')), isTrue);
  });

  test('an ordinary near-even price is not listed just because of the fee', () {
    final event = SportEvent(
      'even',
      'Buffalo Bills',
      'Miami Dolphins',
      now.add(const Duration(days: 2)),
    );
    final board = OddsBoard(
      events: [event],
      quotes: [
        for (final book in ['fanduel', 'draftkings']) ...[
          OddsQuote(
            selection: Selection(
              eventId: event.id,
              market: 'h2h',
              outcome: event.home,
            ),
            bookId: book,
            book: book,
            provider: 'test',
            decimal: 1.91,
            sourceAt: now,
            collectedAt: now,
          ),
          OddsQuote(
            selection: Selection(
              eventId: event.id,
              market: 'h2h',
              outcome: event.away,
            ),
            bookId: book,
            book: book,
            provider: 'test',
            decimal: 1.91,
            sourceAt: now,
            collectedAt: now,
          ),
        ],
      ],
      fetchedAt: now,
    );
    final skips = skipList(board: board, now: now, prices: const []);
    expect(skips, isEmpty);
    expect(stalePrices(board, now), isEmpty);
  });

  test(
    'a book short of the best price and the consensus is on the stale board',
    () {
      final event = SportEvent(
        'lag',
        'Buffalo Bills',
        'Miami Dolphins',
        now.add(const Duration(days: 2)),
      );
      OddsQuote quote(String book, String outcome, double decimal) => OddsQuote(
        selection: Selection(
          eventId: event.id,
          market: 'spreads',
          outcome: outcome,
          point: outcome == event.home ? -3.5 : 3.5,
        ),
        bookId: book,
        book: book,
        provider: 'test',
        decimal: decimal,
        sourceAt: now,
        collectedAt: now,
      );
      final board = OddsBoard(
        events: [event],
        quotes: [
          quote('fanduel', event.home, 1.91),
          quote('fanduel', event.away, 1.91),
          quote('draftkings', event.home, 1.50),
          quote('draftkings', event.away, 2.40),
        ],
        fetchedAt: now,
      );
      final rows = stalePrices(board, now);
      expect(rows.map((row) => row.bookId), contains('draftkings'));
      expect(rows.every((row) => row.reason.contains('not a pick')), isTrue);
      expect(
        rows.every((row) => row.reason.contains('fee-free consensus')),
        isTrue,
      );
      final short = rows.where((row) => row.bookId == 'draftkings');
      expect(short, isNotEmpty);
      expect(short.every((row) => row.gap >= staleConsensusGap), isTrue);
      expect(
        short.every((row) => row.brief.contains('pts above the other books')),
        isTrue,
      );
    },
  );
}
