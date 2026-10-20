import 'dart:convert';
import 'dart:io';

import 'package:odds_edge/domain/odds.dart';

import 'providers.dart';
import 'quota.dart';

const collectedHistoryNotice =
    'History contains snapshots collected by this installation, not a historical archive.';

/// Journal path for one provider, so demonstration snapshots cannot be
/// restored as a live board.
String snapshotJournalPath(String providerId) {
  final safe = providerId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]+'), '');
  if (safe.isEmpty) {
    throw ArgumentError('Provider id cannot be used as a snapshot file name.');
  }
  return 'backend/data/snapshots-$safe.jsonl';
}

/// A saved board may be shown for [provider] only when its demo flag and
/// quote identities agree. Anything else must trigger a fresh fetch.
bool snapshotMatchesProvider(OddsBoard board, OddsProvider provider) {
  final demoProvider = provider is DemoProvider;
  if (board.demo != demoProvider) return false;
  for (final quote in board.quotes) {
    if (quote.demo != demoProvider || quote.provider != provider.id) {
      return false;
    }
  }
  return true;
}

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
    this.maxSlotAttempts = 2,
    this.dailyOnDemandCap = 6,
    this.billingResetDay = 1,
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

  /// Failed tries for one planned snapshot before that slot is left alone.
  final int maxSlotAttempts;

  /// Manual refreshes allowed per UTC day. Zero means no daily cap.
  final int dailyOnDemandCap;

  /// UTC day of the month when the credit allowance renews.
  final int billingResetDay;
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
  DateTime? _openSlot;
  int _slotAttempts = 0;
  int _startupAttempts = 0;
  int _onDemandToday = 0;
  DateTime? _onDemandDay;
  Future<OddsBoard>? _pending;

  /// Reloads the last saved snapshot so a restart does not spend credits
  /// just to paint the screen. A due scheduled slot still refreshes later.
  /// A demonstration snapshot, or one from another provider, is ignored so
  /// the next request fetches a live board.
  Future<void> restore() async {
    if (_freeTier == null || providers.length != 1) return;
    final provider = providers.first;
    final last = await store.latest();
    if (last == null || !snapshotMatchesProvider(last, provider)) return;
    _cache[provider.id] = OddsBoard(
      events: last.events,
      quotes: last.quotes,
      fetchedAt: last.fetchedAt,
      demo: last.demo,
      notices: [
        for (final notice in last.notices)
          if (notice != collectedHistoryNotice) notice,
      ],
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
    final hold = _creditHold(now);
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
      'creditReserve': hold.credits,
      'creditReserveBuffer': tier.ledger.reserve,
      'scheduledRefreshesRemaining': hold.slots,
      'onDemandAllowed':
          cooled &&
          !_dailyCapReached(now) &&
          tier.ledger.allowSpend(
            cost: tier.estimatedCost,
            essential: false,
            protect: hold.credits,
          ) &&
          !_backingOff(now),
      'onDemandCooldownSeconds': tier.cooldown.inSeconds,
      'onDemandDailyCap': tier.dailyOnDemandCap,
      'onDemandUsedToday': _onDemandCount(now),
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
    final slot = tier.schedule.dueSlot(
      now: now,
      lastFetch: _lastOddsSuccess,
      kickoffs: _kickoffs,
    );
    if (slot != _openSlot) {
      _openSlot = slot;
      _slotAttempts = 0;
    }
    final slotBudgetLeft = slot != null && _slotAttempts < tier.maxSlotAttempts;
    final startupBudgetLeft =
        _cache.isEmpty &&
        slot == null &&
        _startupAttempts < tier.maxSlotAttempts;
    final wantsSnapshot = slotBudgetLeft || startupBudgetLeft;
    final backingOff = _backingOff(now);
    var fetch = false;
    var onDemandFetch = false;
    if (wantsSnapshot && backingOff) {
      _transientNotices.add(
        'Waiting to retry a failed refresh. Showing the cached snapshot.',
      );
    } else if (wantsSnapshot) {
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
      final hold = _creditHold(now);
      if (_dailyCapReached(now)) {
        _transientNotices.add(
          'Daily refresh limit reached. Showing the cached snapshot.',
        );
      } else if (!cooled) {
        _transientNotices.add(
          'On-demand refresh is cooling down. Showing the cached snapshot.',
        );
      } else if (backingOff) {
        _transientNotices.add(
          'Waiting to retry a failed refresh. Showing the cached snapshot.',
        );
      } else if (!tier.ledger.allowSpend(
        cost: tier.estimatedCost,
        essential: false,
        protect: hold.credits,
      )) {
        _transientNotices.add(
          'Credit reserve reached. On-demand refresh was skipped. Showing the cached snapshot.',
        );
      } else {
        fetch = true;
        onDemandFetch = true;
      }
    }
    var changed = false;
    if (fetch) {
      if (onDemandFetch) _noteOnDemand(now);
      var charged = false;
      for (final provider in providers) {
        changed = await _fetchOne(provider, now) || changed;
        if (_wasCharged(provider)) charged = true;
      }
      if (changed) {
        _lastOddsSuccess = now;
        _oddsBackoffUntil = null;
        _slotAttempts = 0;
        _startupAttempts = 0;
      } else if (onDemandFetch) {
        _oddsBackoffUntil = now.add(tier.failureBackoff);
      } else {
        _closeFailedAttempt(
          tier,
          now,
          slot: slotBudgetLeft ? slot : null,
          startup: startupBudgetLeft,
          charged: charged,
        );
      }
    }
    final board = _assemble(now, fetchedAt: _snapshotTime(now));
    if (changed) await store.append(board);
    return board;
  }

  void _closeFailedAttempt(
    FreeTierPlan tier,
    DateTime now, {
    required DateTime? slot,
    required bool startup,
    required bool charged,
  }) {
    if (slot != null) _slotAttempts++;
    if (startup) _startupAttempts++;
    final exhausted = slot != null
        ? _slotAttempts >= tier.maxSlotAttempts
        : _startupAttempts >= tier.maxSlotAttempts;
    // A billed call is finished even when the body cannot be parsed.
    if (charged || exhausted) {
      if (slot != null) {
        if (_lastOddsSuccess == null || _lastOddsSuccess!.isBefore(slot)) {
          _lastOddsSuccess = slot;
        }
        _slotAttempts = tier.maxSlotAttempts;
      }
      if (startup || _cache.isEmpty) _startupAttempts = tier.maxSlotAttempts;
      _oddsBackoffUntil = null;
      return;
    }
    _oddsBackoffUntil = now.add(tier.failureBackoff);
  }

  bool _wasCharged(OddsProvider provider) {
    if (provider is! TheOddsApiProvider) return false;
    final cost = provider.lastObservation?.lastCost;
    return cost != null && cost > 0;
  }

  ({int slots, int credits}) _creditHold(DateTime now) {
    final tier = _freeTier!;
    final end = billingPeriodEnd(now, resetDay: tier.billingResetDay);
    final upcoming = tier.schedule.slots(
      from: now,
      until: end,
      kickoffs: _kickoffs,
    );
    final due = tier.schedule.dueSlot(
      now: now,
      lastFetch: _lastOddsSuccess,
      kickoffs: _kickoffs,
    );
    final slots = <DateTime>{...upcoming};
    if (due != null && due.isBefore(end)) slots.add(due);
    final last = _lastOddsSuccess;
    final remaining = slots
        .where((slot) => last == null || last.isBefore(slot))
        .length;
    return (
      slots: remaining,
      credits: scheduledCreditHold(
        scheduledRefreshes: remaining,
        cost: tier.estimatedCost,
        buffer: tier.ledger.reserve,
      ),
    );
  }

  int _onDemandCount(DateTime now) {
    final day = DateTime.utc(now.year, now.month, now.day);
    if (_onDemandDay != day) return 0;
    return _onDemandToday;
  }

  void _noteOnDemand(DateTime now) {
    final day = DateTime.utc(now.year, now.month, now.day);
    if (_onDemandDay != day) {
      _onDemandDay = day;
      _onDemandToday = 0;
    }
    _onDemandToday++;
  }

  bool _dailyCapReached(DateTime now) {
    final cap = _freeTier?.dailyOnDemandCap ?? 0;
    if (cap <= 0) return false;
    return _onDemandCount(now) >= cap;
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
        await _recordCredits(provider, now, oddsCall: false);
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
      await _recordCredits(provider, now, oddsCall: true);
    }
  }

  Future<void> _recordCredits(
    OddsProvider provider,
    DateTime now, {
    required bool oddsCall,
  }) async {
    final tier = _freeTier;
    if (tier == null || provider is! TheOddsApiProvider) return;
    final observation = provider.lastObservation;
    if (observation == null || !observation.hasAny) return;
    tier.ledger.apply(observation, at: now, updateLastCost: oddsCall);
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
        collectedHistoryNotice,
      ],
    );
  }
}
