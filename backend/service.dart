import 'dart:convert';
import 'dart:io';

import 'package:odds_edge/domain/odds.dart';

import 'providers.dart';
import 'quota.dart';

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

  Future<OddsBoard?> latest() async {
    if (!await file.exists()) return null;
    OddsBoard? last;
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      try {
        last = OddsBoard.fromJson(jsonDecode(line));
      } catch (_) {
        /* Ignore an incomplete final line after interrupted writes. */
      }
    }
    return last;
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

/// Free-tier polling policy. When this is omitted, [OddsService] keeps the
/// original fixed interval used by demonstration mode and existing tests.
class FreeTierPlan {
  const FreeTierPlan({
    required this.schedule,
    required this.ledger,
    required this.estimatedCost,
    this.cooldown = const Duration(minutes: 10),
    this.failureBackoff = const Duration(minutes: 5),
    this.eventsMaxAge = const Duration(hours: 6),
    this.fixedKickoffs,
    this.bookmakers = const [],
    this.markets = const [],
  });

  final OddsRefreshSchedule schedule;
  final CreditLedger ledger;
  final int estimatedCost;
  final Duration cooldown;
  final Duration failureBackoff;
  final Duration eventsMaxAge;

  /// When set, kickoffs are not loaded from the network.
  final List<DateTime>? fixedKickoffs;
  final List<String> bookmakers;
  final List<String> markets;
}

