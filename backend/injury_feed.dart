import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:odds_edge/domain/injury_report.dart';

/// One public page per source. The Odds API is never called.
const injuryUserAgent = 'OddsEdge/1.0 (personal research; cached injury check)';
const espnInjuriesUri =
    'https://site.api.espn.com/apis/site/v2/sports/football/nfl/injuries';
const nflInjuriesUri = 'https://www.nfl.com/injuries/';

const injurySourceHosts = {'site.api.espn.com', 'www.nfl.com', 'github.com'};

Uri nflverseInjuriesUri(int season) => Uri.parse(
  'https://github.com/nflverse/nflverse-data/releases/download/injuries/injuries_$season.csv',
);

class InjuryBytes {
  const InjuryBytes({required this.status, required this.body});

  final int status;
  final String body;
}

typedef InjuryTransport = Future<InjuryBytes> Function(Uri uri);

/// The default transport allows only the three public injury hosts.
/// Redirects stay inside the client, and the body is capped.
Future<InjuryBytes> fetchInjuryBytes(Uri uri) async {
  if (!injurySourceHosts.contains(uri.host)) {
    throw StateError('Injury checks do not call ${uri.host}.');
  }
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = true;
    request.maxRedirects = 3;
    request.headers.set(HttpHeaders.userAgentHeader, injuryUserAgent);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json,text/html,text/csv,text/plain',
    );
    final response = await request.close().timeout(const Duration(seconds: 20));
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      builder.add(chunk);
      if (builder.length > 16 * 1024 * 1024) {
        throw const HttpException('Injury response was larger than 16 MB.');
      }
    }
    return InjuryBytes(
      status: response.statusCode,
      body: utf8.decode(builder.takeBytes(), allowMalformed: true),
    );
  } finally {
    client.close(force: true);
  }
}

class _SavedSource {
  _SavedSource({this.fetchedAt, this.entries = const []});
  DateTime? fetchedAt;
  List<InjuryEntry> entries;
}

/// Polls ESPN, then NFL.com and nflverse, and keeps the result on disk.
/// A fresh cache is not downloaded again. A failure keeps the last good copy.
class InjuryFeed {
  InjuryFeed({
    InjuryTransport? transport,
    this.cacheFile,
    DateTime Function()? clock,
  }) : _transport = transport ?? fetchInjuryBytes,
       _clock = clock ?? DateTime.now;

  final InjuryTransport _transport;
  final File? cacheFile;
  final DateTime Function() _clock;
  Future<void>? _inflight;
  bool _loaded = false;
  _SavedSource _espn = _SavedSource();
  _SavedSource _nfl = _SavedSource();
  _SavedSource _nflverse = _SavedSource();
  List<InjuryEntry> previous = const [];
  InjuryReport? report;

  Future<InjuryReport> current({
    List<DateTime> kickoffs = const [],
    bool wait = false,
  }) async {
    await _load();
    if (wait) {
      await refresh(kickoffs: kickoffs);
    } else {
      final due = _anyDue(kickoffs);
      if (due) {
        // The caller gets the saved copy now. The download continues.
        unawaited(refresh(kickoffs: kickoffs));
      }
    }
    return report ??
        _empty(_clock().toUtc(), 'The injury check has not finished.');
  }

  Future<void> refresh({List<DateTime> kickoffs = const []}) {
    final existing = _inflight;
    if (existing != null) return existing;
    final run = _refresh(kickoffs);
    _inflight = run;
    return run.whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
  }

  bool _anyDue(List<DateTime> kickoffs) {
    final now = _clock().toUtc();
    final fast = injuryPollInterval(now: now, kickoffs: kickoffs);
    return _due(_espn.fetchedAt, now, fast) ||
        _due(_nfl.fetchedAt, now, nflConfirmationInterval(fast)) ||
        _due(_nflverse.fetchedAt, now, nflverseRefreshInterval);
  }

  Future<void> _refresh(List<DateTime> kickoffs) async {
    await _load();
    final now = _clock().toUtc();
    final fast = injuryPollInterval(now: now, kickoffs: kickoffs);
    final notes = <SourceNote>[];
    if (_due(_espn.fetchedAt, now, fast)) {
      notes.add(await _pullEspn(now));
    } else {
      notes.add(_kept('espn', 'ESPN, unofficial', _espn));
    }
    if (_due(_nfl.fetchedAt, now, nflConfirmationInterval(fast))) {
      notes.add(await _pullNfl(now));
    } else {
      notes.add(_kept('nfl', 'NFL.com', _nfl));
    }
    final backupDue = _due(_nflverse.fetchedAt, now, nflverseRefreshInterval);
    final needBackup = _espn.entries.isEmpty && _nfl.entries.isEmpty;
    if (backupDue || (needBackup && _nflverse.entries.isEmpty)) {
      notes.add(await _pullNflverse(now));
    } else {
      notes.add(_kept('nflverse', 'nflverse', _nflverse));
    }
    final hadNew = notes.any((note) => note.ok && note.fetchedAt == now);
    final next = assembleInjuryReport(
      now: now,
      live: true,
      espn: _espn.entries,
      nfl: _nfl.entries,
      nflverse: _nflverse.entries,
      previous: previous,
      sources: notes,
    );
    if (!hadNew && report != null) return;
    if (next.entries.isNotEmpty) {
      if (hadNew) previous = next.entries;
      report = next;
    } else if (report == null) {
      report = next;
    } else {
      return;
    }
    await _save();
  }

