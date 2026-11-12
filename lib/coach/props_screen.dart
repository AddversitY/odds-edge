import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/research_store.dart';
import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../domain/hit_rate.dart';
import '../domain/matchup.dart';
import '../domain/nfl_teams.dart';
import '../domain/odds.dart';
import '../domain/player_stats.dart';
import '../domain/prop_history.dart';
import '../domain/prop_value.dart';
import '../domain/saved_play.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import 'coach_widgets.dart';
import 'value_view.dart';

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
  });

  final OddsBoard board;
  final DateTime now;
  final ResearchStore store;
  final Future<PlayerStatsDataset> Function()? loadPlayers;
  final Future<MatchupContext> Function()? loadMatchup;
  final Future<List<OddsQuote>> Function(Selection selection)? history;
  final Set<String>? enabledBooks;

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
                    _PropCard(
                      card: card,
                      cards: cards,
                      now: widget.now,
                      board: widget.board,
                      facts: facts,
                      onOpen: () => _open(card, facts, cards),
                      onSave: () => _save(card),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  PropWindows _windows(PlayerDirectory directory, PropCardModel card) =>
      propWindows(directory, card, widget.now);

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
        builder: (_) => _PropDetail(
          card: card,
          cards: cards,
          facts: facts,
          board: widget.board,
          now: widget.now,
          history: widget.history,
          boardNow: widget.now,
          windowsFor: facts == null
              ? null
              : (item) => _windows(facts.players, item),
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

Future<PlayerStatsDataset> loadBundledNflPlayers() async {
  final json = await rootBundle.loadString('assets/nfl-player-stats.json');
  return compute(_decodeNflPlayers, json);
}

PlayerStatsDataset _decodeNflPlayers(String json) =>
    PlayerStatsDataset.fromJson(
      Map<String, dynamic>.from(jsonDecode(json.replaceFirst('\uFEFF', ''))),
    );

Future<MatchupContext> loadBundledMatchup() async {
  final json = await rootBundle.loadString('assets/nfl-matchup.json');
  return compute(_decodeMatchup, json);
}

MatchupContext _decodeMatchup(String json) => MatchupContext.fromJson(
  Map<String, dynamic>.from(jsonDecode(json.replaceFirst('\uFEFF', ''))),
);

class _PropFacts {
  const _PropFacts(this.players, this.matchup);
  final PlayerDirectory players;
  final MatchupContext? matchup;
}

class _PropCard extends StatelessWidget {
  const _PropCard({
    required this.card,
    required this.cards,
    required this.now,
    required this.board,
    required this.facts,
    required this.onOpen,
    required this.onSave,
  });

  final PropCardModel card;
  final List<PropCardModel> cards;
  final DateTime now;
  final OddsBoard board;
  final _PropFacts? facts;
  final VoidCallback onOpen;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final quote = card.best;
    final event = card.event;
    final windows = facts == null
        ? null
        : propWindows(facts!.players, card, now);
    final priced = _priced(facts, windows);
    final gap = historyGap(
      clearRate: windows?.season?.clearRate,
      fairProbability: card.fairProbability,
    );
    final matchup = priced.matchup;
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueView(
            verdict: priced.verdict,
            caption: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onDoubleTap: onSave,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(card.player, style: EdgeType.title)),
                      IconButton(
                        tooltip: 'Save play',
                        onPressed: onSave,
                        icon: const Icon(Icons.bookmark_add_outlined),
                      ),
                    ],
                  ),
                ),
                Text(
                  [
                    if ((windows?.position ?? '').isNotEmpty) windows!.position,
                    if ((windows?.team ?? '').isNotEmpty) windows!.team,
                    if (event != null) '${event.away} at ${event.home}',
                  ].join(' · '),
                  style: EdgeType.label,
                ),
                const SizedBox(height: 8),
                Text(
                  '${card.marketLabel}  ${card.lineLabel}',
                  style: EdgeType.body.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  quote == null
                      ? 'No open price'
                      : '${quote.book} ${americanLabel(quote.decimal)}',
                  style: EdgeType.title,
                ),
              ],
            ),
            extraWhy: matchup == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(matchup.sentence, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.defenseLine, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.injuryLine, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.scriptLine, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.snapLine, style: EdgeType.body),
                        const SizedBox(height: 12),
                        LineChart(
                          samples:
                              windows?.season?.samples ??
                              windows?.last10?.samples ??
                              const [],
                          line: card.line,
                        ),
                      ],
                    ),
                  ),
            extraMath: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                ChanceBar(
                  fraction: card.fairProbability,
                  label: 'Books\' fee-free chance',
                ),
                const SizedBox(height: 12),
                _blocks(quote, gap),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    HitChip(label: 'L5', rate: windows?.last5),
                    HitChip(label: 'L10', rate: windows?.last10),
                    HitChip(label: 'L20', rate: windows?.last20),
                    HitChip(label: 'H2H', rate: windows?.headToHead),
                    HitChip(
                      label: windows?.seasonYear == null
                          ? 'Season'
                          : '${windows!.seasonYear}',
                      rate: windows?.season,
                    ),
                  ],
                ),
                if (matchup != null) ...[
                  const SizedBox(height: 12),
                  Text(matchup.credit, style: EdgeType.label),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onOpen,
              child: const Text('Open this prop'),
            ),
          ),
        ],
      ),
    );
  }

  PropValue _priced(_PropFacts? facts, PropWindows? windows) {
    final players = facts?.players;
    return priceProp(
      card: card,
      cards: cards,
      rateFor: (item) => preferredRate(
        players == null
            ? (item.id == card.id ? windows : null)
            : propWindows(players, item, now),
      ),
      context: facts?.matchup,
      rows: players?.data.rows ?? const [],
      playerTeam: windows?.team,
      position: windows?.position,
      opponent: _opponent(windows),
      teamSpread: _teamSpread(windows),
      total: _total(),
      seasonYear: windows?.seasonYear,
      recent: windows?.last5,
    );
  }

  String? _opponent(PropWindows? windows) {
    final event = card.event;
    final team = windows?.team;
    if (event == null || team == null) return null;
    final away = canonicalTeam(event.away);
    final home = canonicalTeam(event.home);
    final club = boxScoreTeam(team);
    if (club == boxScoreTeam(away ?? '')) return home;
    if (club == boxScoreTeam(home ?? '')) return away;
    return null;
  }

  double? _teamSpread(PropWindows? windows) {
    final event = card.event;
    final team = windows?.team;
    if (event == null || team == null) return null;
    final line = readMarketLine(event, board.quotes);
    final home = line.homeSpread;
    if (home == null) return null;
    final club = boxScoreTeam(team);
    if (club == boxScoreTeam(canonicalTeam(event.home) ?? '')) return home;
    if (club == boxScoreTeam(canonicalTeam(event.away) ?? '')) return -home;
    return null;
  }

  double? _total() {
    final event = card.event;
    if (event == null) return null;
    return readMarketLine(event, board.quotes).total;
  }

  Widget _blocks(OddsQuote? quote, double? gap) {
    final blocks = [
      StatBlock(
        kicker: 'Best price',
        value: quote == null
            ? '—'
            : '${quote.book} ${americanLabel(quote.decimal)}',
        title: 'Best price',
        body: bestPriceExplanation,
        valueColor: quote == null ? null : EdgeColors.accent,
      ),
      StatBlock(
        kicker: 'Price implies',
        value: card.implied == null ? '—' : percentLabel(card.implied!),
        title: 'What the price implies',
        body: impliedChanceExplanation,
      ),
      StatBlock(
        kicker: 'Expected profit',
        value: card.expectedProfit == null
            ? '—'
            : signedPercent(card.expectedProfit!),
        title: 'Expected profit',
        body: expectedProfitExplanation,
        valueColor: card.expectedProfit == null
            ? null
            : (card.expectedProfit! > 0 ? EdgeColors.good : EdgeColors.bad),
      ),
      StatBlock(
        kicker: 'History gap',
        value: gap == null ? '—' : signedPercent(gap),
        title: 'History gap',
        body: historyGapExplanation,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 460) {
          return Column(
            children: [
              Row(children: [blocks[0], const SizedBox(width: 8), blocks[1]]),
              const SizedBox(height: 8),
              Row(children: [blocks[2], const SizedBox(width: 8), blocks[3]]),
            ],
          );
        }
        return Row(
          children: [
            blocks[0],
            const SizedBox(width: 8),
            blocks[1],
            const SizedBox(width: 8),
            blocks[2],
            const SizedBox(width: 8),
            blocks[3],
          ],
        );
      },
    );
  }
}

