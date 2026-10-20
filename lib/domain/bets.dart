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
    impliedProbability(decimal);
    if (closingDecimal != null) impliedProbability(closingDecimal!);
  }

  final String id, description, book, notes;
  final DateTime placedAt;
  final double decimal, stake;
  final double? closingDecimal;
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

  TrackedBet copyWith({
    BetResult? result,
    double? closingDecimal,
    bool replaceClosing = false,
    String? notes,
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

  int get wins => bets.where((bet) => bet.result == BetResult.won).length;
  int get losses => bets.where((bet) => bet.result == BetResult.lost).length;
  int get pushes => bets.where((bet) => bet.result == BetResult.push).length;
  int get pending =>
      bets.where((bet) => bet.result == BetResult.pending).length;
}
