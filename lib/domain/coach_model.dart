import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'coach_line_v2.dart';
import 'injury_report.dart';
import 'nfl_teams.dart';
import 'odds.dart';
import 'value_check.dart';

/// How much a past game still counts. A game one half-life ago counts half.
double decayWeight(int daysAgo, {double halfLifeDays = 42}) {
  if (daysAgo < 0) {
    throw ArgumentError('A future game cannot be part of a rating.');
  }
  if (halfLifeDays <= 0) {
    throw ArgumentError('The half-life has to be a positive number of days.');
  }
  return math.pow(0.5, daysAgo / halfLifeDays).toDouble();
}

/// Play-weighted average. Each sample is the rate, the number of plays, and
/// how many days ago the game was. The prior keeps a short sample near average.
double shrunkAverage(
  List<(double rate, double plays, int daysAgo)> samples, {
  required double priorValue,
  double priorPlays = 200,
}) {
  if (priorPlays <= 0) {
    throw ArgumentError('The prior needs a positive number of plays.');
  }
  var numerator = priorValue * priorPlays;
  var denominator = priorPlays;
  for (final (rate, plays, daysAgo) in samples) {
    if (plays < 0) throw ArgumentError('Plays cannot be negative.');
    final weight = plays * decayWeight(daysAgo);
    numerator += rate * weight;
    denominator += weight;
  }
  return numerator / denominator;
}

/// Home margin in points. Positive means the home team is expected to win by that many.
double projectedMargin({
  required double homeNet,
  required double awayNet,
  required double scale,
  required double homeField,
}) => scale * (homeNet - awayNet) + homeField;

/// Offense and defense rates added together. Defense is the EPA the defense
/// allows, so a higher number means more scoring.
double combinedScoringRate({
  required double homeOff,
  required double homeDef,
  required double awayOff,
  required double awayDef,
}) => homeOff + homeDef + awayOff + awayDef;

double projectedTotal({
  required double homeOff,
  required double homeDef,
  required double awayOff,
  required double awayDef,
  required double intercept,
  required double scale,
}) =>
    intercept +
    scale *
        combinedScoringRate(
          homeOff: homeOff,
          homeDef: homeDef,
          awayOff: awayOff,
          awayDef: awayDef,
        );

/// True when [season]/[week] is strictly earlier than the week being scored.
/// The same week is not training material.
bool gameIsBefore(int season, int week, int testSeason, int testWeek) {
  if (season < testSeason) return true;
  if (season > testSeason) return false;
  return week < testWeek;
}

double _sigmoid(double logit) {
  if (logit >= 20) return 1;
  if (logit <= -20) return 0;
  return 1 / (1 + math.exp(-logit));
}

/// Home covered when the final margin plus the home number is greater than zero.
/// A zero result is a push, returned as null.
bool? homeCovered(double margin, double spreadLine) {
  final result = margin + spreadLine;
  if (result.abs() < 1e-6) return null;
  return result > 0;
}

bool? overHit(double total, double totalLine) {
  final result = total - totalLine;
  if (result.abs() < 1e-6) return null;
  return result > 0;
}

/// Chance the side the books favored covers. Null when the line is a pick'em.
double? favoriteCoverProbability(
  double homeCoverProbability,
  double marketMargin,
) {
  if (marketMargin.abs() < 1e-9) return null;
  if (marketMargin > 0) return homeCoverProbability;
  return 1 - homeCoverProbability;
}

/// An Edge when the numbers differ by enough points, or the price is clearly
/// ahead of our chance. [pointGap] is positive when it favors this side.
bool clearsEdge({
  required double pointGap,
  required double? expectedProfit,
  required double pointThreshold,
  required double minExpectedValue,
}) {
  if (pointGap >= pointThreshold) return true;
  if (expectedProfit != null && expectedProfit >= minExpectedValue) return true;
  return false;
}

class EdgeSettings {
  const EdgeSettings({
    required this.spreadPoints,
    required this.totalPoints,
    required this.minExpectedValue,
  });

  final double spreadPoints;
  final double totalPoints;
  final double minExpectedValue;

  EdgeSettings copyWith({
    double? spreadPoints,
    double? totalPoints,
    double? minExpectedValue,
  }) => EdgeSettings(
    spreadPoints: spreadPoints ?? this.spreadPoints,
    totalPoints: totalPoints ?? this.totalPoints,
    minExpectedValue: minExpectedValue ?? this.minExpectedValue,
  );
}

class LogisticModel {
  const LogisticModel({
    required this.features,
    required this.mean,
    required this.scale,
    required this.coefficients,
    required this.intercept,
  });

  final List<String> features;
  final List<double> mean;
  final List<double> scale;
  final List<double> coefficients;
  final double intercept;

  double probability(Map<String, double> values) {
    if (features.length != mean.length ||
        features.length != scale.length ||
        features.length != coefficients.length) {
      throw StateError('The model file has a mismatched coefficient list.');
    }
    var logit = intercept;
    for (var i = 0; i < features.length; i++) {
      final value = values[features[i]];
      if (value == null) {
        throw ArgumentError('Missing model input ${features[i]}.');
      }
      final width = scale[i] == 0 ? 1.0 : scale[i];
      logit += coefficients[i] * ((value - mean[i]) / width);
    }
    return _sigmoid(logit);
  }