PropWindows propWindows(
  PlayerDirectory directory,
  PropCardModel card,
  DateTime now,
) {
  final event = card.event;
  String? opponent;
  if (event != null) {
    final away = canonicalTeam(event.away);
    final home = canonicalTeam(event.home);
    final looked = directory.lookup(
      playerName: card.player,
      market: card.market,
      line: card.line,
      side: card.lineSide,
    );
    final team = looked.team;
    if (team != null && boxScoreTeam(team) == boxScoreTeam(away ?? '')) {
      opponent = home;
    } else if (team != null && boxScoreTeam(team) == boxScoreTeam(home ?? '')) {
      opponent = away;
    }
  }
  return directory.lookup(
    playerName: card.player,
    market: card.market,
    line: card.line,
    side: card.lineSide,
    opponent: opponent,
    through: now,
  );
}

class _PropDetail extends StatefulWidget {
  const _PropDetail({
    required this.card,
    required this.cards,
    required this.facts,
    required this.board,
    required this.now,
    required this.history,
    required this.boardNow,
    required this.windowsFor,
  });

  final PropCardModel card;
  final List<PropCardModel> cards;
  final _PropFacts? facts;
  final OddsBoard board;
  final DateTime now;
  final Future<List<OddsQuote>> Function(Selection selection)? history;
  final DateTime boardNow;
  final PropWindows Function(PropCardModel card)? windowsFor;

