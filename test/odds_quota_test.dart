import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/odds.dart';

import '../backend/providers.dart';
import '../backend/quota.dart';
import '../backend/service.dart';

void main() {
  test('bookmakers cost one region; two regions cost twice as much', () {
    expect(oddsRequestCost(markets: 3, regions: 2), 6);
    expect(oddsRequestCost(markets: 3, regions: 2, bookmakers: true), 3);
    expect(oddsRequestCost(markets: 1, regions: 1), 1);
    expect(oddsRequestCost(markets: 3, bookmakers: true), 3);
    expect(oddsRequestCost(markets: 0, regions: 2), 0);
    expect(() => oddsRequestCost(markets: -1), throwsArgumentError);
  });

  test('odds requests name up to 10 books and do not send regions', () {
    final provider = TheOddsApiProvider('test-key');
    final odds = provider.oddsUri();
    final events = provider.eventsUri();
    expect(odds.path, '/v4/sports/americanfootball_nfl/odds');
    expect(odds.queryParameters.containsKey('regions'), isFalse);
    expect(odds.queryParameters['bookmakers']!.split(','), defaultUsBookmakers);
    expect(defaultUsBookmakers, hasLength(10));
    expect(odds.queryParameters['markets'], 'h2h,spreads,totals');
    expect(provider.estimatedCost, 3);
    expect(events.path, '/v4/sports/americanfootball_nfl/events');
    expect(events.queryParameters.containsKey('markets'), isFalse);
    expect(events.queryParameters.containsKey('regions'), isFalse);
    expect(events.queryParameters.containsKey('bookmakers'), isFalse);
    expect(
      TheOddsApiProvider('test-key', markets: const ['h2h']).estimatedCost,
      1,
    );
    expect(
      () => TheOddsApiProvider(
        'test-key',
        bookmakers: [for (var i = 0; i < 11; i++) 'book$i'],
      ),
      throwsFormatException,
    );
  });

  test('mocked odds and events calls record credit headers', () async {
    final calls = <Uri>[];
    final provider = TheOddsApiProvider(
      'test-key',
      transport: _ScriptedTransport((uri) {
        calls.add(uri);
        if (uri.path.endsWith('/events')) {
          return OddsApiResponse(
            statusCode: 200,
            body: '[{"commence_time":"2026-10-18T17:00:00Z"},{"commence_time":"not-a-time"}]',
            headers: const {
              'x-requests-remaining': '500',
              'x-requests-used': '0',
              'x-requests-last': '0',
            },
          );
        }
        return OddsApiResponse(
          statusCode: 200,
          body:
              '[{"home_team":"Kansas City Chiefs","away_team":"Buffalo Bills",'
              '"commence_time":"2026-10-18T17:00:00Z","bookmakers":[{"key":"fanduel",'
              '"title":"FanDuel","markets":[{"key":"h2h","last_update":"2026-10-18T16:00:00Z",'
              '"outcomes":[{"name":"Buffalo Bills","price":2.1},{"name":"Kansas City Chiefs","price":1.8}]}]}]}]',
          headers: const {
            'X-Requests-Remaining': '497',
            'X-Requests-Used': '3',
            'X-Requests-Last': '3',
          },
        );
      }),
    );
    final kickoffs = await provider.fetchKickoffs(
      DateTime.utc(2026, 10, 18, 12),
    );
    expect(kickoffs, [DateTime.utc(2026, 10, 18, 17)]);
    expect(provider.lastObservation?.lastCost, 0);
    final board = await provider.fetch(DateTime.utc(2026, 10, 18, 12));
    expect(board.quotes, isNotEmpty);
    expect(board.fetchedAt, DateTime.utc(2026, 10, 18, 12));
    expect(provider.lastObservation?.remaining, 497);
    expect(provider.lastObservation?.used, 3);
    expect(provider.lastObservation?.lastCost, 3);
    expect(calls.map((uri) => uri.path), [
      '/v4/sports/americanfootball_nfl/events',
      '/v4/sports/americanfootball_nfl/odds',
    ]);
    expect(calls.last.queryParameters.containsKey('regions'), isFalse);
    expect(calls.last.queryParameters['bookmakers'], contains('draftkings'));
  });

  test('a rate limit does not send another request during backoff', () async {
    var calls = 0;
    final provider = TheOddsApiProvider(
      'test-key',
      transport: _ScriptedTransport((uri) {
        calls++;
        return OddsApiResponse(
          statusCode: 429,
          body: '',
          headers: const {'retry-after': '120', 'x-requests-remaining': '10'},
        );
      }),
    );
    final start = DateTime.utc(2026, 10, 18, 12);
    await expectLater(provider.fetch(start), throwsStateError);
    expect(provider.lastObservation?.remaining, 10);
    await expectLater(
      provider.fetch(start.add(const Duration(seconds: 30))),
      throwsStateError,
    );
    expect(calls, 1);
  });

  test('NFL month schedule stays near 70 refreshes', () {
    const schedule = OddsRefreshSchedule();
    final kickoffs = <DateTime>[];
    for (final thursday in [
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 10, 8),
      DateTime.utc(2026, 10, 15),
      DateTime.utc(2026, 10, 22),
    ]) {
      // Thursday night, Sunday early / late / night, Monday night.
      kickoffs.add(_utc(thursday, days: 1, hour: 0, minute: 20));
      final sunday = thursday.add(const Duration(days: 3));
      kickoffs.add(_utc(sunday, hour: 17));
      kickoffs.add(_utc(sunday, hour: 20, minute: 5));
      kickoffs.add(_utc(sunday, hour: 20, minute: 25));
      kickoffs.add(_utc(sunday, days: 1, hour: 0, minute: 20));
      kickoffs.add(_utc(sunday, days: 2, hour: 0, minute: 15));
    }
    final slots = schedule.slots(
      from: DateTime.utc(2026, 10, 1),
      until: DateTime.utc(2026, 11, 1),
      kickoffs: kickoffs,
    );
    // 31 daily snapshots + 4 weeks × 6 kickoffs × 2 leads = 79.
    // Games that share a kickoff are already one slot. About 70, under 90.
    expect(slots.length, 79);
    expect(slots.length, inInclusiveRange(60, 90));
    expect(
      schedule.slots(
        from: DateTime.utc(2026, 10, 18),
        until: DateTime.utc(2026, 10, 19),
        kickoffs: [DateTime.utc(2026, 10, 18, 17)],
      ),
      [
        DateTime.utc(2026, 10, 18, 15),
        DateTime.utc(2026, 10, 18, 16),
        DateTime.utc(2026, 10, 18, 16, 50),
      ],
    );
  });

  test('nearby kickoffs share a refresh and missed slots expire', () {
    const schedule = OddsRefreshSchedule();
    expect(
      schedule.slots(
        from: DateTime.utc(2026, 10, 18, 15),
        until: DateTime.utc(2026, 10, 18, 17),
        kickoffs: [
          DateTime.utc(2026, 10, 18, 17),
          DateTime.utc(2026, 10, 18, 17, 8),
        ],
      ),
      [
        DateTime.utc(2026, 10, 18, 15),
        DateTime.utc(2026, 10, 18, 16),
        DateTime.utc(2026, 10, 18, 16, 50),
      ],
    );
    final kickoffs = [DateTime.utc(2026, 10, 18, 17)];
    expect(
      schedule.dueSlot(
        now: DateTime.utc(2026, 10, 18, 16),
        lastFetch: DateTime.utc(2026, 10, 18, 12),
        kickoffs: kickoffs,
      ),
      DateTime.utc(2026, 10, 18, 15),
    );
    expect(
      schedule.dueSlot(
        now: DateTime.utc(2026, 10, 18, 16, 10),
        lastFetch: DateTime.utc(2026, 10, 18, 16),
        kickoffs: kickoffs,
      ),
      isNull,
    );
    expect(
      schedule.dueSlot(
        now: DateTime.utc(2026, 10, 18, 16, 50),
        lastFetch: DateTime.utc(2026, 10, 18, 16),
        kickoffs: kickoffs,
      ),
      DateTime.utc(2026, 10, 18, 16, 50),
    );
    expect(
      schedule.dueSlot(
        now: DateTime.utc(2026, 10, 18, 16, 21),
        lastFetch: DateTime.utc(2026, 10, 18, 15),
        kickoffs: kickoffs,
      ),
      isNull,
    );
    expect(
      schedule.dueSlot(
        now: DateTime.utc(2026, 10, 19, 10),
        lastFetch: null,
        kickoffs: const [],
      ),
      isNull,
    );
    expect(
      schedule.dueSlot(
        now: DateTime.utc(2026, 10, 18, 23),
        lastFetch: null,
        kickoffs: const [],
      ),
      DateTime.utc(2026, 10, 18, 15),
    );
  });

  test(
    'credit reserve blocks manual refresh and still allows the schedule',
    () {
      final ledger = CreditLedger(reserve: 50);
      expect(ledger.allowSpend(cost: 3, essential: false), isTrue);
      ledger.remaining = 53;
      expect(ledger.allowSpend(cost: 3, essential: false), isTrue);
      ledger.remaining = 52;
      expect(ledger.allowSpend(cost: 3, essential: false), isFalse);
      expect(ledger.allowSpend(cost: 3, essential: true), isTrue);
      ledger.remaining = 2;
      expect(ledger.allowSpend(cost: 3, essential: true), isFalse);
      ledger.apply(
        const CreditObservation(remaining: 470, used: 30, lastCost: 3),
        at: DateTime.utc(2026, 10, 18),
      );
      expect(ledger.remaining, 470);
      expect(ledger.lastCost, 3);
    },
  );

  test('credit counters survive a restart and ignore a damaged file', () async {
    final dir = await Directory.systemTemp.createTemp('odds-credits');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/credits.json');
    final ledger = CreditLedger(reserve: 50, file: file)
      ..apply(
        const CreditObservation(remaining: 470, used: 30, lastCost: 3),
        at: DateTime.utc(2026, 10, 18, 12),
      );
    await ledger.save();
    final loaded = CreditLedger(reserve: 40, file: file);
    await loaded.load();
    expect(loaded.remaining, 470);
    expect(loaded.used, 30);
    expect(loaded.lastCost, 3);
    expect(loaded.reserve, 40);
    await file.writeAsString('{not json');
    final damaged = CreditLedger(reserve: 50, file: file);
    await damaged.load();
    expect(damaged.remaining, isNull);
  });

  test('environment config defaults to 10 books and a 10 minute cooldown', () {
    final config = OddsBackendConfig.fromEnvironment({
      'ODDS_PROVIDER': 'the-odds-api',
      'THE_ODDS_API_KEY': 'test-key',
    });
    expect(config.bookmakers, defaultUsBookmakers);
    expect(config.markets, ['h2h', 'spreads', 'totals']);
    expect(config.creditReserve, 50);
    expect(config.onDemandCooldown, const Duration(minutes: 10));
    expect(config.onDemandDailyCap, 6);
    expect(config.billingResetDay, 1);
    expect(config.leadTimes, const [Duration(hours: 1), Duration(minutes: 10)]);
    expect(config.dailyUtc, const Duration(hours: 15));
    expect(
      oddsRequestCost(markets: config.markets.length, bookmakers: true),
      3,
    );
    final custom = OddsBackendConfig.fromEnvironment({
      'ODDS_PROVIDER': 'the-odds-api',
      'THE_ODDS_API_KEY': 'test-key',
      'ODDS_API_BOOKMAKERS': 'draftkings, fanduel',
      'ODDS_API_MARKETS': 'h2h',
      'ODDS_CREDIT_RESERVE': '25',
    });
    expect(custom.bookmakers, ['draftkings', 'fanduel']);
    expect(custom.markets, ['h2h']);
    expect(custom.creditReserve, 25);
    expect(
      () =>
          OddsBackendConfig.fromEnvironment({'ODDS_PROVIDER': 'the-odds-api'}),
      throwsFormatException,
    );
    expect(
      () => OddsBackendConfig.fromEnvironment({
        'ODDS_PROVIDER': 'the-odds-api',
        'THE_ODDS_API_KEY': 'test-key',
        'ODDS_API_BOOKMAKERS': [for (var i = 0; i < 11; i++) 'book$i']
            .join(','),
      }),
      throwsFormatException,
    );
    expect(OddsBackendConfig.fromEnvironment({}).mode, 'demo');
  });

  test(
    'passive reads share one snapshot and on-demand refresh cools down',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-cooldown');
      addTearDown(() => dir.delete(recursive: true));
      var now = DateTime.utc(2026, 10, 18, 12);
      final provider = _ClockProvider();
      final service = OddsService(
        [provider],
        SnapshotStore(File('${dir.path}/history.jsonl')),
        freeTier: _plan(kickoffs: [DateTime.utc(2026, 10, 18, 17)]),
        clock: () => now,
      );
      final first = await Future.wait([
        service.getBoard(),
        service.getBoard(onDemand: true),
      ]);
      expect(provider.calls, 1);
      expect(first.first.fetchedAt, now);
      now = now.add(const Duration(minutes: 1));
      final cooled = await service.getBoard(onDemand: true);
      expect(provider.calls, 1);
      expect(cooled.fetchedAt, first.first.fetchedAt);
      expect(cooled.notices.join(), contains('cooling down'));
      await service.getBoard();
      expect(provider.calls, 1);
      now = now.add(const Duration(minutes: 10));
      final refreshed = await service.getBoard(onDemand: true);
      expect(provider.calls, 2);
      expect(refreshed.fetchedAt, now);
    },
  );

  test(
    'reserve skips on-demand refresh but a due kickoff snapshot still runs',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-reserve');
      addTearDown(() => dir.delete(recursive: true));
      var now = DateTime.utc(2026, 10, 18, 12);
      final provider = _ClockProvider();
      final ledger = CreditLedger(reserve: 50)..remaining = 500;
      final service = OddsService(
        [provider],
        SnapshotStore(File('${dir.path}/history.jsonl')),
        freeTier: _plan(
          ledger: ledger,
          kickoffs: [DateTime.utc(2026, 10, 18, 17)],
          cooldown: Duration.zero,
        ),
        clock: () => now,
      );
      await service.restore();
      expect(provider.calls, 0);
      await service.getBoard();
      expect(provider.calls, 1);
      ledger.remaining = 52;
      now = now.add(const Duration(hours: 1));
      final skipped = await service.getBoard(onDemand: true);
      expect(provider.calls, 1);
      expect(skipped.notices.join(), contains('Credit reserve'));
      expect(skipped.quotes, isNotEmpty);
      now = DateTime.utc(2026, 10, 18, 16);
      await service.getBoard();
      expect(provider.calls, 2);
      ledger.remaining = 2;
      now = DateTime.utc(2026, 10, 18, 16, 50);
      final blocked = await service.getBoard();
      expect(provider.calls, 2);
      expect(blocked.fetchedAt, DateTime.utc(2026, 10, 18, 16));
      expect(blocked.notices.join(), contains('Not enough credits'));
      expect(service.status()['creditsRemaining'], 2);
      expect(service.status()['onDemandAllowed'], isFalse);
      expect(service.status()['estimatedCreditsPerRefresh'], 3);
    },
  );

  test(
    'restart serves the saved snapshot until the next planned slot',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-restore');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/history.jsonl');
      const selection = Selection(
        eventId: 'game',
        market: 'h2h',
        outcome: 'Bills',
      );
      final takenAt = DateTime.utc(2026, 10, 18, 12);
      await SnapshotStore(file).append(
        OddsBoard(
          events: [],
          quotes: [
            OddsQuote(
              selection: selection,
              bookId: 'fanduel',
              book: 'FanDuel',
              provider: 'clock',
              decimal: 2,
              sourceAt: takenAt,
              collectedAt: takenAt,
            ),
          ],
          fetchedAt: takenAt,
        ),
      );
      var now = DateTime.utc(2026, 10, 18, 12, 30);
      final provider = _ClockProvider();
      final service = OddsService(
        [provider],
        SnapshotStore(file),
        freeTier: _plan(kickoffs: [DateTime.utc(2026, 10, 18, 17)]),
        clock: () => now,
      );
      await service.restore();
      final cached = await service.getBoard();
      expect(provider.calls, 0);
      expect(cached.fetchedAt, takenAt);
      expect(cached.quotes.single.book, 'FanDuel');
      now = DateTime.utc(2026, 10, 18, 16);
      final scheduled = await service.getBoard();
      expect(provider.calls, 1);
      expect(scheduled.fetchedAt, now);
    },
  );

  test(
    'a failed refresh backs off instead of calling again immediately',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-backoff');
      addTearDown(() => dir.delete(recursive: true));
      var now = DateTime.utc(2026, 10, 18, 12);
      final provider = _ClockProvider()..fail = true;
      final service = OddsService(
        [provider],
        SnapshotStore(File('${dir.path}/history.jsonl')),
        freeTier: _plan(),
        clock: () => now,
      );
      final failed = await service.getBoard();
      expect(provider.calls, 1);
      expect(failed.notices.join(), contains('unavailable'));
      now = now.add(const Duration(minutes: 1));
      await service.getBoard();
      expect(provider.calls, 1);
      provider.fail = false;
      now = now.add(const Duration(minutes: 5));
      final recovered = await service.getBoard();
      expect(provider.calls, 2);
      expect(recovered.quotes, isNotEmpty);
      expect(recovered.quotes.single.status, 'open');
    },
  );

  test('service stores credit headers from the odds response', () async {
    final dir = await Directory.systemTemp.createTemp('odds-headers');
    addTearDown(() => dir.delete(recursive: true));
    final transport = _ScriptedTransport((uri) {
      if (uri.path.endsWith('/events')) {
        return OddsApiResponse(
          statusCode: 200,
          body: '[{"commence_time":"2026-10-19T17:00:00Z"}]',
          headers: const {
            'x-requests-remaining': '500',
            'x-requests-used': '0',
            'x-requests-last': '0',
          },
        );
      }
      return OddsApiResponse(
        statusCode: 200,
        body:
            '[{"home_team":"Kansas City Chiefs","away_team":"Buffalo Bills",'
            '"commence_time":"2026-10-19T17:00:00Z","bookmakers":[]}]',
        headers: const {
          'x-requests-remaining': '497',
          'x-requests-used': '3',
          'x-requests-last': '3',
        },
      );
    });
    final provider = TheOddsApiProvider('test-key', transport: transport);
    final ledger = CreditLedger(
      reserve: 50,
      file: File('${dir.path}/credits.json'),
    );
    final service = OddsService(
      [provider],
      SnapshotStore(File('${dir.path}/history.jsonl')),
      freeTier: FreeTierPlan(
        schedule: const OddsRefreshSchedule(),
        ledger: ledger,
        estimatedCost: provider.estimatedCost,
        bookmakers: provider.bookmakers,
        markets: provider.markets,
      ),
      clock: () => DateTime.utc(2026, 10, 18, 12),
    );
    await service.getBoard();
    expect(ledger.remaining, 497);
    expect(ledger.used, 3);
    expect(ledger.lastCost, 3);
    expect(
      transport.uris.where((uri) => uri.path.endsWith('/odds')),
      hasLength(1),
    );
    await service.getBoard();
    expect(
      transport.uris.where((uri) => uri.path.endsWith('/odds')),
      hasLength(1),
    );
    final reloaded = CreditLedger(reserve: 50, file: ledger.file);
    await reloaded.load();
    expect(reloaded.remaining, 497);
    expect(service.status()['snapshotAsOf'], isNotNull);
    expect(service.status()['bookmakers'], defaultUsBookmakers);
  });

  test('snapshot best price is labeled separately from a live price', () {
    final now = DateTime.utc(2026, 10, 18, 12);
    const selection = Selection(
      eventId: 'game',
      market: 'h2h',
      outcome: 'Bills',
    );
    OddsQuote sample(
      double price, {
      int age = 600,
      String book = 'a',
      String status = 'open',
    }) => OddsQuote(
      selection: selection,
      bookId: book,
      book: book,
      provider: 'test',
      decimal: price,
      sourceAt: now.subtract(Duration(seconds: age)),
      collectedAt: now.subtract(Duration(seconds: age)),
      status: status,
    );
    final quotes = [
      sample(2.1),
      sample(2.4, book: 'b'),
      sample(9, book: 'suspended', status: 'suspended'),
    ];
    expect(bestQuote(quotes, selection, now), isNull);
    expect(bestSnapshotQuote(quotes, selection, now)?.decimal, 2.4);
    expect(
      bestSnapshotQuote(quotes, selection, now, books: {'a'})?.decimal,
      2.1,
    );
  });

  test('demo and live snapshots use different journals', () {
    expect(
      snapshotJournalPath('demonstration'),
      'backend/data/snapshots-demonstration.jsonl',
    );
    expect(
      snapshotJournalPath('the-odds-api'),
      'backend/data/snapshots-the-odds-api.jsonl',
    );
    expect(
      snapshotJournalPath('demonstration'),
      isNot(snapshotJournalPath('the-odds-api')),
    );
    expect(
      billingPeriodEnd(DateTime.utc(2026, 10, 19)),
      DateTime.utc(2026, 11, 1),
    );
    expect(
      billingPeriodEnd(DateTime.utc(2026, 10, 10), resetDay: 15),
      DateTime.utc(2026, 10, 15),
    );
    expect(scheduledCreditHold(scheduledRefreshes: 10, cost: 3, buffer: 5), 35);
  });

  test(
    'live mode refetches instead of restoring demonstration prices',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-mismatch');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/history.jsonl');
      final takenAt = DateTime.utc(2026, 10, 18, 12);
      const selection = Selection(
        eventId: 'game',
        market: 'h2h',
        outcome: 'Bills',
      );
      await SnapshotStore(file).append(
        OddsBoard(
          events: const [],
          quotes: [
            OddsQuote(
              selection: selection,
              bookId: 'fanduel',
              book: 'FanDuel',
              provider: 'demonstration',
              decimal: 2,
              sourceAt: takenAt,
              collectedAt: takenAt,
              demo: true,
            ),
          ],
          fetchedAt: takenAt,
          demo: false,
        ),
      );
      final provider = _ClockProvider();
      final service = OddsService(
        [provider],
        SnapshotStore(file),
        freeTier: _plan(kickoffs: [DateTime.utc(2026, 10, 18, 17)]),
        clock: () => DateTime.utc(2026, 10, 18, 12, 30),
      );
      await service.restore();
      final board = await service.getBoard();
      expect(provider.calls, 1);
      expect(board.demo, isFalse);
      expect(board.quotes.single.provider, 'clock');
      expect(board.quotes.single.demo, isFalse);
      expect(snapshotMatchesProvider(board, provider), isTrue);
    },
  );

  test('restore keeps settlement notices for a matching snapshot', () async {
    final dir = await Directory.systemTemp.createTemp('odds-notices');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/history.jsonl');
    final takenAt = DateTime.utc(2026, 10, 18, 12);
    const selection = Selection(
      eventId: 'game',
      market: 'h2h',
      outcome: 'Bills',
    );
    const settlement =
        'Settlement rules need verification before affected books can enter best-price comparisons.';
    await SnapshotStore(file).append(
      OddsBoard(
        events: const [],
        quotes: [
          OddsQuote(
            selection: selection,
            bookId: 'fanduel',
            book: 'FanDuel',
            provider: 'clock',
            decimal: 2,
            sourceAt: takenAt,
            collectedAt: takenAt,
          ),
        ],
        fetchedAt: takenAt,
        notices: [settlement, collectedHistoryNotice],
      ),
    );
    final provider = _ClockProvider();
    final service = OddsService(
      [provider],
      SnapshotStore(file),
      freeTier: _plan(kickoffs: [DateTime.utc(2026, 10, 18, 17)]),
      clock: () => DateTime.utc(2026, 10, 18, 12, 30),
    );
    await service.restore();
    final board = await service.getBoard();
    expect(provider.calls, 0);
    expect(board.notices, contains(settlement));
    expect(
      board.notices.where((notice) => notice == collectedHistoryNotice),
      hasLength(1),
    );
  });

  test(
    'a planned snapshot is attempted twice, then left until the next slot',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-slot-attempts');
      addTearDown(() => dir.delete(recursive: true));
      var now = DateTime.utc(2026, 10, 18, 15);
      final provider = _ClockProvider()..fail = true;
      final service = OddsService(
        [provider],
        SnapshotStore(File('${dir.path}/history.jsonl')),
        freeTier: _plan(kickoffs: [DateTime.utc(2026, 10, 18, 17)]),
        clock: () => now,
      );
      await service.getBoard();
      expect(provider.calls, 1);
      now = DateTime.utc(2026, 10, 18, 15, 4);
      await service.getBoard();
      expect(provider.calls, 1);
      now = DateTime.utc(2026, 10, 18, 15, 5);
      await service.getBoard();
      expect(provider.calls, 2);
      now = DateTime.utc(2026, 10, 18, 23);
      await service.getBoard();
      expect(provider.calls, 2);
      provider.fail = false;
      now = DateTime.utc(2026, 10, 18, 16);
      final next = await service.getBoard();
      expect(provider.calls, 3);
      expect(next.quotes.single.status, 'open');
    },
  );

  test('a charged unreadable response finishes the scheduled slot', () async {
    final dir = await Directory.systemTemp.createTemp('odds-charged');
    addTearDown(() => dir.delete(recursive: true));
    var calls = 0;
    final provider = TheOddsApiProvider(
      'test-key',
      transport: _ScriptedTransport((uri) {
        calls++;
        return OddsApiResponse(
          statusCode: 200,
          body: '{"not":"a list"}',
          headers: const {
            'x-requests-remaining': '497',
            'x-requests-used': '3',
            'x-requests-last': '3',
          },
        );
      }),
    );
    var now = DateTime.utc(2026, 10, 18, 15);
    final ledger = CreditLedger(reserve: 50)..remaining = 500;
    final service = OddsService(
      [provider],
      SnapshotStore(File('${dir.path}/history.jsonl')),
      freeTier: FreeTierPlan(
        schedule: const OddsRefreshSchedule(),
        ledger: ledger,
        estimatedCost: provider.estimatedCost,
        fixedKickoffs: [DateTime.utc(2026, 10, 18, 17)],
      ),
      clock: () => now,
    );
    await service.getBoard();
    expect(calls, 1);
    expect(ledger.lastCost, 3);
    now = DateTime.utc(2026, 10, 18, 23);
    await service.getBoard();
    expect(calls, 1);
    expect(ledger.lastCost, 3);
  });

  test(
    'on-demand refresh preserves credits for the rest of the month',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-hold');
      addTearDown(() => dir.delete(recursive: true));
      final ledger = CreditLedger(reserve: 0)..remaining = 95;
      var now = DateTime.utc(2026, 10, 1, 12);
      final provider = _ClockProvider();
      final service = OddsService(
        [provider],
        SnapshotStore(File('${dir.path}/history.jsonl')),
        freeTier: FreeTierPlan(
          schedule: const OddsRefreshSchedule(),
          ledger: ledger,
          estimatedCost: 3,
          cooldown: Duration.zero,
          fixedKickoffs: const [],
          dailyOnDemandCap: 0,
        ),
        clock: () => now,
      );
      await service.getBoard();
      expect(provider.calls, 1);
      expect(service.status()['scheduledRefreshesRemaining'], 31);
      expect(service.status()['creditReserve'], 93);
      final blocked = await service.getBoard(onDemand: true);
      expect(provider.calls, 1);
      expect(blocked.notices.join(), contains('Credit reserve'));
      ledger.remaining = 96;
      await service.getBoard(onDemand: true);
      expect(provider.calls, 2);
      ledger.remaining = 3;
      now = DateTime.utc(2026, 10, 1, 15);
      await service.getBoard();
      expect(provider.calls, 3);
    },
  );

  test(
    'manual refreshes stop after the daily cap until the next UTC day',
    () async {
      final dir = await Directory.systemTemp.createTemp('odds-daily-cap');
      addTearDown(() => dir.delete(recursive: true));
      final ledger = CreditLedger(reserve: 0)..remaining = 500;
      var now = DateTime.utc(2026, 10, 18, 12);
      final provider = _ClockProvider();
      final service = OddsService(
        [provider],
        SnapshotStore(File('${dir.path}/history.jsonl')),
        freeTier: FreeTierPlan(
          schedule: const OddsRefreshSchedule(),
          ledger: ledger,
          estimatedCost: 3,
          cooldown: Duration.zero,
          fixedKickoffs: const [],
          dailyOnDemandCap: 2,
        ),
        clock: () => now,
      );
      await service.getBoard();
      await service.getBoard(onDemand: true);
      await service.getBoard(onDemand: true);
      expect(provider.calls, 3);
      final capped = await service.getBoard(onDemand: true);
      expect(provider.calls, 3);
      expect(capped.notices.join(), contains('Daily refresh limit'));
      now = DateTime.utc(2026, 10, 19, 12);
      await service.getBoard(onDemand: true);
      expect(provider.calls, 4);
    },
  );

  test('a free events refresh does not clear the last odds cost', () async {
    final dir = await Directory.systemTemp.createTemp('odds-last-cost');
    addTearDown(() => dir.delete(recursive: true));
    final transport = _ScriptedTransport((uri) {
      if (uri.path.endsWith('/events')) {
        return OddsApiResponse(
          statusCode: 200,
          body: '[{"commence_time":"2026-10-19T17:00:00Z"}]',
          headers: const {
            'x-requests-remaining': '497',
            'x-requests-used': '3',
            'x-requests-last': '0',
          },
        );
      }
      return OddsApiResponse(
        statusCode: 200,
        body:
            '[{"home_team":"Kansas City Chiefs","away_team":"Buffalo Bills",'
            '"commence_time":"2026-10-19T17:00:00Z","bookmakers":[]}]',
        headers: const {
          'x-requests-remaining': '497',
          'x-requests-used': '3',
          'x-requests-last': '3',
        },
      );
    });
    final ledger = CreditLedger(reserve: 0)..remaining = 500;
    final service = OddsService(
      [TheOddsApiProvider('test-key', transport: transport)],
      SnapshotStore(File('${dir.path}/history.jsonl')),
      freeTier: FreeTierPlan(
        schedule: const OddsRefreshSchedule(),
        ledger: ledger,
        estimatedCost: 3,
        eventsMaxAge: Duration.zero,
        dailyOnDemandCap: 0,
      ),
      clock: () => DateTime.utc(2026, 10, 18, 12),
    );
    await service.getBoard();
    expect(ledger.lastCost, 3);
    final oddsCalls = transport.uris
        .where((uri) => uri.path.endsWith('/odds'))
        .length;
    await service.getBoard();
    expect(ledger.lastCost, 3);
    expect(
      transport.uris.where((uri) => uri.path.endsWith('/odds')),
      hasLength(oddsCalls),
    );
    expect(
      transport.uris.where((uri) => uri.path.endsWith('/events')).length,
      greaterThan(1),
    );
    ledger.apply(
      const CreditObservation(remaining: 497, used: 3, lastCost: 0),
      at: DateTime.utc(2026, 10, 18, 13),
      updateLastCost: false,
    );
    expect(ledger.lastCost, 3);
  });
}

