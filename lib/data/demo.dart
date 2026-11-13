import '../domain/eastern.dart';
import '../domain/odds.dart';

OddsBoard demoBoard(DateTime now) {
  final sunday = nextEasternKickoff(now, DateTime.sunday, 13, 0);
  final late = nextEasternKickoff(now, DateTime.sunday, 16, 25);
  final night = nextEasternKickoff(now, DateTime.sunday, 20, 20);
  final monday = nextEasternKickoff(now, DateTime.monday, 20, 15);
  final events = [
    NflEvent('demo-buf-kc', 'Buffalo Bills', 'Kansas City Chiefs', sunday),
    NflEvent('demo-det-gb', 'Detroit Lions', 'Green Bay Packers', late),
    NflEvent('demo-bal-cin', 'Baltimore Ravens', 'Cincinnati Bengals', night),
    NflEvent('demo-phi-dal', 'Philadelphia Eagles', 'Dallas Cowboys', monday),
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
      for (final prop in _exampleProps[e]) {
        add(
          prop.market,
          'Over',
          prop.line,
          prop.over + b * .015,
          participant: prop.player,
        );
        add(
          prop.market,
          'Under',
          prop.line,
          prop.under + b * .008,
          participant: prop.player,
        );
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

class _ExampleProp {
  const _ExampleProp(
    this.market,
    this.player,
    this.line,
    this.over,
    this.under,
  );
  final String market, player;
  final double line, over, under;
}

/// One line per player. Both sides are priced so the no-vig chance exists.
/// Hit rates still come from the bundled box scores, not from these prices.
const _exampleProps = <List<_ExampleProp>>[
  [
    _ExampleProp('player_pass_tds', 'Josh Allen', 1.5, 1.72, 2.10),
    _ExampleProp('player_rush_yds', 'James Cook', 72.5, 1.87, 1.91),
    _ExampleProp('player_receptions', 'Khalil Shakir', 4.5, 1.83, 1.95),
    _ExampleProp('player_pass_yds', 'Patrick Mahomes', 254.5, 1.91, 1.87),
    _ExampleProp('player_reception_yds', 'Travis Kelce', 47.5, 1.87, 1.91),
  ],
  [
    _ExampleProp('player_pass_tds', 'Jared Goff', 1.5, 1.80, 2.00),
    _ExampleProp('player_reception_yds', 'Amon-Ra St. Brown', 76.5, 1.87, 1.91),
    _ExampleProp('player_rush_yds', 'Jahmyr Gibbs', 64.5, 1.83, 1.95),
    _ExampleProp('player_rush_yds', 'Josh Jacobs', 68.5, 1.91, 1.87),
  ],
  [
    _ExampleProp('player_rush_yds', 'Lamar Jackson', 58.5, 1.87, 1.91),
    _ExampleProp('player_rush_yds', 'Derrick Henry', 78.5, 1.83, 1.95),
    _ExampleProp('player_reception_yds', 'Zay Flowers', 52.5, 1.91, 1.87),
    _ExampleProp('player_reception_yds', "Ja'Marr Chase", 78.5, 1.80, 2.00),
    _ExampleProp('player_pass_tds', 'Joe Burrow', 1.5, 1.74, 2.08),
  ],
  [
    _ExampleProp('player_rush_yds', 'Saquon Barkley', 84.5, 1.87, 1.91),
    _ExampleProp('player_pass_tds', 'Jalen Hurts', 1.5, 1.70, 2.12),
    _ExampleProp('player_reception_yds', 'CeeDee Lamb', 68.5, 1.83, 1.95),
    _ExampleProp('player_receptions', 'George Pickens', 4.5, 1.91, 1.87),
  ],
];
