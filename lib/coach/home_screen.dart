import 'package:flutter/material.dart';

import '../data/nfl_assets.dart';
import '../domain/coach_board.dart';
import '../domain/injury_report.dart';
import '../domain/matchup.dart';
import '../domain/nfl_teams.dart';
import '../domain/odds.dart';
import '../domain/parlay_slip.dart';
import '../domain/player_stats.dart';
import '../domain/prop_history.dart';
import '../domain/skip_list.dart';
import '../ui/scan_card.dart';
import '../domain/value_check.dart';
import '../theme/edge_theme.dart';
import '../ui/feed_card.dart';
import '../ui/value_check.dart';
import '../ui/wordmark.dart';
import 'prop_detail_screen.dart';
import 'prop_pricing.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.board,
    required this.now,
    required this.stamp,
    this.games,
    this.enabledBooks,
    this.injuries,
    this.loadPlayers,
    this.loadMatchup,
    this.onOpenGame,
    this.slip,
    this.onSave,
    this.onOpenReport,
    this.onOpenStale,
  });

  /// Prices for the prop feed. In sample mode this is the same board as the games.
  final OddsBoard board;
  final DateTime now;
  final String Function(DateTime time) stamp;

  /// Games to list on the Games segment. Defaults to [board].
  final OddsBoard? games;
  final Set<String>? enabledBooks;
  final InjuryReport? injuries;
  final Future<PlayerStatsDataset> Function()? loadPlayers;
  final Future<MatchupContext> Function()? loadMatchup;
  final ValueChanged<String>? onOpenGame;
  final ParlaySlipController? slip;
  final ValueChanged<PropCardModel>? onSave;
  final VoidCallback? onOpenReport;
  final VoidCallback? onOpenStale;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int segment = 0;
  bool searching = false;
  String query = '';
  PlayerDirectory? directory;
  MatchupContext? matchup;
  String? statsNote;
  final search = TextEditingController();

  OddsBoard get gamesBoard => widget.games ?? widget.board;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await (widget.loadPlayers ?? loadBundledNflPlayers)();
      if (!mounted) return;
      setState(() => directory = PlayerDirectory(data));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => statsNote =
            'Box scores could not be read, so hit rates are left blank.',
      );
    }
    try {
      final context = await (widget.loadMatchup ?? loadBundledMatchup)();
      if (!mounted) return;
      setState(() => matchup = context);
    } catch (_) {
      // A missing matchup file leaves the meter blank. It does not invent a rank.
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = propCards(
      widget.board,
      widget.now,
      books: widget.enabledBooks,
    );
    final shown = showProps(
      cards: cards,
      directory: directory,
      context: matchup,
      board: widget.board,
      now: widget.now,
      injuries: widget.injuries,
    );
    final filtered = _filter(shown);
    final kickoffs = gamesBoard.events.map((event) => event.startsAt);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          key: const Key('home-feed'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            EdgeSegments(
              labels: const ['Value', 'Trending', 'Games', "Don't"],
              index: segment,
              onChanged: (index) => setState(() => segment = index),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    segment == 3
                        ? "Don't"
                        : segment == 2
                        ? 'Games'
                        : segment == 1
                        ? 'Trending hit rates'
                        : slateTitle(kickoffs),
                    style: EdgeType.title.copyWith(
                      fontFamily: EdgeFont.display,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  slateDate(kickoffs),
                  style: EdgeType.label.copyWith(fontSize: 12),
                ),
                IconButton(
                  tooltip: 'Search',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    searching = !searching;
                    if (!searching) {
                      query = '';
                      search.clear();
                    }
                  }),
                  icon: Icon(searching ? Icons.close : Icons.search, size: 20),
                ),
              ],
            ),
            if (widget.board.demo) ...[
              const SizedBox(height: 6),
              const ExamplePill(),
            ],
            Text(
              'Snapshot as of ${widget.stamp(widget.board.fetchedAt)}',
              style: EdgeType.label.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.onOpenReport != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('open-report-card'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 36),
                    alignment: Alignment.centerLeft,
                    foregroundColor: EdgeColors.accent,
                  ),
                  onPressed: widget.onOpenReport,
                  child: const Text('Report card'),
                ),
              ),
            if (searching) ...[
              const SizedBox(height: 8),
              TextField(
                controller: search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Player, team, or stat',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => query = value),
              ),
            ],
            const SizedBox(height: 12),
            if (statsNote != null) ...[
              Text(statsNote!, style: EdgeType.label),
              const SizedBox(height: 8),
            ],
            if (segment == 3)
              ..._dont(shown)
            else if (segment == 2)
              ..._games(shown)
            else
              ..._props(filtered, trending: segment == 1),
            const SizedBox(height: 8),
            Text(
              segment == 3
                  ? 'Comparison, not a pick.'
                  : widget.board.demo
                  ? 'Example data · our chance versus the book\'s fee-free chance · not a pick'
                  : 'Our chance versus the book\'s fee-free chance · not a pick',
              textAlign: TextAlign.center,
              style: EdgeType.label.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: EdgeColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<ShownProp> _filter(List<ShownProp> shown) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return shown;
    return [
      for (final prop in shown)
        if (_haystack(prop).contains(q)) prop,
    ];
  }

  String _haystack(ShownProp prop) {
    final event = prop.card.event;
    return [
      prop.card.player,
      prop.card.marketLabel,
      prop.card.lineLabel,
      prop.windows?.team ?? '',
      event?.away ?? '',
      event?.home ?? '',
    ].join(' ').toLowerCase();
  }

  List<Widget> _props(List<ShownProp> shown, {required bool trending}) {
    final ranked = [...shown];
    if (trending) {
      final withRates = ranked.where((prop) {
        final recent = prop.windows?.last5 ?? prop.windows?.last10;
        return recent != null && recent.observed > 0;
      }).toList();
      if (directory != null && withRates.isEmpty) {
        return const [
          EmptyNote(
            'No recent box scores match the names in this snapshot, so there is no trending list.',
          ),
        ];
      }
      if (directory == null) {
        return const [
          EmptyNote('Hit rates are still loading from the stored box scores.'),
        ];
      }
      withRates.sort(compareByRecent);
      return _cards(withRates);
    }
    if (ranked.isEmpty) {
      return const [
        EmptyNote(
          'No player-prop prices in this snapshot. Hit rates are not invented to fill the list.',
        ),
      ];
    }
    ranked.sort(compareByEdge);
    return _cards(ranked);
  }

  List<Widget> _cards(List<ShownProp> ranked) {
    if (ranked.isEmpty && query.trim().isNotEmpty) {
      return const [EmptyNote('Nothing in this snapshot matches that search.')];
    }
    return [
      for (final prop in ranked) ...[
        FeedPropCard(
          key: ValueKey(prop.card.id),
          shown: prop,
          onOpen: () => _open(prop),
          onSave: widget.onSave == null
              ? null
              : () => widget.onSave!(prop.card),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  List<Widget> _dont(List<ShownProp> shown) {
    final items = skipList(
      board: widget.board,
      now: widget.now,
      prices: [
        for (final prop in shown)
          RatedPrice(
            id: prop.card.id,
            name: prop.card.player,
            market: [
              prop.card.lineLabel,
              prop.card.marketLabel,
            ].where((part) => part.isNotEmpty).join(' · '),
            title: '${prop.card.player} ${prop.card.lineLabel}',
            detail: [
              prop.card.marketLabel,
              if (prop.card.event != null)
                '${prop.card.event!.away} at ${prop.card.event!.home}',
              if (prop.card.best != null) prop.card.best!.book,
              if (prop.card.best != null)
                americanLabel(prop.card.best!.decimal),
            ].join(' · '),
            decimal: prop.card.best?.decimal,
            fair: prop.card.fairProbability,
            hits:
                (prop.windows?.season ??
                        prop.windows?.last10 ??
                        prop.windows?.last20)
                    ?.hits,
            observed:
                (prop.windows?.season ??
                        prop.windows?.last10 ??
                        prop.windows?.last20)
                    ?.observed,
          ),
      ],
      books: widget.enabledBooks,
    );
    final q = query.trim().toLowerCase();
    final filtered = [
      for (final item in items)
        if (q.isEmpty ||
            '${item.title} ${item.detail} ${item.reason}'
                .toLowerCase()
                .contains(q))
          item,
    ];
    return [
      if (widget.onOpenStale != null) ...[
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('open-stale-board'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 36),
              alignment: Alignment.centerLeft,
              foregroundColor: EdgeColors.accent,
            ),
            onPressed: widget.onOpenStale,
            child: const Text('Books behind the market'),
          ),
        ),
      ],
      const SizedBox(height: 8),
      if (filtered.isEmpty)
        const EmptyNote('Nothing here is short of the fee-free chance.')
      else
        for (final item in filtered) ...[
          ScanCard(
            title: item.name,
            meta: item.market,
            line: item.brief,
            detail: item.reason,
            rail: ValueCheck(
              word: ValueWord.skip,
              ourChance: item.fair,
              bookChance: item.breakEven,
              ourLabel: 'Fee-free',
              bookLabel: 'Price needs',
              overpriced: true,
              compact: true,
            ),
          ),
          const SizedBox(height: 8),
        ],
    ];
  }

  List<Widget> _games(List<ShownProp> shown) {
    final q = query.trim().toLowerCase();
    final events = [
      for (final event in gamesBoard.events)
        if (q.isEmpty ||
            '${event.away} ${event.home}'.toLowerCase().contains(q))
          event,
    ];
    if (events.isEmpty) {
      return const [EmptyNote('No games in this snapshot.')];
    }
    return [
      for (final event in events) ...[
        _GameRow(
          event: event,
          props: shown.where((prop) => prop.card.event?.id == event.id).length,
          onTap: widget.onOpenGame == null
              ? null
              : () => widget.onOpenGame!(event.id),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  void _open(ShownProp prop) {
    final cards = propCards(
      widget.board,
      widget.now,
      books: widget.enabledBooks,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PropDetailScreen(
          card: prop.card,
          cards: cards,
          board: widget.board,
          now: widget.now,
          directory: directory,
          context: matchup,
          injuries: widget.injuries,
          slip: widget.slip,
        ),
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.event, required this.props, this.onTap});

  final SportEvent event;
  final int props;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final away = canonicalTeam(event.away) ?? event.away;
    final home = canonicalTeam(event.home) ?? event.home;
    return Material(
      color: EdgeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: EdgeColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$away at $home',
                      style: EdgeType.title.copyWith(
                        fontFamily: EdgeFont.display,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(kickoffLabel(event.startsAt), style: EdgeType.label),
                  ],
                ),
              ),
              Text(
                props == 0
                    ? 'No props'
                    : '$props ${props == 1 ? 'prop' : 'props'}',
                style: EdgeType.label,
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: EdgeColors.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