DateTime _utc(DateTime day, {int days = 0, int hour = 0, int minute = 0}) {
  final shifted = day.add(Duration(days: days));
  return DateTime.utc(shifted.year, shifted.month, shifted.day, hour, minute);
}

FreeTierPlan _plan({
  CreditLedger? ledger,
  List<DateTime>? kickoffs,
  Duration cooldown = const Duration(minutes: 10),
}) => FreeTierPlan(
  schedule: const OddsRefreshSchedule(),
  ledger: ledger ?? (CreditLedger(reserve: 50)..remaining = 500),
  estimatedCost: 3,
  cooldown: cooldown,
  fixedKickoffs: kickoffs ?? const [],
);

class _ClockProvider implements OddsProvider {
  @override
  String get id => 'clock';
  int calls = 0;
  bool fail = false;

  @override
  Future<OddsBoard> fetch(DateTime time) async {
    calls++;
    if (fail) throw StateError('offline');
    const selection = Selection(
      eventId: 'game',
      market: 'h2h',
      outcome: 'Bills',
    );
    return OddsBoard(
      events: [],
      quotes: [
        OddsQuote(
          selection: selection,
          bookId: 'a',
          book: 'A',
          provider: id,
          decimal: 2,
          sourceAt: time,
          collectedAt: time,
        ),
      ],
      fetchedAt: time,
    );
  }
}

class _ScriptedTransport implements OddsApiTransport {
  _ScriptedTransport(this.onGet);
  final OddsApiResponse Function(Uri uri) onGet;
  final uris = <Uri>[];

  @override
  Future<OddsApiResponse> get(Uri uri) async {
    uris.add(uri);
    return onGet(uri);
  }
}