class OddsService {
  OddsService(
    this.providers,
    this.store, {
    this.refreshInterval = const Duration(seconds: 60),
    FreeTierPlan? freeTier,
    DateTime Function()? clock,
  }) : _freeTier = freeTier,
       _clock = clock ?? DateTime.now,
       _kickoffs = List<DateTime>.from(freeTier?.fixedKickoffs ?? const []),
       _kickoffsFixed = freeTier?.fixedKickoffs != null {
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
  final FreeTierPlan? _freeTier;
  final DateTime Function() _clock;
  final bool _kickoffsFixed;
  final Map<String, OddsBoard> _cache = {};
  final Map<String, DateTime> _attempted = {};
  final Map<String, String> _failures = {};
  final List<String> _transientNotices = [];
  List<DateTime> _kickoffs;
  DateTime? _kickoffsAt;
  DateTime? _eventsBackoffUntil;
  DateTime? _lastOddsSuccess;
  DateTime? _oddsBackoffUntil;
  Future<OddsBoard>? _pending;

  /// Reloads the last saved snapshot so a restart does not spend credits
  /// just to paint the screen. A due scheduled slot still refreshes later.
  Future<void> restore() async {
    if (_freeTier == null || providers.length != 1) return;
    final last = await store.latest();
    if (last == null) return;
    _cache[providers.first.id] = OddsBoard(
      events: last.events,
      quotes: last.quotes,
      fetchedAt: last.fetchedAt,
      demo: last.demo,
    );
    _lastOddsSuccess = last.fetchedAt.toUtc();
  }

  Future<void> maintain() async {
    try {
      await getBoard();
    } catch (_) {
      // Request handling reports provider failures on the board.
    }
  }

  Future<OddsBoard> getBoard({bool onDemand = false}) {
    // Coalesce concurrent client requests into one set of provider requests.
    return _pending ??= _load(onDemand: onDemand)
        .whenComplete(() => _pending = null);
  }

  Map<String, Object?> status() {
    final tier = _freeTier;
    final now = _now();
    final snapshot = _cache.isEmpty
        ? null
        : _snapshotTime(now).toUtc().toIso8601String();
    if (tier == null) {
      return {
        'refresh': 'interval',
        'refreshSeconds': refreshInterval.inSeconds,
        'snapshotAsOf': snapshot,
      };
    }
    final last = _lastOddsSuccess;
    final cooled = last == null || now.difference(last) >= tier.cooldown;
    return {
      'refresh': 'free-tier-schedule',
      'schedule': tier.schedule.describe(),
      'bookmakers': tier.bookmakers,
      'markets': tier.markets,
      'estimatedCreditsPerRefresh': tier.estimatedCost,
      'creditsRemaining': tier.ledger.remaining,
      'creditsUsed': tier.ledger.used,
      'creditsLastRequest': tier.ledger.lastCost,
      'creditsUpdatedAt': tier.ledger.updatedAt?.toUtc().toIso8601String(),
      'creditReserve': tier.ledger.reserve,
      'onDemandAllowed':
          cooled &&
          tier.ledger.allowSpend(cost: tier.estimatedCost, essential: false) &&
          !_backingOff(now),
      'onDemandCooldownSeconds': tier.cooldown.inSeconds,
      'snapshotAsOf': snapshot,
      'kickoffsTracked': _kickoffs.length,
    };
  }

  Future<OddsBoard> _load({required bool onDemand}) async {
    final now = _now();
    if (_freeTier == null) return _loadInterval(now);
    return _loadFreeTier(now, onDemand: onDemand);
  }

  DateTime _now() => (_freeTier == null ? DateTime.now() : _clock()).toUtc();

  Future<OddsBoard> _loadInterval(DateTime now) async {
    var changed = false;
    for (final provider in providers) {
      final last = _attempted[provider.id];
      if (last != null && now.difference(last) < refreshInterval) continue;
      _attempted[provider.id] = now;
      changed = await _fetchOne(provider, now) || changed;
    }
    final board = _assemble(now, fetchedAt: now);
    if (changed) await store.append(board);
    return board;
  }

  Future<OddsBoard> _loadFreeTier(
    DateTime now, {
    required bool onDemand,
  }) async {
    final tier = _freeTier!;
    _transientNotices.clear();
    await _refreshKickoffs(now);
    final due =
        tier.schedule.dueSlot(
          now: now,
          lastFetch: _lastOddsSuccess,
          kickoffs: _kickoffs,
        ) !=
        null;
    final backingOff = _backingOff(now);
    final wantsScheduled = _cache.isEmpty || due;
    var fetch = false;
    if (wantsScheduled && backingOff) {
      _transientNotices.add(
        'Waiting to retry a failed refresh. Showing the cached snapshot.',
      );
    } else if (wantsScheduled) {
      if (tier.ledger.allowSpend(cost: tier.estimatedCost, essential: true)) {
        fetch = true;
      } else {
        _transientNotices.add(
          'Not enough credits left to request a new snapshot. Showing the cached snapshot.',
        );
      }
    } else if (onDemand) {
      final last = _lastOddsSuccess;
      final cooled = last == null || now.difference(last) >= tier.cooldown;
      if (!cooled) {
        _transientNotices.add(
          'On-demand refresh is cooling down. Showing the cached snapshot.',
        );
      } else if (!tier.ledger.allowSpend(
        cost: tier.estimatedCost,
        essential: false,
      )) {
        _transientNotices.add(
          'Credit reserve reached. On-demand refresh was skipped. Showing the cached snapshot.',
        );
      } else {
        fetch = true;
      }
    }
    var changed = false;
    if (fetch) {
      for (final provider in providers) {
        changed = await _fetchOne(provider, now) || changed;
      }
      if (changed) {
        _lastOddsSuccess = now;
        _oddsBackoffUntil = null;
      } else {
        _oddsBackoffUntil = now.add(tier.failureBackoff);
      }
    }
    final board = _assemble(now, fetchedAt: _snapshotTime(now));
    if (changed) await store.append(board);
    return board;
  }

  bool _backingOff(DateTime now) =>
      _oddsBackoffUntil != null && now.isBefore(_oddsBackoffUntil!);

  Future<void> _refreshKickoffs(DateTime now) async {
    final tier = _freeTier;
    if (tier == null || _kickoffsFixed) return;
    if (_kickoffsAt != null &&
        now.difference(_kickoffsAt!) < tier.eventsMaxAge) {
      return;
    }
    if (_eventsBackoffUntil != null && now.isBefore(_eventsBackoffUntil!)) {
      return;
    }
    for (final provider in providers) {
      if (provider is! TheOddsApiProvider) continue;
      try {
        _kickoffs = await provider.fetchKickoffs(now);
        _kickoffsAt = now;
        _eventsBackoffUntil = null;
      } catch (_) {
        _eventsBackoffUntil = now.add(tier.failureBackoff);
      } finally {
        await _recordCredits(provider, now);
      }
    }
  }

  Future<bool> _fetchOne(OddsProvider provider, DateTime now) async {
    try {
      _cache[provider.id] = await provider.fetch(now);
      _failures.remove(provider.id);
      return true;
    } catch (_) {
      _failures[provider.id] =
          '${provider.id} unavailable. Last successful timestamps retained; no replacement feed was invented.';
      return false;
    } finally {
      await _recordCredits(provider, now);
    }
  }

  Future<void> _recordCredits(OddsProvider provider, DateTime now) async {
    final tier = _freeTier;
    if (tier == null || provider is! TheOddsApiProvider) return;
    final observation = provider.lastObservation;
    if (observation == null || !observation.hasAny) return;
    tier.ledger.apply(observation, at: now);
    await tier.ledger.save();
  }

  DateTime _snapshotTime(DateTime fallback) {
    DateTime? latest;
    for (final board in _cache.values) {
      if (latest == null || board.fetchedAt.isAfter(latest)) {
        latest = board.fetchedAt;
      }
    }
    return latest ?? fallback;
  }

  OddsBoard _assemble(DateTime now, {required DateTime fetchedAt}) {
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
    return OddsBoard(
      events: events.values.toList(),
      quotes: deduplicateQuotes(quotes),
      fetchedAt: fetchedAt,
      demo: providers.every((p) => p is DemoProvider),
      notices: [
        ..._failures.values,
        ..._transientNotices,
        ..._cache.values.expand((b) => b.notices),
        'History contains snapshots collected by this installation, not a historical archive.',
      ],
    );
  }
}