  factory LogisticModel.fromJson(Map<String, dynamic> json) {
    List<double> numbers(String key) {
      final raw = json[key];
      if (raw is! List || raw.isEmpty) {
        throw FormatException('Model $key is missing.');
      }
      return [
        for (final value in raw)
          if (value is num)
            value.toDouble()
          else
            throw FormatException('Model $key is not numeric.'),
      ];
    }

    final names = json['features'];
    if (names is! List || names.isEmpty) {
      throw const FormatException('Model features are missing.');
    }
    return LogisticModel(
      features: [for (final name in names) name.toString()],
      mean: numbers('mean'),
      scale: numbers('scale'),
      coefficients: numbers('coefficients'),
      intercept: _asDouble(json['intercept'], 'intercept'),
    );
  }
}

class TeamStrength {
  const TeamStrength({
    required this.abbr,
    required this.name,
    required this.rank,
    required this.offEpa,
    required this.defEpa,
    required this.netEpa,
    required this.strengthPoints,
    required this.offensePoints,
    required this.defensePoints,
    required this.successRate,
    required this.explosiveRate,
    required this.turnoverRate,
    required this.formEpa,
    required this.playersOut,
    required this.lastGame,
    required this.samplePlays,
  });

  final String abbr;
  final String name;
  final int rank;
  final double offEpa;
  final double defEpa;
  final double netEpa;
  final double strengthPoints;
  final double offensePoints;
  final double defensePoints;
  final double successRate;
  final double explosiveRate;
  final double turnoverRate;
  final double formEpa;
  final int playersOut;
  final String? lastGame;
  final double samplePlays;

  factory TeamStrength.fromJson(Map<String, dynamic> json) => TeamStrength(
    abbr: '${json['abbr'] ?? ''}',
    name: '${json['name'] ?? ''}',
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    offEpa: _asDouble(json['offEpa'], 'offEpa'),
    defEpa: _asDouble(json['defEpa'], 'defEpa'),
    netEpa: _asDouble(json['netEpa'], 'netEpa'),
    strengthPoints: _asDouble(json['strengthPoints'], 'strengthPoints'),
    offensePoints: _asDouble(json['offensePoints'], 'offensePoints'),
    defensePoints: _asDouble(json['defensePoints'], 'defensePoints'),
    successRate: _asDouble(json['successRate'], 'successRate'),
    explosiveRate: _asDouble(json['explosiveRate'], 'explosiveRate'),
    turnoverRate: _asDouble(json['turnoverRate'], 'turnoverRate'),
    formEpa: _asDouble(json['formEpa'], 'formEpa'),
    playersOut: (json['playersOut'] as num?)?.toInt() ?? 0,
    lastGame: json['lastGame']?.toString(),
    samplePlays: (json['samplePlays'] as num?)?.toDouble() ?? 0,
  );
}

class CalibrationBin {
  const CalibrationBin({
    required this.from,
    required this.to,
    required this.games,
    required this.predicted,
    required this.actual,
  });

  final double from;
  final double to;
  final int games;
  final double predicted;
  final double actual;
}

class BacktestReport {
  const BacktestReport({
    required this.method,
    required this.seasons,
    required this.games,
    required this.decided,
    required this.wins,
    required this.losses,
    required this.pushes,
    required this.hitRate,
    required this.roi,
    required this.brier,
    required this.calibration,
    required this.clvBeatRate,
    required this.clvGames,
    required this.meanModelError,
    required this.meanMarketError,
    required this.favoriteHitRate,
    required this.homeHitRate,
    required this.flaggedGames,
    required this.flaggedDecided,
    required this.flaggedHitRate,
    required this.flaggedRoi,
    required this.flaggedRule,
    required this.totalsHitRate,
    required this.totalsRoi,
    required this.hasEdge,
    required this.plainEnglish,
    this.logLoss,
    this.breakEvenHitRate = 0.52381,
  });

  final String method;
  final List<int> seasons;
  final int games;
  final int decided;
  final int wins;
  final int losses;
  final int pushes;
  final double? hitRate;
  final double? roi;
  final double? brier;
  final double? logLoss;
  final List<CalibrationBin> calibration;
  final double? clvBeatRate;
  final int clvGames;
  final double? meanModelError;
  final double? meanMarketError;
  final double? favoriteHitRate;
  final double? homeHitRate;
  final int flaggedGames;
  final int flaggedDecided;
  final double? flaggedHitRate;
  final double? flaggedRoi;
  final String flaggedRule;
  final double? totalsHitRate;
  final double? totalsRoi;
  final bool hasEdge;
  final String plainEnglish;

  /// Hit rate a -110 price needs. 1.10 staked to win 1.00.
  final double breakEvenHitRate;

  String get seasonSpan => seasons.isEmpty
      ? 'no seasons'
      : seasons.length == 1
      ? '${seasons.first}'
      : '${seasons.first}–${seasons.last}';
}

class ModelSource {
  const ModelSource({
    required this.name,
    required this.license,
    required this.url,
    required this.licenseUrl,
    required this.changes,
  });

  final String name;
  final String license;
  final String url;
  final String licenseUrl;
  final String changes;
}

