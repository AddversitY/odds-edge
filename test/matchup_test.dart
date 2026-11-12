import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/matchup.dart';
import 'package:odds_edge/domain/player_stats.dart';

void main() {
  PlayerGame game({
    required String name,
    required String position,
    required String team,
    required String opponent,
    required int week,
    required num yards,
    String metric = 'passing_yards',
  }) => PlayerGame(
    playerId: name.toLowerCase().replaceAll(' ', '-'),
    name: name,
    position: position,
    team: team,
    opponent: opponent,
    season: 2026,
    week: week,
    date: DateTime.utc(2026, 9, week),
    seasonType: 'REG',
    stats: {metric: yards},
  );

  HitRate rate(int hits, int games) => HitRate(
    label: 'season',
    games: games,
    hits: hits,
    misses: games - hits,
    pushes: 0,
    missing: 0,
    samples: const [],
  );

  test('defense rank, injuries, script, and snaps stay in one sentence', () {
    final rows = [
      for (var week = 1; week <= 3; week++) ...[
        game(
          name: 'A Quarterback',
          position: 'QB',
          team: 'BUF',
          opponent: 'KC',
          week: week,
          yards: 180,
        ),
        game(
          name: 'B Quarterback',
          position: 'QB',
          team: 'DET',
          opponent: 'BUF',
          week: week,
          yards: 320,
        ),
      ],
    ];
    final defense = defenseAllowed(
      rows: rows,
      opponent: 'KC',
      playerPosition: 'QB',
      metric: 'passing_yards',
      season: 2026,
    );
    expect(defense, isNotNull);
    expect(defense!.rank, 1);
    expect(defense.teams, 2);
    expect(defense.statLabel, contains('quarterbacks'));

    final context = MatchupContext(
      season: 2026,
      note: MatchupContext.participationNote,
      injuries: const [
        ListedInjury(
          week: 3,
          team: 'BUF',
          player: 'Top Receiver',
          position: 'WR',
          status: 'Out',
          injury: 'Ankle',
        ),
        ListedInjury(
          week: 3,
          team: 'KC',
          player: 'Corner One',
          position: 'CB',
          status: 'Questionable',
          injury: 'Hamstring',
        ),
        ListedInjury(
          week: 3,
          team: 'BUF',
          player: 'Kicker',
          position: 'K',
          status: 'Out',
        ),
      ],
      snaps: const [
        SnapShare(
          week: 3,
          team: 'BUF',
          opponent: 'KC',
          player: 'Josh Allen',
          position: 'QB',
          offensePct: 0.98,
        ),
      ],
    );
    final card = buildMatchup(
      player: 'Josh Allen',
      market: 'player_pass_yds',
      lineLabel: 'Over 249.5',
      valueWord: 'Skip',
      rows: rows,
      context: context,
      playerTeam: 'BUF',
      position: 'QB',
      opponent: 'KC',
      teamSpread: 7.5,
      total: 51,
      season: rate(2, 5),
    );
    expect(card.sentence, contains('Josh Allen'));
    expect(card.sentence, contains('ranks 1'));
    expect(card.sentence, contains('Top Receiver'));
    expect(card.sentence, contains('Corner One'));
    expect(card.sentence.toLowerCase(), contains('trailing'));
    expect(card.sentence, endsWith('so this is a skip.'));
    expect(card.injuryLine.contains('Kicker'), isFalse);
    expect(card.snapLine, contains('98%'));
    expect(card.snapLine, contains('participation'));
    expect(card.credit, contains('CC BY 4.0'));
    expect(card.scriptLine, contains('more passes'));
  });

  test('missing defense, injuries, and snaps stay blank', () {
    final context = MatchupContext(
      note: MatchupContext.participationNote,
      injuries: const [],
      snaps: const [],
    );
    final card = buildMatchup(
      player: 'Josh Allen',
      market: 'player_pass_yds',
      lineLabel: 'Over 249.5',
      valueWord: 'Skip',
      rows: const [],
      context: context,
    );
    expect(card.defenseLine, contains('No defensive rank'));
    expect(card.injuryLine, contains('No Out or Questionable'));
    expect(card.snapLine, contains('No snap count'));
    expect(card.snapLine, contains('participation'));
    expect(card.scriptLine, contains('left blank'));
  });

  test('Rams box scores use LA', () {
    expect(boxScoreTeam('LAR'), 'LA');
    expect(boxScoreTeam('BUF'), 'BUF');
  });
}