  bool _due(DateTime? fetchedAt, DateTime now, Duration interval) {
    if (fetchedAt == null) return true;
    final age = now.difference(fetchedAt.toUtc());
    if (age.isNegative) return true;
    return age >= interval;
  }

  SourceNote _kept(String id, String label, _SavedSource saved) => SourceNote(
    id: id,
    label: label,
    ok: saved.entries.isNotEmpty,
    fetchedAt: saved.fetchedAt,
    problem: saved.entries.isEmpty ? '$label has no saved rows.' : null,
  );

  Future<SourceNote> _pullEspn(DateTime now) async {
    try {
      final bytes = await _transport(Uri.parse(espnInjuriesUri));
      if (bytes.status != 200) {
        return _failed(
          'espn',
          'ESPN, unofficial',
          'ESPN answered ${bytes.status}. The last saved list is kept.',
        );
      }
      final decoded = jsonDecode(bytes.body);
      final entries = parseEspnInjuries(decoded, fetchedAt: now);
      if (entries.isEmpty) {
        return _failed(
          'espn',
          'ESPN, unofficial',
          'ESPN returned no Out, Doubtful, or Questionable players. The last saved list is kept.',
        );
      }
      _espn = _SavedSource(fetchedAt: now, entries: entries);
      return SourceNote(
        id: 'espn',
        label: 'ESPN, unofficial',
        ok: true,
        fetchedAt: now,
      );
    } catch (_) {
      return _failed(
        'espn',
        'ESPN, unofficial',
        'ESPN could not be read. The last saved list is kept.',
      );
    }
  }

  Future<SourceNote> _pullNfl(DateTime now) async {
    try {
      final bytes = await _transport(Uri.parse(nflInjuriesUri));
      if (bytes.status != 200) {
        return _failed(
          'nfl',
          'NFL.com',
          'NFL.com answered ${bytes.status}. The last saved list is kept.',
        );
      }
      final entries = parseNflInjuryPage(bytes.body, fetchedAt: now);
      if (entries.isEmpty) {
        return _failed(
          'nfl',
          'NFL.com',
          'The NFL.com report had no game statuses to read. The last saved list is kept.',
        );
      }
      _nfl = _SavedSource(fetchedAt: now, entries: entries);
      return SourceNote(id: 'nfl', label: 'NFL.com', ok: true, fetchedAt: now);
    } catch (_) {
      return _failed(
        'nfl',
        'NFL.com',
        'NFL.com could not be read. The last saved list is kept.',
      );
    }
  }

  Future<SourceNote> _pullNflverse(DateTime now) async {
    final year = nflSeasonYear(now);
    final first = await _verseYear(year, now);
    if (first != null) return first;
    final earlier = await _verseYear(year - 1, now);
    if (earlier != null) return earlier;
    return _failed(
      'nflverse',
      'nflverse',
      'The nflverse injury file could not be read. The last saved list is kept.',
    );
  }

  Future<SourceNote?> _verseYear(int year, DateTime now) async {
    try {
      final bytes = await _transport(nflverseInjuriesUri(year));
      if (bytes.status != 200) return null;
      final entries = parseNflverseInjuries(
        bytes.body,
        fetchedAt: now,
        season: year,
      );
      if (entries.isEmpty) return null;
      _nflverse = _SavedSource(fetchedAt: now, entries: entries);
      return const SourceNote(
        id: 'nflverse',
        label: 'nflverse',
        ok: true,
      ).copyFetched(now);
    } catch (_) {
      return null;
    }
  }

  SourceNote _failed(String id, String label, String problem) {
    final saved = switch (id) {
      'espn' => _espn,
      'nfl' => _nfl,
      _ => _nflverse,
    };
    return SourceNote(
      id: id,
      label: label,
      ok: false,
      fetchedAt: saved.fetchedAt,
      problem: problem,
    );
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final file = cacheFile;
    if (file == null || !file.existsSync()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      _espn = _readSource(map['espn']);
      _nfl = _readSource(map['nfl']);
      _nflverse = _readSource(map['nflverse']);
      previous = _readEntries(map['previous']);
      final saved = map['report'];
      if (saved is Map) {
        report = InjuryReport.fromJson(Map<String, dynamic>.from(saved));
      }
    } catch (_) {
      // A broken cache is ignored. The next check replaces it.
    }
  }

  Future<void> _save() async {
    final file = cacheFile;
    if (file == null) return;
    final payload = {
      'espn': _writeSource(_espn),
      'nfl': _writeSource(_nfl),
      'nflverse': _writeSource(_nflverse),
      'previous': [for (final entry in previous) entry.toJson()],
      'report': report?.toJson(),
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload));
  }
}

_SavedSource _readSource(Object? raw) {
  if (raw is! Map) return _SavedSource();
  return _SavedSource(
    fetchedAt: DateTime.tryParse('${raw['fetchedAt'] ?? ''}')?.toUtc(),
    entries: _readEntries(raw['entries']),
  );
}

List<InjuryEntry> _readEntries(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) InjuryEntry.fromJson(Map<String, dynamic>.from(item)),
  ];
}

Map<String, Object?> _writeSource(_SavedSource source) => {
  'fetchedAt': source.fetchedAt?.toUtc().toIso8601String(),
  'entries': [for (final entry in source.entries) entry.toJson()],
};

InjuryReport _empty(DateTime now, String notice) => InjuryReport(
  fetchedAt: now,
  live: true,
  entries: const [],
  changes: const [],
  sources: const [],
  notice: notice,
);

extension on SourceNote {
  SourceNote copyFetched(DateTime at) =>
      SourceNote(id: id, label: label, ok: ok, fetchedAt: at, problem: problem);
}
