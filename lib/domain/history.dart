class HistoricalGame {
  const HistoricalGame({
    required this.season,
    this.week = 1,
    required this.date,
    required this.home,
    required this.away,
    required this.homeScore,
    required this.awayScore,
  });
  final int season, homeScore, awayScore, week;
  final DateTime date;
  final String home, away;
  factory HistoricalGame.fromJson(Map<String, dynamic> j) => HistoricalGame(
    season: j['season'],
    week: j['week'],
    date: DateTime.parse(j['date']),
    home: j['home'],
    away: j['away'],
    homeScore: j['homeScore'],
    awayScore: j['awayScore'],
  );
}

/// NFL calendar-week windows. A bye contributes no observation, never a zero.
List<HistoricalGame> gamesBeforeWeek(
  List<HistoricalGame> games,
  String team,
  int season,
  int beforeWeek, {
  int? lastWeeks,
}) =>
    games
        .where(
          (g) =>
              g.season == season &&
              (g.home == team || g.away == team) &&
              g.week < beforeWeek &&
              (lastWeeks == null || g.week >= beforeWeek - lastWeeks),
        )
        .toList()
      ..sort((a, b) => a.week.compareTo(b.week));

List<HistoricalGame> recentGames(
  List<HistoricalGame> games,
  String team,
  int season,
  int beforeWeek,
  int count,
) {
  if (count < 1) throw ArgumentError.value(count, 'count');
  final prior = gamesBeforeWeek(games, team, season, beforeWeek);
  return prior.length <= count ? prior : prior.sublist(prior.length - count);
}

class TeamWindow {
  TeamWindow(this.games, this.team);
  final List<HistoricalGame> games;
  final String team;
  int own(HistoricalGame g) => g.home == team ? g.homeScore : g.awayScore;
  int opponent(HistoricalGame g) => g.home == team ? g.awayScore : g.homeScore;
  int get wins => games.where((g) => own(g) > opponent(g)).length;
  int get losses => games.where((g) => own(g) < opponent(g)).length;
  int get ties => games.length - wins - losses;
  double? get pointsFor => games.isEmpty
      ? null
      : games.map(own).reduce((a, b) => a + b) / games.length;
  double? get pointsAgainst => games.isEmpty
      ? null
      : games.map(opponent).reduce((a, b) => a + b) / games.length;
  double? get margin => games.isEmpty ? null : pointsFor! - pointsAgainst!;
}

/// Fixed chronological holdout demonstration, not a betting model.
class HistoricalBenchmark {
  HistoricalBenchmark(List<HistoricalGame> games) {
    final train = games
        .where(
          (g) =>
              g.season >= 2022 &&
              g.season <= 2024 &&
              g.homeScore != g.awayScore,
        )
        .toList();
    final test = games
        .where((g) => g.season == 2025 && g.homeScore != g.awayScore)
        .toList();
    trainingCount = train.length;
    testCount = test.length;
    if (train.isEmpty || test.isEmpty) return;
    probability =
        train.where((g) => g.homeScore > g.awayScore).length / train.length;
    brier =
        test
            .map((g) {
              final error = probability! - (g.homeScore > g.awayScore ? 1 : 0);
              return error * error;
            })
            .reduce((a, b) => a + b) /
        test.length;
  }
  int trainingCount = 0, testCount = 0;
  double? probability, brier;
}
