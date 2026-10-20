import 'dart:convert';
import 'dart:io';

import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/data/demo.dart';

import 'quota.dart';

abstract interface class OddsProvider {
  String get id;
  Future<OddsBoard> fetch(DateTime now);
}

class DemoProvider implements OddsProvider {
  @override
  String get id => 'demonstration';
  @override
  Future<OddsBoard> fetch(DateTime now) async => demoBoard(now);
}

const nflTeams = <String, String>{
  'Arizona Cardinals': 'ARI',
  'Atlanta Falcons': 'ATL',
  'Baltimore Ravens': 'BAL',
  'Buffalo Bills': 'BUF',
  'Carolina Panthers': 'CAR',
  'Chicago Bears': 'CHI',
  'Cincinnati Bengals': 'CIN',
  'Cleveland Browns': 'CLE',
  'Dallas Cowboys': 'DAL',
  'Denver Broncos': 'DEN',
  'Detroit Lions': 'DET',
  'Green Bay Packers': 'GB',
  'Houston Texans': 'HOU',
  'Indianapolis Colts': 'IND',
  'Jacksonville Jaguars': 'JAX',
  'Kansas City Chiefs': 'KC',
  'Las Vegas Raiders': 'LV',
  'Los Angeles Chargers': 'LAC',
  'Los Angeles Rams': 'LAR',
  'Miami Dolphins': 'MIA',
  'Minnesota Vikings': 'MIN',
  'New England Patriots': 'NE',
  'New Orleans Saints': 'NO',
  'New York Giants': 'NYG',
  'New York Jets': 'NYJ',
  'Philadelphia Eagles': 'PHI',
  'Pittsburgh Steelers': 'PIT',
  'San Francisco 49ers': 'SF',
  'Seattle Seahawks': 'SEA',
  'Tampa Bay Buccaneers': 'TB',
  'Tennessee Titans': 'TEN',
  'Washington Commanders': 'WAS',
};

String? canonicalTeam(String name) {
  final normalized = name.trim().toLowerCase();
  for (final team in nflTeams.entries) {
    if (team.key.toLowerCase() == normalized ||
        team.value.toLowerCase() == normalized) {
      return team.value;
    }
  }
  return const {
    'jax': 'JAX',
    'jac': 'JAX',
    'gbp': 'GB',
    'kcc': 'KC',
    'sfo': 'SF',
  }[normalized];
}

abstract interface class OddsApiTransport {
  Future<OddsApiResponse> get(Uri uri);
}

class OddsApiResponse {
  OddsApiResponse({
    required this.statusCode,
    required this.body,
    Map<String, String> headers = const {},
  }) : headers = {
         for (final entry in headers.entries)
           entry.key.toLowerCase(): entry.value,
       };

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  String? header(String name) => headers[name.toLowerCase()];
}

