import 'dart:math' as math;

import 'injury_report.dart';
import 'nfl_teams.dart';

/// Live half of Coach's Line version 2.
///
/// The Python backtest in model/nfl_model_v2.py owns the fit. The app only
/// applies the stored scales to a current game. The constants below match
/// that file. A normal week, a closed roof, and the usual quarterback are zero.

const qbPointsPerEpa = 18.0;
const qbSwapCap = 6.0;
const backupEpa = -0.10;
const injuryTeamCap = 6.0;
const injuryTotalFactor = 0.35;
const qbTotalFactor = 0.25;

const positionWeights = <String, double>{
  'LT': 1.8,
  'RT': 1.5,
  'T': 1.6,
  'OT': 1.6,
  'LG': 0.9,
  'RG': 0.9,
  'G': 0.9,
  'C': 1.2,
  'OL': 1.1,
  'WR': 1.0,
  'TE': 0.8,
  'RB': 0.7,
  'HB': 0.7,
  'FB': 0.3,
  'DE': 1.0,
  'DT': 0.9,
  'DL': 0.9,
  'NT': 0.9,
  'EDGE': 1.2,
  'LB': 0.7,
  'ILB': 0.7,
  'OLB': 0.8,
  'MLB': 0.7,
  'CB': 0.9,
  'S': 0.6,
  'FS': 0.6,
  'SS': 0.6,
  'DB': 0.7,
  'SAF': 0.6,
  'K': 0.15,
  'P': 0.1,
  'LS': 0.05,
};