class CoachModel {
  const CoachModel({
    required this.generatedAt,
    required this.asOf,
    required this.source,
    required this.settings,
    required this.marginScale,
    required this.homeFieldAdvantage,
    required this.totalIntercept,
    required this.totalScale,
    required this.cover,
    required this.total,
    required this.teams,
    required this.backtest,
    this.lineVersion,
  });

  final String? generatedAt;
  final String? asOf;
  final ModelSource source;
  final EdgeSettings settings;
  final double marginScale;
  final double homeFieldAdvantage;
  final double totalIntercept;
  final double totalScale;
  final LogisticModel cover;
  final LogisticModel total;
  final List<TeamStrength> teams;
  final BacktestReport backtest;
  final LineVersion? lineVersion;

  bool get usesV2 => lineVersion?.adopted == true;

  BacktestReport get liveReport =>
      usesV2 ? lineVersion!.report : backtest;

  TeamStrength? team(String nameOrAbbr) {
    final abbr = canonicalTeam(nameOrAbbr);
    if (abbr == null) return null;
    for (final team in teams) {
      if (team.abbr == abbr) return team;
    }
    return null;
  }

  CoachLine? lineFor(
    SportEvent event,
    List<OddsQuote> quotes, {
    required EdgeSettings settings,
    Set<String>? books,
    InjuryReport? injuries,
  }) {
    final home = team(event.home);
    final away = team(event.away);
    if (home == null || away == null) return null;
    final market = readMarketLine(event, quotes, books: books);
    var ourMargin = projectedMargin(
      homeNet: home.netEpa,
      awayNet: away.netEpa,
      scale: marginScale,
      homeField: homeFieldAdvantage,
    );
    var ourTotal = projectedTotal(
      homeOff: home.offEpa,
      homeDef: home.defEpa,
      awayOff: away.offEpa,
      awayDef: away.defEpa,
      intercept: totalIntercept,
      scale: totalScale,
    );
    final homeRest = restDays(home.lastGame, event.startsAt);
    final awayRest = restDays(away.lastGame, event.startsAt);
    double? homeCover;
    double? overChance;
    final version = lineVersion;
    final homeAbbr = canonicalTeam(event.home);
    final awayAbbr = canonicalTeam(event.away);
    LineBreakdown? breakdown;
    if (version != null &&
        market.homeSpread != null &&
        homeAbbr != null &&
        awayAbbr != null) {
      breakdown = projectVersion2(
        scales: version.scales,
        cover: version.cover,
        totalFit: version.total,
        sigma: version.sigma,
        totalSigma: version.totalSigma,
        marginCap: version.marginCap,
        totalCap: version.totalCap,
        teams: version.teams,
        players: version.players,
        forecasts: version.forecasts,
        home: homeAbbr,
        away: awayAbbr,
        marketMargin: -market.homeSpread!,
        marketTotal: market.total,
        marketCover: market.homeCoverFair,
        marketOver: market.overFair,
        marketSource: market.sourceLabel,
        homeRest: homeRest,
        awayRest: awayRest,
        injuries: injuries,
      );
    }
    if (usesV2 && breakdown != null) {
      ourMargin = breakdown.finalMargin;
      if (breakdown.finalTotal != null) ourTotal = breakdown.finalTotal!;
      homeCover = breakdown.homeCover;
      overChance = breakdown.overChance;
    } else {
      if (homeRest != null && awayRest != null && market.homeSpread != null) {
        final marketMargin = -market.homeSpread!;
        homeCover = cover.probability({
          'spread_edge': ourMargin - marketMargin,
          'off_diff': home.offEpa - away.offEpa,
          'def_diff': away.defEpa - home.defEpa,
          'form_diff': home.formEpa - away.formEpa,
          'rest_diff': (homeRest - awayRest).toDouble(),
          'success_diff': home.successRate - away.successRate,
          'explosive_diff': home.explosiveRate - away.explosiveRate,
          'turnover_diff': away.turnoverRate - home.turnoverRate,
          'out_diff': (away.playersOut - home.playersOut).toDouble(),
        });
      }
      if (homeRest != null && awayRest != null && market.total != null) {
        overChance = total.probability({
          'total_edge': ourTotal - market.total!,
          'off_sum': home.offEpa + away.offEpa,
          'def_sum': home.defEpa + away.defEpa,
          'explosive_sum': home.explosiveRate + away.explosiveRate,
          'success_sum': home.successRate + away.successRate,
          'rest_sum': (homeRest + awayRest).toDouble(),
          'out_sum': (home.playersOut + away.playersOut).toDouble(),
        });
      }
    }
    return CoachLine(
      event: event,
      away: away,
      home: home,
      projectedMargin: ourMargin,
      projectedTotal: ourTotal,
      marketHomeSpread: market.homeSpread,
      marketTotal: market.total,
      homeCoverProbability: homeCover,
      overProbability: overChance,
      homeSpreadPrice: market.homeSpreadPrice,
      awaySpreadPrice: market.awaySpreadPrice,
      overPrice: market.overPrice,
      underPrice: market.underPrice,
      settings: settings,
      marketSource: market.sourceLabel,
      marketFirst: !liveReport.hasEdge,
      differsAllowed: usesV2 ? version!.differsHelped : true,
      breakdown: breakdown,
      breakdownIsLive: usesV2 && breakdown != null,
    );
  }

