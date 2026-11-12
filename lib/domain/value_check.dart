import 'market_math.dart';
import 'odds.dart' hide expectedValue;
import 'odds.dart' as odds;

/// The one word on a bet. Bet and Lean are about the price, not about
/// whether the side is likely to happen.
enum ValueWord { bet, lean, skip }

/// A clearly better price than a coin-flip -110. Below this, a small
/// advantage is a Lean. Zero or worse is a Skip.
const betExpectedValue = 0.03;

/// Recorded clears, with two wins and two losses mixed in so a short
/// streak cannot become a certainty. Fewer than four recorded games
/// is not an estimate.
double? shrunkClearRate({required int hits, required int observed}) {
  if (observed < 4) return null;
  if (hits < 0 || hits > observed) {
    throw ArgumentError('Hits must sit inside the recorded games.');
  }
  return (hits + 2) / (observed + 4);
}

/// Fee-free chance of [decimal] when the same book posted [otherDecimal]
/// on the other side. Null when either price is missing.
double? noVigChance(double? decimal, double? otherDecimal) {
  if (decimal == null || otherDecimal == null) return null;
  try {
    return removeVigProportional([
      impliedProbability(decimal),
      impliedProbability(otherDecimal),
    ]).probabilities.first;
  } on ArgumentError {
    return null;
  }
}

class ValueInput {
  const ValueInput({
    required this.label,
    this.ourChance,
    this.decimal,
    this.otherDecimal,
    this.consensusFair,
    this.source = 'our number',
    this.modelUnproven = false,
    this.hits,
    this.observed,
  });

  final String label;

  /// Chance we are willing to use. Null means we will not invent one.
  final double? ourChance;

  /// The price being judged.
  final double? decimal;

  /// The other side at the same book and the same number.
  final double? otherDecimal;

  /// Books averaged after the fee, used only when this book did not
  /// post both sides.
  final double? consensusFair;

  /// Plain name of where [ourChance] came from.
  final String source;

  /// Coach's Line has a past test that lost money. The words say so.
  final bool modelUnproven;
  final int? hits;
  final int? observed;

  double? get breakEven {
    final price = decimal;
    if (price == null) return null;
    try {
      return impliedProbability(price);
    } on ArgumentError {
      return null;
    }
  }

  double? get fairChance =>
      noVigChance(decimal, otherDecimal) ?? _usable(consensusFair);

  double? get expectedValue {
    final price = decimal;
    final chance = ourChance;
    if (price == null || chance == null) return null;
    try {
      return odds.expectedValue(price, chance);
    } on ArgumentError {
      return null;
    }
  }
}

double? _usable(double? value) =>
    value != null && value.isFinite && value > 0 && value < 1 ? value : null;

class ValueVerdict {
  const ValueVerdict({
    required this.word,
    required this.why,
    required this.math,
    this.ourChance,
    this.fairChance,
    this.breakEven,
    this.expectedValue,
    this.alternative,
    this.overpriced = false,
  });

  final ValueWord word;
  final String why;
  final String math;
  final double? ourChance;
  final double? fairChance;
  final double? breakEven;
  final double? expectedValue;
  final String? alternative;

  /// True when we have a chance and the price still loses money against it.
  /// A likely side can be overpriced.
  final bool overpriced;

  String get wordLabel => switch (word) {
    ValueWord.bet => 'Bet',
    ValueWord.lean => 'Lean',
    ValueWord.skip => 'Skip',
  };
}

