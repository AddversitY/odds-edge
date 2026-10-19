import 'dart:convert';

import 'research.dart';

String researchId(SavedResearch r) => jsonEncode([
  r.savedAt.toUtc().toIso8601String(),
  r.context.identity,
  r.context.price,
  r.context.quote?.sourceAt.toUtc().toIso8601String(),
  r.name,
  r.assumptions.toJson(),
]);

enum ResearchOutcome { win, loss, push, voided }

class ResearchReview {
  const ResearchReview({
    required this.researchKey,
    required this.outcome,
    required this.recordedAt,
    required this.source,
    required this.notes,
  });
  final String researchKey, source, notes;
  final ResearchOutcome outcome;
  final DateTime recordedAt;
  Map<String, dynamic> toJson() => {
    'schema': 1,
    'researchKey': researchKey,
    'outcome': outcome.name,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'source': source,
    'notes': notes,
  };
  factory ResearchReview.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 1) throw const FormatException('Unknown review schema');
    final r = ResearchReview(
      researchKey: j['researchKey'],
      outcome: ResearchOutcome.values.byName(j['outcome']),
      recordedAt: DateTime.parse(j['recordedAt']),
      source: j['source'],
      notes: j['notes'],
    );
    if (r.researchKey.isEmpty ||
        r.source.trim().isEmpty ||
        r.source.length > 300 ||
        r.notes.length > 2000) {
      throw const FormatException('Invalid review');
    }
    return r;
  }
}

/// Half the sum of squared win/loss/push probability errors; range 0..1.
/// Reduces to ordinary binary Brier error when push probability is zero.
double? forecastError(SavedResearch r, ResearchOutcome outcome) {
  if (outcome == ResearchOutcome.voided) return null;
  final probabilities = [
    r.assumptions.probability,
    1 - r.assumptions.probability - r.assumptions.push,
    r.assumptions.push,
  ];
  final target = outcome == ResearchOutcome.win
      ? 0
      : outcome == ResearchOutcome.loss
      ? 1
      : 2;
  var total = 0.0;
  for (var i = 0; i < 3; i++) {
    final d = probabilities[i] - (i == target ? 1 : 0);
    total += d * d;
  }
  return total / 2;
}

class AutopsySummary {
  AutopsySummary(
    List<SavedResearch> records,
    Map<String, ResearchReview> reviews,
  ) {
    total = records.length;
    // Keep the earliest pregame snapshot per exact selection, selected BEFORE
    // checking outcome availability, to avoid picking the best-looking revision.
    final first = <String, SavedResearch>{};
    final sorted = [...records]
      ..sort((a, b) {
        final order = a.savedAt.compareTo(b.savedAt);
        return order == 0 ? researchId(a).compareTo(researchId(b)) : order;
      });
    for (final r in sorted) {
      if (reviews.containsKey(researchId(r))) reviewed++;
      if (r.context.demo) {
        demo++;
        continue;
      }
      if (r.context.event == null ||
          !r.savedAt.isBefore(r.context.event!.startsAt)) {
        late++;
        continue;
      }
      first.putIfAbsent(r.context.identity, () => r);
    }
    eligible = first.length;
    final errors = <double>[];
    for (final r in first.values) {
      final review = reviews[researchId(r)];
      if (review == null) continue;
      // A manual review must be recorded after the event begins.
      if (review.recordedAt.isBefore(r.context.event!.startsAt)) continue;
      final score = forecastError(r, review.outcome);
      if (score != null) errors.add(score);
    }
    scored = errors.length;
    if (errors.isNotEmpty) {
      meanError = errors.reduce((a, b) => a + b) / errors.length;
    }
  }
  int total = 0, reviewed = 0, demo = 0, late = 0, eligible = 0, scored = 0;
  double? meanError;
}
