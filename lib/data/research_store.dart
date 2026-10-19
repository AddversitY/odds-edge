import 'dart:convert';
import 'dart:io';

import '../domain/research.dart';
import '../domain/autopsy.dart';

class ResearchStore {
  ResearchStore({this.directory});
  final Directory? directory;
  final List<String> warnings = [];
  Future<void> _writes = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<File> _file() async {
    final root = directory ?? _supportDirectory();
    final folder = Directory('${root.path}${Platform.pathSeparator}odds_edge');
    await folder.create(recursive: true);
    return File('${folder.path}${Platform.pathSeparator}research.jsonl');
  }

  Directory _supportDirectory() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['LOCALAPPDATA'];
      if (appData != null && appData.isNotEmpty) return Directory(appData);
    } else if (Platform.isIOS || Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/Library/Application Support');
      }
    }
    // No working-directory fallback: never pretend an ephemeral location is persistent.
    throw StateError('Application support directory unavailable');
  }

  Future<List<SavedResearch>> load() async {
    await _writes;
    warnings.clear();
    final file = await _file();
    if (!await file.exists()) return [];
    final results = <SavedResearch>[];
    var number = 0;
    for (final line in const LineSplitter().convert(
      utf8.decode(await file.readAsBytes(), allowMalformed: true),
    )) {
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
    final file = await _file();
    // A leading newline isolates an incomplete tail left by a power loss.
    await file.writeAsString(
      '\n${jsonEncode(research.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  });

  Future<File> _aux(String name) async =>
      File('${(await _file()).parent.path}${Platform.pathSeparator}$name');

  Future<void> saveDraft(SavedResearch record) =>
      _appendState('drafts.jsonl', record.toJson());
  Future<SavedResearch?> loadDraft({String? selectionKey}) async {
    await _writes;
    final file = await _aux('drafts.jsonl');
    if (!await file.exists()) return null;
    for (final line in (await file.readAsLines()).reversed) {
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
    final file = await _aux('reviews.jsonl');
    final result = <String, ResearchReview>{};
    if (!await file.exists()) return result;
    for (final line in const LineSplitter().convert(
      utf8.decode(await file.readAsBytes(), allowMalformed: true),
    )) {
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

  Future<void> _appendState(String name, Map<String, dynamic> value) =>
      _serial(() async {
        await (await _aux(name)).writeAsString(
          '\n${jsonEncode(value)}\n',
          mode: FileMode.append,
          flush: true,
        );
      });
  Future<Map<String, dynamic>?> _lastState(String name) async {
    await _writes;
    final file = await _aux(name);
    if (!await file.exists()) return null;
    for (final line in (await file.readAsLines()).reversed) {
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

  Future<String> backup() => _serial(() async {
    final source = await _file();
    final target = await _aux(
      'research-backup-${DateTime.now().microsecondsSinceEpoch}.jsonl',
    );
    await target.writeAsBytes(
      await source.exists() ? await source.readAsBytes() : <int>[],
      flush: true,
    );
    final reviews = await _aux('reviews.jsonl');
    if (await reviews.exists()) await reviews.copy('${target.path}.reviews');
    return target.path;
  });
  Future<String> exportJson() async => jsonEncode({
    'format': 'odds-edge-research-v2',
    'records': (await load()).map((r) => r.toJson()).toList(),
    'reviews': (await loadReviews()).values.map((r) => r.toJson()).toList(),
  });
  Future<int> importJson(String text) async {
    if (text.length > 10000000) throw const FormatException('Backup too large');
    final j = jsonDecode(text);
    if (j['format'] != 'odds-edge-research-v2') {
      throw const FormatException('Unknown backup format');
    }
    // Validate everything before writing anything.
    final records = (j['records'] as List)
        .map((r) => SavedResearch.fromJson(r))
        .toList();
    final existing = (await load()).map((r) => jsonEncode(r.toJson())).toSet();
    final reviews = (j['reviews'] as List? ?? [])
        .map((r) => ResearchReview.fromJson(r))
        .toList();
    final existingReviews = await loadReviews();
    await backup();
    var count = 0;
    for (final record in records.reversed) {
      if (existing.add(jsonEncode(record.toJson()))) {
        await save(record);
        count++;
      }
    }
    final validKeys = (await load()).map(researchId).toSet();
    for (final review in reviews) {
      // Import never overwrites a local outcome assessment.
      if (validKeys.contains(review.researchKey) &&
          !existingReviews.containsKey(review.researchKey)) {
        await saveReview(review);
        existingReviews[review.researchKey] = review;
      }
    }
    return count;
  }
}
