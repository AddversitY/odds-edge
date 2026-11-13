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
    expect(data.metadata['license'], 'CC BY 4.0');
    expect(data.metadata['source'], contains('nflverse'));
    final cutoff = DateTime.parse('${data.metadata['cutoff']}T00:00:00Z');
    expect(cutoff.isAfter(DateTime.utc(2026, 10, 18)), isTrue);
    final goff = playerGames(data.rows, '00-0033106', season: 2023);
    expect(goff.length, 17);
    expect(PlayerStatWindow(goff).total('passing_yards'), 4575);
    expect(
      data.rows.any(
        (game) =>
            game.season == 2026 &&
            game.seasonType == 'REG' &&
            game.date.isAfter(DateTime.utc(2026, 10, 18)),
      ),
      isTrue,
    );
    expect(data.rows.every((g) => !g.date.isAfter(cutoff)), isTrue);
  });
}
