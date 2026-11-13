import 'public_sharp.dart';
import 'value_check.dart';

/// Closing-line value for props that were saved twice.
///
/// The earlier no-vig is the price. The later no-vig is the close.
/// Positive means the close moved toward the side. Reading snapshots
/// does not call the odds API. A missing second price stays blank.
class PropClv {
  const PropClv({
    required this.compared,
    required this.average,
    required this.sentence,
  });

  final int compared;

  /// Average no-vig points gained on the side that was ahead of the
  /// earlier price. Null when no side was supplied or no prop repeated.
  final double? average;
  final String sentence;

  static const empty = PropClv(
    compared: 0,
    average: null,
    sentence:
        'No prop has two saved prices, so closing-line value is blank. A later snapshot of the same player and line will fill it. Reading snapshots does not spend a credit.',
  );
}

class _PropPoint {
  const _PropPoint({
    required this.at,
    required this.player,
    required this.market,
    required this.line,
    required this.overNoVig,
  });

  final DateTime at;
  final String player, market;
  final double line;
  final double overNoVig;
}

/// [overChance] is our chance of the over at the earlier snapshot.
/// When it is omitted, the count of repeated props is still reported
/// and the average is left blank.
PropClv propClosingValue(
  Map<String, List<LineSnapshot>> history, {
  double? Function(
    String player,
    String market,
    double line,
    DateTime at,
    double earlierNoVig,
  )?
  overChance,
}) {
  final series = <String, List<_PropPoint>>{};
  for (final shots in history.values) {
    for (final shot in shots) {
      final byBook = <String, Map<String, double>>{};
      final lines = <String, double>{};
      for (final price in shot.prices) {
        final player = price.player.trim();
        if (player.isEmpty) continue;
        if (price.point == null || !price.usable) continue;
        if (price.outcome != 'Over' && price.outcome != 'Under') continue;
        final key = '$player|${price.market}|${price.point}';
        lines[key] = price.point!;
        final book = byBook.putIfAbsent(key, () => {});
        book['${price.bookId}|${price.outcome}'] = price.decimal;
      }
      for (final entry in byBook.entries) {
        final parts = entry.key.split('|');
        if (parts.length < 3) continue;
        final player = parts[0];
        final market = parts[1];
        final line = lines[entry.key];
        if (line == null) continue;
        final vigs = <double>[];
        final books = <String>{};
        for (final priceKey in entry.value.keys) {
          books.add(priceKey.split('|').first);
        }
        for (final book in books) {
          final over = entry.value['$book|Over'];
          final under = entry.value['$book|Under'];
          final fair = noVigChance(over, under);
          if (fair != null) vigs.add(fair);
        }
        if (vigs.isEmpty) continue;
        final mean = vigs.reduce((a, b) => a + b) / vigs.length;
        (series[entry.key] ??= []).add(
          _PropPoint(
            at: shot.at,
            player: player,
            market: market,
            line: line,
            overNoVig: mean,
          ),
        );
      }
    }
  }
  final rows = <({double clv})>[];
  var repeated = 0;
  for (final points in series.values) {
    points.sort((a, b) => a.at.compareTo(b.at));
    if (points.length < 2) continue;
    repeated++;
    final earlier = points.first;
    final later = points.last;
    if (!later.at.isAfter(earlier.at)) continue;
    final chance = overChance?.call(
      earlier.player,
      earlier.market,
      earlier.line,
      earlier.at,
      earlier.overNoVig,
    );
    if (chance == null) continue;
    final tookOver = chance > earlier.overNoVig;
    final tookUnder = (1 - chance) > (1 - earlier.overNoVig) && !tookOver;
    if (!tookOver && !tookUnder) continue;
    final clv = tookOver
        ? later.overNoVig - earlier.overNoVig
        : earlier.overNoVig - later.overNoVig;
    rows.add((clv: clv));
  }
  if (repeated == 0) return PropClv.empty;
  if (overChance == null || rows.isEmpty) {
    return PropClv(
      compared: 0,
      average: null,
      sentence:
          '$repeated ${repeated == 1 ? 'prop has' : 'props have'} an earlier price and a later one. Closing-line value stays blank until the side from the earlier snapshot is scored. No credit was spent to read them.',
    );
  }
  final average = rows.map((row) => row.clv).reduce((a, b) => a + b) / rows.length;
  final points = (average * 100);
  final direction = points > 0.05
      ? 'The close moved toward that side.'
      : points < -0.05
      ? 'The close moved away from that side.'
      : 'The close barely moved.';
  return PropClv(
    compared: rows.length,
    average: average,
    sentence:
        'On ${rows.length} ${rows.length == 1 ? 'prop' : 'props'} with two saved prices, the side ahead of the earlier no-vig gained ${points.toStringAsFixed(1)} points of no-vig by the later price. $direction This is not a profit and not a pick.',
  );
}
