import 'dart:convert';
import 'dart:io';

import 'package:odds_edge/domain/odds.dart';

import 'line_history.dart';
import 'providers.dart';
import 'quota.dart';

/// Player-prop markets whose hit rate can be counted from the bundled NFL
/// box scores. The free credit plan requests the first four, on one game.
const propMarketAllowlist = <String>[
  'player_pass_yds',
  'player_receptions',
  'player_rush_yds',
  'player_reception_yds',
  'player_pass_tds',
  'player_rush_tds',
  'player_reception_tds',
];

/// Passing yards, receptions, rushing yards, and receiving yards.
/// Four markets on one game cost 4 credits with a bookmaker list, the
/// same as the old two markets on two games. The daily cap stays 4.
/// The monthly cap stays 60. More markets means fewer games, not more credits.
const defaultPropMarkets = <String>[
  'player_pass_yds',
  'player_receptions',
  'player_rush_yds',
  'player_reception_yds',
];

/// One upcoming game. 1 event × 4 markets = 4 credits per refresh.
const defaultPropMaxEvents = 1;

/// One refresh a day. 4 credits × 30 days = 120, and the monthly cap below
/// stops it sooner so the main-line schedule still fits in 500.
const defaultPropDailyCreditCap = 4;

/// Hard stop for prop calls in a billing month. Main-line snapshots are a
/// separate budget. 60 + a busy main-line month (about 240) stays near 300,
/// leaving a large share of the 500 free credits untouched.
const defaultPropMonthlyCreditCap = 60;

const propCacheFor = Duration(hours: 18);

List<String> resolvePropMarkets(Iterable<String>? raw) {
  if (raw == null) return List<String>.from(defaultPropMarkets);
  final values = [
    for (final item in raw)
      if (item.trim().isNotEmpty) item.trim().toLowerCase(),
  ];
  if (values.isEmpty) return List<String>.from(defaultPropMarkets);
  if (values.toSet().length != values.length ||
      values.any((market) => !propMarketAllowlist.contains(market))) {
    throw const FormatException(
      'Prop markets must be a subset of the NFL box-score list.',
    );
  }
  if (values.length > defaultPropMarkets.length) {
    throw const FormatException(
      'At most four prop markets. More than that does not fit the free credit plan.',
    );
  }
  return values;
}

class UpstreamEvent {
  const UpstreamEvent({
    required this.id,
    required this.away,
    required this.home,
    required this.awayName,
    required this.homeName,
    required this.startsAt,
  });

  final String id, away, home, awayName, homeName;
  final DateTime startsAt;

  /// Same identity the main-line adapter uses, so a prop can sit on that game.
  String get eventId => 'nfl:$away:$home:${startsAt.toUtc().toIso8601String()}';
}

class PropRefreshDecision {
  const PropRefreshDecision({
    required this.allowed,
    required this.reason,
    required this.events,
    required this.credits,
  });

  final bool allowed;
  final String reason;
  final List<UpstreamEvent> events;
  final int credits;
}

/// Whether a prop refresh may spend credits. Does not call the network.
PropRefreshDecision decidePropRefresh({
  required DateTime now,
  required DateTime? cacheFetchedAt,
  required int creditsSpentToday,
  required int creditsSpentThisMonth,
  required int? creditsRemaining,
  required int scheduledHold,
  required List<UpstreamEvent> upcoming,
  int maxEvents = defaultPropMaxEvents,
  List<String> markets = defaultPropMarkets,
  int dailyCreditCap = defaultPropDailyCreditCap,
  int monthlyCreditCap = defaultPropMonthlyCreditCap,
  Duration cacheFor = propCacheFor,
  bool force = false,
}) {
  final costPerEvent = oddsRequestCost(
    markets: markets.length,
    bookmakers: true,
  );
  final events = choosePropEvents(upcoming, now, maxEvents: maxEvents);
  final credits = events.length * costPerEvent;
  if (events.isEmpty) {
    return const PropRefreshDecision(
      allowed: false,
      reason: 'No upcoming NFL games were listed, so no prop prices were requested.',
      events: [],
      credits: 0,
    );
  }
  if (!force &&
      cacheFetchedAt != null &&
      now.difference(cacheFetchedAt.toUtc()) < cacheFor) {
    return PropRefreshDecision(
      allowed: false,
      reason:
          'Saved prop prices are ${priceAgeHours(now.difference(cacheFetchedAt.toUtc()))} old, so they were kept. A refresh waits ${cacheFor.inHours} hours.',
      events: events,
      credits: credits,
    );
  }
  if (creditsSpentToday + credits > dailyCreditCap) {
    return PropRefreshDecision(
      allowed: false,
      reason:
          'Today\'s prop budget is $dailyCreditCap credits. This refresh would cost $credits more, so it was skipped.',
      events: events,
      credits: credits,
    );
  }
  if (creditsSpentThisMonth + credits > monthlyCreditCap) {
    return PropRefreshDecision(
      allowed: false,
      reason:
          'This month\'s prop budget is $monthlyCreditCap credits. The refresh was skipped.',
      events: events,
      credits: credits,
    );
  }
  if (creditsRemaining != null &&
      creditsRemaining < scheduledHold + credits) {
    return PropRefreshDecision(
      allowed: false,
      reason:
          'Refreshing props would cut into the credits kept for the regular moneyline, spread, and total snapshots, so it was skipped.',
      events: events,
      credits: credits,
    );
  }
  return PropRefreshDecision(
    allowed: true,
    reason: 'Refreshing prop prices for ${events.length} games uses $credits credits.',
    events: events,
    credits: credits,
  );
}

