import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/data/demo_lines.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/public_sharp.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 18);

  test('demo history shows a steam, the first book, and no invented public percent', () {
    final board = demoBoard(now);
    final chiefs = board.events.first;
    final read = readSharp(
      event: chiefs,
      history: demoLineHistory(board)[chiefs.id]!,
      currentQuotes: board.quotes,
      sample: true,
      now: now,
      pricesAt: board.fetchedAt,
    );
    expect(read.oneLine, 'Fast move to the Chiefs');
    expect(read.sparkline.length, greaterThan(1));
    expect(read.sparkline.first, -2.5);
    expect(read.sparkline.last, -3.5);
    expect(
      read.detail.join('\n'),
      contains('DraftKings moved first in these snapshots, from -2.5 to -3.5.'),
    );
    expect(read.detail.join('\n'), contains('inside 20 minutes'));
    expect(read.detail.join('\n'), contains('steam'));
    expect(
      read.detail.join('\n'),
      contains('Earlier, Pinnacle had the Chiefs 1 point more favored'),
    );
    expect(read.publicLine, publicSplitsUnavailableNotice);
    expect(read.reverseLine, isNull);
    expect(read.detail.join('\n'), isNot(contains('Most bets')));
    expect(read.sample, isTrue);

    final reads = readSlate(
      events: board.events,
      history: demoLineHistory(board),
      currentQuotes: board.quotes,
      sample: true,
      now: now,
      pricesAt: board.fetchedAt,
    );
    expect(reads.first.home, 'Kansas City Chiefs');
    expect(reads[1].oneLine, contains('Bengals'));
    expect(reads.last.oneLine, 'No clear move');
    expect(reads.first.clarity, greaterThan(reads[1].clarity));
  });

  test('a slow move across books is not called a steam', () {
    final event = _event(now);
    final read = readSharp(
      event: event,
      history: [
        _shot(event, now.subtract(const Duration(hours: 6)), -3),
        _shot(event, now.subtract(const Duration(hours: 1)), -4.5),
      ],
      currentQuotes: const [],
      now: now,
      pricesAt: now,
    );
    expect(read.oneLine, 'Chiefs -3 to -4.5');
    expect(
      read.detail.join('\n'),
      contains('No fast move across several books'),
    );
    expect(read.detail.join('\n'), contains('moved first'));
  });

  test(
    'books that change in one snapshot are not given a false first mover',
    () {
      final event = _event(now);
      final earlier = _shot(
        event,
        now.subtract(const Duration(minutes: 10)),
        -3,
      );
      final later = _shot(event, now, -4);
      final read = readSharp(
        event: event,
        history: [earlier, later],
        currentQuotes: const [],
        now: now.add(const Duration(hours: 2)),
        pricesAt: now.add(const Duration(hours: 2)),
      );
      expect(
        read.detail.join('\n'),
        contains('cannot say which book moved first'),
      );
    },
  );

  test('an alternate line does not set the number, and a suspended book is ignored', () {
    final event = _event(now);
    final shot = LineSnapshot(
      at: now.subtract(const Duration(hours: 2)),
      eventId: event.id,
      away: event.away,
      home: event.home,
      prices: [
        _price('fanduel', event.home, -3.5, 1.91),
        _price('fanduel', event.home, -10.5, 1.4),
        _price('draftkings', event.home, -3.5, 1.91),
        _price('betmgm', event.home, -3.5, 1.91),
        LinePrice(
          bookId: 'thescore',
          market: 'spreads',
          outcome: event.home,
          decimal: 1.91,
          point: -14,
          status: 'suspended',
        ),
        _price('pinnacle', event.home, -6, 1.91),
      ],
    );
    final read = readSharp(
      event: event,
      history: [shot],
      currentQuotes: const [],
      now: now,
      pricesAt: now,
    );
    expect(read.oneLine, 'Pinnacle 2.5 points to the Chiefs');
    expect(read.sparkline, [-3.5]);
    expect(
      read.detail.join('\n'),
      contains('Pinnacle has the Chiefs 2.5 points more favored'),
    );
  });

  test('reverse line movement and a ticket-money split use plain language', () {
    final event = _event(now);
    final read = readSharp(
      event: event,
      history: [
        _shot(event, now.subtract(const Duration(hours: 5)), -6),
        _shot(event, now.subtract(const Duration(hours: 1)), -3),
      ],
      currentQuotes: const [],
      now: now,
      pricesAt: now,
      publicSplit: PublicSplit(
        eventId: event.id,
        market: 'spreads',
        sourceName: 'Example source',
        attribution: 'Shown with permission',
        fetchedAt: now,
        homeLabel: event.home,
        awayLabel: event.away,
        homeTickets: 70,
        awayTickets: 30,
        homeMoney: 38,
        awayMoney: 62,
      ),
    );
    expect(
      read.reverseLine,
      'Most bets are on the Chiefs, but the line moved toward the Bills. '
      'That usually means bigger bettors like the Bills.',
    );
    expect(
      read.ticketMoney,
      'Most bets are on the Chiefs (70% of tickets), '
      'but most of the money is on the Bills (62% of the money).',
    );
    expect(read.oneLine, 'Bets on the Chiefs, line to the Bills');
    expect(read.publicLine, contains('Example source'));
    expect(read.publicLine, contains('Shown with permission'));
  });

  test(
    'the same side for bets and money is not called reverse line movement',
    () {
      final event = _event(now);
      final read = readSharp(
        event: event,
        history: [
          _shot(event, now.subtract(const Duration(hours: 4)), -3),
          _shot(event, now.subtract(const Duration(hours: 1)), -6),
        ],
        currentQuotes: const [],
        now: now,
        pricesAt: now,
        publicSplit: PublicSplit(
          eventId: event.id,
          market: 'spreads',
          sourceName: 'Example source',
          attribution: '',
          fetchedAt: now,
          homeLabel: event.home,
          awayLabel: event.away,
          homeTickets: 60,
          awayTickets: 40,
          homeMoney: 80,
          awayMoney: 20,
        ),
      );
      expect(read.reverseLine, isNull);
      expect(
        read.ticketMoney,
        contains('60% of the bets and 80% of the money'),
      );
      expect(read.oneLine, 'Chiefs -3 to -6');
    },
  );

  test('a public feed with a missing percent is not filled in', () {
    final parsed = PublicFeed.parse({
      'available': true,
      'source': 'Example source',
      'notice': 'unused',
      'games': [
        {
          'eventId': 'g',
          'home': 'Kansas City Chiefs',
          'away': 'Buffalo Bills',
          'fetchedAt': now.toIso8601String(),
          'spread': {'homeTickets': 70, 'awayTickets': 30},
        },
      ],
    });
    expect(parsed.available, isFalse);
    expect(parsed.splits, isEmpty);
    expect(parsed.notice, 'unused');

    final kept = PublicFeed.parse({
      'available': true,
      'source': 'Example source',
      'attribution': 'Shown with permission',
      'games': [
        {
          'eventId': 'g',
          'home': 'Kansas City Chiefs',
          'away': 'Buffalo Bills',
          'fetchedAt': now.toIso8601String(),
          'spread': {
            'homeTickets': 70,
            'awayTickets': 30,
            'homeMoney': 40,
            'awayMoney': 60,
          },
        },
      ],
    });
    expect(kept.available, isTrue);
    expect(kept.splits.single.homeTickets, 70);
    expect(kept.splits.single.awayMoney, 60);
  });

  test('a game that has started is not given a live sharp signal', () {
    final event = SportEvent(
      'g',
      'Buffalo Bills',
      'Kansas City Chiefs',
      now.subtract(const Duration(hours: 1)),
    );
    final read = readSharp(
      event: event,
      history: [_shot(event, now.subtract(const Duration(hours: 5)), -3)],
      currentQuotes: const [],
      now: now,
      pricesAt: now,
    );
    expect(read.oneLine, 'Kickoff has passed');
    expect(read.clarity, 0);
    expect(read.sparkline, isEmpty);
  });
}

SportEvent _event(DateTime now) => SportEvent(
  'g',
  'Buffalo Bills',
  'Kansas City Chiefs',
  now.add(const Duration(days: 1)),
);

LineSnapshot _shot(SportEvent event, DateTime at, double point) {
  return LineSnapshot(
    at: at,
    eventId: event.id,
    away: event.away,
    home: event.home,
    prices: [
      for (final book in const [
        'fanduel',
        'draftkings',
        'betmgm',
        'caesars',
      ]) ...[
        _price(book, event.home, point, 1.91),
        _price(book, event.away, -point, 1.91),
      ],
    ],
  );
}

LinePrice _price(String book, String outcome, double point, double decimal) {
  return LinePrice(
    bookId: book,
    market: 'spreads',
    outcome: outcome,
    decimal: decimal,
    point: point,
    status: 'unverified',
  );
}
