import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/research.dart';
import 'package:odds_edge/data/research_store.dart';

void main() {
  test('Illustrative sensitivity computes EV and flags a sign reversal', () {
    const a = ResearchAssumptions();
    expect(a.probability, closeTo(.495, 1e-10));
    expect(a.ev, closeTo(.11375, 1e-10));
    expect(a.scenarios[2].ev, lessThan(0));
    expect(a.sensitive, isTrue);
    expect(
      const ResearchAssumptions(
        performance: 10,
        availability: 10,
        environment: 10,
      ).probability,
      .78,
    );
    expect(ResearchAssumptions.baseline, .48);
  });
  test('Local snapshots persist and preserve immutable assumptions', () async {
    final dir = await Directory.systemTemp.createTemp('proof-lab-test');
    addTearDown(() => dir.delete(recursive: true));
    final store = ResearchStore(directory: dir);
    final record = SavedResearch(
      savedAt: DateTime.utc(2026, 10, 18),
      thesis: 'Test theory',
      assumptions: const ResearchAssumptions(),
    );
    await store.save(record);
    await store.save(
      SavedResearch(
        savedAt: DateTime.utc(2026, 10, 19),
        thesis: 'Changed theory',
        assumptions: const ResearchAssumptions(performance: -4),
      ),
    );
    final restored = await ResearchStore(directory: dir).load();
    expect(restored.length, 2);
    expect(restored.first.thesis, 'Changed theory');
    expect(restored.last.assumptions.probability, closeTo(.495, 1e-10));
    expect(restored.last.toJson()['dataOrigin'], 'demonstration');
    expect(restored.last.toJson()['decimalOdds'], 2.25);
  });
  test('Unknown model versions and invalid assumptions fail visibly', () {
    final j = SavedResearch(
      savedAt: DateTime.utc(2026),
      thesis: '',
      assumptions: const ResearchAssumptions(),
    ).toJson();
    j['modelVersion'] = 'unknown';
    expect(() => SavedResearch.fromJson(j), throwsFormatException);
    expect(
      () => ResearchAssumptions.fromJson({
        'performance': double.nan,
        'availability': 0,
        'environment': 0,
      }),
      throwsFormatException,
    );
  });
}
