import 'odds.dart';

enum BetResult { pending, won, lost, push, voided }

BetResult _resultFrom(Object? value) {
  if (value is! String) {
    throw const FormatException('Bet result is missing.');
  }
  for (final result in BetResult.values) {
    if (result.name == value) return result;
  }
  throw FormatException('Unknown bet result: $value');
}

const betMarkets = {'', 'spreads', 'totals', 'h2h'};
const betSides = {'', 'home', 'away', 'over', 'under'};

class TrackedBet {
  TrackedBet({
    required this.id,
    required this.placedAt,
    required this.description,
    required this.book,
    required this.decimal,
    required this.stake,
    required this.result,
    this.closingDecimal,
    this.notes = '',
    this.market = '',
    this.side = '',
    this.line,
    this.closingLine,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError('A bet needs an id.');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError('Describe the bet.');
    }
    if (book.trim().isEmpty) throw ArgumentError('Name the sportsbook.');
    if (!stake.isFinite || stake <= 0) {
      throw ArgumentError('Stake must be a positive amount.');
    }
    if (!betMarkets.contains(market)) {
      throw ArgumentError('Unknown bet kind.');
    }
    if (!betSides.contains(side)) {
      throw ArgumentError('Unknown bet side.');
    }
    if (line != null && !line!.isFinite) {
      throw ArgumentError('The number on the ticket has to be a real number.');
    }
    if (closingLine != null && !closingLine!.isFinite) {
      throw ArgumentError('The closing number has to be a real number.');
    }
    impliedProbability(decimal);
    if (closingDecimal != null) impliedProbability(closingDecimal!);
  }

  final String id, description, book, notes, market, side;
  final DateTime placedAt;
  final double decimal, stake;
  final double? closingDecimal;

  /// The spread or total on the ticket when the bet was logged.
  /// For a spread this is the bettor's number, with a minus when laying points.
  final double? line;

  /// The same number at the close. Compared with [line] for closing-number value.
  final double? closingLine;
  final BetResult result;

  /// Profit for a settled bet. Pending and void bets are left out.
  double? get profit {
    switch (result) {
      case BetResult.pending:
      case BetResult.voided:
        return null;
      case BetResult.push:
        return 0;
      case BetResult.won:
        return stake * (decimal - 1);
      case BetResult.lost:
        return -stake;
    }
  }

  /// Closing implied chance minus the chance implied by the price you took.
  /// Positive means the close you typed was shorter than your price.
  /// This is not a no-vig close and not a downloaded closing line.
  double? get closingLineValue {
    final close = closingDecimal;
    if (close == null) return null;
    return impliedProbability(close) - impliedProbability(decimal);
  }

  /// Points by which the logged number beat the closing number.
  /// Positive means the ticket had the better number.
  /// A spread uses the bettor's points. An over wants the total to close higher.
  /// An under wants the total to close lower.
  double? get lineClvPoints {
    final logged = line;
    final close = closingLine;
    if (logged == null || close == null) return null;
    switch (market) {
      case 'spreads':
        return logged - close;
      case 'totals':
        if (side == 'over') return close - logged;
        if (side == 'under') return logged - close;
        return null;
      default:
        return null;
    }
  }

  TrackedBet copyWith({
    BetResult? result,
    double? closingDecimal,
    bool replaceClosing = false,
    String? notes,
    double? line,
    double? closingLine,
    bool replaceClosingLine = false,
    String? market,
    String? side,
  }) => TrackedBet(
    id: id,
    placedAt: placedAt,
    description: description,
    book: book,
    decimal: decimal,
    stake: stake,
    result: result ?? this.result,
    closingDecimal: replaceClosing
        ? closingDecimal
        : (closingDecimal ?? this.closingDecimal),
    notes: notes ?? this.notes,
    market: market ?? this.market,
    side: side ?? this.side,
    line: line ?? this.line,
    closingLine: replaceClosingLine
        ? closingLine
        : (closingLine ?? this.closingLine),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'placedAt': placedAt.toUtc().toIso8601String(),
    'description': description,
    'book': book,
    'decimal': decimal,
    'stake': stake,
    'result': result.name,
    'closingDecimal': closingDecimal,
    'notes': notes,
    'market': market,
    'side': side,
    'line': line,
    'closingLine': closingLine,
  };

  factory TrackedBet.fromJson(Map<String, dynamic> json) {
    final placed = json['placedAt'];
    if (placed is! String) {
      throw const FormatException('Bet placedAt must be a timestamp.');
    }
    final decimal = json['decimal'];
    final stake = json['stake'];
    if (decimal is! num || stake is! num) {
      throw const FormatException('Bet price and stake must be numbers.');
    }
    final closing = json['closingDecimal'];
    if (closing != null && closing is! num) {
      throw const FormatException('Closing price must be a number.');
    }
    final line = json['line'];
    final closingLine = json['closingLine'];
    if (line != null && line is! num) {
      throw const FormatException('The logged number must be a number.');
    }
    if (closingLine != null && closingLine is! num) {
      throw const FormatException('The closing number must be a number.');
    }
    final market = json['market'];
    final side = json['side'];
    if (market != null && market is! String) {
      throw const FormatException('Bet kind must be text.');
    }
    if (side != null && side is! String) {
      throw const FormatException('Bet side must be text.');
    }
    return TrackedBet(
      id: '${json['id'] ?? ''}',
      placedAt: DateTime.parse(placed),
      description: '${json['description'] ?? ''}',
      book: '${json['book'] ?? ''}',
      decimal: decimal.toDouble(),
      stake: stake.toDouble(),
      result: _resultFrom(json['result']),
      closingDecimal: (closing as num?)?.toDouble(),
      notes: '${json['notes'] ?? ''}',
      market: market ?? '',
      side: side ?? '',
      line: (line as num?)?.toDouble(),
      closingLine: (closingLine as num?)?.toDouble(),
    );
  }
}

class BetLedger {
  BetLedger(List<TrackedBet> bets) : bets = List.unmodifiable(bets);

  final List<TrackedBet> bets;

  List<TrackedBet> get settled => [
    for (final bet in bets)
      if (bet.profit != null) bet,
  ];

  double get profit => settled.fold<double>(0, (sum, bet) => sum + bet.profit!);

  double get staked => settled.fold<double>(0, (sum, bet) => sum + bet.stake);

  /// Profit divided by stake on settled bets. Null when nothing is settled.
  double? get roi => staked == 0 ? null : profit / staked;

  List<double> get closingLineValues => [
    for (final bet in bets)
      if (bet.closingLineValue != null) bet.closingLineValue!,
  ];

  double? get averageClosingLineValue {
    final values = closingLineValues;
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  int get beatClose => closingLineValues.where((value) => value > 0).length;

  List<double> get lineClvPoints => [
    for (final bet in bets)
      if (bet.lineClvPoints != null) bet.lineClvPoints!,
  ];

  int get beatClosingNumber => lineClvPoints.where((value) => value > 0).length;

  /// Average points by which the logged number beat the close. Null when no
  /// closing number has been entered.
  double? get averageLineClv {
    final values = lineClvPoints;
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  int get wins => bets.where((bet) => bet.result == BetResult.won).length;
  int get losses => bets.where((bet) => bet.result == BetResult.lost).length;
  int get pushes => bets.where((bet) => bet.result == BetResult.push).length;
  int get pending =>
      bets.where((bet) => bet.result == BetResult.pending).length;
}