double normalCdf(double x) {
  if (x >= 8) return 1;
  if (x <= -8) return 0;
  final z = x.abs();
  final t = 1 / (1 + 0.2316419 * z);
  final density = 0.3989422804014327 * math.exp(-0.5 * z * z);
  final poly = t *
      (0.319381530 +
          t *
              (-0.356563782 +
                  t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
  final tail = density * poly;
  if (x >= 0) return 1 - tail;
  return tail;
}

double positionWeight(String position) {
  final key = position.trim().toUpperCase();
  if (key == 'QB' || key == 'QUARTERBACK') return 0;
  return positionWeights[key] ?? 0.4;
}

double injuryPoints(String position, double snapShare) {
  if (snapShare <= 0) return 0;
  return positionWeight(position) * math.min(snapShare, 1);
}

double qbSwapPoints({
  required String starterId,
  required String usualId,
  required double starterEpa,
  required double usualEpa,
}) {
  if (starterId.isEmpty || usualId.isEmpty || starterId == usualId) return 0;
  final raw = (starterEpa - usualEpa) * qbPointsPerEpa;
  return raw.clamp(-qbSwapCap, qbSwapCap).toDouble();
}

double restSidePoints(double days) {
  if (days <= 5) return math.max(-2, (days - 7) * 0.45);
  if (days >= 10) return math.min(0.8, (days - 7) * 0.15);
  return 0;
}

double travelMarginPoints(double? awayHomeLon, double? gameLon) {
  if (awayHomeLon == null || gameLon == null) return 0;
  final zones = (gameLon - awayHomeLon) / 15;
  if (zones.abs() < 1.5) return 0;
  return (0.35 * zones).clamp(-1.0, 1.0).toDouble();
}

double weatherTotalPoints({
  required double? windMph,
  required double? tempF,
  required double? precipMm,
  required bool openRoof,
}) {
  if (!openRoof) return 0;
  final wind = windMph == null ? 0.0 : math.min(8, math.max(0, windMph - 8) * 0.35);
  final cold = tempF == null ? 0.0 : math.min(3, math.max(0, 35 - tempF) * 0.05);
  var rain = 0.0;
  if (precipMm != null) {
    if (precipMm >= 4) {
      rain = 2.5;
    } else if (precipMm >= 1) {
      rain = 1.2;
    } else if (precipMm >= 0.3) {
      rain = 0.5;
    }
  }
  return math.max(-10, -(wind + cold + rain));
}

List<double> scaleAndCap(List<double> parts, List<double> scales, double cap) {
  if (parts.length != scales.length) {
    throw ArgumentError('Each nudge needs one scale.');
  }
  final scaled = [
    for (var i = 0; i < parts.length; i++) parts[i] * scales[i],
  ];
  final total = scaled.fold<double>(0, (sum, part) => sum + part);
  if (total.abs() > cap && total.abs() > 1e-12) {
    final factor = cap / total.abs();
    return [for (final part in scaled) part * factor];
  }
  return scaled;
}

double shiftedProbability(double? marketProbability, double deltaPoints, double sigma) {
  if (sigma <= 0) throw ArgumentError('sigma must be positive.');
  final base = (marketProbability ?? 0.5).clamp(0.02, 0.98).toDouble();
  final shift = normalCdf(deltaPoints / sigma) - 0.5;
  return (base + shift).clamp(0.02, 0.98).toDouble();
}

double _logit(double probability) {
  final p = probability.clamp(1e-6, 1 - 1e-6).toDouble();
  return math.log(p / (1 - p));
}

double applyPlatt(double probability, double intercept, double slope) {
  final linear = (intercept + slope * _logit(probability)).clamp(-20.0, 20.0);
  return 1 / (1 + math.exp(-linear));
}

String normName(String name) {
  final text = name
      .toLowerCase()
      .replaceAll("'", '')
      .replaceAll('’', '')
      .replaceAll('.', ' ')
      .replaceAll('-', ' ');
  return text.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).join(' ');
}

bool namesMatch(String left, String right) {
  final a = normName(left);
  final b = normName(right);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  final aParts = a.split(' ');
  final bParts = b.split(' ');
  if (aParts.length < 2 || bParts.length < 2 || aParts.last != bParts.last) {
    return false;
  }
  final firstA = aParts.first;
  final firstB = bParts.first;
  if (firstA.length <= 2 && firstB.startsWith(firstA[0])) return true;
  if (firstB.length <= 2 && firstA.startsWith(firstB[0])) return true;
  return false;
}

class V2Scales {
  const V2Scales({
    required this.qb,
    required this.injury,
    required this.rest,
    required this.travel,
    required this.weather,
    required this.injuryTotal,
    required this.qbTotal,
  });

  final double qb, injury, rest, travel, weather, injuryTotal, qbTotal;

  List<double> get margin => [qb, injury, rest, travel];
  List<double> get total => [weather, injuryTotal, qbTotal];

  factory V2Scales.fromJson(Map<String, dynamic> json) {
    double read(String key) {
      final value = json[key];
      if (value is! num || !value.isFinite) return 0;
      return value.toDouble();
    }

    return V2Scales(
      qb: read('qb'),
      injury: read('injury'),
      rest: read('rest'),
      travel: read('travel'),
      weather: read('weather'),
      injuryTotal: read('injuryTotal'),
      qbTotal: read('qbTotal'),
    );
  }
}

class PlattFit {
  const PlattFit({required this.intercept, required this.slope});

  final double intercept;
  final double slope;

  double apply(double probability) => applyPlatt(probability, intercept, slope);

  factory PlattFit.fromJson(Object? json) {
    if (json is! Map) return const PlattFit(intercept: 0, slope: 1);
    final intercept = json['intercept'];
    final slope = json['slope'];
    return PlattFit(
      intercept: intercept is num ? intercept.toDouble() : 0,
      slope: slope is num ? slope.toDouble() : 1,
    );
  }
}

class V2Quarterback {
  const V2Quarterback({
    required this.id,
    required this.name,
    required this.epa,
    required this.dropbacks,
  });

  final String id;
  final String name;
  final double epa;
  final double dropbacks;

  factory V2Quarterback.fromJson(Object? json) {
    if (json is! Map) {
      return const V2Quarterback(id: '', name: '', epa: 0, dropbacks: 0);
    }
    return V2Quarterback(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      epa: json['epa'] is num ? (json['epa'] as num).toDouble() : 0,
      dropbacks: json['dropbacks'] is num
          ? (json['dropbacks'] as num).toDouble()
          : 0,
    );
  }
}

class V2TeamContext {
  const V2TeamContext({
    required this.homeLon,
    required this.usual,
    required this.planned,
    required this.replacements,
  });

  final double? homeLon;
  final V2Quarterback? usual;
  final V2Quarterback? planned;
  final List<V2Quarterback> replacements;
}

class V2PlayerWeight {
  const V2PlayerWeight({
    required this.team,
    required this.name,
    required this.position,
    required this.points,
  });

  final String team;
  final String name;
  final String position;
  final double points;
}

class GameForecast {
  const GameForecast({
    required this.home,
    required this.away,
    required this.stadium,
    required this.openRoof,
    required this.windMph,
    required this.tempF,
    required this.precipMm,
    required this.source,
    required this.at,
    required this.longitude,
  });

  final String home;
  final String away;
  final String stadium;
  final bool openRoof;
  final double? windMph;
  final double? tempF;
  final double? precipMm;
  final String source;
  final String at;
  final double? longitude;

  String get conditions {
    if (!openRoof) return 'Roof closed';
    final bits = <String>[
      if (tempF != null) '${tempF!.round()}°F',
      if (windMph != null) '${windMph!.round()} mph',
      if (precipMm != null && precipMm! >= 0.3) 'rain',
    ];
    if (stadium.isEmpty) return bits.isEmpty ? 'Open roof' : bits.join(' · ');
    final sky = bits.isEmpty ? 'Open roof' : bits.join(' · ');
    return '$stadium · $sky';
  }
}

class LineNudge {
  const LineNudge({
    required this.label,
    required this.points,
    this.detail = '',
  });

  final String label;
  final double points;
  final String detail;
}

class LineBreakdown {
  const LineBreakdown({
    required this.marketSource,
    required this.marketMargin,
    required this.finalMargin,
    required this.spread,
    required this.marketTotal,
    required this.finalTotal,
    required this.total,
    required this.homeCover,
    required this.overChance,
  });

  /// "Pinnacle" when that book is in the snapshot, otherwise "Books".
  final String marketSource;
  final double marketMargin;
  final double finalMargin;
  final List<LineNudge> spread;
  final double? marketTotal;
  final double? finalTotal;
  final List<LineNudge> total;
  final double? homeCover;
  final double? overChance;
}

double chooseQuarterback({
  required V2Quarterback? usual,
  required V2Quarterback? planned,
  required List<V2Quarterback> replacements,
  required List<String> outNames,
}) {
  if (usual == null || usual.id.isEmpty) return 0;
  bool isOut(String name) => outNames.any((out) => namesMatch(name, out));
  var starter = planned ?? usual;
  if (starter.name.isNotEmpty && isOut(starter.name)) {
    V2Quarterback? next;
    for (final qb in replacements) {
      if (!isOut(qb.name)) {
        next = qb;
        break;
      }
    }
    starter = next ??
        V2Quarterback(
          id: 'backup',
          name: 'Backup',
          epa: backupEpa,
          dropbacks: 0,
        );
  }
  return qbSwapPoints(
    starterId: starter.id,
    usualId: usual.id,
    starterEpa: starter.epa,
    usualEpa: usual.epa,
  );
}

GameForecast? forecastFor(
  List<GameForecast> forecasts,
  String home,
  String away,
) {
  GameForecast? homeOnly;
  for (final forecast in forecasts) {
    if (forecast.home != home) continue;
    if (forecast.away == away) return forecast;
    homeOnly ??= forecast;
  }
  return homeOnly;
}

List<String> _outsFor(InjuryReport? injuries, String team) {
  if (injuries == null) return const [];
  final abbr = canonicalTeam(team) ?? team;
  final names = <String>[];
  for (final entry in injuries.entries) {
    if (!entry.outLike) continue;
    final entryTeam = canonicalTeam(entry.team) ?? entry.team;
    if (entryTeam != abbr && entry.team.toUpperCase() != abbr) continue;
    if (entry.player.trim().isEmpty) continue;
    names.add(entry.player);
  }
  return names;
}

double _injurySide(List<V2PlayerWeight> players, String team, List<String> outs) {
  if (outs.isEmpty) return 0;
  var total = 0.0;
  final seen = <String>{};
  for (final player in players) {
    if (player.team != team) continue;
    final key = normName(player.name);
    if (key.isEmpty || seen.contains(key)) continue;
    if (!outs.any((out) => namesMatch(player.name, out))) continue;
    seen.add(key);
    total += player.points;
  }
  return math.min(injuryTeamCap, total);
}

/// The line for one game. [marketMargin] is the home side's expected margin
/// (the home spread with the sign flipped). Positive nudges favor the home team.
LineBreakdown projectVersion2({
  required V2Scales scales,
  required PlattFit cover,
  required PlattFit totalFit,
  required double sigma,
  required double totalSigma,
  required double marginCap,
  required double totalCap,
  required Map<String, V2TeamContext> teams,
  required List<V2PlayerWeight> players,
  required List<GameForecast> forecasts,
  required String home,
  required String away,
  required double marketMargin,
  required double? marketTotal,
  required double marketCover,
  required double marketOver,
  required String marketSource,
  required int? homeRest,
  required int? awayRest,
  InjuryReport? injuries,
}) {
  final homeTeam = teams[home];
  final awayTeam = teams[away];
  final homeOuts = _outsFor(injuries, home);
  final awayOuts = _outsFor(injuries, away);
  final homeQb = chooseQuarterback(
    usual: homeTeam?.usual,
    planned: homeTeam?.planned,
    replacements: homeTeam?.replacements ?? const [],
    outNames: homeOuts,
  );
  final awayQb = chooseQuarterback(
    usual: awayTeam?.usual,
    planned: awayTeam?.planned,
    replacements: awayTeam?.replacements ?? const [],
    outNames: awayOuts,
  );
  final homeInjury = _injurySide(players, home, homeOuts);
  final awayInjury = _injurySide(players, away, awayOuts);
  final forecast = forecastFor(forecasts, home, away);
  final gameLon = forecast?.longitude ?? homeTeam?.homeLon;
  final spreadParts = scaleAndCap(
    [
      homeQb - awayQb,
      awayInjury - homeInjury,
      (homeRest == null ? 0 : restSidePoints(homeRest.toDouble())) -
          (awayRest == null ? 0 : restSidePoints(awayRest.toDouble())),
      travelMarginPoints(awayTeam?.homeLon, gameLon),
    ],
    scales.margin,
    marginCap,
  );
  final qbNames = <String>[];
  if (homeQb.abs() >= 0.05 && homeTeam?.planned != null) {
    qbNames.add(homeTeam!.planned!.name);
  }
  if (awayQb.abs() >= 0.05 && awayTeam?.planned != null) {
    qbNames.add(awayTeam!.planned!.name);
  }
  final spread = [
    LineNudge(
      label: 'Quarterback',
      points: spreadParts[0],
      detail: qbNames.isEmpty ? 'Usual starters' : qbNames.join(' · '),
    ),
    LineNudge(
      label: 'Injuries',
      points: spreadParts[1],
      detail: homeOuts.isEmpty && awayOuts.isEmpty
          ? 'No weighted outs'
          : '${homeOuts.length + awayOuts.length} out',
    ),
    LineNudge(
      label: 'Rest',
      points: spreadParts[2],
      detail: homeRest == null && awayRest == null ? '' : 'Days since the last game',
    ),
    LineNudge(
      label: 'Travel',
      points: spreadParts[3],
      detail: spreadParts[3].abs() < 0.05 ? '' : 'Time zones',
    ),
  ];
  final finalMargin = marketMargin + spreadParts.fold<double>(0, (sum, part) => sum + part);
  double? finalTotal;
  var totalNudges = <LineNudge>[];
  if (marketTotal != null) {
    final open = forecast?.openRoof ?? false;
    final totalParts = scaleAndCap(
      [
        weatherTotalPoints(
          windMph: forecast?.windMph,
          tempF: forecast?.tempF,
          precipMm: forecast?.precipMm,
          openRoof: open,
        ),
        -injuryTotalFactor * (homeInjury + awayInjury),
        qbTotalFactor * (homeQb + awayQb),
      ],
      scales.total,
      totalCap,
    );
    totalNudges = [
      LineNudge(
        label: 'Weather',
        points: totalParts[0],
        detail: forecast == null
            ? 'No forecast'
            : forecast.conditions,
      ),
      LineNudge(label: 'Injuries', points: totalParts[1]),
      LineNudge(label: 'Quarterback', points: totalParts[2]),
    ];
    finalTotal = marketTotal + totalParts.fold<double>(0, (sum, part) => sum + part);
  }
  final homeCover = cover.apply(
    shiftedProbability(marketCover, finalMargin - marketMargin, sigma),
  );
  final over = finalTotal == null || marketTotal == null
      ? null
      : totalFit.apply(
          shiftedProbability(marketOver, finalTotal - marketTotal, totalSigma),
        );
  return LineBreakdown(
    marketSource: marketSource,
    marketMargin: finalMargin - spread.fold<double>(0, (sum, nudge) => sum + nudge.points),
    finalMargin: finalMargin,
    spread: spread,
    marketTotal: marketTotal,
    finalTotal: finalTotal,
    total: totalNudges,
    homeCover: homeCover,
    overChance: over,
  );
}