  @override
  State<_PropDetail> createState() => _PropDetailState();
}

class _PropDetailState extends State<_PropDetail> {
  late PropCardModel card = widget.card;

  @override
  Widget build(BuildContext context) {
    final shown = _rewindow();
    final samples =
        shown?.season?.samples ?? shown?.last10?.samples ?? const <HitSample>[];
    final priced = _priced(shown);
    final matchup = priced.matchup;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prop detail'),
        actions: [
          if (card.otherSide != null)
            TextButton(
              onPressed: _toggle,
              child: Text(card.lineSide == LineSide.over ? 'Under' : 'Over'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            card.player,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          Text(
            '${card.marketLabel} ${card.lineLabel}',
            style: EdgeType.body.copyWith(
              color: EdgeColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ValueView(
            verdict: priced.verdict,
            extraWhy: matchup == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(matchup.sentence, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.defenseLine, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.injuryLine, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.scriptLine, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.snapLine, style: EdgeType.body),
                        const SizedBox(height: 8),
                        Text(matchup.credit, style: EdgeType.label),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          const ToolNote(
            'Over and under use the other side only when that price is in the snapshot.',
          ),
          const SizedBox(height: 12),
          ChanceBar(
            fraction: card.fairProbability,
            label: 'Books\' fee-free chance',
          ),
          const SizedBox(height: 8),
          Text(
            feeFreeChanceExplanation,
            style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const SectionLabel('ODDS OVER TIME'),
          const SizedBox(height: 8),
          if (widget.history == null)
            const Text(
              'Price history is collected by the local backend. It is not available in this view, and no line was drawn to fill the gap.',
              style: TextStyle(color: Colors.white60, height: 1.4),
            )
          else
            FutureBuilder<List<OddsQuote>>(
              future: widget.history!(card.side),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  return const Text(
                    'Saved price history could not be read.',
                    style: TextStyle(color: Colors.white60),
                  );
                }
                return OddsHistoryChart(quotes: snapshot.data ?? const []);
              },
            ),
          const SizedBox(height: 16),
          const SectionLabel('RECORDED GAMES'),
          const SizedBox(height: 8),
          LineChart(samples: samples, line: card.line),
          const SizedBox(height: 16),
          const SectionLabel('BOOKS, BEST PRICE FIRST'),
          const SizedBox(height: 8),
          if (card.bookRows.isEmpty)
            const Text('No open price for this side.')
          else
            for (final row in card.bookRows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row.quote.book),
                subtitle: Text(
                  '${row.quote.demo ? 'Sample' : 'Saved'} · ${priceAge(row.quote.sourceAt, widget.now)}'
                  '${row.expectedProfit == null ? '' : ' · expected profit ${signedPercent(row.expectedProfit!)} if the fee-free chance is right'}',
                ),
                trailing: Text(
                  americanLabel(row.quote.decimal),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          if (shown?.note != null) ...[
            const SizedBox(height: 8),
            Text(
              shown!.note!,
              style: const TextStyle(color: Colors.white54, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  PropWindows? _rewindow() => widget.windowsFor?.call(card);

  PropValue _priced(PropWindows? windows) {
    final players = widget.facts?.players;
    return priceProp(
      card: card,
      cards: widget.cards,
      rateFor: (item) => preferredRate(widget.windowsFor?.call(item)),
      context: widget.facts?.matchup,
      rows: players?.data.rows ?? const [],
      playerTeam: windows?.team,
      position: windows?.position,
      opponent: _opponent(windows),
      teamSpread: _teamSpread(windows),
      total: card.event == null
          ? null
          : readMarketLine(card.event!, widget.board.quotes).total,
      seasonYear: windows?.seasonYear,
      recent: windows?.last5,
    );
  }

  String? _opponent(PropWindows? windows) {
    final event = card.event;
    final team = windows?.team;
    if (event == null || team == null) return null;
    final away = canonicalTeam(event.away);
    final home = canonicalTeam(event.home);
    final club = boxScoreTeam(team);
    if (club == boxScoreTeam(away ?? '')) return home;
    if (club == boxScoreTeam(home ?? '')) return away;
    return null;
  }

  double? _teamSpread(PropWindows? windows) {
    final event = card.event;
    final team = windows?.team;
    if (event == null || team == null) return null;
    final home = readMarketLine(event, widget.board.quotes).homeSpread;
    if (home == null) return null;
    final club = boxScoreTeam(team);
    if (club == boxScoreTeam(canonicalTeam(event.home) ?? '')) return home;
    if (club == boxScoreTeam(canonicalTeam(event.away) ?? '')) return -home;
    return null;
  }

  void _toggle() {
    final other = card.otherSide;
    if (other == null) return;
    final match = widget.cards.where((item) => item.side.key == other.key);
    if (match.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The other side is not in this snapshot, so it was not switched.',
          ),
        ),
      );
      return;
    }
    setState(() => card = match.first);
  }
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
