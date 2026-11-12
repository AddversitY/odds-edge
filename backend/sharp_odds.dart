import 'dart:convert';
import 'dart:io';

import 'package:odds_edge/domain/odds.dart';

import 'providers.dart';
import 'quota.dart';

/// Pinnacle, and only Pinnacle, for NFL spreads and totals.
///
/// The Odds API lists Pinnacle in the eu region. Two markets with a
/// bookmaker list cost 2 credits. The free plan is 500 credits a month.
/// About 200 were left when this guard was added, and the regular
/// snapshots still need most of those, so this budget is small on purpose.
const sharpBookId = 'pinnacle';
const sharpRegion = 'eu';
const sharpMarkets = <String>['spreads', 'totals'];
const sharpEstimatedCost = 2;

/// Three pulls. 3 × 2 credits.
const sharpDailyCreditCap = 6;

/// Eighteen pulls. Leaves the rest of a thin month for the regular board.
const sharpMonthlyCreditCap = 36;

const sharpDailyPullCap = 3;
const sharpMonthlyPullCap = 18;

/// Long enough that a server left running cannot pull more than three
/// times in a day even before the pull cap is checked.
const sharpCacheFor = Duration(hours: 8);

class SharpRefreshDecision {
  const SharpRefreshDecision({
    required this.allowed,
    required this.reason,
    required this.credits,
  });

  final bool allowed;
  final String reason;
  final int credits;
}

/// Whether one Pinnacle pull may spend credits. Does not call the network.
SharpRefreshDecision decideSharpRefresh({
  required DateTime now,
  required DateTime? cacheFetchedAt,
  required int creditsSpentToday,
  required int creditsSpentThisMonth,
  required int pullsToday,
  required int pullsThisMonth,
  required int? creditsRemaining,
  required int scheduledHold,
  int estimatedCost = sharpEstimatedCost,
  int dailyCreditCap = sharpDailyCreditCap,
  int monthlyCreditCap = sharpMonthlyCreditCap,
  int dailyPullCap = sharpDailyPullCap,
  int monthlyPullCap = sharpMonthlyPullCap,
  Duration cacheFor = sharpCacheFor,
  bool force = false,
}) {
  if (estimatedCost <= 0) {
    return const SharpRefreshDecision(
      allowed: false,
      reason:
          'The Pinnacle pull has no credit cost on file, so it was skipped.',
      credits: 0,
    );
  }
  if (!force &&
      cacheFetchedAt != null &&
      !now.toUtc().difference(cacheFetchedAt.toUtc()).isNegative &&
      now.toUtc().difference(cacheFetchedAt.toUtc()) < cacheFor) {
    return SharpRefreshDecision(
      allowed: false,
      reason:
          'Saved Pinnacle prices are still inside ${cacheFor.inHours} hours, so they were kept.',
      credits: estimatedCost,
    );
  }
  if (pullsToday >= dailyPullCap ||
      creditsSpentToday + estimatedCost > dailyCreditCap) {
    return SharpRefreshDecision(
      allowed: false,
      reason:
          'Today\'s Pinnacle budget is $dailyPullCap pulls and $dailyCreditCap credits. The pull was skipped.',
      credits: estimatedCost,
    );
  }
  if (pullsThisMonth >= monthlyPullCap ||
      creditsSpentThisMonth + estimatedCost > monthlyCreditCap) {
    return SharpRefreshDecision(
      allowed: false,
      reason:
          'This month\'s Pinnacle budget is $monthlyPullCap pulls and $monthlyCreditCap credits. The pull was skipped.',
      credits: estimatedCost,
    );
  }
  if (creditsRemaining != null &&
      creditsRemaining < scheduledHold + estimatedCost) {
    return SharpRefreshDecision(
      allowed: false,
      reason: 'A Pinnacle pull would cut into the credits kept for the regular snapshots, so it was skipped.',
      credits: estimatedCost,
    );
  }
  return SharpRefreshDecision(
    allowed: true,
    reason:
        'Refreshing Pinnacle spreads and totals uses $estimatedCost credits. The eu region is the one that lists Pinnacle.',
    credits: estimatedCost,
  );
}

