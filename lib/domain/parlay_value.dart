import 'dart:math' as math;

import 'odds.dart';
import 'value_check.dart';

/// How much two legs in the same game move together.
///
/// Different games are unrelated. The same side of one prop cannot
/// both hit, so that pair is almost a perfect opposite. Other
/// same-game pairs share a script, so they are not multiplied as if
/// they were separate games.
double legCorrelation({
  required String eventA,
  required String eventB,
  required String marketA,
  required String marketB,
  required String outcomeA,
  required String outcomeB,
  String playerA = '',
  String playerB = '',
  String teamA = '',
  String teamB = '',
  double? pointA,
  double? pointB,
}) {
  if (eventA.isEmpty || eventA != eventB) return 0;
  final samePoint =
      pointA != null && pointB != null && (pointA - pointB).abs() < 0.01;
  final opposite = outcomeA != outcomeB;
  final samePlayer =
      playerA.isNotEmpty && playerA.toLowerCase() == playerB.toLowerCase();
  if (marketA == marketB &&
      opposite &&
      samePoint &&
      (playerA.isEmpty || samePlayer)) {
    return -0.95;
  }
  if (samePlayer) return 0.40;
  if (_quarterbackAndReceiver(marketA, marketB, teamA, teamB)) return 0.30;
  if ((marketA == 'spreads' && marketB == 'totals') ||
      (marketA == 'totals' && marketB == 'spreads')) {
    return 0.10;
  }
  return 0.15;
}

bool _quarterbackAndReceiver(
  String marketA,
  String marketB,
  String teamA,
  String teamB,
) {
  final passing =
      marketA.startsWith('player_pass') || marketB.startsWith('player_pass');
  final catching =
      marketA.startsWith('player_reception') ||
      marketB.startsWith('player_reception');
  if (!passing || !catching) return false;
  if (teamA.isEmpty || teamB.isEmpty) return false;
  return teamA.toUpperCase() == teamB.toUpperCase();
}

/// Chance every leg hits. Unrelated legs multiply. Same-game legs add
/// the shared movement, then the result is kept between zero and the
/// smallest leg.
double jointChance(List<double> probabilities, List<List<double>> correlation) {
  if (probabilities.isEmpty) {
    throw ArgumentError('A ticket needs a leg.');
  }
  for (final chance in probabilities) {
    if (!chance.isFinite || chance <= 0 || chance >= 1) {
      throw ArgumentError('Each chance must be between 0 and 1.');
    }
  }
  if (probabilities.length == 1) return probabilities.single;
  var joint = probabilities.reduce((a, b) => a * b);
  for (var i = 0; i < probabilities.length; i++) {
    for (var j = i + 1; j < probabilities.length; j++) {
      final left = probabilities[i];
      final right = probabilities[j];
      final rho = correlation[i][j];
      final covariance =
          rho * math.sqrt(left * (1 - left) * right * (1 - right));
      var others = 1.0;
      for (var k = 0; k < probabilities.length; k++) {
        if (k == i || k == j) continue;
        others *= probabilities[k];
      }
      joint += covariance * others;
    }
  }
  final high = probabilities.reduce(math.min);
  if (joint < 0) return 0;
  if (joint > high) return high;
  return joint;
}

class TicketLegInput {
  const TicketLegInput({
    required this.label,
    required this.eventId,
    required this.market,
    required this.outcome,
    required this.decimal,
    this.player = '',
    this.team = '',
    this.point,
    this.ourChance,
    this.otherDecimal,
    this.consensusFair,
    this.source = 'our number',
    this.modelUnproven = false,
    this.hits,
    this.observed,
    this.sameLine = const [],
    this.altLines = const [],
    this.otherLegs = const [],
  });

  final String label, eventId, market, outcome, player, team, source;
  final double decimal;
  final double? point, ourChance, otherDecimal, consensusFair;
  final bool modelUnproven;
  final int? hits, observed;
  final List<ValueInput> sameLine, altLines, otherLegs;

  ValueInput get asValue => ValueInput(
    label: label,
    ourChance: ourChance,
    decimal: decimal,
    otherDecimal: otherDecimal,
    consensusFair: consensusFair,
    source: source,
    modelUnproven: modelUnproven,
    hits: hits,
    observed: observed,
  );
}

class TicketLegValue {
  const TicketLegValue({required this.input, required this.verdict});

  final TicketLegInput input;
  final ValueVerdict verdict;
}

class BookLegPrice {
  const BookLegPrice({
    required this.bookId,
    required this.book,
    required this.decimal,
  });

  final String bookId, book;
  final double decimal;
}

class TicketValue {
  const TicketValue({
    required this.word,
    required this.why,
    required this.math,
    required this.legs,
    required this.payoutDecimal,
    required this.payoutEstimated,
    required this.sameGame,
    this.joint,
    this.independent,
    this.bestBook,
    this.expectedValue,
  });

