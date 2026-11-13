import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/coach_line_v2.dart';
import 'package:odds_edge/domain/injury_report.dart';

void main() {
  test('the normal curve matches the usual checkpoints', () {
    expect(normalCdf(0), closeTo(0.5, 1e-4));
    expect(normalCdf(1), closeTo(0.841345, 1e-3));
    expect(normalCdf(-1), closeTo(1 - normalCdf(1), 1e-9));
  });

  test('a zero residual leaves the market chance where it was', () {
    expect(shiftedProbability(0.53, 0, 13), closeTo(0.53, 1e-6));
    expect(shiftedProbability(null, 0, 13), closeTo(0.5, 1e-6));
  });

  test('the usual quarterback adds nothing, and a swap is capped', () {
    expect(
      qbSwapPoints(
        starterId: 'love',
        usualId: 'love',
        starterEpa: 0.2,
        usualEpa: -0.4,
      ),
      0,
    );
    expect(
      qbSwapPoints(
        starterId: '',
        usualId: 'love',
        starterEpa: 0.2,
        usualEpa: 0,
      ),
      0,
    );
    expect(
      qbSwapPoints(
        starterId: 'backup',
        usualId: 'love',
        starterEpa: 0.2,
        usualEpa: 0,
      ),
      closeTo(3.6, 1e-9),
    );
    expect(
      qbSwapPoints(
        starterId: 'backup',
        usualId: 'love',
        starterEpa: 1,
        usualEpa: -1,
      ),
      qbSwapCap,
    );
  });

  test('injuries are weighted by position and snaps, and a quarterback is not counted twice', () {
    expect(injuryPoints('QB', 1), 0);
    expect(injuryPoints('LT', 1), closeTo(1.8, 1e-9));
    expect(injuryPoints('WR', 0.5), closeTo(0.5, 1e-9));
    expect(injuryPoints('K', 1), closeTo(0.15, 1e-9));
    expect(injuryPoints('WR', 0), 0);
    expect(positionWeight('ZZ'), 0.4);
  });

  test('weather changes an open-roof total and leaves a closed roof alone', () {
    expect(
      weatherTotalPoints(windMph: 20, tempF: 10, precipMm: 5, openRoof: false),
      0,
    );
    expect(
      weatherTotalPoints(windMph: 2, tempF: 70, precipMm: 0, openRoof: true),
      0,
    );
    // 18 mph → 3.5, 20°F → 0.75, 4 mm → 2.5.
    expect(
      weatherTotalPoints(windMph: 18, tempF: 20, precipMm: 4, openRoof: true),
      closeTo(-6.75, 1e-9),
    );
  });

  test('rest and travel are zero on an ordinary week', () {
    expect(restSidePoints(7), 0);
    expect(restSidePoints(6), 0);
    expect(restSidePoints(9), 0);
    expect(restSidePoints(4), lessThan(0));
    expect(restSidePoints(12), greaterThan(0));
    expect(travelMarginPoints(-88, -80), 0);
    expect(travelMarginPoints(-118, -71), closeTo(1, 1e-9));
  });

  test('scaled nudges cannot add up past the cap', () {
    final scaled = scaleAndCap([10, 10], [1, 1], 4);
    expect(scaled.reduce((a, b) => a + b), closeTo(4, 1e-9));
    final quiet = scaleAndCap([1, -1], [0.5, 0.5], 4);
    expect(quiet, [0.5, -0.5]);
  });

  test('an initial can match a full name, and two different Allens do not', () {
    expect(namesMatch('J. Love', 'Jordan Love'), isTrue);
    expect(namesMatch('Josh Allen', 'Jason Allen'), isFalse);
    expect(namesMatch('Ja\'Marr Chase', 'Jamarr Chase'), isTrue);
  });

  test('with no nudges the line stays on the market', () {
    final line = projectVersion2(
      scales: const V2Scales(
        qb: 1,
        injury: 1,
        rest: 1,
        travel: 1,
        weather: 1,
        injuryTotal: 1,
        qbTotal: 1,
      ),
      cover: const PlattFit(intercept: 0, slope: 1),
      totalFit: const PlattFit(intercept: 0, slope: 1),
      sigma: 13,
      totalSigma: 13,
      marginCap: 4,
      totalCap: 6,
      teams: {
        'GB': V2TeamContext(
          homeLon: -88.06,
          usual: const V2Quarterback(
            id: 'love',
            name: 'Jordan Love',
            epa: 0.15,
            dropbacks: 2000,
          ),
          planned: const V2Quarterback(
            id: 'love',
            name: 'Jordan Love',
            epa: 0.15,
            dropbacks: 2000,
          ),
          replacements: const [],
        ),
        'MIN': V2TeamContext(
          homeLon: -93.26,
          usual: const V2Quarterback(
            id: 'cousins',
            name: 'Kirk Cousins',
            epa: 0.05,
            dropbacks: 3000,
          ),
          planned: const V2Quarterback(
            id: 'cousins',
            name: 'Kirk Cousins',
            epa: 0.05,
            dropbacks: 3000,
          ),
          replacements: const [],
        ),
      },
      players: const [],
      forecasts: const [
        GameForecast(
          home: 'GB',
          away: 'MIN',
          stadium: 'Lambeau Field',
          openRoof: true,
          windMph: 2,
          tempF: 45,
          precipMm: 0,
          source: 'nws',
          at: '2026-11-15T18:00:00Z',
          longitude: -88.0622,
        ),
      ],
      home: 'GB',
      away: 'MIN',
      marketMargin: 2.5,
      marketTotal: 43.5,
      marketCover: 0.5,
      marketOver: 0.5,
      marketSource: 'Pinnacle',
      homeRest: 7,
      awayRest: 7,
    );
    expect(line.finalMargin, closeTo(2.5, 1e-9));
    expect(line.finalTotal, closeTo(43.5, 1e-9));
    expect(line.homeCover, closeTo(0.5, 1e-6));
    expect(line.spread.every((nudge) => nudge.points.abs() < 1e-9), isTrue);
  });

  test('an out tackle moves the market, and a closed roof does not', () {
    final line = projectVersion2(
      scales: const V2Scales(
        qb: 1,
        injury: 1,
        rest: 1,
        travel: 1,
        weather: 1,
        injuryTotal: 1,
        qbTotal: 1,
      ),
      cover: const PlattFit(intercept: 0, slope: 1),
      totalFit: const PlattFit(intercept: 0, slope: 1),
      sigma: 13,
      totalSigma: 13,
      marginCap: 4,
      totalCap: 6,
      teams: const {},
      players: const [
        V2PlayerWeight(team: 'CLE', name: 'Jack Conklin', position: 'RT', points: 1.5),
      ],
      forecasts: const [
        GameForecast(
          home: 'CLE',
          away: 'HOU',
          stadium: 'Huntington Bank Field',
          openRoof: true,
          windMph: 12,
          tempF: 47,
          precipMm: 0.4,
          source: 'nws',
          at: '2026-11-15T18:00:00Z',
          longitude: -81.6995,
        ),
      ],
      home: 'CLE',
      away: 'HOU',
      marketMargin: 3,
      marketTotal: 41.5,
      marketCover: 0.52,
      marketOver: 0.5,
      marketSource: 'Books',
      homeRest: 7,
      awayRest: 7,
      injuries: InjuryReport(
        fetchedAt: DateTime.utc(2026, 11, 13),
        live: false,
        changes: const [],
        sources: const [],
        notice: '',
        entries: [
          InjuryEntry(
            player: 'Jack Conklin',
            team: 'CLE',
            position: 'RT',
            status: 'Out',
            sourceId: 'test',
            sourceLabel: 'test',
            official: false,
            fetchedAt: DateTime.utc(2026, 11, 13),
          ),
        ],
      ),
    );
    expect(line.spread[1].points, closeTo(-1.5, 1e-9));
    expect(line.finalMargin, closeTo(1.5, 1e-9));
    expect(line.total.first.points, lessThan(0));
    expect(line.finalTotal, lessThan(41.5));
  });
}
