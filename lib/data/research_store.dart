import 'dart:convert';

import '../domain/research.dart';
import '../domain/autopsy.dart';
import '../domain/player_investigation.dart';
import '../domain/bets.dart';
import '../domain/saved_play.dart';
import 'journal_stub.dart'
    if (dart.library.io) 'journal_io.dart'
    if (dart.library.html) 'journal_web.dart'
    if (dart.library.js_interop) 'journal_web.dart';
import 'text_journal.dart';

class ResearchStore {
  ResearchStore({Object? directory, TextJournal? journal})
    : _journal = journal ?? createJournal(directory);
  final TextJournal _journal;
  final List<String> warnings = [];
  Future<void> _writes = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  List<String> _lines(List<int>? bytes) {
    if (bytes == null) return const [];
    return const LineSplitter().convert(
      utf8.decode(bytes, allowMalformed: true),
    );
  }

  Future<List<SavedResearch>> load() async {
    await _writes;
    warnings.clear();
    final results = <SavedResearch>[];
    var number = 0;
    for (final line in _lines(await _journal.readBytes('research.jsonl'))) {
      number++;
      if (line.trim().isEmpty) continue;
      try {
        results.add(SavedResearch.fromJson(jsonDecode(line)));
      } catch (_) {
        warnings.add(
          'Record $number could not be read. Its original bytes remain in the file and backup.',
        );
      }
    }
    return results.reversed.toList();
  }

  Future<void> save(SavedResearch research) => _serial(() async {
    await _journal.append('research.jsonl', '\n${jsonEncode(research.toJson())}\n');
  });

  Future<void> saveDraft(SavedResearch record) =>
      _appendState('drafts.jsonl', record.toJson());
  Future<SavedResearch?> loadDraft({String? selectionKey}) async {
    await _writes;
    for (final line in _lines(await _journal.readBytes('drafts.jsonl')).reversed) {
      if (line.trim().isEmpty) continue;
      try {
        final record = SavedResearch.fromJson(jsonDecode(line));
        if (selectionKey == null || record.context.identity == selectionKey) {
          return record;
        }
      } catch (_) {
        warnings.add(
          'An unreadable draft was preserved; recovering an earlier draft.',
        );
      }
    }
    return null;
  }

  Future<void> saveBooks(Set<String>? books) =>
      _appendState('preferences.jsonl', {'books': books?.toList()});
  Future<void> saveReview(ResearchReview review) =>
      _appendState('reviews.jsonl', review.toJson());
  Future<Map<String, ResearchReview>> loadReviews() async {
    await _writes;
    final result = <String, ResearchReview>{};
    for (final line in _lines(await _journal.readBytes('reviews.jsonl'))) {
      if (line.trim().isEmpty) continue;
      try {
        final r = ResearchReview.fromJson(jsonDecode(line));
        result[r.researchKey] = r;
      } catch (_) {
        warnings.add(
          'An unreadable outcome review was preserved. Other reviews remain available.',
        );
      }
    }
    return result;
  }

  Future<Set<String>?> loadBooks() async {
    final j = await _lastState('preferences.jsonl');
    return (j?['books'] as List?)?.cast<String>().toSet();
  }

  Future<void> saveInvestigation(PlayerInvestigation record) =>
      _appendState('player-investigations.jsonl', record.toJson());
  Future<void> saveInvestigationReview(PlayerInvestigationReview review) =>
      _appendState(
        'player-investigation-reviews.jsonl',
        PlayerInvestigationReview.fromJson(review.toJson()).toJson(),
      );
  Future<List<T>> _readJournal<T>(
    String name,
    T Function(Map<String, dynamic>) decode,
  ) async {
    await _writes;
    final records = <T>[];
    for (final line in _lines(await _journal.readBytes(name))) {
      if (line.trim().isEmpty) continue;
      try {
        records.add(decode(Map<String, dynamic>.from(jsonDecode(line))));
      } catch (_) {
        warnings.add(
          'An unreadable $name entry was preserved; readable entries remain available.',
        );
      }
    }
    return records;
  }

  Future<List<PlayerInvestigation>> loadInvestigations() async =>
      (await _readJournal(
        'player-investigations.jsonl',
        PlayerInvestigation.fromJson,
      )).reversed.toList();
  Future<Map<String, PlayerInvestigationReview>>
  loadInvestigationReviews() async => {
    for (final r in await _readJournal(
      'player-investigation-reviews.jsonl',
      PlayerInvestigationReview.fromJson,
    ))
      r.id: r,
  };

  Future<void> saveBet(TrackedBet bet) =>
      _appendState('bets.jsonl', bet.toJson());

  /// Latest write wins for each bet id. Older result updates stay in the file.
  Future<List<TrackedBet>> loadBets() async {
    final latest = <String, TrackedBet>{};
    for (final bet in await _readJournal('bets.jsonl', TrackedBet.fromJson)) {
      latest[bet.id] = bet;
    }
    final values = latest.values.toList()
      ..sort((a, b) => b.placedAt.compareTo(a.placedAt));
    return values;
  }

  Future<void> saveSavedPlay(SavedPlay play) =>
      _appendState('saved-plays.jsonl', play.toJson());

