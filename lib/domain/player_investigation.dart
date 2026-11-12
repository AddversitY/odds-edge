import 'dart:convert';

import 'player_simulation.dart';
import 'player_stats.dart';

class PlayerInvestigation {
  PlayerInvestigation({
    required this.savedAt,
    required this.playerId,
    required this.playerName,
    required this.scenario,
    required List<PlayerGame> games,
    required this.cutoff,
    required this.source,
    required this.sourceRetrievedAt,
    this.book = '',
    this.thesis = '',
    this.targetDate,
    this.sourceDigest = '',
    this.sourceUrl = '',
    this.license = '',
    this.licenseUrl = '',
  }) : games = List.unmodifiable(games) {
    scenario.validate();
    if (playerId.isEmpty ||
        playerName.isEmpty ||
        games.length < 5 ||
        games.length > 100 ||
        games.any(
          (g) =>
              g.playerId != playerId ||
              g.date.isAfter(cutoff) ||
              g.seasonType != 'REG',
        ) ||
        games.map((g) => g.identity).toSet().length != games.length ||
        book.length > 100 ||
        thesis.length > 1000 ||
        source.length > 500 ||
        cutoff.isAfter(
          DateTime.utc(savedAt.year, savedAt.month, savedAt.day),
        ) ||
        (targetDate != null && !targetDate!.isAfter(cutoff)) ||
        !simulation.available) {
      throw const FormatException('Invalid player investigation');
    }
  }
  final DateTime savedAt, cutoff;
  final DateTime? targetDate;
  final String playerId,
      playerName,
      source,
      sourceRetrievedAt,
      sourceDigest,
      book,
      thesis;
  final PlayerScenario scenario;
  final List<PlayerGame> games;
  String get id => jsonEncode([
    savedAt.toUtc().toIso8601String(),
    playerId,
    scenario.toJson(),
  ]);
  String get selectionKey => jsonEncode([
    playerId,
    scenario.metric,
    scenario.over,
    scenario.line,
    targetDate?.toIso8601String(),
  ]);
  String get title =>
      '$playerName · ${scenario.over ? 'Over' : 'Under'} ${scenario.line} ${scenario.label.toLowerCase()}';
  final String sourceUrl, license, licenseUrl;
  late final PlayerSimulation simulation = PlayerSimulation(games, scenario);
  bool get pregameDateConfirmed =>
      targetDate != null &&
      DateTime.utc(
        savedAt.year,
        savedAt.month,
        savedAt.day,
      ).isBefore(targetDate!);
  Map<String, dynamic> toJson() => {
    'schema': 1,
    'modelVersion': playerSimulationVersion,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'playerId': playerId,
    'playerName': playerName,
    'scenario': scenario.toJson(),
    'games': games.map(playerGameJson).toList(),
    'cutoff': cutoff.toIso8601String().substring(0, 10),
    'source': source,
    'sourceRetrievedAt': sourceRetrievedAt,
    'sourceDigest': sourceDigest,
    'sourceUrl': sourceUrl,
    'license': license,
    'licenseUrl': licenseUrl,
    'book': book,
    'thesis': thesis,
    'targetDate': targetDate?.toIso8601String().substring(0, 10),
    'priceOrigin': 'manual_unverified',
  };
  factory PlayerInvestigation.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 1 ||
        j['modelVersion'] != playerSimulationVersion ||
        j['priceOrigin'] != 'manual_unverified') {
      throw const FormatException('Unsupported player investigation');
    }
    return PlayerInvestigation(
      savedAt: DateTime.parse(j['savedAt']).toUtc(),
      playerId: j['playerId'],
      playerName: j['playerName'],
      scenario: PlayerScenario.fromJson(j['scenario']),
      games: (j['games'] as List).map((g) => PlayerGame.fromJson(g)).toList(),
      cutoff: DateTime.parse('${j['cutoff']}T00:00:00Z'),
      source: j['source'],
      sourceRetrievedAt: j['sourceRetrievedAt'],
      sourceDigest: j['sourceDigest'] ?? '',
      sourceUrl: j['sourceUrl'] ?? '',
      license: j['license'] ?? '',
      licenseUrl: j['licenseUrl'] ?? '',
      book: j['book'],
      thesis: j['thesis'],
      targetDate: j['targetDate'] == null
          ? null
          : DateTime.parse('${j['targetDate']}T00:00:00Z'),
    );
  }
}

class PlayerInvestigationReview {
  const PlayerInvestigationReview({
    required this.id,
    required this.recordedAt,
    required this.source,
    required this.notes,
    this.actualYards,
    this.actualVolume,
    this.voided = false,
  });
  final String id, source, notes;
  final DateTime recordedAt;
  final double? actualYards, actualVolume;
  final bool voided;
  String outcome(PlayerScenario s) => voided
      ? 'Void'
      : (actualYards! - s.line).abs() < 1e-9
      ? 'Push'
      : ((actualYards! > s.line) == s.over)
      ? 'Win'
      : 'Loss';
  double? probabilityError(PlayerSimulation sim) {
    if (voided || !sim.available) return null;
    final result = outcome(sim.scenario);
    final probabilities = [
      sim.winProbability!,
      1 - sim.winProbability! - sim.pushProbability!,
      sim.pushProbability!,
    ];
    final actual = result == 'Win'
        ? 0
        : result == 'Loss'
        ? 1
        : 2;
    var sum = 0.0;
    for (var i = 0; i < 3; i++) {
      final d = probabilities[i] - (i == actual ? 1 : 0);
      sum += d * d;
    }
    return sum / 2;
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'source': source,
    'notes': notes,
    'actualYards': actualYards,
    'actualVolume': actualVolume,
    'voided': voided,
  };
  factory PlayerInvestigationReview.fromJson(Map<String, dynamic> j) {
    final r = PlayerInvestigationReview(
      id: j['id'],
      recordedAt: DateTime.parse(j['recordedAt']).toUtc(),
      source: j['source'],
      notes: j['notes'],
      actualYards: (j['actualYards'] as num?)?.toDouble(),
      actualVolume: (j['actualVolume'] as num?)?.toDouble(),
      voided: j['voided'],
    );
    if (j['schema'] != 1 ||
        r.id.isEmpty ||
        r.source.trim().isEmpty ||
        r.source.length > 300 ||
        r.notes.length > 2000 ||
        (!r.voided &&
            (r.actualYards == null ||
                !r.actualYards!.isFinite ||
                r.actualYards! < -100 ||
                r.actualYards! > 2000 ||
                r.actualYards! % 1 != 0)) ||
        (r.actualVolume != null &&
            (!r.actualVolume!.isFinite ||
                r.actualVolume! < 0 ||
                r.actualVolume! > 150 ||
                r.actualVolume! % 1 != 0))) {
      throw const FormatException('Invalid player review');
    }
    return r;
  }
}