String priceAgeHours(Duration age) {
  if (age.inMinutes < 60) return '${age.inMinutes} minutes';
  return '${age.inHours} hours';
}

/// Soonest games that have not started. Ties keep the upstream order.
List<UpstreamEvent> choosePropEvents(
  List<UpstreamEvent> upcoming,
  DateTime now, {
  int maxEvents = defaultPropMaxEvents,
}) {
  final future = [
    for (final event in upcoming)
      if (event.startsAt.isAfter(now.toUtc())) event,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (future.length <= maxEvents) return future;
  return future.sublist(0, maxEvents);
}

List<UpstreamEvent> parsePropEvents(List raw) {
  final events = <UpstreamEvent>[];
  for (final item in raw) {
    try {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) continue;
      final awayName = item['away_team'];
      final homeName = item['home_team'];
      if (awayName is! String || homeName is! String) continue;
      final away = canonicalTeam(awayName);
      final home = canonicalTeam(homeName);
      if (away == null || home == null || away == home) continue;
      final start = DateTime.parse(item['commence_time'] as String).toUtc();
      events.add(
        UpstreamEvent(
          id: id,
          away: away,
          home: home,
          awayName: nflClubName(away) ?? awayName,
          homeName: nflClubName(home) ?? homeName,
          startsAt: start,
        ),
      );
    } catch (_) {
      /* Skip an event whose kickoff or teams cannot be read. */
    }
  }
  return events;
}

/// One event-odds payload from The Odds API, in decimal format.
/// Player name is `description`. Over/Under is `name`. A row missing either
/// is dropped and counted, never filled in.
({List<OddsQuote> quotes, int rejected}) parsePropEvent(
  Map raw,
  UpstreamEvent event,
  DateTime collectedAt, {
  required String providerId,
  Set<String> allowedMarkets = const {
    'player_pass_yds',
    'player_receptions',
    'player_rush_yds',
    'player_reception_yds',
    'player_pass_tds',
    'player_rush_tds',
    'player_reception_tds',
  },
}) {
  final quotes = <OddsQuote>[];
  var rejected = 0;
  final books = raw['bookmakers'];
  if (books is! List) return (quotes: quotes, rejected: 1);
  for (final book in books) {
    try {
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
      final bookId = normalizeBookId(rawBook);
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
        if (key is! String || !allowedMarkets.contains(key)) {
          rejected++;
          continue;
        }
        final sourceAt = DateTime.parse(market['last_update'] as String).toUtc();
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
            final player = outcome['description'];
            final point = outcome['point'];
            final price = outcome['price'];
            if (name is! String ||
                (name != 'Over' && name != 'Under') ||
                player is! String ||
                player.trim().isEmpty ||
                point is! num ||
                price is! num) {
              rejected++;
              continue;
            }
            quotes.add(
              OddsQuote(
                selection: Selection(
                  eventId: event.eventId,
                  market: key,
                  outcome: name,
                  participant: player.trim(),
                  point: point.toDouble(),
                  rules: 'player_prop_unverified',
                ),
                bookId: bookId,
                book: title,
                provider: providerId,
                decimal: price.toDouble(),
                sourceAt: sourceAt,
                collectedAt: collectedAt,
                status: 'unverified',
              ),
            );
          } catch (_) {
            rejected++;
          }
        }
      }
    } catch (_) {
      rejected++;
    }
  }
  return (quotes: quotes, rejected: rejected);
}

