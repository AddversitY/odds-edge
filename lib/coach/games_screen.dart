import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/eastern.dart';
import '../domain/coach_model.dart';
import '../domain/injury_report.dart';
import '../domain/market_math.dart';
import '../domain/matchup.dart';
import '../domain/nfl_teams.dart';
import '../domain/odds.dart';
import '../domain/public_sharp.dart' hide clubNickname;
import '../domain/value_check.dart';
import '../domain/why_brief.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../theme/reveal.dart';
import 'coach_line_view.dart';
import 'coach_widgets.dart';
import 'sharp_view.dart';
import 'value_view.dart';
import 'why_view.dart';

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
    this.lineHistory = const {},
    this.publicSplits = const [],
    this.sampleHistory = false,
    this.injuries,
    this.openEventId,
    this.onEventOpened,
  });

  final OddsBoard board;
  final DateTime now;
  final Set<String>? enabledBooks;
  final CoachModel? model;
  final EdgeSettings settings;
  final Map<String, List<LineSnapshot>> lineHistory;
  final List<PublicSplit> publicSplits;
  final bool sampleHistory;
  final InjuryReport? injuries;

  /// Opens this game once, then [onEventOpened] clears the request.
  final String? openEventId;
  final VoidCallback? onEventOpened;

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  _When when = _When.all;
  String? _opened;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequested());
  }

  @override
  void didUpdateWidget(GamesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openEventId != null && widget.openEventId != _opened) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRequested());
    }
  }

  void _openRequested() {
    final id = widget.openEventId;
    if (id == null || !mounted || id == _opened) return;
    final slate = summarizeSlate(
      widget.board,
      widget.now,
      books: widget.enabledBooks,
    );
    GameSummary? game;
    for (final item in slate.games) {
      if (item.event.id == id) game = item;
    }
    _opened = id;
    widget.onEventOpened?.call();
    if (game == null) return;
    _open(game);
  }

  void _open(GameSummary game) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _GameDetail(
          game: game,
          board: widget.board,
          now: widget.now,
          books: widget.enabledBooks,
          injuries: widget.injuries,
          sharp: _sharpFor(game.event),
          line: widget.model?.lineFor(
            game.event,
            widget.board.quotes,
            settings: widget.settings,
            books: widget.enabledBooks,
            injuries: widget.injuries,
          ),
        ),
      ),
    );
  }

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
        const SizedBox(height: 8),
        Text(
          widget.board.demo
              ? 'Example games. The comparison is not a pick.'
              : 'A comparison with the books. It is not a pick.',
          style: EdgeType.label,
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
              sharp: _sharpFor(game.event),
              injuries: widget.injuries,
              line: widget.model?.lineFor(
                game.event,
                widget.board.quotes,
                settings: widget.settings,
                books: widget.enabledBooks,
                injuries: widget.injuries,
              ),
              onOpen: () => _open(game),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  SharpRead _sharpFor(SportEvent event) => readSharp(
    event: event,
    history: historyForEvent(event, widget.lineHistory),
    currentQuotes: widget.board.quotes,
    publicSplit: publicSplitFor(event, widget.publicSplits),
    sample: widget.sampleHistory,
    now: widget.now,
    pricesAt: widget.board.fetchedAt,
  );

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
  const _GameCard({
    required this.game,
    required this.onOpen,
    required this.sharp,
    this.line,
    this.injuries,
  });
  final GameSummary game;
  final SharpRead sharp;
  final CoachLine? line;
  final InjuryReport? injuries;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final event = game.event;
    final badge = badgeForClubs(injuries, [event.away, event.home]);
    return Material(
      color: EdgeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: EdgeColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${event.league} · ${formatEastern(event.startsAt)}',
                      style: EdgeType.label,
                    ),
                  ),
                  if (badge != null)
                    InjuryBadgePill(label: badge.label, severe: badge.severe),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                event.away,
                style: EdgeType.title.copyWith(
                  fontFamily: EdgeFont.display,
                  fontSize: 22,
                ),
              ),
              Text(
                event.home,
                style: EdgeType.title.copyWith(
                  fontFamily: EdgeFont.display,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 10),
              if (line != null)
                CoachLineSummary(line: line!)
              else
                Text(
                  "Coach's Line is not on this game.",
                  style: EdgeType.label,
                ),
              if (sharp.hasSignal) ...[
                const SizedBox(height: 8),
                Text(
                  'Sharp  ${sharp.oneLine}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EdgeType.label.copyWith(color: EdgeColors.text),
                ),
              ],
            ],
          ),
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
    required this.sharp,
    this.line,
    this.injuries,
  });

  final GameSummary game;
  final OddsBoard board;
  final DateTime now;
  final Set<String>? books;
  final SharpRead sharp;
  final CoachLine? line;
  final InjuryReport? injuries;

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
          SharpWhyRow(read: sharp),
          const SizedBox(height: 16),
          Reveal(
            verdict: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('FEE-FREE WIN CHANCE'),
                const SizedBox(height: 12),
                if (game.awayChance == null || game.homeChance == null)
                  Text(
                    'Unavailable',
                    style: EdgeType.title.copyWith(
                      color: EdgeColors.textSecondary,
                    ),
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
              line: line,
              game: game,
              injuries: injuries,
            ),
          const SizedBox(height: 12),
          ToolNote(
            line?.breakdownIsLive == true
                ? 'Place the bet at the sportsbook. This app does not send it. '
                      "Coach's Line starts from the books' number, then adds the quarterback, weighted injuries, open-roof weather, rest, and travel. "
                      'Past nflverse games are shared under CC BY 4.0. Odds Edge is not affiliated with nflverse. '
                      'Weather for past games is from Open-Meteo. A US forecast is from the National Weather Service when it has one. '
                      'A model does not guarantee the result.'
                : 'Place the bet at the sportsbook. This app does not send it. '
                      "Coach's Line uses past nflverse games, shared under CC BY 4.0. Odds Edge is not affiliated with nflverse. "
                      'The injury count is only players listed Out, not a starting lineup. Weather is not in the model. '
                      'A model does not guarantee the result.',
          ),
          const SizedBox(height: 8),
          const ToolNote(responsibleGamblingNote),
          const SizedBox(height: 12),
          Text(
            'Comparison, not a pick.',
            style: EdgeType.label.copyWith(color: EdgeColors.textSecondary),
          ),
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
    required this.game,
    this.line,
    this.injuries,
  });

  final String title;
  final Iterable<PricedMarket> markets;
  final OddsBoard board;
  final DateTime now;
  final Set<String>? books;
  final GameSummary game;
  final CoachLine? line;
  final InjuryReport? injuries;

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
                    line: line,
                    game: game,
                    injuries: injuries,
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
    required this.game,
    this.line,
    this.injuries,
  });
  final PricedSide side;
  final PricedMarket market;
  final OddsBoard board;
  final DateTime now;
  final Set<String>? books;
  final GameSummary game;
  final CoachLine? line;
  final InjuryReport? injuries;

  @override
  State<_SideRow> createState() => _SideRowState();
}

