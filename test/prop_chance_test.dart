import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/prop_pricing.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_board.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_history.dart';
import 'package:odds_edge/domain/prop_chance.dart';
import 'package:odds_edge/domain/prop_value.dart';
import 'package:odds_edge/domain/value_check.dart';

void main() {
  test(
    'a short streak is pulled toward the no-vig and stays inside 10 points',
    () {
      final hot = propSideChance(hits: 5, observed: 5, market: 0.5);
      expect(hot, closeTo(21 / 37, 1e-12));
      expect((hot! - 0.5).abs(), lessThanOrEqualTo(propEdgeCap));
      expect(hot, isNot(closeTo(1, 0.2)));
      expect(hot, isNot(closeTo(7 / 9, 1e-6)));

      final cold = propSideChance(hits: 0, observed: 5, market: 0.5);
      expect(cold, closeTo(16 / 37, 1e-12));
      expect((cold! - 0.5).abs(), lessThanOrEqualTo(propEdgeCap));
    },
  );

  test(
    'a long one-sided record may pass 10 points and still has a ceiling',
    () {
      final chance = propSideChance(hits: 40, observed: 50, market: 0.5);
      expect(chance, closeTo(0.5 + propEdgeCapCeiling, 1e-9));
      expect((chance! - 0.5).abs(), closeTo(propEdgeCapCeiling, 1e-9));
      expect(propEdgeCapFor(hits: 8, observed: 10, market: 0.5), propEdgeCap);
    },
  );

  test('fewer than four games stays blank, and a missing market uses the even shrink', () {
    expect(propSideChance(hits: 3, observed: 3, market: 0.5), isNull);
    expect(
      propSideChance(hits: 5, observed: 5, market: null),
      shrunkClearRate(hits: 5, observed: 5),
    );
    expect(
      () => propSideChance(hits: 6, observed: 5, market: 0.5),
      throwsArgumentError,
    );
  });

  test('the example board has a cross-game Bet or Lean pair, and no short-sample 26-point edge', () {
    final data = PlayerStatsDataset.fromJson(
      jsonDecode(
        File('assets/nfl-player-stats.json')
            .readAsStringSync()
            .replaceFirst('\uFEFF', ''),
      ),
    );
    final now = DateTime.utc(2026, 11, 12, 18);
    final board = demoBoard(now);
    final cards = propCards(board, now);
    final shown = showProps(
      cards: cards,
      directory: PlayerDirectory(data),
      context: null,
      board: board,
      now: now,
    );
    final playable = shown.where((prop) {
      final word = prop.verdict.word;
      return word == ValueWord.bet || word == ValueWord.lean;
    }).toList();
    final events = playable.map((prop) => prop.card.event?.id).toSet();
    expect(events.length, greaterThanOrEqualTo(2));
    for (final prop in shown) {
      final edge = prop.edge;
      if (edge == null) continue;
      final observed = prop.usingProjection
          ? (prop.projection?.games ?? 0)
          : (preferredRate(prop.windows)?.observed ?? 0);
      expect(
        edge.abs(),
        lessThanOrEqualTo(observed < propStrongSample ? 10.05 : 15.05),
        reason:
            '${prop.card.player} ${prop.card.market} ${edge.toStringAsFixed(1)} on $observed games',
      );
    }
  });
}
