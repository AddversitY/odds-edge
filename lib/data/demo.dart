import '../domain/odds.dart';

OddsBoard demoBoard(DateTime now) {
  final events = [
    NflEvent(
      'demo-buf-kc',
      'Buffalo Bills',
      'Kansas City Chiefs',
      now.add(const Duration(days: 1)),
    ),
    NflEvent(
      'demo-det-gb',
      'Detroit Lions',
      'Green Bay Packers',
      now.add(const Duration(days: 2)),
    ),
    NflEvent(
      'demo-bal-pit',
      'Baltimore Ravens',
      'Pittsburgh Steelers',
      now.add(const Duration(days: 2)),
    ),
  ];
  const books = {
    'fanduel': 'FanDuel',
    'draftkings': 'DraftKings',
    'betmgm': 'BetMGM',
    'caesars': 'Caesars',
    'bet365': 'bet365',
    'fanatics': 'Fanatics',
    'thescore': 'theScore Bet (formerly ESPN BET)',
    'hardrock': 'Hard Rock Bet',
  };
  final quotes = <OddsQuote>[];
  for (var e = 0; e < events.length; e++) {
    final event = events[e];
    for (var b = 0; b < books.length; b++) {
      final book = books.entries.elementAt(b);
      final age = b == 4 ? 600 : 12 + b * 6;
      void add(
        String market,
        String outcome,
        double? point,
        double decimal, {
        String participant = '',
      }) {
        quotes.add(
          OddsQuote(
            selection: Selection(
              eventId: event.id,
              market: market,
              outcome: outcome,
              point: point,
              participant: participant,
            ),
            bookId: book.key,
            book: book.value,
            provider: 'demonstration',
            decimal: decimal,
            sourceAt: now.subtract(Duration(seconds: age)),
            collectedAt: now,
            demo: true,
            status: b == 6 ? 'suspended' : 'open',
          ),
        );
      }

      add('h2h', event.away, null, 2.05 + b * .04 + e * .03);
      add('h2h', event.home, null, 1.75 + b * .015);
      add('spreads', event.away, 3.5, 1.85 + b * .015);
      add('spreads', event.home, -3.5, 1.91 + b * .01);
      add('spreads', event.away, 2.5, 2.04 + b * .01);
      add('totals', 'Over', 47.5, 1.88 + b * .012);
      add('totals', 'Under', 47.5, 1.91 + b * .008);
      if (e == 0) {
        add(
          'player_pass_yds',
          'Over',
          249.5,
          1.83 + b * .02,
          participant: 'Josh Allen',
        );
        add(
          'player_pass_yds',
          'Under',
          249.5,
          1.94 + b * .005,
          participant: 'Josh Allen',
        );
        if (b < 4) {
          add(
            'player_pass_yds',
            'Over',
            149.5,
            1.18 + b * .01,
            participant: 'Josh Allen',
          );
          add(
            'player_pass_yds',
            'Under',
            149.5,
            4.40 + b * .05,
            participant: 'Josh Allen',
          );
        }
      }
    }
    quotes.add(
      OddsQuote(
        selection: Selection(
          eventId: event.id,
          market: 'spreads',
          outcome: event.away,
          point: 3.5,
        ),
        bookId: 'pinnacle',
        book: 'Pinnacle',
        provider: 'demonstration',
        decimal: 1.90,
        sourceAt: now.subtract(const Duration(minutes: 8)),
        collectedAt: now,
        demo: true,
      ),
    );
    quotes.add(
      OddsQuote(
        selection: Selection(
          eventId: event.id,
          market: 'spreads',
          outcome: event.home,
          point: -3.5,
        ),
        bookId: 'pinnacle',
        book: 'Pinnacle',
        provider: 'demonstration',
        decimal: 1.90,
        sourceAt: now.subtract(const Duration(minutes: 8)),
        collectedAt: now,
        demo: true,
      ),
    );
    quotes.add(
      OddsQuote(
        selection: Selection(
          eventId: event.id,
          market: 'totals',
          outcome: 'Over',
          point: 47.5,
        ),
        bookId: 'pinnacle',
        book: 'Pinnacle',
        provider: 'demonstration',
        decimal: 1.90,
        sourceAt: now.subtract(const Duration(minutes: 8)),
        collectedAt: now,
        demo: true,
      ),
    );
    quotes.add(
      OddsQuote(
        selection: Selection(
          eventId: event.id,
          market: 'totals',
          outcome: 'Under',
          point: 47.5,
        ),
        bookId: 'pinnacle',
        book: 'Pinnacle',
        provider: 'demonstration',
        decimal: 1.90,
        sourceAt: now.subtract(const Duration(minutes: 8)),
        collectedAt: now,
        demo: true,
      ),
    );
  }
  return OddsBoard(
    events: events,
    quotes: quotes,
    fetchedAt: now,
    demo: true,
    notices: [
      'All games, prices, and market states here are synthetic examples. No sportsbook feed is connected.',
    ],
  );
}
