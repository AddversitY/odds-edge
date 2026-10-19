import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/player_stats.dart';

void main() {
  test('Bundled player source decodes and preserves real three-game and season values', () {
    final data = PlayerStatsDataset.fromJson(
      jsonDecode(
        File('assets/nfl-player-stats.json')
            .readAsStringSync()
            .replaceFirst('\uFEFF', ''),
      ),
    );
    expect(data.rows.length, greaterThan(60000));
    expect(data.metadata['currentSeason'], 2026);
    expect(data.metadata['cutoff'], '2026-10-18');
    final goff = playerGames(data.rows, '00-0033106', season: 2023);
    expect(goff.length, 17);
    expect(PlayerStatWindow(goff).total('passing_yards'), 4575);
    final recent = lastPlayerGames(data.rows, '00-0033106', season: 2026);
    expect(recent.map((g) => g.week), [5, 4, 3]);
    expect(PlayerStatWindow(recent).total('passing_yards'), 952);
    expect(PlayerStatWindow(recent).average('receiving_yards'), 0);
    expect(PlayerStatWindow(recent).observed('receiving_yards'), 3);
    expect(
      data.rows.every((g) => !g.date.isAfter(DateTime.utc(2026, 10, 18))),
      isTrue,
    );
  });
}