ValueVerdict judgeValue(ValueInput input) {
  final chance = _usable(input.ourChance);
  final price = input.decimal;
  final fair = input.fairChance;
  final breakEven = input.breakEven;
  if (chance == null || price == null || breakEven == null) {
    return ValueVerdict(
      word: ValueWord.skip,
      ourChance: chance,
      fairChance: fair,
      breakEven: breakEven,
      why: _missingWhy(input, chance, price),
      math: _math(input, chance, fair, breakEven, null),
    );
  }
  final profit = input.expectedValue;
  if (profit == null) {
    return ValueVerdict(
      word: ValueWord.skip,
      ourChance: chance,
      fairChance: fair,
      breakEven: breakEven,
      why: 'Skip. The price could not be compared with our chance.',
      math: _math(input, chance, fair, breakEven, null),
    );
  }
  final word = profit >= betExpectedValue
      ? ValueWord.bet
      : profit > 0
      ? ValueWord.lean
      : ValueWord.skip;
  final overpriced = profit <= 0;
  return ValueVerdict(
    word: word,
    ourChance: chance,
    fairChance: fair,
    breakEven: breakEven,
    expectedValue: profit,
    overpriced: overpriced,
    why: _why(input, chance, fair, breakEven, profit, word),
    math: _math(input, chance, fair, breakEven, profit),
  );
}

String _missingWhy(ValueInput input, double? chance, double? price) {
  if (price == null) {
    return 'Skip. ${input.label} has no open price in this snapshot, so there is nothing to judge.';
  }
  if (chance == null) {
    final games = input.observed;
    if (games != null && games < 4) {
      return 'Skip. ${input.label} has only $games recorded ${games == 1 ? 'game' : 'games'}. '
          'That is not enough to estimate a chance, and a short streak is not filled in.';
    }
    return 'Skip. ${input.label} has no chance from ${input.source}, so the price is not called a bet.';
  }
  return 'Skip. ${input.label} could not be priced.';
}

String _why(
  ValueInput input,
  double chance,
  double? fair,
  double breakEven,
  double profit,
  ValueWord word,
) {
  final likely =
      chance >= 0.6 &&
      profit <= 0 &&
      input.hits != null &&
      input.observed != null;
  final buffer = StringBuffer();
  if (likely) {
    buffer.write(
      '${input.label} has cleared in ${input.hits} of ${input.observed} recorded games, so it is likely to hit. '
      'The price still needs ${_pct(breakEven)} to break even, and our chance is ${_pct(chance)}. '
      'The price is short. ',
    );
  } else {
    buffer.write(
      'Our chance for ${input.label} is ${_pct(chance)}, from ${input.source}. ',
    );
    if (fair != null) {
      final sameBook = input.otherDecimal != null;
      buffer.write(
        sameBook
            ? 'After the fee is taken off this book, the fair chance is ${_pct(fair)}. '
            : 'This book did not post both sides, so the fair chance is the books averaged after the fee, ${_pct(fair)}. ',
      );
    }
    buffer.write('The price needs ${_pct(breakEven)} to break even. ');
    if (profit > 0) {
      buffer.write(
        'A dollar expects to make about ${_cents(profit)} if our chance is right. ',
      );
    } else if (profit < 0) {
      buffer.write(
        'A dollar expects to lose about ${_cents(profit.abs())} if our chance is right. The price is short. ',
      );
    } else {
      buffer.write('A dollar expects to break even if our chance is right. ');
    }
  }
  buffer.write(switch (word) {
    ValueWord.bet => 'Bet.',
    ValueWord.lean => 'Lean. The advantage is small.',
    ValueWord.skip => 'Skip.',
  });
  if (input.modelUnproven) {
    buffer.write(
      ' This chance is Coach\'s Line. The past test of that number lost money, so this word compares the price with our number. It is not a claim the number has beaten the books.',
    );
  }
  return buffer.toString();
}

String _math(
  ValueInput input,
  double? chance,
  double? fair,
  double? breakEven,
  double? profit,
) {
  final parts = <String>[
    if (input.hits != null && input.observed != null)
      'Recorded ${input.hits} of ${input.observed}. Two wins and two losses are mixed in before that becomes our chance, so a short run cannot look certain.',
    'Our chance: ${chance == null ? 'blank' : _pct(chance)}.',
    'Fee-free chance: ${fair == null ? 'blank' : _pct(fair)}.',
    'Price break-even: ${breakEven == null ? 'blank' : _pct(breakEven)}.',
    if (input.decimal != null) 'Price: ${americanLabel(input.decimal!)}.',
    'Expected profit per \$1: ${profit == null ? 'blank' : _signedCents(profit)}.',
    'Bet means at least ${_cents(betExpectedValue)} of expected profit per dollar. Lean is any smaller profit. Skip is zero, a loss, or a missing chance.',
  ];
  return parts.join(' ');
}