class _SideRowState extends State<_SideRow> {
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
    final other = _otherSide(widget.market, widget.side);
    final chance = _ourChance(widget.line, widget.side.selection);
    final verdict = judgeValue(
      ValueInput(
        label: widget.side.selection.label,
        ourChance: chance,
        decimal: best?.decimal,
        otherDecimal: best == null || other == null
            ? null
            : _priceAt(widget.board, other, best.bookId),
        consensusFair: widget.side.fairProbability,
        source: "Coach's Line",
        modelUnproven: chance != null,
      ),
    );
    final sharp = pinnacleFairChance(
      widget.board,
      widget.side.selection,
      other,
      widget.now,
    );
    final alternative = suggestAlternative(
      current: verdict,
      sameLine: [
        for (final row in ladder)
          if (best == null || row.quote.bookId != best.bookId)
            ValueInput(
              label: '${row.quote.book} ${widget.side.selection.label}',
              ourChance: chance,
              decimal: row.quote.decimal,
              otherDecimal: other == null
                  ? null
                  : _priceAt(widget.board, other, row.quote.bookId),
              consensusFair: widget.side.fairProbability,
              source: "Coach's Line",
              modelUnproven: chance != null,
            ),
      ],
      altLines: const [],
      otherLegs: [
        for (final side in widget.market.sides)
          if (side.selection.key != widget.side.selection.key &&
              side.best != null)
            ValueInput(
              label: side.selection.label,
              ourChance: _ourChance(widget.line, side.selection),
              decimal: side.best!.decimal,
              consensusFair: side.fairProbability,
              source: "Coach's Line",
              modelUnproven: _ourChance(widget.line, side.selection) != null,
            ),
      ],
    );
    final shown = alternative == null
        ? verdict
        : ValueVerdict(
            word: verdict.word,
            why: '${verdict.why} $alternative',
            math: verdict.math,
            ourChance: verdict.ourChance,
            fairChance: verdict.fairChance,
            breakEven: verdict.breakEven,
            expectedValue: verdict.expectedValue,
            alternative: alternative,
            overpriced: verdict.overpriced,
          );
    final event = widget.game.event;
    final brief = buildSideBrief(
      verdict: shown,
      modelUnproven: chance != null,
      injuryText: gameInjuryText(widget.injuries, event.away, event.home),
      scriptText: _sideScript(widget.game, widget.side),
      sharpLine: sharpText(sharp),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ValueView(
        verdict: shown,
        caption: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(widget.side.selection.label, style: EdgeType.body),
            Text(
              best == null
                  ? 'No open price'
                  : '${best.book} ${americanLabel(best.decimal)} · ${priceAge(best.sourceAt, widget.now)}',
              style: EdgeType.label,
            ),
          ],
        ),
        whyBody: WhyBriefView(brief: brief),
        extraMath: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              sharp == null
                  ? 'Pinnacle is not in this snapshot for this side. The fee-free chance is the books that are here.'
                  : 'Pinnacle\'s fee-free chance is ${percentLabel(sharp)}. That is the sharp book\'s number for the spread or total, not a pick.',
              style: EdgeType.body,
            ),
            const SizedBox(height: 8),
            for (final row in ladder)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${row.quote.book}  ${americanLabel(row.quote.decimal)}'
                  '${row.expectedProfit == null ? '' : '  ${signedPercent(row.expectedProfit!)} if the fee-free chance is right'}'
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
        ),
      ),
    );
  }
}

