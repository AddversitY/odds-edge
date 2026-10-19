import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/research_store.dart';
import 'package:odds_edge/domain/autopsy.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/research.dart';

void main() {
  final start = DateTime.utc(2026, 9, 1);
  SavedResearch record(int hours, {bool demo = false, double push = 0}) =>
      SavedResearch(
        savedAt: start.add(Duration(hours: hours)),
        thesis: 'Original theory',
        assumptions: ResearchAssumptions(
          baseProbability: .6,
          performance: 0,
          availability: 0,
          environment: 0,
          push: push,
        ),
        context: ResearchContext(
          event: SportEvent('e', 'A', 'B', start),
          quote: OddsQuote(
            selection: const Selection(
              eventId: 'e',
              market: 'h2h',
              outcome: 'A',
            ),
            bookId: 'b',
            book: 'Book',
            provider: 'test',
            decimal: 2,
            sourceAt: start,
            collectedAt: start,
            demo: demo,
          ),
        ),
      );
  ResearchReview review(SavedResearch r, ResearchOutcome outcome) =>
      ResearchReview(
        researchKey: researchId(r),
        outcome: outcome,
        recordedAt: start.add(const Duration(hours: 5)),
        source: 'Manual test',
        notes: 'Reviewed',
      );
  test('Probability error handles losses, pushes and voids', () {
    expect(forecastError(record(-1), ResearchOutcome.win), closeTo(.16, 1e-9));
    expect(forecastError(record(-1), ResearchOutcome.loss), closeTo(.36, 1e-9));
    expect(
      forecastError(record(-1, push: .1), ResearchOutcome.push),
      closeTo(.63, 1e-9),
    );
    expect(forecastError(record(-1), ResearchOutcome.voided), isNull);
  });
  test('Accuracy excludes demo and late predictions and does not cherry-pick reviewed revisions', () {
    final first = record(-2),
        revision = record(-1),
        late = record(1),
        demo = record(-3, demo: true);
    final reviews = {
      researchId(revision): review(revision, ResearchOutcome.win),
      researchId(late): review(late, ResearchOutcome.win),
      researchId(demo): review(demo, ResearchOutcome.win),
    };
    final a = AutopsySummary([revision, late, demo, first], reviews);
    expect(a.scored, 0);
    expect(a.eligible, 1);
    expect(a.demo, 1);
    expect(a.late, 1);
    reviews[researchId(first)] = review(first, ResearchOutcome.loss);
    expect(
      AutopsySummary([revision, first], reviews).meanError,
      closeTo(.36, 1e-9),
    );
  });
  test(
    'Outcome corrections persist and export/import preserves original research',
    () async {
      final dir = await Directory.systemTemp.createTemp('autopsy');
      addTearDown(() => dir.delete(recursive: true));
      final store = ResearchStore(directory: dir);
      final r = record(-1);
      await store.save(r);
      await store.saveReview(review(r, ResearchOutcome.win));
      await store.saveReview(review(r, ResearchOutcome.loss));
      final reopened = ResearchStore(directory: dir);
      expect(
        (await reopened.loadReviews())[researchId(r)]!.outcome,
        ResearchOutcome.loss,
      );
      expect((await reopened.load()).single.thesis, 'Original theory');
      final exported = await store.exportJson();
      final other = ResearchStore(directory: Directory('${dir.path}/other'));
      expect(await other.importJson(exported), 1);
      expect(
        (await other.loadReviews())[researchId(r)]!.outcome,
        ResearchOutcome.loss,
      );
      expect(await other.importJson(exported), 0);
    },
  );
}
