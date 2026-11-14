import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_board.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/injury_report.dart';
import 'package:odds_edge/domain/nfl_teams.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_history.dart';
import 'package:odds_edge/domain/prop_evidence.dart';
import 'package:odds_edge/domain/prop_projection.dart';
import 'package:odds_edge/coach/prop_pricing.dart';

void main() {
  test(
    'stored, future and 24-hour-old reports are not current availability',
    () {
      final now = DateTime.utc(2026, 11, 14);
      InjuryReport report(DateTime at, {bool live = true}) => InjuryReport(
        fetchedAt: at,
        live: live,
        notice: '',
        entries: const [],
        changes: const [],
        sources: const [],
      );
      expect(hasCurrentInjuries(report(now), now), isTrue);
      expect(hasCurrentInjuries(report(now, live: false), now), isFalse);
      expect(
        hasCurrentInjuries(report(now.add(const Duration(minutes: 1))), now),
        isFalse,
      );
      expect(
        hasCurrentInjuries(
          report(now.subtract(const Duration(hours: 24))),
          now,
        ),
        isFalse,
      );
    },
  );
  test(
    'Sunday-night UTC crossover excludes its own box score and later position',
    () {
      final now = DateTime.utc(2026, 11, 14);
      final board = demoBoard(now), cards = propCards(demoBoard(now), now);
      final original = cards.firstWhere(
        (c) => c.player == 'Patrick Mahomes' && c.lineSide == LineSide.over,
      );
      final card = PropCardModel(
        side: original.side,
        otherSide: original.otherSide,
        event: SportEvent(
          original.side.eventId,
          'BUF',
          'KC',
          DateTime.utc(2026, 11, 9, 1, 20),
        ),
        player: original.player,
        market: original.market,
        marketLabel: original.marketLabel,
        line: original.line,
        lineSide: original.lineSide,
        best: original.best,
        implied: original.implied,
        fairProbability: original.fairProbability,
        expectedProfit: original.expectedProfit,
        bookRows: original.bookRows,
        rulesUnverified: true,
        demo: true,
      );
      final directory = PlayerDirectory(
        PlayerStatsDataset(
          rows: [
            for (var day = 4; day <= 9; day++)
              PlayerGame(
                playerId: 'p',
                name: 'Patrick Mahomes',
                position: day >= 8 ? 'WR' : 'QB',
                team: 'KC',
                opponent: 'BUF',
                season: 2026,
                week: day,
                date: DateTime.utc(2026, 11, day),
                seasonType: 'REG',
                stats: {'passing_yards': day >= 8 ? 999 : 240, 'attempts': 34},
              ),
          ],
        ),
      );
      final shown = showProp(
        card: card,
        cards: [card],
        directory: directory,
        context: null,
        board: board,
        now: now,
      );
      expect(shown.windows!.position, 'QB');
      expect(shown.windows!.last10!.observed, 4);
      expect(shown.projection, isNotNull);
      expect(shown.projection!.games, 4);
    },
  );
  test(
    'support and caution reverse for under, missing inputs stay explicit',
    () {
      const projection = PropProjection(
        metric: 'passing_yards',
        mean: 240,
        sd: 50,
        distribution: 'normal',
        rawChance: .6,
        adjustedChance: .6,
        chance: .55,
        market: .5,
        capped: true,
        games: 20,
        side: LineSide.over,
        factors: [
          PropFactor(label: 'Defense', detail: 'Tough matchup', delta: -12),
          PropFactor(label: 'Script', detail: 'More volume', delta: 8),
        ],
      );
      final now = DateTime.utc(2026, 11, 14);
      final over = explainPropEvidence(
        side: LineSide.over,
        projection: projection,
        now: now,
        example: true,
      );
      final under = explainPropEvidence(
        side: LineSide.under,
        projection: projection,
        now: now,
      );
      expect(over.support.single, contains('Script'));
      expect(under.support.single, contains('Defense'));
      expect(over.cautions.join(), contains('Tough matchup'));
      expect(
        over.cautions.join(),
        contains('current injury report is unavailable'),
      );
      expect(over.context.join(), contains('Weather is not an input'));
      expect(over.cautions.join(), contains('invented examples'));
    },
  );
  test('sample players match latest recorded clubs and wrong events disable projections', () {
    final data = PlayerStatsDataset.fromJson(
      jsonDecode(File('assets/nfl-player-stats.json').readAsStringSync()),
    );
    final directory = PlayerDirectory(data);
    final now = DateTime.utc(2026, 11, 14);
    final board = demoBoard(now), cards = propCards(demoBoard(now), now);
    final memo = PropPricingMemo();
    for (final card in cards) {
      final windows = directory.lookup(
        playerName: card.player,
        market: card.market,
        line: card.line,
        side: card.lineSide,
        through: now,
      );
      expect(windows.playerId, isNotNull, reason: card.player);
      expect(
        {canonicalTeam(card.event!.home), canonicalTeam(card.event!.away)},
        contains(canonicalTeam(windows.team!)),
        reason: card.player,
      );
    }
    final allen = cards.firstWhere((c) => c.player == 'Josh Allen');
    final wrongRows = data.rows
        .where((r) => r.name == 'Josh Allen')
        .map(
          (r) => PlayerGame(
            playerId: r.playerId,
            name: r.name,
            position: r.position,
            team: 'DAL',
            opponent: r.opponent,
            season: r.season,
            week: r.week,
            date: r.date,
            seasonType: r.seasonType,
            stats: r.stats,
          ),
        )
        .toList();
    final shown = showProp(
      card: allen,
      cards: cards,
      directory: PlayerDirectory(PlayerStatsDataset(rows: wrongRows)),
      context: null,
      board: board,
      now: now,
      memo: memo,
    );
    expect(shown.dataWarning, contains('does not match'));
    expect(shown.projection, isNull);
    expect(scriptLegFor(shown), isNull);
  });
}