class IoOddsApiTransport implements OddsApiTransport {
  @override
  Future<OddsApiResponse> get(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) headers[name] = values.first;
      });
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
      return OddsApiResponse(
        statusCode: response.statusCode,
        body: body,
        headers: headers,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class TheOddsApiProvider implements OddsProvider {
  TheOddsApiProvider(
    this.apiKey, {
    this.verifiedRuleBooks = const {},
    List<String>? bookmakers,
    List<String>? markets,
    this.sport = 'americanfootball_nfl',
    OddsApiTransport? transport,
  }) : bookmakers = resolveBookmakers(bookmakers),
       markets = resolveMarkets(markets),
       transport = transport ?? IoOddsApiTransport();

  final String apiKey;
  // Populate only after confirming equivalent NFL full-game settlement rules.
  final Set<String> verifiedRuleBooks;
  final List<String> bookmakers;
  final List<String> markets;
  final String sport;
  final OddsApiTransport transport;
  DateTime? _retryAfter;
  CreditObservation? lastObservation;

  @override
  String get id => 'the-odds-api';

  /// Credits the next odds call is expected to cost. Events calls cost nothing.
  int get estimatedCost => oddsRequestCost(
    markets: markets.length,
    bookmakers: bookmakers.isNotEmpty,
  );

  Uri oddsUri() => Uri.https('api.the-odds-api.com', '/v4/sports/$sport/odds', {
    'apiKey': apiKey,
    'bookmakers': bookmakers.join(','),
    'markets': markets.join(','),
    'oddsFormat': 'decimal',
    'dateFormat': 'iso',
  });

  /// Kickoff list. The Odds API does not charge credits for `/events`.
  Uri eventsUri() => Uri.https(
    'api.the-odds-api.com',
    '/v4/sports/$sport/events',
    {'apiKey': apiKey, 'dateFormat': 'iso'},
  );

  @override
  Future<OddsBoard> fetch(DateTime now) async {
    final response = await _send(oddsUri(), now);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw StateError('Provider response was not a list.');
      }
      return parse(decoded, now.toUtc());
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('Provider request failed or timed out.');
    }
  }

  Future<List<DateTime>> fetchKickoffs(DateTime now) async {
    final response = await _send(eventsUri(), now);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw StateError('Provider response was not a list.');
      }
      return parseKickoffs(decoded);
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('Provider request failed or timed out.');
    }
  }

  List<DateTime> parseKickoffs(List raw) {
    final times = <DateTime>{};
    for (final item in raw) {
      try {
        if (item is! Map) continue;
        times.add(DateTime.parse(item['commence_time'] as String).toUtc());
      } catch (_) {
        /* Skip an event whose kickoff cannot be read. */
      }
    }
    final sorted = times.toList()..sort();
    return sorted;
  }

  Future<OddsApiResponse> _send(Uri uri, DateTime now) async {
    if (_retryAfter != null && now.isBefore(_retryAfter!)) {
      throw StateError(
        'Provider rate limited; retry after ${_retryAfter!.toIso8601String()}',
      );
    }
    lastObservation = null;
    final OddsApiResponse response;
    try {
      response = await transport.get(uri);
    } on StateError {
      rethrow;
    } catch (_) {
      // Never include URLs or underlying HTTP errors: they may contain API keys.
      throw StateError('Provider request failed or timed out.');
    }
    lastObservation = CreditObservation.fromHeaders(response.headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.header('retry-after') ?? '') ?? 60;
      _retryAfter = now.add(Duration(seconds: seconds.clamp(30, 3600)));
      throw StateError('Provider rate limited; backing off.');
    }
    if (response.statusCode != 200) {
      throw StateError('Provider HTTP ${response.statusCode}');
    }
    return response;
  }

  OddsBoard parse(List raw, DateTime collectedAt) {
    final events = <NflEvent>[];
    final quotes = <OddsQuote>[];
    var rejected = 0;
    for (final item in raw) {
      try {
        final home = canonicalTeam(item['home_team']);
        final away = canonicalTeam(item['away_team']);
        if (home == null || away == null || home == away) {
          rejected++;
          continue;
        }
        final start = DateTime.parse(item['commence_time']).toUtc();
        final eventId = 'nfl:$away:$home:${start.toIso8601String()}';
        final homeName = nflTeams.entries
            .firstWhere((e) => e.value == home)
            .key;
        final awayName = nflTeams.entries
            .firstWhere((e) => e.value == away)
            .key;
        events.add(NflEvent(eventId, awayName, homeName, start));
        // A requested book that sends nothing is omitted. That is not an error.
        for (final book in item['bookmakers'] as List) {
          final rawBook = book['key'] as String;
          // State-specific operators deliberately remain distinct.
          final bookId =
              const {
                'williamhill_us': 'caesars',
                'espnbet': 'thescore',
                'hardrockbet': 'hardrock',
              }[rawBook] ??
              rawBook;
          for (final market in book['markets'] as List) {
            final key = market['key'] as String;
            if (!['h2h', 'spreads', 'totals'].contains(key)) {
              rejected++;
              continue;
            }
            for (final outcome in market['outcomes'] as List) {
              try {
                final name = outcome['name'] as String;
                final team = canonicalTeam(name);
                if (key == 'totals'
                    ? !['Over', 'Under'].contains(name)
                    : team == null || ![home, away].contains(team)) {
                  rejected++;
                  continue;
                }
                final point = (outcome['point'] as num?)?.toDouble();
                if (key != 'h2h' && point == null) {
                  rejected++;
                  continue;
                }
                // Require market timestamp; a book-level time may mask an old market.
                final sourceAt = DateTime.parse(market['last_update']);
                final rules = verifiedRuleBooks.contains(bookId)
                    ? 'includes_overtime_push_on_tie'
                    : 'unverified:$bookId:$key';
                quotes.add(
                  OddsQuote(
                    selection: Selection(
                      eventId: eventId,
                      market: key,
                      outcome: key == 'totals'
                          ? name
                          : (team == home ? homeName : awayName),
                      point: point,
                      rules: rules,
                    ),
                    bookId: bookId,
                    book: book['title'],
                    provider: id,
                    decimal: (outcome['price'] as num).toDouble(),
                    sourceAt: sourceAt,
                    collectedAt: collectedAt,
                    status: rules.startsWith('unverified:')
                        ? 'unverified'
                        : 'open',
                  ),
                );
              } catch (_) {
                rejected++;
              }
            }
          }
        }
      } catch (_) {
        rejected++;
      }
    }
    return OddsBoard(
      events: events,
      quotes: quotes,
      fetchedAt: collectedAt,
      notices: [
        if (rejected > 0)
          '$rejected records rejected because identity or fields could not be verified.',
        'Live adapter currently requests main NFL markets only; prop and alternate feeds need separate provider entitlement and identity mapping.',
        if (quotes.any((q) => q.status == 'unverified')) 'Settlement rules need verification before affected books can enter best-price comparisons.',
      ],
    );
  }
}