  factory CoachModel.fromJson(Map<String, dynamic> json) {
    final projection = json['projection'];
    final settings = json['settings'];
    final backtest = json['backtest'];
    final source = json['source'];
    final cover = json['coverModel'];
    final total = json['totalModel'];
    final teams = json['teams'];
    if (projection is! Map ||
        settings is! Map ||
        backtest is! Map ||
        source is! Map ||
        cover is! Map ||
        total is! Map ||
        teams is! List) {
      throw const FormatException('Coach model file is missing a section.');
    }
    return CoachModel(
      generatedAt: json['generatedAt']?.toString(),
      asOf: json['asOf']?.toString(),
      source: ModelSource(
        name: '${source['name'] ?? 'nflverse'}',
        license: '${source['license'] ?? 'CC BY 4.0'}',
        url: '${source['url'] ?? ''}',
        licenseUrl: '${source['licenseUrl'] ?? ''}',
        changes: '${source['changes'] ?? ''}',
      ),
      settings: EdgeSettings(
        spreadPoints: _asDouble(
          settings['spreadEdgePoints'],
          'spreadEdgePoints',
        ),
        totalPoints: _asDouble(settings['totalEdgePoints'], 'totalEdgePoints'),
        minExpectedValue: _asDouble(
          settings['minExpectedValue'],
          'minExpectedValue',
        ),
      ),
      marginScale: _asDouble(projection['marginScale'], 'marginScale'),
      homeFieldAdvantage: _asDouble(
        projection['homeFieldAdvantage'],
        'homeFieldAdvantage',
      ),
      totalIntercept: _asDouble(projection['totalIntercept'], 'totalIntercept'),
      totalScale: _asDouble(projection['totalScale'], 'totalScale'),
      cover: LogisticModel.fromJson(Map<String, dynamic>.from(cover)),
      total: LogisticModel.fromJson(Map<String, dynamic>.from(total)),
      teams: [
        for (final team in teams)
          if (team is Map)
            TeamStrength.fromJson(Map<String, dynamic>.from(team)),
      ],
      backtest: _readBacktest(backtest),
      lineVersion: _readLineVersion(json['v2']),
    );
  }
}

BacktestReport _readBacktest(Map<dynamic, dynamic> backtest) {
  final flagged = backtest['flagged'];
  final totals = backtest['totals'];
  if (flagged is! Map || totals is! Map) {
    throw const FormatException('Coach model backtest is missing a section.');
  }
  final seasons = backtest['seasons'];
  if (seasons is! List) {
    throw const FormatException('Coach model seasons are missing.');
  }
  final bins = backtest['calibration'];
  return BacktestReport(
    method: '${backtest['method'] ?? ''}',
    seasons: [for (final season in seasons) (season as num).toInt()],
    games: _asInt(backtest['games']),
    decided: _asInt(backtest['decided']),
    wins: _asInt(backtest['wins']),
    losses: _asInt(backtest['losses']),
    pushes: _asInt(backtest['pushes']),
    hitRate: _maybeDouble(backtest['hitRate']),
    roi: _maybeDouble(backtest['roi']),
    brier: _maybeDouble(backtest['brier']),
    logLoss: _maybeDouble(backtest['logLoss']),
    calibration: [
      if (bins is List)
        for (final bin in bins)
          if (bin is Map)
            CalibrationBin(
              from: _asDouble(bin['from'], 'from'),
              to: _asDouble(bin['to'], 'to'),
              games: _asInt(bin['games']),
              predicted: _asDouble(bin['predicted'], 'predicted'),
              actual: _asDouble(bin['actual'], 'actual'),
            ),
    ],
    clvBeatRate: _maybeDouble(backtest['clvBeatRate']),
    clvGames: _asInt(backtest['clvGames']),
    meanModelError: _maybeDouble(backtest['meanModelError']),
    meanMarketError: _maybeDouble(backtest['meanMarketError']),
    favoriteHitRate: _maybeDouble(backtest['favoriteHitRate']),
    homeHitRate: _maybeDouble(backtest['homeHitRate']),
    flaggedGames: _asInt(flagged['games']),
    flaggedDecided: _asInt(flagged['decided']),
    flaggedHitRate: _maybeDouble(flagged['hitRate']),
    flaggedRoi: _maybeDouble(flagged['roi']),
    flaggedRule: '${flagged['rule'] ?? ''}',
    totalsHitRate: _maybeDouble(totals['hitRate']),
    totalsRoi: _maybeDouble(totals['roi']),
    hasEdge: backtest['hasEdge'] == true,
    plainEnglish: '${backtest['plainEnglish'] ?? ''}',
    breakEvenHitRate: _maybeDouble(backtest['breakEvenHitRate']) ?? 0.52381,
  );
}

