import 'dart:math' as math;

/// Earlier forecasts required before the curve is allowed to move.
/// Below this the map is the identity. Chosen before the bundled run.
const calibrationMinSamples = 200;

/// Forecasts in each bin before the monotone fit. Chosen before the run.
const calibrationBinSize = 80;

/// A monotone map from a raw over-chance to a recalibrated over-chance.
///
/// Fit with pool-adjacent-violators on equal-count bins. The map is
/// applied to the over, then the under is one minus that. It is fit
/// only on forecasts from earlier weeks.
class PropCalibrator {
  const PropCalibrator._(this.points, this.samples);

  /// (raw over chance, calibrated over chance), sorted by the raw chance.
  final List<(double, double)> points;
  final int samples;

  static const identity = PropCalibrator._([], 0);

  bool get isIdentity => points.isEmpty;

  double apply(double raw) {
    if (!raw.isFinite) return raw;
    if (points.isEmpty) return _clamp(raw);
    if (raw <= points.first.$1) return _clamp(points.first.$2);
    if (raw >= points.last.$1) return _clamp(points.last.$2);
    for (var i = 1; i < points.length; i++) {
      final left = points[i - 1];
      final right = points[i];
      if (raw > right.$1) continue;
      final span = right.$1 - left.$1;
      if (span <= 1e-12) return _clamp(right.$2);
      final t = (raw - left.$1) / span;
      return _clamp(left.$2 + t * (right.$2 - left.$2));
    }
    return _clamp(points.last.$2);
  }
}

double _clamp(double value) => value.clamp(1e-4, 1 - 1e-4).toDouble();

/// Fit on [rows] of raw over-chances and whether the over cleared.
/// Fewer than [calibrationMinSamples] returns the identity.
PropCalibrator fitPropCalibrator(List<({double raw, bool hit})> rows) {
  if (rows.length < calibrationMinSamples) return PropCalibrator.identity;
  final usable = [
    for (final row in rows)
      if (row.raw.isFinite) row,
  ];
  if (usable.length < calibrationMinSamples) return PropCalibrator.identity;
  usable.sort((a, b) => a.raw.compareTo(b.raw));
  final bins = <_Bin>[];
  var start = 0;
  while (start < usable.length) {
    var end = math.min(start + calibrationBinSize, usable.length);
    final tail = usable.length - end;
    if (tail > 0 && tail < calibrationBinSize ~/ 2) end = usable.length;
    var rawSum = 0.0;
    var hits = 0;
    for (var i = start; i < end; i++) {
      rawSum += usable[i].raw;
      if (usable[i].hit) hits++;
    }
    final count = end - start;
    bins.add(_Bin(rawSum / count, hits / count, count.toDouble()));
    start = end;
  }
  final stack = <_Bin>[];
  for (final bin in bins) {
    stack.add(bin);
    while (stack.length >= 2 &&
        stack[stack.length - 2].y > stack.last.y + 1e-12) {
      final right = stack.removeLast();
      final left = stack.removeLast();
      final weight = left.weight + right.weight;
      stack.add(
        _Bin(
          (left.x * left.weight + right.x * right.weight) / weight,
          (left.y * left.weight + right.y * right.weight) / weight,
          weight,
        ),
      );
    }
  }
  return PropCalibrator._(
    [for (final bin in stack) (bin.x, _clamp(bin.y))],
    usable.length,
  );
}

class _Bin {
  const _Bin(this.x, this.y, this.weight);
  final double x;
  final double y;
  final double weight;
}