class PropCacheRecord {
  const PropCacheRecord({
    required this.fetchedAt,
    required this.dayKey,
    required this.daySpent,
    required this.monthKey,
    required this.monthSpent,
    required this.board,
    required this.notice,
  });

  final DateTime? fetchedAt;
  final String dayKey, monthKey;
  final int daySpent, monthSpent;
  final OddsBoard? board;
  final String notice;

  PropCacheRecord spending(DateTime now, int credits) {
    final day = _dayKey(now);
    final month = _monthKey(now);
    return PropCacheRecord(
      fetchedAt: fetchedAt,
      dayKey: day,
      monthKey: month,
      daySpent: (dayKey == day ? daySpent : 0) + credits,
      monthSpent: (monthKey == month ? monthSpent : 0) + credits,
      board: board,
      notice: notice,
    );
  }

  int spentToday(DateTime now) => dayKey == _dayKey(now) ? daySpent : 0;
  int spentThisMonth(DateTime now) =>
      monthKey == _monthKey(now) ? monthSpent : 0;
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

class PropCache {
  PropCache(this.file);
  final File file;

  Future<PropCacheRecord> load() async {
    if (!await file.exists()) return _empty();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return _empty();
      final boardRaw = decoded['board'];
      return PropCacheRecord(
        fetchedAt: decoded['fetchedAt'] is String
            ? DateTime.parse(decoded['fetchedAt'] as String).toUtc()
            : null,
        dayKey: '${decoded['dayKey'] ?? ''}',
        monthKey: '${decoded['monthKey'] ?? ''}',
        daySpent: (decoded['daySpent'] as num?)?.toInt() ?? 0,
        monthSpent: (decoded['monthSpent'] as num?)?.toInt() ?? 0,
        board: boardRaw is Map
            ? OddsBoard.fromJson(Map<String, dynamic>.from(boardRaw))
            : null,
        notice: '${decoded['notice'] ?? ''}',
      );
    } catch (_) {
      return _empty();
    }
  }