LineVersion? _readLineVersion(Object? raw) {
  if (raw is! Map) return null;
  final backtest = raw['backtest'];
  final scales = raw['scales'];
  if (backtest is! Map || scales is! Map) return null;
  final teams = <String, V2TeamContext>{};
  final teamRaw = raw['teams'];
  if (teamRaw is Map) {
    for (final entry in teamRaw.entries) {
      if (entry.value is! Map) continue;
      final team = Map<String, dynamic>.from(entry.value as Map);
      final replacements = <V2Quarterback>[];
      final listed = team['replacements'];
      if (listed is List) {
        for (final item in listed) {
          if (item is Map) replacements.add(V2Quarterback.fromJson(item));
        }
      }
      final lon = team['homeLon'];
      teams['${entry.key}'] = V2TeamContext(
        homeLon: lon is num ? lon.toDouble() : null,
        usual: team['usualQb'] == null
            ? null
            : V2Quarterback.fromJson(team['usualQb']),
        planned: team['plannedQb'] == null
            ? null
            : V2Quarterback.fromJson(team['plannedQb']),
        replacements: replacements,
      );
    }
  }
  final players = <V2PlayerWeight>[];
  final playerRaw = raw['players'];
  if (playerRaw is List) {
    for (final item in playerRaw) {
      if (item is! Map) continue;
      players.add(
        V2PlayerWeight(
          team: '${item['team'] ?? ''}',
          name: '${item['name'] ?? ''}',
          position: '${item['position'] ?? ''}',
          points: item['points'] is num ? (item['points'] as num).toDouble() : 0,
        ),
      );
    }
  }
  final forecasts = <GameForecast>[];
  final forecastRaw = raw['forecasts'];
  if (forecastRaw is List) {
    for (final item in forecastRaw) {
      if (item is! Map) continue;
      double? numOrNull(Object? value) =>
          value is num ? value.toDouble() : null;
      forecasts.add(
        GameForecast(
          home: '${item['home'] ?? ''}',
          away: '${item['away'] ?? ''}',
          stadium: '${item['stadium'] ?? ''}',
          openRoof: item['openRoof'] == true,
          windMph: numOrNull(item['windMph']),
          tempF: numOrNull(item['tempF']),
          precipMm: numOrNull(item['precipMm']),
          source: '${item['source'] ?? ''}',
          at: '${item['at'] ?? ''}',
          longitude: numOrNull(item['longitude']),
        ),
      );
    }
  }
  final weather = raw['weather'];
  return LineVersion(
    adopted: raw['adopted'] == true,
    hasEdge: raw['hasEdge'] == true,
    differsHelped: raw['differsHelped'] == true,
    sigma: raw['sigma'] is num ? (raw['sigma'] as num).toDouble() : 13,
    totalSigma: raw['totalSigma'] is num
        ? (raw['totalSigma'] as num).toDouble()
        : 13,
    marginCap: raw['marginCap'] is num
        ? (raw['marginCap'] as num).toDouble()
        : 4,
    totalCap: raw['totalCap'] is num ? (raw['totalCap'] as num).toDouble() : 6,
    scales: V2Scales.fromJson(Map<String, dynamic>.from(scales)),
    cover: PlattFit.fromJson(raw['coverCalibration']),
    total: PlattFit.fromJson(raw['totalCalibration']),
    report: _readBacktest(backtest),
    teams: teams,
    players: players,
    forecasts: forecasts,
    weatherNote: weather is Map ? '${weather['attribution'] ?? ''}' : '',
  );
}

class LineVersion {
  const LineVersion({
    required this.adopted,
    required this.hasEdge,
    required this.differsHelped,
    required this.sigma,
    required this.totalSigma,
    required this.marginCap,
    required this.totalCap,
    required this.scales,
    required this.cover,
    required this.total,
    required this.report,
    required this.teams,
    required this.players,
    required this.forecasts,
    required this.weatherNote,
  });

  final bool adopted;
  final bool hasEdge;
  final bool differsHelped;
  final double sigma;
  final double totalSigma;
  final double marginCap;
  final double totalCap;
  final V2Scales scales;
  final PlattFit cover;
  final PlattFit total;
  final BacktestReport report;
  final Map<String, V2TeamContext> teams;
  final List<V2PlayerWeight> players;
  final List<GameForecast> forecasts;
  final String weatherNote;
}

class MarketLine {
  const MarketLine({
    this.homeSpread,
    this.total,
    this.homeSpreadPrice,
    this.awaySpreadPrice,
    this.overPrice,
    this.underPrice,
    this.sourceLabel = 'Books',
    this.homeCoverFair = 0.5,
    this.overFair = 0.5,
  });

  /// Home team's number. Negative means the home team is laying points.
  final double? homeSpread;
  final double? total;
  final OddsQuote? homeSpreadPrice;
  final OddsQuote? awaySpreadPrice;
  final OddsQuote? overPrice;
  final OddsQuote? underPrice;

  /// "Pinnacle" when that book posted both sides, otherwise "Books".
  final String sourceLabel;

  /// No-vig chance the home side covers, and the no-vig chance of the over.
  final double homeCoverFair;
  final double overFair;
}

class SideEdge {
  const SideEdge({
    required this.label,
    required this.pointGap,
    required this.probability,
    required this.flagged,
    required this.reason,
    this.quote,
    this.expectedProfit,
  });

  final String label;
  final double pointGap;
  final double probability;
  final bool flagged;
  final String reason;
  final OddsQuote? quote;
  final double? expectedProfit;
}

