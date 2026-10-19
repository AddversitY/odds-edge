import 'dart:convert';
import 'dart:io';

import 'package:odds_edge/domain/odds.dart';

import 'providers.dart';

class SnapshotStore {
  SnapshotStore(this.file);
  final File file;
  Future<void> append(OddsBoard board) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(board.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<List<OddsQuote>> history(String selectionKey, {DateTime? at}) async {
    if (!await file.exists()) return [];
    final quotes = <OddsQuote>[];
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      try {
        final board = OddsBoard.fromJson(jsonDecode(line));
        for (final q in board.quotes) {
          if (q.selection.key == selectionKey &&
              (at == null ||
                  (!q.sourceAt.isAfter(at) && !q.collectedAt.isAfter(at)))) {
            quotes.add(q);
          }
        }
      } catch (_) {
        /* Ignore an incomplete final line after interrupted writes. */
      }
    }
    quotes.sort((a, b) => a.collectedAt.compareTo(b.collectedAt));
    return quotes.length > 2000 ? quotes.sublist(quotes.length - 2000) : quotes;
  }
}

class OddsService {
  OddsService(
    this.providers,
    this.store, {
    this.refreshInterval = const Duration(seconds: 60),
  }) {
    if (providers.isEmpty ||
        providers.map((p) => p.id).toSet().length != providers.length) {
      throw ArgumentError(
        'Provide at least one adapter with unique provider IDs.',
      );
    }
    if (providers.any((p) => p is DemoProvider) && providers.length > 1) {
      throw ArgumentError(
        'Demonstration data cannot be combined with provider feeds.',
      );
    }
  }
  final List<OddsProvider> providers;
  final SnapshotStore store;
  final Duration refreshInterval;
  final Map<String, OddsBoard> _cache = {};
  final Map<String, DateTime> _attempted = {};
  final Map<String, String> _failures = {};
  Future<OddsBoard>? _pending;

  Future<OddsBoard> getBoard() {
    // Coalesce concurrent client requests into one set of provider requests.
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<OddsBoard> _load() async {
    final now = DateTime.now().toUtc();
    var changed = false;
    for (final provider in providers) {
      final last = _attempted[provider.id];
      if (last != null && now.difference(last) < refreshInterval) continue;
      _attempted[provider.id] = now;
      try {
        _cache[provider.id] = await provider.fetch(now);
        _failures.remove(provider.id);
        changed = true;
      } catch (_) {
        _failures[provider.id] =
            '${provider.id} unavailable. Last successful timestamps retained; no replacement feed was invented.';
      }
    }
    final events = <String, NflEvent>{};
    final quotes = <OddsQuote>[];
    for (final board in _cache.values) {
      for (final event in board.events) {
        events[event.id] = event;
      }
      for (final q in board.quotes) {
        // During an outage retain the observation for inspection, exclude from best.
        quotes.add(
          _failures.containsKey(q.provider)
              ? OddsQuote(
                  selection: q.selection,
                  bookId: q.bookId,
                  book: q.book,
                  provider: q.provider,
                  decimal: q.decimal,
                  sourceAt: q.sourceAt,
                  collectedAt: q.collectedAt,
                  status: 'provider unavailable',
                  demo: q.demo,
                )
              : q,
        );
      }
    }
    final board = OddsBoard(
      events: events.values.toList(),
      quotes: deduplicateQuotes(quotes),
      fetchedAt: now,
      demo: providers.every((p) => p is DemoProvider),
      notices: [
        ..._failures.values,
        ..._cache.values.expand((b) => b.notices),
        'History contains snapshots collected by this installation, not a historical archive.',
      ],
    );
    if (changed) await store.append(board);
    return board;
  }
}
