import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/edge_gap.dart';
import 'package:odds_edge/domain/parlay_slip.dart';

void main() {
  test('edge points are our chance minus the book, in percentage points', () {
    expect(edgePoints(0.61, 0.52), closeTo(9, 0.0001));
    expect(edgePoints(0.48, 0.52), closeTo(-4, 0.0001));
    expect(edgePoints(null, 0.52), isNull);
    expect(edgePoints(0.61, null), isNull);
    expect(edgePoints(0, 0.5), isNull);
    expect(edgePoints(1, 0.5), isNull);
    expect(edgePointsLabel(9), '+9 pts');
    expect(edgePointsLabel(2.14), '+2.1 pts');
    expect(edgePointsLabel(-2.5), '−2.5 pts');
    expect(edgePointsLabel(0.01), '0 pts');
    expect(edgePointsLabel(null), '—');
    expect(chanceLabel(0.61), '61%');
    expect(chanceLabel(0.525), '52.5%');
    expect(chanceLabel(null), '—');
  });

  test('sample stats skip missing games', () {
    final stats = sampleStats([10, null, 30, 20]);
    expect(stats.count, 3);
    expect(stats.average, 20);
    expect(stats.median, 20);
    expect(sampleStats([null]).count, 0);
    expect(sampleStats(const []).average, isNull);
  });

  test('a slip adds, removes, and refuses a non-positive stake', () {
    const empty = ParlaySlip();
    final one = empty.add('a');
    expect(one.selectionKeys, ['a']);
    expect(identical(one.add('a'), one), isTrue);
    expect(one.add('  ').selectionKeys, ['a']);
    final two = one.add('b');
    expect(two.remove('a').selectionKeys, ['b']);
    expect(two.clear().selectionKeys, isEmpty);
    expect(two.clear().stake, 10);
    expect(two.withStake(25).stake, 25);
    expect(() => two.withStake(0), throwsArgumentError);
  });
}