class CoachLine {
  const CoachLine({
    required this.event,
    required this.away,
    required this.home,
    required this.projectedMargin,
    required this.projectedTotal,
    required this.marketHomeSpread,
    required this.marketTotal,
    required this.homeCoverProbability,
    required this.overProbability,
    required this.homeSpreadPrice,
    required this.awaySpreadPrice,
    required this.overPrice,
    required this.underPrice,
    required this.settings,
    this.marketSource = 'Books',
    this.marketFirst = false,
    this.differsAllowed = true,
    this.breakdown,
    this.breakdownIsLive = false,
  });

  final SportEvent event;
  final TeamStrength away;
  final TeamStrength home;
  final double projectedMargin;
  final double projectedTotal;
  final double? marketHomeSpread;
  final double? marketTotal;
  final double? homeCoverProbability;
  final double? overProbability;
  final OddsQuote? homeSpreadPrice;
  final OddsQuote? awaySpreadPrice;
  final OddsQuote? overPrice;
  final OddsQuote? underPrice;
  final EdgeSettings settings;
  final String marketSource;
  final bool marketFirst;
  final bool differsAllowed;
  final LineBreakdown? breakdown;
  final bool breakdownIsLive;

  double? get marketMargin =>
      marketHomeSpread == null ? null : -marketHomeSpread!;

  double? get favoriteCover =>
      homeCoverProbability == null || marketMargin == null
      ? null
      : favoriteCoverProbability(homeCoverProbability!, marketMargin!);

  String get ourSpread => spreadLabel(away.name, home.name, projectedMargin);

  String? get booksSpread => marketMargin == null
      ? null
      : spreadLabel(away.name, home.name, marketMargin!);

  String get ourTotal => projectedTotal.toStringAsFixed(1);

  String? get booksTotal => marketTotal?.toStringAsFixed(1);

  SideEdge? get homeSpreadEdge => _spreadEdge(homeSide: true);

  SideEdge? get awaySpreadEdge => _spreadEdge(homeSide: false);

  SideEdge? get overEdge => _totalEdge(over: true);

  SideEdge? get underEdge => _totalEdge(over: false);

  bool get flagged =>
      differsAllowed &&
      ((homeSpreadEdge?.flagged ?? false) ||
          (awaySpreadEdge?.flagged ?? false) ||
          (overEdge?.flagged ?? false) ||
          (underEdge?.flagged ?? false));

  String get edgeReason {
    final reasons = <String>[
      if (homeSpreadEdge?.flagged ?? false) homeSpreadEdge!.reason,
      if (awaySpreadEdge?.flagged ?? false) awaySpreadEdge!.reason,
      if (overEdge?.flagged ?? false) overEdge!.reason,
      if (underEdge?.flagged ?? false) underEdge!.reason,
    ];
    if (reasons.isEmpty) {
      return 'Our number is close to the books at the current setting. It can still be compared.';
    }
    return reasons.join(' ');
  }

  String get askCoachSentence {
    final cover = favoriteCover == null
        ? 'Cover chance was not computed.'
        : 'Chance the favorite covers ${(favoriteCover! * 100).toStringAsFixed(1)}%.';
    final over = overProbability == null
        ? 'Over chance was not computed.'
        : 'Chance the over hits ${(overProbability! * 100).toStringAsFixed(1)}%.';
    return "Coach's Line $ourSpread. The books: ${booksSpread ?? 'no spread'}. $cover $over ${flagged ? 'Differs from the books: yes.' : 'Differs from the books: no.'} Comparison, not a pick.";
  }

  Map<String, dynamic> evidence() => {
    'source': "Coach's Line",
    'matchup': '${event.away} at ${event.home}',
    'ourSpread': ourSpread,
    'booksSpread': booksSpread ?? 'not in this snapshot',
    'ourTotal': ourTotal,
    'booksTotal': booksTotal ?? 'not in this snapshot',
    'favoriteCoverChance': favoriteCover,
    'homeCoverChance': homeCoverProbability,
    'overChance': overProbability,
    'edge': flagged,
    'note': "The app's past-seasons model. Not a guarantee and not a recommendation to bet.",
  };

  SideEdge? _spreadEdge({required bool homeSide}) {
    final probability = homeCoverProbability;
    final margin = marketMargin;
    if (probability == null || margin == null) return null;
    final gap = homeSide ? projectedMargin - margin : margin - projectedMargin;
    final chance = homeSide ? probability : 1 - probability;
    final quote = homeSide ? homeSpreadPrice : awaySpreadPrice;
    final profit = quote == null ? null : expectedValue(quote.decimal, chance);
    final name = homeSide ? shortClub(home.name) : shortClub(away.name);
    final number = homeSide ? marketHomeSpread! : -marketHomeSpread!;
    final flagged = clearsEdge(
      pointGap: gap,
      expectedProfit: profit,
      pointThreshold: settings.spreadPoints,
      minExpectedValue: settings.minExpectedValue,
    );
    return SideEdge(
      label: '$name ${signedNumber(number)}',
      pointGap: gap,
      probability: chance,
      flagged: flagged,
      reason: _reason(
        name: name,
        flagged: flagged,
        pointGap: gap,
        profit: profit,
        points: settings.spreadPoints,
        kind: 'spread',
      ),
      quote: quote,
      expectedProfit: profit,
    );
  }