  Future<void> save(PropCacheRecord record) async {
    await file.parent.create(recursive: true);
    final payload = {
      'fetchedAt': record.fetchedAt?.toUtc().toIso8601String(),
      'dayKey': record.dayKey,
      'daySpent': record.daySpent,
      'monthKey': record.monthKey,
      'monthSpent': record.monthSpent,
      'notice': record.notice,
      if (record.board != null) 'board': record.board!.toJson(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  PropCacheRecord _empty() => const PropCacheRecord(
    fetchedAt: null,
    dayKey: '',
    monthKey: '',
    daySpent: 0,
    monthSpent: 0,
    board: null,
    notice: '',
  );
}

/// Reads the free events list, then prop prices for a few games.
/// The API key is a query parameter, matching The Odds API, and is never
/// copied into an error string.
class PropCoordinator {
  PropCoordinator({
    required this.apiKey,
    required this.bookmakers,
    required this.transport,
    required this.cache,
    this.markets = defaultPropMarkets,
    this.maxEvents = defaultPropMaxEvents,
    this.dailyCreditCap = defaultPropDailyCreditCap,
    this.monthlyCreditCap = defaultPropMonthlyCreditCap,
    this.cacheFor = propCacheFor,
    this.sport = 'americanfootball_nfl',
    this.scheduledHold = 0,
    this.creditsRemaining,
    this.onCredit,
    this.lines,
  });

  final String apiKey;
  final List<String> bookmakers;
  final OddsApiTransport transport;
  final PropCache cache;
  final List<String> markets;
  final int maxEvents, dailyCreditCap, monthlyCreditCap, scheduledHold;
  final Duration cacheFor;
  final String sport;
  final int? Function()? creditsRemaining;
  final void Function(CreditObservation observation, {required bool oddsCall})?
  onCredit;

  /// Same journal as the main board. Written only after a prop fetch that
  /// already happened, never as a reason to fetch again.
  final LineHistory? lines;
  Future<OddsBoard>? _pending;

  int get creditsPerEvent =>
      oddsRequestCost(markets: markets.length, bookmakers: bookmakers.isNotEmpty);

  Uri eventsUri() => Uri.https(
    'api.the-odds-api.com',
    '/v4/sports/$sport/events',
    {'apiKey': apiKey, 'dateFormat': 'iso'},
  );

  Uri eventOddsUri(String eventId) => Uri.https(
    'api.the-odds-api.com',
    '/v4/sports/$sport/events/$eventId/odds',
    {
      'apiKey': apiKey,
      'bookmakers': bookmakers.join(','),
      'markets': markets.join(','),
      'oddsFormat': 'decimal',
      'dateFormat': 'iso',
    },
  );

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
    if (!refresh && cached.board != null && cached.fetchedAt != null) {
      final age = now.toUtc().difference(cached.fetchedAt!);
      if (age < cacheFor && !age.isNegative) return cached.board!;
    }
    if (apiKey.isEmpty) {
      return _emptyBoard(
        now,
        'No odds key is set on the server, so player-prop prices were not requested.',
      );
    }
    try {
      final eventsResponse = await _send(eventsUri(), oddsCall: false);
      final decoded = jsonDecode(eventsResponse.body);
      if (decoded is! List) {
        throw StateError('Provider response was not a list.');
      }
      final decision = decidePropRefresh(
        now: now.toUtc(),
        cacheFetchedAt: cached.fetchedAt,
        creditsSpentToday: cached.spentToday(now),
        creditsSpentThisMonth: cached.spentThisMonth(now),
        creditsRemaining: creditsRemaining?.call(),
        scheduledHold: scheduledHold,
        upcoming: parsePropEvents(decoded),
        maxEvents: maxEvents,
        markets: markets,
        dailyCreditCap: dailyCreditCap,
        monthlyCreditCap: monthlyCreditCap,
        cacheFor: cacheFor,
        force: refresh,
      );
      if (!decision.allowed) {
        if (cached.board != null) return cached.board!;
        return _emptyBoard(now, decision.reason);
      }
      final quotes = <OddsQuote>[];
      final events = <SportEvent>[];
      var rejected = 0;
      var charged = _charged(eventsResponse);
      for (final event in decision.events) {
        final response = await _send(eventOddsUri(event.id), oddsCall: true);
        charged += _charged(response);
        final body = jsonDecode(response.body);
        if (body is! Map) {
          rejected++;
          continue;
        }
        final parsed = parsePropEvent(
          body,
          event,
          now.toUtc(),
          providerId: 'the-odds-api',
          allowedMarkets: markets.toSet(),
        );
        rejected += parsed.rejected;
        quotes.addAll(parsed.quotes);
        events.add(
          SportEvent(
            event.eventId,
            event.awayName,
            event.homeName,
            event.startsAt,
          ),
        );
      }
      final notice = rejected == 0
          ? 'Prop prices for ${events.length} games. Each price keeps the time the book last updated it.'
          : '$rejected prop rows were dropped because the player, line, or price could not be read.';
      final board = OddsBoard(
        events: events,
        quotes: quotes,
        fetchedAt: now.toUtc(),
        notices: [notice, decision.reason],
      );
      var record = cached.spending(now, charged);
      record = PropCacheRecord(
        fetchedAt: now.toUtc(),
        dayKey: record.dayKey,
        daySpent: record.daySpent,
        monthKey: record.monthKey,
        monthSpent: record.monthSpent,
        board: board,
        notice: notice,
      );
      await cache.save(record);
      final history = lines;
      if (history != null) {
        try {
          await history.record(board, kind: 'props');
        } catch (_) {
          // The prices are already cached. History is a copy, not the source.
        }
      }
      return board;
    } on StateError catch (error) {
      final safe = _scrub(error.message);
      if (cached.board != null) return cached.board!;
      return _emptyBoard(now, safe);
    } catch (_) {
      if (cached.board != null) return cached.board!;
      return _emptyBoard(
        now,
        'Player-prop prices could not be refreshed. No stand-in prices were added.',
      );
    }
  }

  Future<OddsApiResponse> _send(Uri uri, {required bool oddsCall}) async {
    final OddsApiResponse response;
    try {
      response = await transport.get(uri);
    } catch (_) {
      throw StateError('Provider request failed or timed out.');
    }
    onCredit?.call(
      CreditObservation.fromHeaders(response.headers),
      oddsCall: oddsCall,
    );
    if (response.statusCode == 429) {
      throw StateError('Provider rate limited; backing off.');
    }
    if (response.statusCode != 200) {
      throw StateError('Provider HTTP ${response.statusCode}');
    }
    return response;
  }

  int _charged(OddsApiResponse response) =>
      int.tryParse(response.header('x-requests-last') ?? '') ?? 0;

  String _scrub(String value) =>
      apiKey.isEmpty ? value : value.replaceAll(apiKey, '[redacted]');

  OddsBoard _emptyBoard(DateTime now, String notice) => OddsBoard(
    events: const [],
    quotes: const [],
    fetchedAt: now.toUtc(),
    notices: [notice],
  );
}