  final ValueWord word;
  final String why, math;
  final List<TicketLegValue> legs;
  final double payoutDecimal;
  final bool payoutEstimated;
  final bool sameGame;
  final double? joint, independent, expectedValue;
  final String? bestBook;

  String get wordLabel => switch (word) {
    ValueWord.bet => 'Review',
    ValueWord.lean => 'Thin margin',
    ValueWord.skip => 'Pass',
  };
}

TicketValue priceTicket(
  List<TicketLegInput> legs, {
  double? pastedDecimal,
  List<List<BookLegPrice>> booksByLeg = const [],
  double? simulatedJoint,
  bool requireSimulation = false,
}) {
  if (legs.length < 2) {
    throw ArgumentError('A parlay needs at least two legs.');
  }
  if (pastedDecimal != null &&
      (!pastedDecimal.isFinite || pastedDecimal <= 1)) {
    throw ArgumentError('Ticket odds must be a finite decimal greater than 1.');
  }
  if (simulatedJoint != null &&
      (!simulatedJoint.isFinite || simulatedJoint < 0 || simulatedJoint > 1)) {
    throw ArgumentError('The simulated joint chance must be between 0 and 1.');
  }
  final judged = [
    for (final leg in legs)
      TicketLegValue(input: leg, verdict: _withAlternative(leg)),
  ];
  final sameGame =
      legs.length >= 2 &&
      legs.map((leg) => leg.eventId).toSet().length < legs.length;
  final chances = [for (final leg in legs) leg.ourChance];
  final complete = chances.every(
    (chance) => chance != null && chance > 0 && chance < 1,
  );
  double? independent;
  double? joint;
  if (complete) {
    final values = chances.cast<double>();
    independent = values.reduce((a, b) => a * b);
    joint =
        simulatedJoint ??
        (requireSimulation
            ? (sameGame ? null : independent)
            : jointChance(values, _correlation(legs)));
  }
  final multiplied = legs.fold<double>(1, (total, leg) => total * leg.decimal);
  final pasted = pastedDecimal != null;
  final best = _bestBook(booksByLeg);
  double payout = multiplied;
  var estimated = false;
  if (pasted) {
    payout = pastedDecimal;
  } else if (sameGame && joint != null) {
    payout = _estimatedPayout(joint, multiplied);
    estimated = true;
  } else if (sameGame) {
    payout = multiplied;
    estimated = true;
  } else if (best != null) {
    payout = best.decimal;
  } else if (booksByLeg.isNotEmpty) {
    estimated = true;
  }
  TicketLegValue? skippedLeg;
  for (final leg in judged) {
    if (leg.verdict.word == ValueWord.skip) {
      skippedLeg = leg;
      break;
    }
  }
  double? profit;
  ValueWord word;
  if (skippedLeg != null ||
      joint == null ||
      (requireSimulation && sameGame && !pasted)) {
    word = ValueWord.skip;
  } else {
    profit = expectedValue(payout, joint);
    word = profit >= betExpectedValue
        ? ValueWord.bet
        : profit > 0
        ? ValueWord.lean
        : ValueWord.skip;
  }
  return TicketValue(
    word: word,
    why: _why(
      judged: judged,
      sameGame: sameGame,
      joint: joint,
      independent: independent,
      word: word,
      estimated: estimated,
      pasted: pasted,
      skipped: skippedLeg,
    ),
    math: _math(
      joint: joint,
      independent: independent,
      payout: payout,
      estimated: estimated,
      pasted: pasted,
      profit: profit,
      best: best,
      sameGame: sameGame,
    ),
    legs: judged,
    payoutDecimal: payout,
    payoutEstimated: estimated,
    sameGame: sameGame,
    joint: joint,
    independent: independent,
    bestBook: sameGame || pasted ? null : best?.book,
    expectedValue: profit,
  );
}

ValueVerdict _withAlternative(TicketLegInput leg) {
  final verdict = judgeValue(leg.asValue);
  final alternative = suggestAlternative(
    current: verdict,
    sameLine: leg.sameLine,
    altLines: leg.altLines,
    otherLegs: leg.otherLegs,
  );
  if (alternative == null) return verdict;
  return ValueVerdict(
    word: verdict.word,
    why: '${verdict.why} $alternative',
    math: verdict.math,
    ourChance: verdict.ourChance,
    fairChance: verdict.fairChance,
    breakEven: verdict.breakEven,
    expectedValue: verdict.expectedValue,
    alternative: alternative,
    overpriced: verdict.overpriced,
  );
}

