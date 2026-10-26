import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/market_math.dart';
import '../domain/odds.dart';
import '../explained_number.dart';
import 'coach_widgets.dart';

enum _When { all, today, upcoming }

class GamesScreen extends StatefulWidget {
  const GamesScreen({
    super.key,
    required this.board,
    required this.now,
    this.enabledBooks,
  });

  final OddsBoard board;
  final DateTime now;
  final Set<String>? enabledBooks;

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  _When when = _When.all;

  @override
  Widget build(BuildContext context) {
    final slate = summarizeSlate(
      widget.board,
      widget.now,
      books: widget.enabledBooks,
    );
    final today = calendarDay(widget.now);
    final games = [
      for (final game in slate.games)
        if (_matches(game, today)) game,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const SectionLabel('GAMES'),
        const SizedBox(height: 6),
        Text(
          widget.board.demo
              ? 'Sample NFL prices. Badges count real comparisons of those samples. They are not live edges.'
              : 'NFL is the league in this free snapshot. Badges count prices in that snapshot.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          children: [
            FilterPill(
              label: 'All',
              selected: when == _When.all,
              onTap: () => setState(() => when = _When.all),
            ),
            FilterPill(
              label: 'Today',
              selected: when == _When.today,
              onTap: () => setState(() => when = _When.today),
            ),
            FilterPill(
              label: 'Upcoming',
              selected: when == _When.upcoming,
              onTap: () => setState(() => when = _When.upcoming),
            ),
            const FilterPill(label: 'NFL', selected: true, onTap: _noop),
          ],
        ),
        const SizedBox(height: 12),
        if (games.isEmpty)
          const CoachCard(
            child: Text('No games in this snapshot for that day.'),
          )
        else
          for (final game in games) ...[
            _GameCard(
              game: game,
              onOpen: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _GameDetail(
                      game: game,
                      board: widget.board,
                      now: widget.now,
                      books: widget.enabledBooks,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  bool _matches(GameSummary game, DateTime today) {
    final day = calendarDay(game.event.startsAt);
    return switch (when) {
      _When.all => true,
      _When.today => day == today,
      _When.upcoming => day.isAfter(today),
    };
  }
}

void _noop() {}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.onOpen});
  final GameSummary game;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final event = game.event;
    return CoachCard(
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${event.league} · ${event.startsAt.toLocal().toString().substring(0, 16)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              event.away,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              event.home,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (game.arbitrageCount > 0)
                  _Badge('${game.arbitrageCount} price gap'),
                if (game.positiveEvMarkets > 0)
                  _Badge('${game.positiveEvMarkets} longer price'),
                if (game.parlayCount > 0)
                  _Badge('${game.parlayCount} ticket'),
                if (game.arbitrageCount == 0 &&
                    game.positiveEvMarkets == 0 &&
                    game.parlayCount == 0)
                  const _Badge('No gap in this snapshot', quiet: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.quiet = false});
  final String text;
  final bool quiet;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: (quiet ? Colors.white : coachMint).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: quiet ? Colors.white70 : coachMint,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _GameDetail extends StatelessWidget {
  const _GameDetail({
    required this.game,
    required this.board,
    required this.now,
    required this.books,
  });

  final GameSummary game;
  final OddsBoard board;
  final DateTime now;
  final Set<String>? books;

  @override
  Widget build(BuildContext context) {
    final event = game.event;
    return Scaffold(
      appBar: AppBar(title: Text('${event.away} at ${event.home}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('FEE-FREE WIN CHANCE'),
          const SizedBox(height: 8),
          if (game.awayChance == null || game.homeChance == null)
            Text(game.chanceExplanation)
          else
            _SplitBar(
              away: event.away,
              home: event.home,
              awayChance: game.awayChance!,
              homeChance: game.homeChance!,
            ),
          const SizedBox(height: 8),
          Text(
            game.chanceExplanation,
            style: const TextStyle(color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 16),
          for (final market in const ['spreads', 'h2h', 'totals'])
            _MarketBlock(
              title: switch (market) {
                'spreads' => 'Spread',
                'h2h' => 'Moneyline',
                _ => 'Total',
              },
              markets: game.markets.where((item) => item.market == market),
              board: board,
              now: now,
              books: books,
            ),
          const SizedBox(height: 12),
          const ToolNote(
            'Place the bet at the sportsbook. This app does not send it. '
            'Weather, injuries, and a starting lineup are not in this snapshot, so those sections are left out rather than filled with guesses.',
          ),
          const SizedBox(height: 8),
          const ToolNote(responsibleGamblingNote),
        ],
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({
    required this.away,
    required this.home,
    required this.awayChance,
    required this.homeChance,
  });
  final String away, home;
  final double awayChance, homeChance;

  @override
  Widget build(BuildContext context) {
    final awayFlex = (awayChance * 100).round().clamp(1, 99);
    final homeFlex = (homeChance * 100).round().clamp(1, 99);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              flex: awayFlex,
              child: ColoredBox(
                color: coachMint.withValues(alpha: .85),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      child: Text(
                        '$away ${percentLabel(awayChance)}',
                        style: const TextStyle(
                          color: Color(0xFF062018),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: homeFlex,
              child: ColoredBox(
                color: const Color(0xFF243041),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      child: Text(
                        '$home ${percentLabel(homeChance)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketBlock extends StatelessWidget {
  const _MarketBlock({
    required this.title,
    required this.markets,
    required this.board,
    required this.now,
    required this.books,
  });

  final String title;
  final Iterable<PricedMarket> markets;
  final OddsBoard board;
  final DateTime now;
  final Set<String>? books;

  @override
  Widget build(BuildContext context) {
    final list = markets.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CoachCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const Text('Not in this snapshot.')
            else
              for (final market in list)
                for (final side in market.sides)
                  _SideRow(
                    side: side,
                    market: market,
                    board: board,
                    now: now,
                    books: books,
                  ),
          ],
        ),
      ),
    );
  }
}

class _SideRow extends StatefulWidget {
  const _SideRow({
    required this.side,
    required this.market,
    required this.board,
    required this.now,
    required this.books,
  });
  final PricedSide side;
  final PricedMarket market;
  final OddsBoard board;
  final DateTime now;
  final Set<String>? books;

  @override
  State<_SideRow> createState() => _SideRowState();
}

class _SideRowState extends State<_SideRow> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final best = widget.side.best;
    final ladder = bookLadder(
      widget.board,
      widget.side.selection,
      widget.now,
      books: widget.books,
      fairProbability: widget.side.fairProbability,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: () => setState(() => open = !open),
          title: Text(widget.side.selection.label),
          subtitle: Text(
            best == null
                ? 'No open price'
                : '${best.book} ${americanLabel(best.decimal)} · ${priceAge(best.sourceAt, widget.now)}'
                      '${widget.side.marketEv == null ? '' : ' · ${signedPercent(widget.side.marketEv!)} expected profit vs the fee-free chance'}',
          ),
          trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
        ),
        if (open)
          for (final row in ladder)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Text(
                '${row.quote.book}  ${americanLabel(row.quote.decimal)}'
                '${row.expectedProfit == null ? '' : '  ${signedPercent(row.expectedProfit!)}'}'
                '  · ${priceAge(row.quote.sourceAt, widget.now)}',
              ),
            ),
        if (widget.market.rulesUnverified && open)
          const Text(
            unverifiedRulesNote,
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          ),
      ],
    );
  }
}