  /// Latest write wins. A later write with removed=true drops the play.
  Future<List<SavedPlay>> loadSavedPlays() async {
    final latest = <String, SavedPlay>{};
    for (final play in await _readJournal(
      'saved-plays.jsonl',
      SavedPlay.fromJson,
    )) {
      latest[play.id] = play;
    }
    final values = [
      for (final play in latest.values)
        if (!play.removed) play,
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return values;
  }

  Future<void> _appendState(String name, Map<String, dynamic> value) =>
      _serial(() async {
        await _journal.append(name, '\n${jsonEncode(value)}\n');
      });
  Future<Map<String, dynamic>?> _lastState(String name) async {
    await _writes;
    final bytes = await _journal.readBytes(name);
    if (bytes == null) return null;
    for (final line in _lines(bytes).reversed) {
      if (line.trim().isEmpty) continue;
      try {
        return Map<String, dynamic>.from(jsonDecode(line));
      } catch (_) {
        warnings.add(
          'An interrupted $name entry was skipped; trying the previous entry.',
        );
      }
    }
    throw const FormatException('No recoverable entries');
  }

  Future<String> backup() => _serial(
    () => _journal.makeBackup(
      researchName: 'research.jsonl',
      copies: const [
        'reviews.jsonl',
        'player-investigations.jsonl',
        'player-investigation-reviews.jsonl',
        'bets.jsonl',
        'saved-plays.jsonl',
      ],
    ),
  );
  Future<String> exportJson() async => jsonEncode({
    'format': 'odds-edge-research-v2',
    'records': (await load()).map((r) => r.toJson()).toList(),
    'reviews': (await loadReviews()).values.map((r) => r.toJson()).toList(),
    'investigations': (await loadInvestigations())
        .map((r) => r.toJson())
        .toList(),
    'investigationReviews': (await loadInvestigationReviews()).values
        .map((r) => r.toJson())
        .toList(),
    'bets': (await loadBets()).map((bet) => bet.toJson()).toList(),
    'savedPlays': (await loadSavedPlays()).map((play) => play.toJson()).toList(),
  });
  Future<int> importJson(String text) async {
    if (text.length > 10000000) throw const FormatException('Backup too large');
    final j = jsonDecode(text);
    if (j['format'] != 'odds-edge-research-v2') {
      throw const FormatException('Unknown backup format');
    }
    final records = (j['records'] as List)
        .map((r) => SavedResearch.fromJson(r))
        .toList();
    final existing = (await load()).map((r) => jsonEncode(r.toJson())).toSet();
    final reviews = (j['reviews'] as List? ?? [])
        .map((r) => ResearchReview.fromJson(r))
        .toList();
    final existingReviews = await loadReviews();
    final investigations = (j['investigations'] as List? ?? [])
        .map((r) => PlayerInvestigation.fromJson(r))
        .toList();
    final investigationReviews = (j['investigationReviews'] as List? ?? [])
        .map((r) => PlayerInvestigationReview.fromJson(r))
        .toList();
    final knownInvestigations = {
      for (final r in await loadInvestigations()) r.id: jsonEncode(r.toJson()),
    };
    final incomingIdentities = Map.of(knownInvestigations);
    for (final r in investigations) {
      if (incomingIdentities.containsKey(r.id) &&
          incomingIdentities[r.id] != jsonEncode(r.toJson())) {
        throw const FormatException('Conflicting investigation identity');
      }
      incomingIdentities[r.id] = jsonEncode(r.toJson());
    }
    final knownInvestigationReviews = await loadInvestigationReviews();
    final incomingBets = (j['bets'] as List? ?? [])
        .map((bet) => TrackedBet.fromJson(Map<String, dynamic>.from(bet)))
        .toList();
    final existingBets = {
      for (final bet in await loadBets()) bet.id: jsonEncode(bet.toJson()),
    };
    for (final bet in incomingBets) {
      final encoded = jsonEncode(bet.toJson());
      if (existingBets.containsKey(bet.id) && existingBets[bet.id] != encoded) {
        throw const FormatException('Conflicting bet identity');
      }
    }
    final incomingPlays = (j['savedPlays'] as List? ?? [])
        .map((play) => SavedPlay.fromJson(Map<String, dynamic>.from(play)))
        .toList();
    final existingPlays = {
      for (final play in await _readJournal(
        'saved-plays.jsonl',
        SavedPlay.fromJson,
      ))
        play.id: jsonEncode(play.toJson()),
    };
    for (final play in incomingPlays) {
      final encoded = jsonEncode(play.toJson());
      if (existingPlays.containsKey(play.id) &&
          existingPlays[play.id] != encoded) {
        throw const FormatException('Conflicting saved play');
      }
    }
    await backup();
    var count = 0;
    for (final record in records.reversed) {
      if (existing.add(jsonEncode(record.toJson()))) {
        await save(record);
        count++;
      }
    }
    final validKeys = (await load()).map(researchId).toSet();
    for (final r in investigations.reversed) {
      if (!knownInvestigations.containsKey(r.id)) {
        await saveInvestigation(r);
        knownInvestigations[r.id] = jsonEncode(r.toJson());
        count++;
      }
    }
    for (final r in investigationReviews) {
      if (knownInvestigations.containsKey(r.id) &&
          !knownInvestigationReviews.containsKey(r.id)) {
        await saveInvestigationReview(r);
        knownInvestigationReviews[r.id] = r;
      }
    }
    for (final bet in incomingBets) {
      if (!existingBets.containsKey(bet.id)) {
        await saveBet(bet);
        existingBets[bet.id] = jsonEncode(bet.toJson());
        count++;
      }
    }
    for (final play in incomingPlays) {
      if (!existingPlays.containsKey(play.id)) {
        await saveSavedPlay(play);
        existingPlays[play.id] = jsonEncode(play.toJson());
        count++;
      }
    }
    for (final review in reviews) {
      if (validKeys.contains(review.researchKey) &&
          !existingReviews.containsKey(review.researchKey)) {
        await saveReview(review);
        existingReviews[review.researchKey] = review;
      }
    }
    return count;
  }
}