/// Picks a better price in the order: same line at another book, a
/// different line, then a different leg. A suggestion has to improve
/// the word. A still-short price is not offered as the alternative.
String? suggestAlternative({
  required ValueVerdict current,
  required List<ValueInput> sameLine,
  required List<ValueInput> altLines,
  required List<ValueInput> otherLegs,
}) {
  final found = _firstBetter(
    current,
    sameLine,
    'The same line at another book',
  );
  if (found != null) return found;
  final line = _firstBetter(current, altLines, 'A different line');
  if (line != null) return line;
  final leg = _firstBetter(current, otherLegs, 'A different leg');
  if (leg != null) return leg;
  if (current.word == ValueWord.skip) {
    return 'No better price, line, or leg is in this snapshot.';
  }
  return null;
}

String? _firstBetter(
  ValueVerdict current,
  List<ValueInput> options,
  String kind,
) {
  ValueVerdict? best;
  ValueInput? source;
  for (final option in options) {
    final judged = judgeValue(option);
    if (!_improves(current, judged)) continue;
    if (best == null || _improves(best, judged)) {
      best = judged;
      source = option;
    }
  }
  final chosen = best;
  final input = source;
  if (chosen == null || input == null || chosen.expectedValue == null) {
    return null;
  }
  final money = chosen.expectedValue! > 0
      ? 'a dollar expects to make about ${_cents(chosen.expectedValue!)}'
      : 'a dollar expects to lose about ${_cents(chosen.expectedValue!.abs())}';
  return '$kind: ${input.label}. ${chosen.wordLabel}, and $money if that chance is right.';
}

bool _improves(ValueVerdict current, ValueVerdict next) {
  final rank = _rank(next.word) - _rank(current.word);
  if (rank > 0) return true;
  if (rank < 0) return false;
  final left = current.expectedValue;
  final right = next.expectedValue;
  if (left == null || right == null) return false;
  return right > left + 0.01 && next.word != ValueWord.skip;
}

int _rank(ValueWord word) => switch (word) {
  ValueWord.bet => 2,
  ValueWord.lean => 1,
  ValueWord.skip => 0,
};

String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _cents(double profit) {
  final cents = (profit * 100).abs();
  final text = cents >= 10
      ? cents.toStringAsFixed(0)
      : cents.toStringAsFixed(1);
  return '$text cents';
}

String _signedCents(double profit) {
  if (profit.abs() < 0.0005) return '0 cents';
  final sign = profit > 0 ? '+' : '-';
  return '$sign${_cents(profit)}';
}

/// Pinnacle's fee-free chance for one side, when both sides are in the
/// snapshot. Spreads and totals only. Any other market returns null.
double? pinnacleFairChance(
  OddsBoard board,
  Selection side,
  Selection? other,
  DateTime now,
) {
  if (side.market != 'spreads' && side.market != 'totals') return null;
  if (other == null) return null;
  final quotes = usableSnapshotQuotes(
    board.quotes,
    now,
    events: board.events,
    fetchedAt: board.fetchedAt,
  );
  double? priceFor(Selection selection) {
    for (final quote in quotes) {
      if (quote.bookId != 'pinnacle') continue;
      if (!_samePrice(quote.selection, selection)) continue;
      return quote.decimal;
    }
    return null;
  }

  return noVigChance(priceFor(side), priceFor(other));
}

bool _samePrice(Selection a, Selection b) {
  if (a.eventId != b.eventId ||
      a.market != b.market ||
      a.outcome != b.outcome) {
    return false;
  }
  if (a.participant.toLowerCase() != b.participant.toLowerCase()) return false;
  final left = a.point;
  final right = b.point;
  if (left == null || right == null) return left == null && right == null;
  return (left - right).abs() < 0.01;
}
