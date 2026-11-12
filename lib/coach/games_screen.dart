import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../domain/market_math.dart';
import '../domain/odds.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../theme/reveal.dart';
import 'coach_line_view.dart';
import 'coach_widgets.dart';

enum _When { all, today, upcoming }

class GamesScreen extends StatefulWidget {
  const GamesScreen({
    super.key,
    required this.board,
    required this.now,
    this.enabledBooks,
    this.model,
    this.settings = const EdgeSettings(
      spreadPoints: 2.5,
      totalPoints: 2.5,
      minExpectedValue: 0.02,
    ),
  });

  final OddsBoard board;
  final DateTime now;
  final Set<String>? enabledBooks;
  final CoachModel? model;
  final EdgeSettings settings;

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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const SectionLabel('GAMES'),
        const SizedBox(height: 8),
        Text(
          widget.board.demo
              ? 'Sample NFL prices. A word on each game compares our number with the books. It is not a pick.'
              : 'NFL is the league in this free snapshot. A word on each game compares our number with the books. It is not a pick.',
          style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
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
              line: widget.model?.lineFor(
                game.event,
                widget.board.quotes,
                settings: widget.settings,
                books: widget.enabledBooks,
              ),
              onOpen: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _GameDetail(
                      game: game,
                      board: widget.board,
                      now: widget.now,
                      books: widget.enabledBooks,
                      line: widget.model?.lineFor(
                        game.event,
                        widget.board.quotes,
                        settings: widget.settings,
                        books: widget.enabledBooks,
                      ),
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
  const _GameCard({required this.game, required this.onOpen, this.line});
  final GameSummary game;
  final CoachLine? line;
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
              style: EdgeType.label,
            ),
            const SizedBox(height: 8),
            Text(event.away, style: EdgeType.title),
            Text(event.home, style: EdgeType.title),
            const SizedBox(height: 12),
            if (line != null)
              CoachLineSummary(line: line!)
            else
              Text(
                "Coach's Line is not on this game.",
                style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _GameDetail extends StatelessWidget {
  const _GameDetail({
    required this.game,
    required this.board,
    required this.now,
    required this.books,
    this.line,
  });

  final GameSummary game;
  final OddsBoard board;
  final DateTime now;
  final Set<String>? books;
  final CoachLine? line;

  @override
  Widget build(BuildContext context) {
    final event = game.event;
    return Scaffold(
      backgroundColor: EdgeColors.background,
      appBar: AppBar(title: Text('${event.away} at ${event.home}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (line != null) ...[
            CoachLineCard(line: line!),
            const SizedBox(height: 16),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                "Coach's Line is not available for this game. No number was filled in.",
                style: EdgeType.body,
              ),
            ),
          Reveal(
            verdict: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('FEE-FREE WIN CHANCE'),
                const SizedBox(height: 12),
                if (game.awayChance == null || game.homeChance == null)
                  Text(
                    'Unavailable',
                    style: EdgeType.title.copyWith(color: EdgeColors.textSecondary),
                  )
                else
                  _SplitBar(
                    away: event.away,
                    home: event.home,
                    awayChance: game.awayChance!,
                    homeChance: game.homeChance!,
                  ),
              ],
            ),
            reasons: Text(game.chanceExplanation, style: EdgeType.body),
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
            "Coach's Line uses past nflverse games, shared under CC BY 4.0. Odds Edge is not affiliated with nflverse. "
            'The injury count is only players listed Out, not a starting lineup. Weather is not in the model. '
            'A model does not guarantee the result.',
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
                color: EdgeColors.accent,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      child: Text(
                        '$away ${percentLabel(awayChance)}',
                          style: const TextStyle(
                            color: EdgeColors.onAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
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
                color: EdgeColors.surfaceHigh,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      child: Text(
                        '$home ${percentLabel(homeChance)}',
                          style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
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
            Text(title, style: EdgeType.title),
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
          minVerticalPadding: 12,
          onTap: () => setState(() => open = !open),
          title: Text(widget.side.selection.label, style: EdgeType.body),
          subtitle: Text(
            best == null
                ? 'No open price'
                : '${best.book} ${americanLabel(best.decimal)} · ${priceAge(best.sourceAt, widget.now)}',
            style: EdgeType.label,
          ),
          trailing: Text(
            open ? 'Hide the math' : 'The math',
            style: EdgeType.label.copyWith(color: EdgeColors.accent),
          ),
        ),
        if (open) ...[
          if (widget.side.marketEv != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${signedPercent(widget.side.marketEv!)} expected profit versus the fee-free chance',
                style: EdgeType.body,
              ),
            ),
          for (final row in ladder)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${row.quote.book}  ${americanLabel(row.quote.decimal)}'
                '${row.expectedProfit == null ? '' : '  ${signedPercent(row.expectedProfit!)}'}'
                '  · ${priceAge(row.quote.sourceAt, widget.now)}',
                style: EdgeType.body,
              ),
            ),
          if (widget.market.rulesUnverified)
            Text(
              unverifiedRulesNote,
              style: EdgeType.label.copyWith(color: EdgeColors.textSecondary),
            ),
        ],
      ],
    );
  }
}