/// A missing or tiny header still counts as a full pull. A larger
/// reported charge is kept, so the guard cannot under-count.
int sharpCreditsCharged(int? reported, {int estimated = sharpEstimatedCost}) {
  if (reported == null || reported < estimated) return estimated;
  return reported;
}

class SharpCacheRecord {
  const SharpCacheRecord({
    required this.fetchedAt,
    required this.dayKey,
    required this.daySpent,
    required this.dayPulls,
    required this.monthKey,
    required this.monthSpent,
    required this.monthPulls,
    required this.board,
    required this.notice,
  });

  final DateTime? fetchedAt;
  final String dayKey, monthKey, notice;
  final int daySpent, dayPulls, monthSpent, monthPulls;
  final OddsBoard? board;

  int spentToday(DateTime now) => dayKey == _dayKey(now) ? daySpent : 0;
  int pullsToday(DateTime now) => dayKey == _dayKey(now) ? dayPulls : 0;
  int spentThisMonth(DateTime now) =>
      monthKey == _monthKey(now) ? monthSpent : 0;
  int pullsThisMonth(DateTime now) =>
      monthKey == _monthKey(now) ? monthPulls : 0;

  SharpCacheRecord spend(DateTime now, int credits) {
    final day = _dayKey(now);
    final month = _monthKey(now);
    return SharpCacheRecord(
      fetchedAt: now.toUtc(),
      dayKey: day,
      monthKey: month,
      daySpent: (dayKey == day ? daySpent : 0) + credits,
      dayPulls: (dayKey == day ? dayPulls : 0) + 1,
      monthSpent: (monthKey == month ? monthSpent : 0) + credits,
      monthPulls: (monthKey == month ? monthPulls : 0) + 1,
      board: board,
      notice: notice,
    );
  }
}

String _dayKey(DateTime now) {
  final utc = now.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

String _monthKey(DateTime now) {
  final utc = now.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  return '${utc.year}-$month';
}

class SharpCache {
  SharpCache(this.file);
  final File file;

  Future<SharpCacheRecord> load() async {
    if (!await file.exists()) return _empty();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return _empty();
      final boardRaw = decoded['board'];
      return SharpCacheRecord(
        fetchedAt: decoded['fetchedAt'] is String
            ? DateTime.parse(decoded['fetchedAt'] as String).toUtc()
            : null,
        dayKey: '${decoded['dayKey'] ?? ''}',
        monthKey: '${decoded['monthKey'] ?? ''}',
        daySpent: (decoded['daySpent'] as num?)?.toInt() ?? 0,
        dayPulls: (decoded['dayPulls'] as num?)?.toInt() ?? 0,
        monthSpent: (decoded['monthSpent'] as num?)?.toInt() ?? 0,
        monthPulls: (decoded['monthPulls'] as num?)?.toInt() ?? 0,
        notice: '${decoded['notice'] ?? ''}',
        board: boardRaw is Map
            ? OddsBoard.fromJson(Map<String, dynamic>.from(boardRaw))
            : null,
      );
    } catch (_) {
      return _empty();
    }
  }

  Future<void> save(SharpCacheRecord record) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'fetchedAt': record.fetchedAt?.toUtc().toIso8601String(),
        'dayKey': record.dayKey,
        'daySpent': record.daySpent,
        'dayPulls': record.dayPulls,
        'monthKey': record.monthKey,
        'monthSpent': record.monthSpent,
        'monthPulls': record.monthPulls,
        'notice': record.notice,
        if (record.board != null) 'board': record.board!.toJson(),
      }),
      flush: true,
    );
  }

  SharpCacheRecord _empty() => const SharpCacheRecord(
    fetchedAt: null,
    dayKey: '',
    monthKey: '',
    daySpent: 0,
    dayPulls: 0,
    monthSpent: 0,
    monthPulls: 0,
    board: null,
    notice: '',
  );
}