  SideEdge? _totalEdge({required bool over}) {
    final probability = overProbability;
    final line = marketTotal;
    if (probability == null || line == null) return null;
    final gap = over ? projectedTotal - line : line - projectedTotal;
    final chance = over ? probability : 1 - probability;
    final quote = over ? overPrice : underPrice;
    final profit = quote == null ? null : expectedValue(quote.decimal, chance);
    final name = over ? 'Over' : 'Under';
    final flagged = clearsEdge(
      pointGap: gap,
      expectedProfit: profit,
      pointThreshold: settings.totalPoints,
      minExpectedValue: settings.minExpectedValue,
    );
    return SideEdge(
      label: '$name ${line.toStringAsFixed(1)}',
      pointGap: gap,
      probability: chance,
      flagged: flagged,
      reason: _reason(
        name: name,
        flagged: flagged,
        pointGap: gap,
        profit: profit,
        points: settings.totalPoints,
        kind: 'total',
      ),
      quote: quote,
      expectedProfit: profit,
    );
  }
}

String _reason({
  required String name,
  required bool flagged,
  required double pointGap,
  required double? profit,
  required double points,
  required String kind,
}) {
  if (!flagged) return '';
  final byPoints = pointGap >= points;
  final byPrice = profit != null && profit > 0;
  final gapText = pointGap.abs().toStringAsFixed(1);
  if (byPoints && byPrice) {
    return '$name differs from the books by $gapText points, and the best price in this snapshot is longer than our chance. The past test of this number lost money.';
  }
  if (byPoints) {
    return '$name differs from the books by $gapText points. The past test of this number lost money.';
  }
  return 'The best price on $name is longer than our chance. The past test of this number lost money.';
}

/// Days from the last game to kickoff, using the UTC date. Null when the last
/// game is missing or after this kickoff.
int? restDays(String? lastGame, DateTime kickoff) {
  if (lastGame == null || lastGame.isEmpty) return null;
  final parsed = DateTime.tryParse(lastGame);
  if (parsed == null) return null;
  final last = DateTime.utc(parsed.year, parsed.month, parsed.day);
  final start = kickoff.toUtc();
  final kick = DateTime.utc(start.year, start.month, start.day);
  final days = kick.difference(last).inDays;
  if (days < 0) return null;
  return days;
}

String shortClub(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length <= 1) return name;
  return parts.last;
}

String signedNumber(double value) {
  final text = value.abs().toStringAsFixed(1);
  if (value > 0) return '+$text';
  if (value < 0) return '-$text';
  return '0.0';
}

/// [homeMargin] positive means the home team is favored by that many points.
String spreadLabel(String away, String home, double homeMargin) {
  if (homeMargin.abs() < 0.05) return "Pick'em";
  if (homeMargin > 0) {
    return '${shortClub(home)} -${homeMargin.toStringAsFixed(1)}';
  }
  return '${shortClub(away)} -${(-homeMargin).toStringAsFixed(1)}';
}

MarketLine readMarketLine(
  SportEvent event,
  List<OddsQuote> quotes, {
  Set<String>? books,
}) {
  bool open(OddsQuote quote) =>
      quote.selection.eventId == event.id &&
      quote.status == 'open' &&
      (books == null || books.contains(quote.bookId));

  final homeSpreads = <double>[];
  final totals = <double>[];
  for (final quote in quotes) {
    if (!open(quote) || quote.selection.point == null) continue;
    if (quote.selection.market == 'spreads' &&
        quote.selection.outcome == event.home) {
      homeSpreads.add(quote.selection.point!);
    } else if (quote.selection.market == 'totals' &&
        (quote.selection.outcome == 'Over' ||
            quote.selection.outcome == 'Under')) {
      totals.add(quote.selection.point!);
    }
  }
  final pinSpread = _pinnaclePair(
    quotes,
    open,
    market: 'spreads',
    homeOutcome: event.home,
    awayOutcome: event.away,
  );
  var homeSpread = pinSpread?.point ?? _mode(homeSpreads);
  if (homeSpread == null) {
    final awaySpreads = <double>[];
    for (final quote in quotes) {
      if (!open(quote) || quote.selection.point == null) continue;
      if (quote.selection.market == 'spreads' &&
          quote.selection.outcome == event.away) {
        awaySpreads.add(-quote.selection.point!);
      }
    }
    homeSpread = _mode(awaySpreads);
  }
  final pinTotal = _pinnaclePair(
    quotes,
    open,
    market: 'totals',
    homeOutcome: 'Over',
    awayOutcome: 'Under',
  );
  final total = pinTotal?.point ?? _mode(totals);
  OddsQuote? best(bool Function(OddsQuote quote) match) {
    OddsQuote? chosen;
    for (final quote in quotes) {
      if (!open(quote) || !match(quote)) continue;
      if (chosen == null || quote.decimal > chosen.decimal) chosen = quote;
    }
    return chosen;
  }

  bool near(double? point, double? target) =>
      point != null && target != null && (point - target).abs() < 0.01;

  final spread = homeSpread;
  final marketTotal = total;
  final coverFair = pinSpread != null
      ? (noVigChance(pinSpread.homeDecimal, pinSpread.awayDecimal) ?? 0.5)
      : _averageNoVig(
          quotes,
          open,
          market: 'spreads',
          side: event.home,
          other: event.away,
          point: spread,
          otherPoint: spread == null ? null : -spread,
        );
  final overFair = pinTotal != null
      ? (noVigChance(pinTotal.homeDecimal, pinTotal.awayDecimal) ?? 0.5)
      : _averageNoVig(
          quotes,
          open,
          market: 'totals',
          side: 'Over',
          other: 'Under',
          point: marketTotal,
          otherPoint: marketTotal,
        );
  return MarketLine(
    homeSpread: spread,
    total: marketTotal,
    sourceLabel: pinSpread != null ? 'Pinnacle' : 'Books',
    homeCoverFair: coverFair,
    overFair: overFair,
    homeSpreadPrice: spread == null
        ? null
        : best(
            (quote) =>
                quote.selection.market == 'spreads' &&
                quote.selection.outcome == event.home &&
                near(quote.selection.point, spread),
          ),
    awaySpreadPrice: spread == null
        ? null
        : best(
            (quote) =>
                quote.selection.market == 'spreads' &&
                quote.selection.outcome == event.away &&
                near(quote.selection.point, -spread),
          ),
    overPrice: marketTotal == null
        ? null
        : best(
            (quote) =>
                quote.selection.market == 'totals' &&
                quote.selection.outcome == 'Over' &&
                near(quote.selection.point, marketTotal),
          ),
    underPrice: marketTotal == null
        ? null
        : best(
            (quote) =>
                quote.selection.market == 'totals' &&
                quote.selection.outcome == 'Under' &&
                near(quote.selection.point, marketTotal),
          ),
  );
}

