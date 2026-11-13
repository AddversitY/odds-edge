import 'dart:math' as math;

import 'value_check.dart';

/// Pseudo-games mixed in at the book's no-vig chance.
///
/// A player prop season is about 17 games. This prior is about two
/// seasons, so one hot month cannot become a 75% chance.
const propPriorGames = 32.0;

/// Ordinary gap limit, in probability. 0.10 is 10 percentage points.
const propEdgeCap = 0.10;

/// The widest gap a long record is allowed to publish.
const propEdgeCapCeiling = 0.15;

/// Recorded games required before the cap may open past [propEdgeCap].
const propStrongSample = 30;

/// Standard error, in probability, that still counts as a tight record.
const propStrongError = 0.08;

const propChanceSource =
    "the recorded games, pulled toward the book's no-vig chance";

const propEvenSource = 'the recorded games, pulled slightly toward even';

/// Our chance for one prop side.
///
/// Fewer than four recorded games stays null. With a no-vig [market],
/// the chance is a binomial mean pulled toward that market, then held
/// inside [propEdgeCap] unless [propEdgeCapFor] opens the cap. With no
/// market, it falls back to [shrunkClearRate].
double? propSideChance({
  required int hits,
  required int observed,
  required double? market,
}) {
  if (observed < 4) return null;
  if (hits < 0 || hits > observed) {
    throw ArgumentError('Hits must sit inside the recorded games.');
  }
  final anchor = market;
  if (anchor == null || !anchor.isFinite || anchor <= 0 || anchor >= 1) {
    return shrunkClearRate(hits: hits, observed: observed);
  }
  final blended =
      (hits + propPriorGames * anchor) / (observed + propPriorGames);
  final cap = propEdgeCapFor(hits: hits, observed: observed, market: anchor);
  final gap = (blended - anchor).clamp(-cap, cap).toDouble();
  final chance = anchor + gap;
  if (chance <= 0 || chance >= 1 || !chance.isFinite) return null;
  return chance;
}

/// How far [propSideChance] may sit from the market.
///
/// The ordinary cap is 10 points. It opens only when the record is at
/// least [propStrongSample] games, the raw rate's standard error is at
/// most [propStrongError], and the raw rate itself is more than 10
/// points from the market. The opened cap is the raw gap minus two
/// standard errors, and it never passes [propEdgeCapCeiling].
double propEdgeCapFor({
  required int hits,
  required int observed,
  required double market,
}) {
  if (observed < propStrongSample) return propEdgeCap;
  final raw = hits / observed;
  final variance = raw * (1 - raw) / observed;
  final error = variance <= 0 ? 0.0 : math.sqrt(variance);
  if (error > propStrongError) return propEdgeCap;
  final rawGap = (raw - market).abs();
  if (rawGap <= propEdgeCap) return propEdgeCap;
  final evidence = rawGap - 2 * error;
  if (evidence <= propEdgeCap) return propEdgeCap;
  if (evidence >= propEdgeCapCeiling) return propEdgeCapCeiling;
  return evidence;
}

String propChanceNote({
  required int hits,
  required int observed,
  required bool usedMarket,
}) {
  if (!usedMarket) {
    return 'Recorded $hits of $observed. Two wins and two losses are mixed in before that becomes our chance, so a short run cannot look certain.';
  }
  return 'Recorded $hits of $observed. ${propPriorGames.toInt()} games at the book\'s no-vig chance are mixed in. The gap stays within ${(propEdgeCap * 100).toInt()} points unless the record is long and one-sided.';
}
