import 'package:flutter/material.dart';

import '../data/nfl_assets.dart';
import '../data/research_store.dart';
import '../domain/coach_board.dart';
import '../domain/injury_report.dart';
import '../domain/matchup.dart';
import '../domain/odds.dart';
import '../domain/parlay_slip.dart';
import '../domain/player_stats.dart';
import '../domain/prop_history.dart';
import '../domain/saved_play.dart';
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
  PropFilter filter = const PropFilter();

  @override
  void initState() {
    super.initState();
    directory = (widget.loadPlayers ?? loadBundledNflPlayers)().then(
      PlayerDirectory.new,
    );
    matchup = _loadMatchup();
    final market = widget.focusMarket;
    if (market != null) filter = PropFilter(market: market);
  }

  @override
  void didUpdateWidget(PropsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final market = widget.focusMarket;
    if (market != null && market != oldWidget.focusMarket) {
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

  Future<_PropFacts> _facts() async {
    final players = await directory;
    final report = await matchup;
    return _PropFacts(players, report);
  }

  @override
  Widget build(BuildContext context) {
    final cards = applyPropFilter(
      propCards(widget.board, widget.now, books: widget.enabledBooks),
      filter,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const SectionLabel('PLAYER PROPS'),
        const SizedBox(height: 6),
        if (widget.board.demo) ...[
          const ExamplePill(),
          const SizedBox(height: 8),
        ],
        Text(
          widget.board.demo
              ? 'Sample prices. The hit rates under a matched name are real box scores, not part of the sample.'
              : 'Prices are a saved snapshot. The age is on each card.',
          style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _openFilters(cards),
            icon: const Icon(Icons.tune),
            label: const Text('Filter and sort'),
          ),
        ),
        const SizedBox(height: 12),
        if (cards.isEmpty)
          const CoachCard(
            child: Text(
              'No player-prop prices in this snapshot. The free plan asks for passing yards and receptions on two upcoming games, at most once a day. Until those prices are saved, this list stays empty. Hit rates are not invented to fill it.',
              style: TextStyle(height: 1.4),
            ),
          )
        else
          FutureBuilder<_PropFacts>(
            future: _facts(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'The NFL box scores could not be read, so hit rates are left blank.',
                );
              }
              final facts = snapshot.data;
              return Column(
                children: [
                  for (final card in cards) ...[
                    FeedPropCard(
                      shown: showProp(
                        card: card,
                        cards: cards,
                        directory: facts?.players,
                        context: facts?.matchup,
                        board: widget.board,
                        now: widget.now,
                        injuries: widget.injuries,
                      ),
                      onOpen: () => _open(card, facts, cards),
                      onSave: () => _save(card),
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

  Future<void> _save(PropCardModel card) async {
    final quote = card.best;
    await widget.store.saveSavedPlay(
      SavedPlay(
        id: card.id,
        savedAt: DateTime.now().toUtc(),
        title: '${card.player} ${card.marketLabel} ${card.lineLabel}',
        detail: card.event == null
            ? card.marketLabel
            : '${card.event!.away} at ${card.event!.home}',
        book: quote?.book ?? '',
        decimal: quote?.decimal,
        demo: card.demo || (quote?.demo ?? false),
        priceNote: quote == null
            ? 'No price in the snapshot'
            : priceAge(quote.sourceAt, widget.now),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Saved to My Bets. Double-tap the player\'s name to do the same.',
        ),
      ),
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
          slip: widget.slip,
        ),
      ),
    );
  }

  Future<void> _openFilters(List<PropCardModel> cards) async {
    final markets = {
      for (final card in propCards(widget.board, widget.now))
        card.market: card.marketLabel,
    };
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
    if (next != null) setState(() => filter = next);
  }
}

class _PropFacts {
  const _PropFacts(this.players, this.matchup);
  final PlayerDirectory players;
  final MatchupContext? matchup;
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
    (widget.filter.minAmerican ?? -250).toDouble(),
    (widget.filter.maxAmerican ?? 250).toDouble(),
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