List<List<double>> _correlation(List<TicketLegInput> legs) {
  return [
    for (var i = 0; i < legs.length; i++)
      [
        for (var j = 0; j < legs.length; j++)
          i == j
              ? 1.0
              : legCorrelation(
                  eventA: legs[i].eventId,
                  eventB: legs[j].eventId,
                  marketA: legs[i].market,
                  marketB: legs[j].market,
                  outcomeA: legs[i].outcome,
                  outcomeB: legs[j].outcome,
                  playerA: legs[i].player,
                  playerB: legs[j].player,
                  teamA: legs[i].team,
                  teamB: legs[j].team,
                  pointA: legs[i].point,
                  pointB: legs[j].point,
                ),
      ],
  ];
}

/// Fair price of the correlated chance, shortened by a normal -110 fee,
/// and never higher than multiplying the leg prices.
double _estimatedPayout(double joint, double multiplied) {
  const hold = 0.045;
  final offered = (1 / joint) / (1 + hold);
  if (!offered.isFinite || offered <= 1) return multiplied;
  if (offered > multiplied) return multiplied;
  return offered;
}

class _BestBook {
  const _BestBook(this.bookId, this.book, this.decimal);
  final String bookId, book;
  final double decimal;
}

_BestBook? _bestBook(List<List<BookLegPrice>> legs) {
  if (legs.length < 2 || legs.any((leg) => leg.isEmpty)) return null;
  final shared = legs.first.map((price) => price.bookId).toSet();
  for (final leg in legs.skip(1)) {
    shared.removeWhere((id) => leg.every((price) => price.bookId != id));
  }
  _BestBook? best;
  for (final id in shared) {
    var product = 1.0;
    String? name;
    for (final leg in legs) {
      final price = leg.firstWhere((item) => item.bookId == id);
      product *= price.decimal;
      name = price.book;
    }
    if (best == null || product > best.decimal) {
      best = _BestBook(id, name ?? id, product);
    }
  }
  return best;
}

String _why({
  required List<TicketLegValue> judged,
  required bool sameGame,
  required double? joint,
  required double? independent,
  required ValueWord word,
  required bool estimated,
  required bool pasted,
  required TicketLegValue? skipped,
}) {
  final buffer = StringBuffer();
  if (skipped != null) {
    buffer.write(
      '${skipped.input.label} is a ${skipped.verdict.wordLabel.toLowerCase()}, so the ticket is a skip. ',
    );
    if (skipped.verdict.overpriced) {
      buffer.write('That leg is overpriced even if it is likely to hit. ');
    }
  }
  for (final leg in judged) {
    final chance = leg.verdict.ourChance;
    buffer.write(
      '${leg.input.label}: ${leg.verdict.wordLabel}'
      '${chance == null ? '' : ', our chance ${_pct(chance)}'}. ',
    );
  }
  if (sameGame) {
    buffer.write(
      'These legs are in the same game, so they move together and the chances are not just multiplied. ',
    );
    if (joint != null && independent != null) {
      buffer.write(
        'Multiplied they would be ${_pct(independent)}. With the shared game they are ${_pct(joint)}. ',
      );
    }
  } else if (independent != null) {
    buffer.write(
      'The games are different, so the chances multiply to ${_pct(independent)}. ',
    );
  }
  if (pasted) {
    buffer.write('The payout is the one on the slip. ');
  } else if (estimated) {
    buffer.write(
      'The same-game payout is estimated, not a price a book posted. ',
    );
  } else {
    buffer.write('The payout is the leg prices multiplied. ');
  }
  buffer.write(switch (word) {
    ValueWord.bet => 'Review.',
    ValueWord.lean => 'Thin margin.',
    ValueWord.skip => 'Pass.',
  });
  return buffer.toString();
}

String _math({
  required double? joint,
  required double? independent,
  required double payout,
  required bool estimated,
  required bool pasted,
  required double? profit,
  required _BestBook? best,
  required bool sameGame,
}) {
  final payoutName = pasted
      ? 'Payout on the slip'
      : estimated
      ? 'Estimated payout'
      : 'Multiplied payout';
  return [
    'Chance if the legs were unrelated: ${independent == null ? 'blank' : _pct(independent)}.',
    'Chance used: ${joint == null ? 'blank' : _pct(joint)}${sameGame ? ', with same-game legs moved together' : ''}.',
    '$payoutName: ${americanLabel(payout)}.',
    if (estimated) 'Estimated means the correlated chance, shortened by the usual fee on a -110 price, and capped at the multiplied leg prices. It is not a posted same-game price.',
    'Expected profit per \$1: ${profit == null ? 'blank' : _signed(profit)}.',
    if (best != null)
      'Best book in this snapshot for these legs: ${best.book}, multiplying to ${americanLabel(best.decimal)}.',
  ].join(' ');
}

String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _signed(double profit) {
  final cents = profit * 100;
  final sign = cents > 0
      ? '+'
      : cents < 0
      ? '-'
      : '';
  return '$sign${cents.abs().toStringAsFixed(1)} cents';
}
