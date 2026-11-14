import 'package:flutter/material.dart';

import '../data/nfl_assets.dart';
import '../data/research_store.dart';
import '../domain/coach_board.dart';
import '../domain/history.dart';
import '../domain/injury_report.dart';
import '../domain/matchup.dart';
import '../domain/odds.dart';
import '../domain/parlay_slip.dart';
import '../domain/player_stats.dart';
import '../domain/prop_history.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../ui/feed_card.dart';
import '../ui/wordmark.dart';
import 'coach_widgets.dart';
import 'prop_detail_screen.dart';
import 'prop_pricing.dart';

class PropsScreen extends StatefulWidget {
  const PropsScreen({
    super.key,
    required this.board,
    required this.now,
    required this.store,
    this.loadPlayers,
    this.loadMatchup,
    this.history,
    this.enabledBooks,
    this.injuries,
    this.focusMarket,
    this.slip,
  });

  final OddsBoard board;
  final DateTime now;
  final ResearchStore store;
  final Future<PlayerStatsDataset> Function()? loadPlayers;
  final Future<MatchupContext> Function()? loadMatchup;
  final Future<List<OddsQuote>> Function(Selection selection)? history;
  final InjuryReport? injuries;

  /// When set, the list shows this stat. Used by a link from Injuries.
  final String? focusMarket;
  final Set<String>? enabledBooks;
  final ParlaySlipController? slip;

  @override
  State<PropsScreen> createState() => _PropsScreenState();
}

