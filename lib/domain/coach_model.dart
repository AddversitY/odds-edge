import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'nfl_teams.dart';
import 'odds.dart';

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
  }) {
    final home = team(event.home);
    final away = team(event.away);
    if (home == null || away == null) return null;
    final market = readMarketLine(event, quotes, books: books);
    final ourMargin = projectedMargin(
      homeNet: home.netEpa,
      awayNet: away.netEpa,
      scale: marginScale,
      homeField: homeFieldAdvantage,
    );
    final ourTotal = projectedTotal(
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
      backtest: BacktestReport(
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
      ),
    );
  }
}

class MarketLine {
  const MarketLine({
    this.homeSpread,
    this.total,
    this.homeSpreadPrice,
    this.awaySpreadPrice,
    this.overPrice,
    this.underPrice,
  });

  /// Home team's number. Negative means the home team is laying points.
  final double? homeSpread;
  final double? total;
  final OddsQuote? homeSpreadPrice;
  final OddsQuote? awaySpreadPrice;
  final OddsQuote? overPrice;
  final OddsQuote? underPrice;
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
      (homeSpreadEdge?.flagged ?? false) ||
      (awaySpreadEdge?.flagged ?? false) ||
      (overEdge?.flagged ?? false) ||
      (underEdge?.flagged ?? false);

  String get edgeReason {
    final reasons = <String>[
      if (homeSpreadEdge?.flagged ?? false) homeSpreadEdge!.reason,
      if (awaySpreadEdge?.flagged ?? false) awaySpreadEdge!.reason,
      if (overEdge?.flagged ?? false) overEdge!.reason,
      if (underEdge?.flagged ?? false) underEdge!.reason,
    ];
    if (reasons.isEmpty) {
      return 'Our number is close to the books at the current setting. It can still be compared. This is a comparison, not a pick.';
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
    return '$name differs from the books by $gapText points, and the best price in this snapshot is longer than our chance. The past test of this number lost money. Comparison, not a pick.';
  }
  if (byPoints) {
    return '$name differs from the books by $gapText points. The past test of this number lost money. Comparison, not a pick.';
  }
  return 'The best price on $name is longer than our chance. The past test of this number lost money. Comparison, not a pick.';
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
  var homeSpread = _mode(homeSpreads);
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
  final total = _mode(totals);
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
  return MarketLine(
    homeSpread: spread,
    total: marketTotal,
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
