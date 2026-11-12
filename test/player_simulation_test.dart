import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/research_store.dart';
import 'package:odds_edge/domain/player_investigation.dart';
import 'package:odds_edge/domain/player_simulation.dart';
import 'package:odds_edge/domain/player_stats.dart';

List<PlayerGame> simulationGames() => [
  for (var i = 0; i < 8; i++)
    PlayerGame(
      playerId: 'p',
      name: 'Test Player',
      position: 'QB',
      team: 'A',
      opponent: 'B',
      season: 2026,
      week: i + 1,
      date: DateTime.utc(2026, 8, 1).add(Duration(days: i * 7)),
      seasonType: 'REG',
      stats: {'passing_yards': i * 50, 'attempts': i == 0 ? 0 : 20},
    ),
];
PlayerScenario scenario({bool over = true, double line = 100}) =>
    PlayerScenario(metric: 'passing_yards', line: line, price: 2, over: over);
PlayerInvestigation investigation() => PlayerInvestigation(
  savedAt: DateTime.utc(2026, 10, 19),
  playerId: 'p',
  playerName: 'Test Player',
  scenario: scenario(),
  games: simulationGames(),
  cutoff: DateTime.utc(2026, 10, 18),
  source: 'Test fixture',
  sourceRetrievedAt: '2026-10-19',
  thesis: 'Opportunity may persist',
  targetDate: DateTime.utc(2026, 10, 25),
);
void main() {
  test('Whole-game replay is reproducible and has mutually exclusive win/loss/push settlement', () {
    final a = PlayerSimulation(simulationGames(), scenario());
    final b = PlayerSimulation(simulationGames(), scenario());
    expect(a.draws, b.draws);
    expect(a.sampleSize, 8);
    expect(a.draws.length, 10000);
    expect(a.winProbability, closeTo(5 / 8, .025));
    expect(a.pushProbability, closeTo(1 / 8, .025));
    expect(a.draws.every((v) => a.outcomes.contains(v)), isTrue);
    expect(
      a.ev,
      closeTo(
        a.winProbability! - (1 - a.winProbability! - a.pushProbability!),
        1e-12,
      ),
    );
    final under = PlayerSimulation(simulationGames(), scenario(over: false));
    expect(
      a.winProbability! + under.winProbability! + a.pushProbability!,
      closeTo(1, 1e-12),
    );
    expect(
      a.percentile(.1)! <= a.percentile(.5)! &&
          a.percentile(.5)! <= a.percentile(.9)!,
      isTrue,
    );
  });
  test('Scaling preserves workload/efficiency pairs and observed zeroes; missing pairs stay missing', () {
    final a = PlayerSimulation(
      simulationGames(),
      scenario().copyWith(workload: .5, efficiency: .8),
    );
    expect(a.outcomes, [for (var i = 0; i < 8; i++) i * 20.0]);
    expect(a.sampleSize, 8);
    expect(a.excluded, 0);
    final missing = PlayerGame.fromJson({
      ...playerGameJson(simulationGames().first),
      'week': 9,
      'stats': {'passing_yards': null, 'attempts': 20},
    });
    expect(
      PlayerSimulation([...simulationGames(), missing], scenario()).excluded,
      1,
    );
    expect(
      PlayerSimulation(
        simulationGames().take(4).toList(),
        scenario(),
      ).available,
      isFalse,
    );
    final zeros = [
      for (final g in simulationGames())
        PlayerGame.fromJson({
          ...playerGameJson(g),
          'stats': {'passing_yards': 0, 'attempts': 0},
        }),
    ];
    expect(PlayerSimulation(zeros, scenario()).available, isFalse);
    expect(
      () => PlayerSimulation([
        simulationGames().first,
        simulationGames().first,
      ], scenario()),
      throwsFormatException,
    );
  });
  test('Form comparison uses separate recent and earlier observations, not overlapping averages', () {
    final f = PlayerFormEvidence(simulationGames(), 'passing_yards');
    expect(f.recent.map((g) => g.week), [8, 7, 6]);
    expect(f.earlier.map((g) => g.week), [5, 4, 3, 2, 1]);
    expect(
      f.recent.any((a) => f.earlier.any((b) => a.identity == b.identity)),
      isFalse,
    );
      expect(f.interpretation, contains('efficiency'));
  });
  test('Frozen investigation rejects changed versions, future evidence and malformed scenarios', () {
    final r = investigation();
    final restored = PlayerInvestigation.fromJson(
      jsonDecode(jsonEncode(r.toJson())),
    );
    expect(restored.simulation.draws, r.simulation.draws);
    expect(restored.id, r.id);
    expect(
      () => PlayerInvestigation.fromJson({
        ...r.toJson(),
        'modelVersion': 'unknown',
      }),
      throwsFormatException,
    );
    expect(
      () =>
          PlayerInvestigation.fromJson({...r.toJson(), 'cutoff': '2027-01-01'}),
      throwsFormatException,
    );
    expect(
      () => PlayerScenario.fromJson({
        ...r.scenario.toJson(),
        'workload': double.nan,
      }),
      throwsFormatException,
    );
    final review = PlayerInvestigationReview.fromJson({
      'schema': 1,
      'id': r.id,
      'recordedAt': '2026-10-26T00:00:00Z',
      'source': 'Manual',
      'notes': 'Checked',
      'actualYards': 100,
      'actualVolume': 20,
      'voided': false,
    });
    expect(review.outcome(r.scenario), 'Push');
    expect(review.probabilityError(r.simulation), inInclusiveRange(0, 1));
  });
  test('Predictions and outcome corrections survive reopening, backups, and duplicate-safe import', () async {
    final dir = await Directory.systemTemp.createTemp('player-replay');
    addTearDown(() => dir.delete(recursive: true));
    final store = ResearchStore(directory: dir);
    final r = investigation();
    await store.saveInvestigation(r);
    for (final yards in [150.0, 100.0]) {
      await store.saveInvestigationReview(
        PlayerInvestigationReview(
          id: r.id,
          recordedAt: DateTime.utc(2026, 10, 26),
          source: 'Manual checked',
          notes: 'Correction',
          actualYards: yards,
        ),
      );
    }
    final reopened = ResearchStore(directory: dir);
    expect(
      (await reopened.loadInvestigations()).single.simulation.draws,
      r.simulation.draws,
    );
    expect((await reopened.loadInvestigationReviews())[r.id]!.actualYards, 100);
    final backup = await store.backup();
    expect(await File('$backup.player-investigations.jsonl').exists(), isTrue);
    final raw = await store.exportJson();
    final other = ResearchStore(directory: Directory('${dir.path}/other'));
    expect(await other.importJson(raw), 1);
    expect(await other.importJson(raw), 0);
    expect(
      (await other.loadInvestigationReviews())[r.id]!.outcome(r.scenario),
      'Push',
    );
    final broken = jsonDecode(raw);
    broken['investigations'][0]['modelVersion'] = 'unsupported';
    await expectLater(
      other.importJson(jsonEncode(broken)),
      throwsFormatException,
    );
    expect((await other.loadInvestigations()).length, 1);
  });
}