class _PropsScreenState extends State<PropsScreen> {
  late Future<PlayerDirectory> directory;
  late Future<MatchupContext?> matchup;
  late Future<_PropFacts> facts;
  List<HistoricalGame> scores = const [];
  PropFilter filter = const PropFilter();
  String query = '';
  final search = TextEditingController();
  String? preferenceNote;
  int filterRevision = 0;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    directory = (widget.loadPlayers ?? loadBundledNflPlayers)().then(
      PlayerDirectory.new,
    );
    matchup = _loadMatchup();
    facts = _loadFacts();
    _loadScores();
    final market = widget.focusMarket;
    if (market != null) filter = PropFilter(market: market);
    _restoreFilter();
  }

  Future<void> _restoreFilter() async {
    final revision = filterRevision;
    try {
      final saved = await widget.store.loadPropFilter();
      if (!mounted ||
          revision != filterRevision ||
          widget.focusMarket != null) {
        return;
      }
      if (saved != null) setState(() => filter = saved);
    } catch (_) {
      if (mounted && revision == filterRevision && widget.focusMarket == null) {
        setState(
          () => preferenceNote = 'Saved filters could not be restored. Choose filters for this session.',
        );
      }
    }
  }

  @override
  void didUpdateWidget(PropsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final market = widget.focusMarket;
    if (market != null && market != oldWidget.focusMarket) {
      filterRevision++;
      filter = PropFilter(market: market);
    }
  }

  Future<MatchupContext?> _loadMatchup() async {
    try {
      return await (widget.loadMatchup ?? loadBundledMatchup)();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadScores() async {
    try {
      final games = await loadBundledHistoryGames();
      if (!mounted) return;
      setState(() => scores = games);
    } catch (_) {
      // Earlier scores only move the curve. The list still prices without them.
    }
  }

  Future<_PropFacts> _loadFacts() async {
    final players = await directory;
    final report = await matchup;
    return _PropFacts(players, report, scores);
  }

  @override
  Widget build(BuildContext context) {
    final cards =
        applyPropFilter(
              propCards(widget.board, widget.now, books: widget.enabledBooks),
              filter,
            )
            .where(
              (card) =>
                  query.trim().isEmpty ||
                  '${card.player} ${card.marketLabel} ${card.event?.home ?? ''} ${card.event?.away ?? ''}'
                      .toLowerCase()
                      .contains(query.trim().toLowerCase()),
            )
            .toList();
    return ListView(
      key: const Key('props-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const SectionLabel('PLAYER PROPS'),
        const SizedBox(height: 6),
        if (widget.board.demo) ...[
          const ExamplePill(),
          const SizedBox(height: 8),
        ],
        Text(
          widget.board.demo
              ? 'Example prices. Hit rates are real box scores.'
              : 'Prices are a saved snapshot.',
          style: EdgeType.label,
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: TextField(
            key: const Key('prop-search'),
            controller: search,
            decoration: InputDecoration(
              hintText: 'Search player, team, or stat',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        search.clear();
                        setState(() => query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        if (preferenceNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(preferenceNote!, style: EdgeType.label),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
            label: const Text('Filter and sort'),
          ),
        ),
        const SizedBox(height: 12),
        if (cards.isEmpty &&
            (query.isNotEmpty ||
                filter.market != null ||
                filter.bookId != null ||
                filter.minAmerican != null ||
                filter.maxAmerican != null ||
                filter.onlyLongerThanTheBooks))
          CoachCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('No matches for this search and these filters.'),
                TextButton(
                  onPressed: () {
                    search.clear();
                    setState(() => query = '');
                    _applyFilter(const PropFilter());
                  },
                  child: const Text('Clear search and filters'),
                ),
              ],
            ),
          )
        else if (cards.isEmpty)
          const CoachCard(
            child: Text(
              'No player-prop prices in this snapshot. The free plan asks for passing yards, receptions, rushing yards, and receiving yards on the next game, at most once a day. Until those prices are saved, this list stays empty. Hit rates are not invented to fill it.',
              style: TextStyle(height: 1.4),
            ),
          )
        else
          FutureBuilder<_PropFacts>(
            future: facts,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'The NFL box scores could not be read, so hit rates are left blank.',
                );
              }
              final facts = snapshot.data;
              final shown = preferredPropSides(
                showProps(
                  cards: cards,
                  directory: facts?.players,
                  context: facts?.matchup,
                  board: widget.board,
                  now: widget.now,
                  injuries: widget.injuries,
                  scores: scores,
                ),
              );
              return Column(
                children: [
                  for (final face in shown) ...[
                    FeedPropCard(
                      shown: face,
                      onOpen: () => _open(face.card, facts, cards),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  void _open(PropCardModel card, _PropFacts? facts, List<PropCardModel> cards) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PropDetailScreen(
          card: card,
          cards: cards,
          board: widget.board,
          now: widget.now,
          directory: facts?.players,
          context: facts?.matchup,
          injuries: widget.injuries,
          history: widget.history,
          scores: scores,
          slip: widget.slip,
        ),
      ),
    );
  }

  Future<void> _openFilters() async {
    filterRevision++;
    final cards = propCards(
      widget.board,
      widget.now,
      books: widget.enabledBooks,
    );
    final markets = {for (final card in cards) card.market: card.marketLabel};
    final books = {
      for (final card in cards)
        for (final row in card.bookRows) row.quote.bookId: row.quote.book,
    };
    final next = await showModalBottomSheet<PropFilter>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _FilterSheet(filter: filter, markets: markets, books: books),
    );
    if (next != null && mounted) {
      await _applyFilter(next);
    }
  }

  Future<void> _applyFilter(PropFilter next) async {
    filterRevision++;
    setState(() {
      filter = next;
      preferenceNote = 'Filters remembered on this device.';
    });
    try {
      await widget.store.savePropFilter(next);
    } catch (_) {
      if (mounted) {
        setState(
          () => preferenceNote =
              'Filters applied for this session; they could not be saved.',
        );
      }
    }
  }
}

class _PropFacts {
  const _PropFacts(this.players, this.matchup, this.scores);
  final PlayerDirectory players;
  final MatchupContext? matchup;
  final List<HistoricalGame> scores;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.filter,
    required this.markets,
    required this.books,
  });
  final PropFilter filter;
  final Map<String, String> markets;
  final Map<String, String> books;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? market = widget.filter.market;
  late String? book = widget.filter.bookId;
  late bool onlyEdge = widget.filter.onlyLongerThanTheBooks;
  late PropSort sort = widget.filter.sort;
  late RangeValues odds = RangeValues(
    (widget.filter.minAmerican ?? -250).clamp(-250, 250).toDouble(),
    (widget.filter.maxAmerican ?? 250).clamp(-250, 250).toDouble(),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: true,
      children: [
        const Text(
          'Filter and sort',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const ToolNote(
          'These filters only hide prices already in the snapshot. They do not create a confidence score.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: market,
          decoration: const InputDecoration(labelText: 'Stat'),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('All stats in the snapshot'),
            ),
            if (market != null && !widget.markets.containsKey(market))
              DropdownMenuItem(
                value: market,
                child: const Text('Saved stat (unavailable)'),
              ),
            for (final entry in widget.markets.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) => setState(() => market = value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: book,
          decoration: const InputDecoration(labelText: 'Sportsbook'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any book')),
            if (book != null && !widget.books.containsKey(book))
              DropdownMenuItem(
                value: book,
                child: const Text('Saved book (unavailable)'),
              ),
            for (final entry in widget.books.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) => setState(() => book = value),
        ),
        const SizedBox(height: 12),
        Text('American odds from ${odds.start.round()} to ${odds.end.round()}'),
        RangeSlider(
          min: -250,
          max: 250,
          divisions: 20,
          values: odds,
          labels: RangeLabels('${odds.start.round()}', '${odds.end.round()}'),
          onChanged: (value) => setState(() {
            var start = value.start;
            var end = value.end;
            if (start > -100 && start < 100) start = start < 0 ? -100 : 100;
            if (end > -100 && end < 100) end = end < 0 ? -100 : 100;
            if (start > end) {
              final swap = start;
              start = end;
              end = swap;
            }
            odds = RangeValues(start, end);
          }),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Only prices longer than the fee-free chance'),
          value: onlyEdge,
          onChanged: (value) => setState(() => onlyEdge = value),
        ),
        const Text('Sort'),
        Wrap(
          spacing: 8,
          children: [
            for (final item in PropSort.values)
              FilterPill(
                label: switch (item) {
                  PropSort.expectedProfit => 'Expected profit',
                  PropSort.historyGap => 'History gap',
                  PropSort.price => 'Price',
                  PropSort.line => 'Line',
                },
                selected: sort == item,
                onTap: () => setState(() => sort = item),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final min = odds.start.round();
            final max = odds.end.round();
            Navigator.pop(
              context,
              PropFilter(
                market: market,
                bookId: book,
                minAmerican: min <= -250 ? null : min,
                maxAmerican: max >= 250 ? null : max,
                onlyLongerThanTheBooks: onlyEdge,
                sort: sort,
              ),
            );
          },
          child: const Text('Apply filters'),
        ),
      ],
    ),
  );
}
