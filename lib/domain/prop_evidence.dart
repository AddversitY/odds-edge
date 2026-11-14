import 'injury_report.dart';
import 'prop_history.dart';
import 'prop_projection.dart';
import 'hit_rate.dart';

bool hasCurrentInjuries(InjuryReport? report, DateTime now) {
  if (report == null || !report.live) return false;
  final checked = report.checkedAt ?? report.fetchedAt;
  return !checked.isAfter(now) &&
      now.difference(checked) < const Duration(hours: 24);
}

class PropEvidence {
  const PropEvidence({
    required this.support,
    required this.cautions,
    required this.context,
  });
  final List<String> support, cautions, context;
}

/// Explains existing inputs without inventing a confidence score. A favorable
/// input for an Over is unfavorable for an Under.
PropEvidence explainPropEvidence({
  required LineSide side,
  PropProjection? projection,
  PropWindows? windows,
  InjuryReport? injuries,
  required DateTime now,
  double? spread,
  double? total,
  bool example = false,
  String? dataWarning,
}) {
  final support = <String>[], caution = <String>[], context = <String>[];
  if (dataWarning != null) caution.add(dataWarning);
  if (example) {
    caution.add(
      'Prices and matchups are invented examples, not current sportsbook offers.',
    );
  }
  final model = projection;
  if (model == null) {
    caution.add(
      'No usage projection is available. Missing workload is not filled with a confidence score.',
    );
  } else {
    for (final factor in model.factors) {
      if (factor.label == 'Usage') {
        context.add('Workload: ${factor.detail}.');
        continue;
      }
      final detail =
          '${factor.label}: ${factor.detail} (${factor.delta >= 0 ? '+' : ''}${factor.delta.toStringAsFixed(1)} ${model.unit} in the raw projection).';
      context.add(detail);
      final direction = factor.delta * (side == LineSide.over ? 1 : -1);
      if (direction > .05) support.add(detail);
      if (direction < -.05) caution.add(detail);
    }
    if (model.capped) {
      caution.add(
        'The market shrink and cap limit the stated chance; the raw projection is not the card probability.',
      );
    }
  }
  final count = windows?.season?.observed ?? windows?.last10?.observed ?? 0;
  if (count < 10) {
    caution.add('Only $count observed games in the preferred history window.');
  }
  if (!hasCurrentInjuries(injuries, now)) {
    caution.add(
      'A current injury report is unavailable. Availability and starting status are not confirmed.',
    );
  } else {
    context.add(
      'Availability: ${injuries!.freshness(now)}. Reports are context, not a guarantee of participation.',
    );
  }
  if (spread != null && total != null) {
    context.add(
      '${example ? 'Example' : 'Snapshot'} game script: team spread ${spread.toStringAsFixed(1)}, total ${total.toStringAsFixed(1)}, implied team points ${((total - spread) / 2).toStringAsFixed(1)}.',
    );
  } else {
    caution.add(
      'A complete spread/total pair is missing; game-script context is limited.',
    );
  }
  context.add(
    'Weather is not an input to this prop projection. No weather adjustment is assumed.',
  );
  return PropEvidence(
    support: List.unmodifiable(support),
    cautions: List.unmodifiable(caution),
    context: List.unmodifiable(context),
  );
}