/// Spreads and totals from Pinnacle only. Moneyline rows and other
/// books are dropped. A row that cannot be read is counted, not guessed.
({List<SportEvent> events, List<OddsQuote> quotes, int rejected})
parseSharpOdds(
  List raw,
  DateTime collectedAt, {
  String providerId = 'the-odds-api',
}) {
  final events = <SportEvent>[];
  final quotes = <OddsQuote>[];
  var rejected = 0;
  for (final item in raw) {
    try {
      if (item is! Map) {
        rejected++;
        continue;
      }
      final home = canonicalTeam(item['home_team']);
      final away = canonicalTeam(item['away_team']);
      if (home == null || away == null || home == away) {
        rejected++;
        continue;
      }
      final start = DateTime.parse(item['commence_time'] as String).toUtc();
      final eventId = 'nfl:$away:$home:${start.toIso8601String()}';
      final homeName = nflClubName(home) ?? item['home_team'] as String;
      final awayName = nflClubName(away) ?? item['away_team'] as String;
      final books = item['bookmakers'];
      if (books is! List) {
        rejected++;
        continue;
      }
      var kept = 0;
      for (final book in books) {
        if (book is! Map) {
          rejected++;
          continue;
        }
        final rawBook = book['key'];
        final title = book['title'];
        if (rawBook is! String || title is! String) {
          rejected++;
          continue;
        }
        if (normalizeBookId(rawBook) != sharpBookId) {
          rejected++;
          continue;
        }
        final markets = book['markets'];
        if (markets is! List) {
          rejected++;
          continue;
        }
        for (final market in markets) {
          if (market is! Map) {
            rejected++;
            continue;
          }
          final key = market['key'];
          if (key is! String || !sharpMarkets.contains(key)) {
            rejected++;
            continue;
          }
          final sourceAt = DateTime.parse(market['last_update'] as String)
              .toUtc();
          final outcomes = market['outcomes'];
          if (outcomes is! List) {
            rejected++;
            continue;
          }
          for (final outcome in outcomes) {
            try {
              if (outcome is! Map) {
                rejected++;
                continue;
              }
              final name = outcome['name'];
              final point = outcome['point'];
              final price = outcome['price'];
              if (name is! String || point is! num || price is! num) {
                rejected++;
                continue;
              }
              final team = canonicalTeam(name);
              if (key == 'totals'
                  ? name != 'Over' && name != 'Under'
                  : team == null || (team != home && team != away)) {
                rejected++;
                continue;
              }
              quotes.add(
                OddsQuote(
                  selection: Selection(
                    eventId: eventId,
                    market: key,
                    outcome: key == 'totals'
                        ? name
                        : (team == home ? homeName : awayName),
                    point: point.toDouble(),
                    rules: 'unverified',
                  ),
                  bookId: sharpBookId,
                  book: title,
                  provider: providerId,
                  decimal: price.toDouble(),
                  sourceAt: sourceAt,
                  collectedAt: collectedAt,
                  status: 'unverified',
                ),
              );
              kept++;
            } catch (_) {
              rejected++;
            }
          }
        }
      }
      if (kept > 0) {
        events.add(SportEvent(eventId, awayName, homeName, start));
      }
    } catch (_) {
      rejected++;
    }
  }
  return (events: events, quotes: quotes, rejected: rejected);
}

/// One cached Pinnacle board. The key stays in the query and is never
/// copied into an error string.
class SharpCoordinator {
  SharpCoordinator({
    required this.apiKey,
    required this.transport,
    required this.cache,
    this.sport = 'americanfootball_nfl',
    this.scheduledHold = 0,
    this.cacheFor = sharpCacheFor,
    this.creditsRemaining,
    this.onCredit,
  });

  final String apiKey;
  final OddsApiTransport transport;
  final SharpCache cache;
  final String sport;
  final int scheduledHold;
  final Duration cacheFor;
  final int? Function()? creditsRemaining;
  final void Function(CreditObservation observation, {required bool oddsCall})?
  onCredit;
  Future<OddsBoard>? _pending;

