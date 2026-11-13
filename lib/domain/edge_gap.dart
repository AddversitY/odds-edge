/// The gap between our chance and the book's no-vig chance, in
/// percentage points. Null when either number is missing. This is a
/// comparison of two chances we already have, not a new model.
double? edgePoints(double? ourChance, double? bookChance) {
  if (!_chance(ourChance) || !_chance(bookChance)) return null;
  return (ourChance! - bookChance!) * 100;
}

bool _chance(double? value) =>
    value != null && value.isFinite && value > 0 && value < 1;

/// "+9 pts", "−2.5 pts", "0 pts", or an em dash when the gap is unknown.
String edgePointsLabel(double? points) {
  if (points == null || !points.isFinite) return '—';
  if (points.abs() < 0.05) return '0 pts';
  final tenths = (points.abs() * 10).round();
  final number = tenths % 10 == 0
      ? '${tenths ~/ 10}'
      : (tenths / 10).toStringAsFixed(1);
  return points > 0 ? '+$number pts' : '−$number pts';
}

/// "61%" when the percent is effectively whole, otherwise one decimal.
/// An em dash when the chance was not supplied.
String chanceLabel(double? value) {
  if (!_chance(value)) return '—';
  final pct = value! * 100;
  final nearest = pct.roundToDouble();
  if ((pct - nearest).abs() < 0.05) return '${nearest.toInt()}%';
  return '${pct.toStringAsFixed(1)}%';
}

/// Average and median of recorded stat values. Missing stats are
/// skipped. Both stay null when nothing was recorded.
({double? average, double? median, int count}) sampleStats(Iterable<num?> values) {
  final recorded = <double>[
    for (final value in values)
      if (value != null && value.isFinite) value.toDouble(),
  ];
  if (recorded.isEmpty) return (average: null, median: null, count: 0);
  final sum = recorded.reduce((a, b) => a + b);
  final sorted = [...recorded]..sort();
  final mid = sorted.length ~/ 2;
  final median = sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
  return (average: sum / recorded.length, median: median, count: recorded.length);
}