class _BookPair {
  const _BookPair({
    required this.point,
    required this.homeDecimal,
    required this.awayDecimal,
  });

  final double point;
  final double homeDecimal;
  final double awayDecimal;
}

double _halfPoint(double point) => (point * 2).round() / 2;

_BookPair? _pinnaclePair(
  List<OddsQuote> quotes,
  bool Function(OddsQuote quote) open, {
  required String market,
  required String homeOutcome,
  required String awayOutcome,
}) {
  final home = <double, double>{};
  final away = <double, double>{};
  for (final quote in quotes) {
    if (!open(quote) || quote.bookId != 'pinnacle') continue;
    if (quote.selection.market != market || quote.selection.point == null) {
      continue;
    }
    final point = _halfPoint(quote.selection.point!);
    if (quote.selection.outcome == homeOutcome) home[point] = quote.decimal;
    if (quote.selection.outcome == awayOutcome) away[point] = quote.decimal;
  }
  for (final entry in home.entries) {
    final other = market == 'totals' ? away[entry.key] : away[-entry.key];
    if (other == null) continue;
    return _BookPair(
      point: entry.key,
      homeDecimal: entry.value,
      awayDecimal: other,
    );
  }
  return null;
}

double _averageNoVig(
  List<OddsQuote> quotes,
  bool Function(OddsQuote quote) open, {
  required String market,
  required String side,
  required String other,
  required double? point,
  required double? otherPoint,
}) {
  if (point == null || otherPoint == null) return 0.5;
  final home = <String, double>{};
  final away = <String, double>{};
  for (final quote in quotes) {
    if (!open(quote) || quote.selection.market != market) continue;
    if (quote.selection.point == null) continue;
    final posted = _halfPoint(quote.selection.point!);
    if (quote.selection.outcome == side && (posted - point).abs() < 0.01) {
      home[quote.bookId] = quote.decimal;
    } else if (quote.selection.outcome == other &&
        (posted - otherPoint).abs() < 0.01) {
      away[quote.bookId] = quote.decimal;
    }
  }
  var sum = 0.0;
  var count = 0;
  for (final entry in home.entries) {
    final fair = noVigChance(entry.value, away[entry.key]);
    if (fair == null) continue;
    sum += fair;
    count += 1;
  }
  if (count == 0) return 0.5;
  return sum / count;
}

double? _mode(List<double> points) {
  if (points.isEmpty) return null;
  final counts = <double, int>{};
  for (final point in points) {
    final key = (point * 2).round() / 2;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  var best = 0;
  final modes = <double>[];
  counts.forEach((point, count) {
    if (count > best) {
      best = count;
      modes
        ..clear()
        ..add(point);
    } else if (count == best) {
      modes.add(point);
    }
  });
  modes.sort();
  return modes[modes.length ~/ 2];
}

double _asDouble(Object? value, String name) {
  if (value is! num || !value.isFinite) {
    throw FormatException('Model $name is missing.');
  }
  return value.toDouble();
}

double? _maybeDouble(Object? value) => value is num ? value.toDouble() : null;

int _asInt(Object? value) => value is num ? value.toInt() : 0;

Future<CoachModel> loadBundledCoachModel() async {
  final raw = await rootBundle.loadString('assets/nfl-model.json');
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Coach model file is not an object.');
  }
  return CoachModel.fromJson(Map<String, dynamic>.from(decoded));
}