  Uri oddsUri() => Uri.https('api.the-odds-api.com', '/v4/sports/$sport/odds', {
    'apiKey': apiKey,
    'regions': sharpRegion,
    'markets': sharpMarkets.join(','),
    'bookmakers': sharpBookId,
    'oddsFormat': 'decimal',
    'dateFormat': 'iso',
  });

  Future<OddsBoard> board(DateTime now, {bool refresh = false}) {
    final pending = _pending;
    if (pending != null && !refresh) return pending;
    final run = _board(now, refresh: refresh);
    _pending = run;
    return run.whenComplete(() {
      if (identical(_pending, run)) _pending = null;
    });
  }

  Future<OddsBoard> _board(DateTime now, {bool refresh = false}) async {
    final cached = await cache.load();
    final current = now.toUtc();
    final decision = decideSharpRefresh(
      now: current,
      cacheFetchedAt: cached.fetchedAt,
      creditsSpentToday: cached.spentToday(current),
      creditsSpentThisMonth: cached.spentThisMonth(current),
      pullsToday: cached.pullsToday(current),
      pullsThisMonth: cached.pullsThisMonth(current),
      creditsRemaining: creditsRemaining?.call(),
      scheduledHold: scheduledHold,
      cacheFor: cacheFor,
      force: refresh,
    );
    if (!decision.allowed) {
      if (cached.board != null) return cached.board!;
      return _empty(current, decision.reason);
    }
    if (apiKey.isEmpty) {
      return _empty(
        current,
        'No odds key is set on the server, so Pinnacle was not requested.',
      );
    }
    try {
      final response = await _send(oddsUri());
      final charged = sharpCreditsCharged(
        int.tryParse(response.header('x-requests-last') ?? ''),
      );
      // Count the pull even when the body cannot be read, so a bad
      // response cannot be requested again on the next minute.
      final spent = cached.spend(current, charged);
      final Object decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        await cache.save(spent);
        throw StateError('Provider response was not a list.');
      }
      if (decoded is! List) {
        await cache.save(spent);
        throw StateError('Provider response was not a list.');
      }
      final parsed = parseSharpOdds(decoded, current);
      final notice = parsed.rejected == 0
          ? 'Pinnacle spreads and totals. Moneylines are not requested.'
          : '${parsed.rejected} rows were dropped. Only Pinnacle spreads and totals are kept.';
      final board = OddsBoard(
        events: parsed.events,
        quotes: parsed.quotes,
        fetchedAt: current,
        notices: [notice, decision.reason],
      );
      await cache.save(
        SharpCacheRecord(
          fetchedAt: current,
          dayKey: spent.dayKey,
          daySpent: spent.daySpent,
          dayPulls: spent.dayPulls,
          monthKey: spent.monthKey,
          monthSpent: spent.monthSpent,
          monthPulls: spent.monthPulls,
          board: board,
          notice: notice,
        ),
      );
      return board;
    } on StateError catch (error) {
      final safe = _scrub(error.message);
      if (cached.board != null) return cached.board!;
      return _empty(current, safe);
    } catch (_) {
      if (cached.board != null) return cached.board!;
      return _empty(
        current,
        'Pinnacle prices could not be refreshed. No stand-in prices were added.',
      );
    }
  }

  Future<OddsApiResponse> _send(Uri uri) async {
    final OddsApiResponse response;
    try {
      response = await transport.get(uri);
    } catch (_) {
      throw StateError('Provider request failed or timed out.');
    }
    onCredit?.call(
      CreditObservation.fromHeaders(response.headers),
      oddsCall: true,
    );
    if (response.statusCode == 429) {
      throw StateError('Provider rate limited; backing off.');
    }
    if (response.statusCode != 200) {
      throw StateError('Provider HTTP ${response.statusCode}');
    }
    return response;
  }

  String _scrub(String value) =>
      apiKey.isEmpty ? value : value.replaceAll(apiKey, '[redacted]');

  OddsBoard _empty(DateTime now, String notice) => OddsBoard(
    events: const [],
    quotes: const [],
    fetchedAt: now,
    notices: [notice],
  );
}
