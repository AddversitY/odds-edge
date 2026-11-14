import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_history.dart';

PlayerGame game({
  required String id,
  required String name,
  required int week,
  required num? yards,
  String team = 'BUF',
  String opponent = 'MIA',
  int season = 2026,
}) => PlayerGame(
  playerId: id,
  name: name,
  position: 'QB',
  team: team,
  opponent: opponent,
  season: season,
  week: week,
  date: DateTime.utc(season, 9, week),
  seasonType: 'REG',
  stats: {'passing_yards': yards},
);

void main() {
  test('historical identity cannot see a later transfer', () {
    final directory = PlayerDirectory(
      PlayerStatsDataset(
        rows: [
          game(id: 'p', name: 'Player', week: 1, yards: 200, team: 'BUF'),
          game(id: 'p', name: 'Player', week: 3, yards: 300, team: 'DAL'),
        ],
      ),
    );
    final historical = directory.lookup(
      playerName: 'Player',
      market: 'player_pass_yds',
      line: 250.5,
      side: LineSide.over,
      through: DateTime.utc(2026, 9, 2),
    );
    expect(historical.team, 'BUF');
    expect(historical.last5!.observed, 1);
    expect(historical.last5!.hits, 0);
  });
  test('history gap is a subtraction, and a missing side stays blank', () {
    expect(
      historyGap(clearRate: 0.6, fairProbability: 0.52),
      closeTo(0.08, 1e-12),
    );
    expect(historyGap(clearRate: null, fairProbability: 0.5), isNull);
    expect(historyGap(clearRate: 0.5, fairProbability: null), isNull);
    expect(historyGap(clearRate: double.nan, fairProbability: 0.5), isNull);
  });

  test(
    'two players with one name, or an unknown name, leave the hit rate blank',
    () {
      final data = PlayerStatsDataset(
        rows: [
          game(id: 'a', name: 'Alex Smith', week: 1, yards: 300),
          game(id: 'b', name: 'Alex Smith', week: 1, yards: 10, team: 'WAS'),
          game(id: 'c', name: 'Only One', week: 1, yards: 280),
          game(id: 'c', name: 'Only One', week: 2, yards: 100),
        ],
        metadata: const {'currentSeason': 2026},
      );
      final directory = PlayerDirectory(data);
      final ambiguous = directory.lookup(
        playerName: 'Alex Smith',
        market: 'player_pass_yds',
        line: 249.5,
        side: LineSide.over,
      );
      expect(ambiguous.hasAnyRate, isFalse);
      expect(ambiguous.note, contains('More than one player'));

      final unknown = directory.lookup(
        playerName: 'Nobody Real',
        market: 'player_pass_yds',
        line: 10,
        side: LineSide.over,
      );
      expect(unknown.hasAnyRate, isFalse);
      expect(unknown.note, contains('left blank'));

      final otherMarket = directory.lookup(
        playerName: 'Only One',
        market: 'player_assists',
        line: 1,
        side: LineSide.over,
      );
      expect(otherMarket.note, contains('not in the free NFL box scores'));

      final windows = directory.lookup(
        playerName: 'Only One',
        market: 'player_pass_yds',
        line: 249.5,
        side: LineSide.over,
        opponent: 'MIA',
      );
      expect(windows.playerId, 'c');
      expect(windows.team, 'BUF');
      expect(windows.last5!.hits, 1);
      expect(windows.last5!.misses, 1);
      expect(windows.last5!.clearRate, 0.5);
      expect(windows.season!.clearRate, 0.5);
      expect(windows.headToHead!.games, 2);
      expect(windows.note, contains('not a confirmation they are starting'));
    },
  );

  test('a missing stat is skipped, so it does not become a miss', () {
    final data = PlayerStatsDataset(
      rows: [
        game(id: 'c', name: 'Only One', week: 1, yards: null),
        game(id: 'c', name: 'Only One', week: 2, yards: 10),
      ],
    );
    final windows = PlayerDirectory(data).lookup(
      playerName: 'Only One',
      market: 'player_pass_yds',
      line: 249.5,
      side: LineSide.under,
    );
    expect(windows.last5!.missing, 1);
    expect(windows.last5!.hits, 1);
    expect(windows.last5!.misses, 0);
    expect(windows.last5!.clearRate, 1);
  });

  test(
    'Josh Allen in the bundled file is one player and has a counted rate',
    () {
      final data = PlayerStatsDataset.fromJson(
        jsonDecode(
          File('assets/nfl-player-stats.json')
              .readAsStringSync()
              .replaceFirst('\uFEFF', ''),
        ),
      );
      final windows = PlayerDirectory(data).lookup(
        playerName: 'Josh Allen',
        market: 'player_pass_yds',
        line: 249.5,
        side: LineSide.over,
      );
      expect(windows.playerId, '00-0034857');
      expect(windows.position, 'QB');
      expect(windows.team, 'BUF');
      expect(windows.seasonYear, 2026);
      expect(windows.last5, isNotNull);
      expect(windows.last5!.observed, inInclusiveRange(1, 5));
      expect(windows.last10!.observed, inInclusiveRange(1, 10));
      expect(windows.season!.observed, greaterThan(0));
      expect(windows.last5!.clearRate, isNotNull);
      expect(windows.note, contains('regular-season games only'));
    },
  );
}
