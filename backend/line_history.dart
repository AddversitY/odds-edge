import 'dart:convert';
import 'dart:io';

import 'package:odds_edge/domain/odds.dart';

/// Append-only journal of odds boards this server already fetched.
///
/// One JSON line per game per response. It does not call The Odds API.
/// The file lives under `backend/data/` and is rewritten when it gets old
/// or large, so a long-running process cannot fill the disk.
class LineHistory {
  LineHistory(
    this.file, {
    this.retain = const Duration(days: 45),
    this.maxPerEvent = 240,
    this.maxLines = 6000,
    this.maxBytes = 2 * 1024 * 1024,
    this.compactEvery = 32,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final File file;
  final Duration retain;
  final int maxPerEvent;
  final int maxLines;
  final int maxBytes;
  final int compactEvery;
  final DateTime Function() _clock;
  Future<void> _queue = Future<void>.value();
  int _writes = 0;
  Set<String>? _seen;

  /// [kind] is `lines` for the main moneyline, spread, and total board,
  /// or `props` for a player-prop board.
  Future<void> record(OddsBoard board, {required String kind}) {
    if (kind != 'lines' && kind != 'props') {
      throw ArgumentError('Line history kind must be lines or props.');
    }
    return _enqueue(() async {
      final lines = _encode(board, kind);
      if (lines.isEmpty) return;
      await _loadSeen();
      final fresh = <String>[];
      for (final line in lines) {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final key = '${decoded['kind']}|${decoded['id']}|${decoded['at']}';
        if (_seen!.add(key)) fresh.add(line);
      }
      if (fresh.isEmpty) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${fresh.join('\n')}\n',
        mode: FileMode.append,
        flush: true,
      );
      _writes++;
      final length = await file.length();
      if (length > maxBytes || _writes % compactEvery == 0) {
        await _compact();
      }
    });
  }

  /// Snapshots for one game, oldest first. A torn last line is skipped.
  Future<List<Map<String, dynamic>>> forEvent(String eventId) {
    return _enqueue(() async {
      final snapshots = <Map<String, dynamic>>[];
      await for (final raw in _decoded()) {
        if (raw['id'] != eventId) continue;
        final view = _view(raw);
        if (view != null) snapshots.add(view);
      }
      snapshots.sort(
        (a, b) => (a['at'] as String).compareTo(b['at'] as String),
      );
      if (snapshots.length > maxPerEvent) {
        return snapshots.sublist(snapshots.length - maxPerEvent);
      }
      return snapshots;
    });
  }

  /// Every main-line snapshot, one pass. Does not call The Odds API.
  Future<List<Map<String, dynamic>>> slate() {
    return _enqueue(() async {
      final grouped = <String, List<Map<String, dynamic>>>{};
      final names = <String, Map<String, String>>{};
      await for (final raw in _decoded()) {
        if (raw['kind'] != 'lines') continue;
        final view = _view(raw);
        if (view == null) continue;
        final id = '${raw['id']}';
        (grouped[id] ??= []).add(view);
        names[id] = {
          'away': '${raw['away'] ?? names[id]?['away'] ?? ''}',
          'home': '${raw['home'] ?? names[id]?['home'] ?? ''}',
          'startsAt': '${raw['kick'] ?? names[id]?['startsAt'] ?? ''}',
        };
      }
      final events = <Map<String, dynamic>>[];
      for (final entry in grouped.entries) {
        final shots = entry.value
          ..sort((a, b) => (a['at'] as String).compareTo(b['at'] as String));
        final name = names[entry.key] ?? const {};
        events.add({
          'id': entry.key,
          'away': name['away'] ?? '',
          'home': name['home'] ?? '',
          'startsAt': name['startsAt'] ?? '',
          'snapshots': shots,
        });
      }
      events.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
      return events;
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  List<String> _encode(OddsBoard board, String kind) {
    final events = {for (final event in board.events) event.id: event};
    final grouped = <String, List<OddsQuote>>{};
    for (final quote in board.quotes) {
      final id = quote.selection.eventId;
      if (id.isEmpty) continue;
      (grouped[id] ??= []).add(quote);
    }
    final at = board.fetchedAt.toUtc().toIso8601String();
    final lines = <String>[];
    for (final entry in grouped.entries) {
      final rows = <List<Object?>>[];
      final seen = <String>{};
      for (final quote in entry.value) {
        final point = quote.selection.point;
        final player = quote.selection.participant;
        final key =
            '${quote.selection.market}|${quote.selection.outcome}|$player|${point ?? ''}|${quote.bookId}|${quote.status}';
        if (!seen.add(key)) continue;
        final row = <Object?>[
          quote.selection.market,
          quote.selection.outcome,
          point,
          quote.bookId,
          (quote.decimal * 10000).round() / 10000,
          quote.status,
        ];
        if (player.isNotEmpty) row.add(player);
        rows.add(row);
      }
      if (rows.isEmpty) continue;
      final event = events[entry.key];
      lines.add(
        jsonEncode({
          'at': at,
          'kind': kind,
          'id': entry.key,
          if (event != null) 'away': event.away,
          if (event != null) 'home': event.home,
          if (event != null) 'kick': event.startsAt.toUtc().toIso8601String(),
          'rows': rows,
        }),
      );
    }
    return lines;
  }

  Future<void> _compact() async {
    final cutoff = _clock().toUtc().subtract(retain);
    final kept = <Map<String, dynamic>>[];
    await for (final raw in _decoded()) {
      final at = DateTime.tryParse('${raw['at']}')?.toUtc();
      if (at == null || at.isBefore(cutoff)) continue;
      kept.add(raw);
    }
    kept.sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    final byEvent = <String, List<Map<String, dynamic>>>{};
    for (final raw in kept) {
      (byEvent['${raw['id']}'] ??= []).add(raw);
    }
    final trimmed = <Map<String, dynamic>>[];
    for (final rows in byEvent.values) {
      final start = rows.length > maxPerEvent ? rows.length - maxPerEvent : 0;
      trimmed.addAll(rows.sublist(start));
    }
    trimmed.sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    var body = trimmed;
    if (body.length > maxLines) {
      body = body.sublist(body.length - maxLines);
    }
    var encoded = body.map(jsonEncode).join('\n');
    if (encoded.isNotEmpty) encoded = '$encoded\n';
    while (body.length > 1 && encoded.length > maxBytes) {
      body = body.sublist(1);
      encoded = '${body.map(jsonEncode).join('\n')}\n';
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encoded, flush: true);
    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
    _seen = null;
  }

  Future<void> _loadSeen() async {
    if (_seen != null) return;
    final seen = <String>{};
    await for (final raw in _decoded()) {
      seen.add('${raw['kind']}|${raw['id']}|${raw['at']}');
    }
    _seen = seen;
  }

  Stream<Map<String, dynamic>> _decoded() async* {
    if (!await file.exists()) return;
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map &&
            (decoded['kind'] == 'lines' || decoded['kind'] == 'props') &&
            decoded['id'] is String &&
            decoded['rows'] is List) {
          yield Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // A crash can leave a partial last line. Skip it.
      }
    }
  }

  Map<String, dynamic>? _view(Map<String, dynamic> raw) {
    final prices = <Map<String, dynamic>>[];
    for (final row in raw['rows'] as List) {
      if (row is! List || row.length < 6) continue;
      final decimal = row[4];
      if (decimal is! num) continue;
      final price = <String, dynamic>{
        'market': '${row[0]}',
        'outcome': '${row[1]}',
        'point': row[2],
        'bookId': '${row[3]}',
        'decimal': decimal.toDouble(),
        'status': '${row[5]}',
      };
      if (row.length > 6 && '${row[6]}'.isNotEmpty) {
        price['player'] = '${row[6]}';
      }
      prices.add(price);
    }
    if (prices.isEmpty) return null;
    return {
      'at': '${raw['at']}',
      'kind': '${raw['kind']}',
      'away': '${raw['away'] ?? ''}',
      'home': '${raw['home'] ?? ''}',
      'startsAt': '${raw['kick'] ?? ''}',
      'prices': prices,
    };
  }
}