Selection? _otherSide(PricedMarket market, PricedSide side) {
  for (final item in market.sides) {
    if (item.selection.key != side.selection.key) return item.selection;
  }
  return null;
}

double? _priceAt(OddsBoard board, Selection selection, String bookId) {
  for (final quote in board.quotes) {
    if (quote.bookId != bookId || quote.selection.key != selection.key) {
      continue;
    }
    return quote.decimal;
  }
  return null;
}

double? _ourChance(CoachLine? line, Selection selection) {
  if (line == null) return null;
  if (selection.market == 'spreads') {
    if (selection.outcome == line.event.home) return line.homeCoverProbability;
    if (selection.outcome == line.event.away &&
        line.homeCoverProbability != null) {
      return 1 - line.homeCoverProbability!;
    }
  }
  if (selection.market == 'totals') {
    if (selection.outcome == 'Over') return line.overProbability;
    if (selection.outcome == 'Under' && line.overProbability != null) {
      return 1 - line.overProbability!;
    }
  }
  return null;
}

String _sideScript(GameSummary game, PricedSide side) {
  double? total;
  double? homeSpread;
  for (final market in game.markets) {
    for (final item in market.sides) {
      if (market.market == 'totals' && item.selection.outcome == 'Over') {
        total ??= item.selection.point;
      }
      if (market.market == 'spreads' &&
          item.selection.outcome == game.event.home) {
        homeSpread ??= item.selection.point;
      }
    }
  }
  final selection = side.selection;
  var team = game.event.home;
  var spread = homeSpread;
  if (selection.market == 'spreads' || selection.market == 'h2h') {
    team = selection.outcome;
    if (selection.market == 'spreads') {
      spread = selection.point;
    } else if (team == game.event.away && homeSpread != null) {
      spread = -homeSpread;
    }
  }
  return scriptBrief(
    teamName: clubNickname(canonicalTeam(team) ?? team),
    teamSpread: spread,
    total: selection.market == 'totals' ? selection.point ?? total : total,
    market: selection.market,
  );
}
