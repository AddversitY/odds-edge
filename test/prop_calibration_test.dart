import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_calibration.dart';
import 'package:odds_edge/domain/prop_model.dart';

PlayerGame box({
  required String id,
  required String name,
  required String position,
  required String team,
  required String opponent,
  required int season,
  required int week,
  required Map<String, num> stats,
}) {
  return PlayerGame(
    playerId: id,
    name: name,
    position: position,
    team: team,
    opponent: opponent,
    season: season,
    week: week,
    date: DateTime.utc(season, 9, week.clamp(1, 28)),
    seasonType: 'REG',
    stats: stats,
  );
}

void main() {
  test('isotonic pulls an overconfident chance down and stays monotone', () {
    final rows = <({double raw, bool hit})>[
      for (var i = 0; i < 80; i++) (raw: 0.30, hit: i < 16),
      for (var i = 0; i < 80; i++) (raw: 0.52, hit: i < 36),
      for (var i = 0; i < 80; i++) (raw: 0.70, hit: i < 56),
    ];
    final fit = fitPropCalibrator(rows);
    expect(fit.isIdentity, isFalse);
    expect(fit.samples, 240);
    expect(fit.apply(0.30), closeTo(0.20, 0.02));
    expect(fit.apply(0.52), closeTo(0.45, 0.02));
    expect(fit.apply(0.70), closeTo(0.70, 0.02));
    expect(fit.apply(0.30), lessThan(fit.apply(0.52)));
    expect(fit.apply(0.52), lessThanOrEqualTo(fit.apply(0.70) + 1e-9));
    expect(fit.apply(0.10), lessThanOrEqualTo(fit.apply(0.30)));
    expect(fit.apply(0.90), greaterThanOrEqualTo(fit.apply(0.70) - 1e-9));
  });

  test('fewer than 200 earlier forecasts leave the chance where it is', () {
    final rows = [
      for (var i = 0; i < calibrationMinSamples - 1; i++)
        (raw: 0.80, hit: false),
    ];
    final fit = fitPropCalibrator(rows);
    expect(fit.isIdentity, isTrue);
    expect(fit.apply(0.80), closeTo(0.80, 1e-9));
  });

  test('a fit already made does not change when later games are added', () {
    final early = [
      for (var i = 0; i < 200; i++) (raw: 0.60, hit: i < 80),
    ];
    final first = fitPropCalibrator(early);
    final later = fitPropCalibrator([
      ...early,
      for (var i = 0; i < 200; i++) (raw: 0.60, hit: false),
    ]);
    expect(first.apply(0.60), closeTo(0.40, 0.02));
    expect(later.apply(0.60), lessThan(first.apply(0.60)));
  });

  test('a later week does not change an earlier recalibrated chance', () {
    List<PlayerGame> season({
      required int year,
      required int from,
      required int to,
      required double yards,
    }) {
      return [
        for (var n = 0; n < 40; n++)
          for (var week = from; week <= to; week++) ...[
            box(
              id: 'qb$n',
              name: 'Passer $n',
              position: 'QB',
              team: 'T$n',
              opponent: 'F$n',
              season: year,
              week: week,
              stats: {'attempts': 35, 'passing_yards': 240 + n},
            ),
            box(
              id: 'wr$n',
              name: 'Catcher $n',
              position: 'WR',
              team: 'T$n',
              opponent: 'F$n',
              season: year,
              week: week,
              stats: {
                'targets': 8,
                'receiving_yards': yards + n,
              },
            ),
          ],
      ];
    }

    final early = [
      ...season(year: 2024, from: 1, to: 8, yards: 70),
      ...season(year: 2025, from: 1, to: 6, yards: 8),
    ];
    final later = [
      ...early,
      ...season(year: 2025, from: 7, to: 8, yards: 8),
    ];
    final first = comparePropModels(early, keepForecasts: true);
    final second = comparePropModels(later, keepForecasts: true);
    expect(first.calibratedChances.length, greaterThan(200));
    expect(
      second.calibratedChances.length,
      greaterThan(first.calibratedChances.length),
    );
    expect(
      _isSubsequence(second.calibratedChances, first.calibratedChances),
      isTrue,
    );
    var moved = false;
    for (var i = 0; i < first.usageChances.length; i++) {
      if (first.calibratedChances[i] < first.usageChances[i] - 0.01) {
        moved = true;
        break;
      }
    }
    expect(moved, isTrue);
  });
}

bool _isSubsequence(List<double> longer, List<double> shorter) {
  var index = 0;
  for (final value in longer) {
    if (index < shorter.length && (value - shorter[index]).abs() < 1e-9) {
      index++;
    }
  }
  return index == shorter.length;
}
