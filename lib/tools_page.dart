import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/research_store.dart';
import 'domain/hit_rate.dart';
import 'domain/market_math.dart';
import 'domain/odds.dart';
import 'domain/player_stats.dart';
import 'explained_number.dart';
import 'theme/edge_theme.dart';

enum ToolId { prices, hedges, movement, parlay, stake, props }

class ToolsPage extends StatefulWidget {
  const ToolsPage({
    super.key,
    required this.board,
    required this.now,
    required this.store,
    required this.history,
    required this.stamp,
    this.enabledBooks,
    this.backendConnected = false,
    this.loadPlayers,
    this.onOpenParlays,
  });

  final OddsBoard board;
  final DateTime now;
  final Set<String>? enabledBooks;
  final bool backendConnected;
  final ResearchStore store;
  final Future<List<OddsQuote>> Function(Selection selection) history;
  final String Function(DateTime time) stamp;
  final Future<PlayerStatsDataset> Function()? loadPlayers;
  final VoidCallback? onOpenParlays;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  ToolId? tool;

  MarketScan get scan =>
      scanMarkets(widget.board, widget.now, books: widget.enabledBooks);

  @override
  Widget build(BuildContext context) {
    final current = tool;
    if (current == null) return _home();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => tool = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('All tools'),
        ),
        const SizedBox(height: 8),
        switch (current) {
          ToolId.prices => _PriceScreen(scan: scan, stamp: widget.stamp),
          ToolId.hedges => _HedgeScreen(scan: scan, stamp: widget.stamp),
          ToolId.movement => _MovementScreen(
            board: widget.board,
            now: widget.now,
            books: widget.enabledBooks,
            backendConnected: widget.backendConnected,
            history: widget.history,
            stamp: widget.stamp,
          ),
          ToolId.parlay => const _ParlayScreen(),
          ToolId.stake => const _StakeScreen(),
          ToolId.props => _PropHistoryScreen(
            loadPlayers: widget.loadPlayers ?? _loadBundledPlayers,
          ),
        },
      ],
    );
  }

  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Tools', style: EdgeType.title),
      const SizedBox(height: 8),
      const Text(
        'Check a price. The math stays one tap away.',
        style: EdgeType.body,
      ),
      const SizedBox(height: 8),
      const ToolNote(
        'Each tool uses odds already saved, stats already on this device, or numbers you type. Nothing here is a live stream or a recommendation.',
      ),
      const SizedBox(height: 18),
      if (widget.onOpenParlays != null) ...[
        OutlinedButton.icon(
          key: const Key('open-parlay-builder'),
          onPressed: widget.onOpenParlays,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Parlay builder'),
        ),
        const SizedBox(height: 16),
      ],
      _link(
        ToolId.prices,
        'Best price',
        'The best number in this snapshot, the sportsbook fee, and the vig-free market.',
        Icons.sell_outlined,
      ),
      _link(
        ToolId.hedges,
        'Arbitrage and middles',
        'When two prices cover both sides, or leave a window where both can win.',
        Icons.swap_horiz,
      ),
      _link(
        ToolId.movement,
        'Line movement',
        'How a price changed across snapshots this computer already saved.',
        Icons.timeline,
      ),
      _link(
        ToolId.parlay,
        'Parlay price',
        'What a multi-leg ticket pays, and a fair price when the legs are separate games.',
        Icons.account_tree_outlined,
      ),
      _link(
        ToolId.stake,
        'Stake size',
        'A Kelly stake from a win chance you supply. Not a suggestion to bet.',
        Icons.pie_chart_outline,
      ),
      _link(
        ToolId.props,
        'Prop history',
        'How often a recorded stat cleared a line: last 5, last 10, last 20, the season, and one opponent.',
        Icons.bar_chart,
      ),
    ],
  );

  Widget _link(ToolId id, String title, String subtitle, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: ListTile(
            leading: Icon(icon, color: EdgeColors.accent),
            title: Text(
              title,
              style: EdgeType.body.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(subtitle, style: EdgeType.label),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => tool = id),
          ),
        ),
      );
}

class _PriceScreen extends StatefulWidget {
  const _PriceScreen({required this.scan, required this.stamp});
  final MarketScan scan;
  final String Function(DateTime time) stamp;

  @override
  State<_PriceScreen> createState() => _PriceScreenState();
}

class _PriceScreenState extends State<_PriceScreen> {
  MarketSort sort = MarketSort.comparison;

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final markets = sortPricedMarkets(scan.markets, sort);
    final longer = markets.where((market) => (market.bestMarketEv ?? 0) > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Best price'),
        _snapshotBanner(scan, widget.stamp),
        const SizedBox(height: 8),
        if (markets.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                scan.emptyReason ?? 'No usable prices in this snapshot.',
              ),
            ),
          )
        else ...[
          Text(
            longer.isEmpty
                ? 'No price in this snapshot is longer than the vig-free market.'
                : '${longer.length} ${longer.length == 1 ? 'price is' : 'prices are'} longer than the vig-free market. That is a comparison with other books, not a prediction.',
          ),
          const SizedBox(height: 8),
          const ToolNote(
            'The vig-free chance removes the sportsbook fee from every book that posted all sides, then averages those books. Tap any figure for the plain-language meaning.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MarketSort>(
            key: ValueKey(sort),
            initialValue: sort,
            decoration: const InputDecoration(labelText: 'Order'),
            items: const [
              DropdownMenuItem(
                value: MarketSort.comparison,
                child: Text('Market comparison'),
              ),
              DropdownMenuItem(
                value: MarketSort.lowestFee,
                child: Text('Lowest fee'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => sort = value);
            },
          ),
          const SizedBox(height: 16),
          for (final market in markets) ...[
            _marketCard(market),
            const SizedBox(height: 12),
          ],
        ],
        const ResponsibleLine(),
      ],
    );
  }

  Widget _marketCard(PricedMarket market) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(market.matchup, style: EdgeType.label),
          const SizedBox(height: 6),
          Text(market.detail, style: EdgeType.title),
          if ((market.bestMarketEv ?? 0) > 0)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Longer than the vig-free market',
                style: TextStyle(color: EdgeColors.good),
              ),
            ),
          const SizedBox(height: 12),
          for (final side in market.sides) ...[
            Text(
              side.selection.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              side.best == null
                  ? 'No open price in this snapshot.'
                  : 'Best in this snapshot: ${americanLabel(side.best!.decimal)} at ${side.best!.book}',
            ),
            if (side.fairProbability != null)
              ExplainedValue(
                value:
                    'Vig-free chance ${(side.fairProbability! * 100).toStringAsFixed(1)}% · fair price ${_fairAmerican(side.fairProbability!)}',
                title: 'Vig-free chance',
                body: 'Each book’s prices are turned into chances, the sportsbook fee is taken off in proportion, and those fee-free chances are averaged. This is the market’s price with the fee removed. It is not a prediction that the side wins.',
              ),
            if (side.marketEv != null)
              ExplainedValue(
                value:
                    'Versus that market: ${_signedPercent(side.marketEv!)} per \$1',
                title: 'Market comparison',
                body: 'If the vig-free chance were right, this is the average profit per \$1 staked at the best snapshot price. A positive number means the sportsbook price is longer than that market chance. It is not a recommendation and not a promise the bet wins. A tie or a push is not included: anything except a win is treated as a loss.',
                style: TextStyle(
                  color: side.marketEv! > 0 ? EdgeColors.good : EdgeColors.bad,
                ),
              ),
            if (side.sharpEv != null)
              ExplainedValue(
                value:
                    'Versus ${market.sharpLabel}: ${_signedPercent(side.sharpEv!)} per \$1',
                title: 'Sharp-book comparison',
                body:
                    'The same comparison, using only ${market.sharpLabel}. A sharp book is a reference price such as Pinnacle. It is still not a prediction.',
              ),
            const SizedBox(height: 10),
          ],
          if (!market.complete)
            const ToolNote(
              'One side is missing, so the fee and the vig-free price are not calculated.',
            )
          else ...[
            if (market.bestHold != null)
              ExplainedValue(
                value:
                    'Fee at the best prices: ${_signedPercent(market.bestHold!)}',
                title: 'Sportsbook fee',
                body: 'The fee, or hold, is the extra probability built into the prices. A 4.5% fee means the two sides add up to 104.5% instead of 100%. Lower is a cheaper market. A negative fee means the best prices add up to less than 100%. That is the arbitrage case, and it still depends on both bets being accepted.',
              ),
            if (market.typicalHold != null)
              ExplainedValue(
                value:
                    'Typical book fee: ${_signedPercent(market.typicalHold!)} · ${market.booksAveraged} ${market.booksAveraged == 1 ? 'book' : 'books'} averaged',
                title: 'Typical book fee',
                body: 'The middle fee among books that posted every side. One unusually long price does not set this number.',
              ),
          ],
          if (market.sharpLabel == null && market.complete)
            const ToolNote(
              'No sharp book in this snapshot. The free US book list does not include Pinnacle, Circa, Bookmaker, BetCRIS, or LowVig, so no substitute is used.',
            ),
          if (market.removalMethodsDisagree)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: ToolNote(
                'Taking the fee off in equal slices would move a win chance by more than 1 percentage point. The figure shown splits the fee in proportion to each price.',
              ),
            ),
          if (market.tieNotPriced && market.complete)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: ToolNote(
                'No draw price is in this snapshot. A tie is not part of this fee or this fair chance.',
              ),
            ),
          if (market.wholeNumberLine)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: ToolNote(
                'This is a whole-number line. It can push. A push is not in the profit figure.',
              ),
            ),
          if (market.rulesUnverified)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: ToolNote(unverifiedRulesNote),
            ),
        ],
      ),
    ),
  );
}

class _HedgeScreen extends StatelessWidget {
  const _HedgeScreen({required this.scan, required this.stamp});
  final MarketScan scan;
  final String Function(DateTime time) stamp;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Arbitrage and middles'),
      _snapshotBanner(scan, stamp),
      const SizedBox(height: 12),
      const Text(
        'Arbitrage',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      const ToolNote(
        'An arbitrage is a pair of prices that cover every listed result with a little left over. It is not a locked profit. Both bets have to be accepted, at these prices, with the same rules.',
      ),
      const SizedBox(height: 12),
      if (scan.markets.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              scan.emptyReason ?? 'No usable prices in this snapshot.',
            ),
          ),
        )
      else if (scan.arbitrage.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No arbitrage in this snapshot. The best prices still include a sportsbook fee.',
            ),
          ),
        ),
      for (final opportunity in scan.arbitrage) ...[
        _arbCard(opportunity),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 12),
      const Text(
        'Middles',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      const ToolNote(
        'A middle is two different numbers. There is a window where both bets win. Outside that window, one bet wins and the other loses, unless a whole-number line pushes and the stake comes back. You are not paid both ways for certain.',
      ),
      const SizedBox(height: 12),
      if (scan.markets.isEmpty)
        const SizedBox.shrink()
      else if (scan.middles.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No middle in this snapshot. A middle needs two different numbers, such as +3.5 on one side and −2.5 on the other.',
            ),
          ),
        ),
      for (final middle in scan.middles) ...[
        _middleCard(middle),
        const SizedBox(height: 12),
      ],
      const ResponsibleLine(),
    ],
  );

  Widget _arbCard(ArbitrageOpportunity opportunity) {
    final returned = 100 * (1 + opportunity.roi);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              opportunity.matchup,
              style: const TextStyle(color: Colors.white54),
            ),
            Text(
              opportunity.detail,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final leg in opportunity.legs)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '\$${(leg.share * 100).toStringAsFixed(2)} of every \$100 on ${leg.quote.selection.label} at ${americanLabel(leg.quote.decimal)} · ${leg.quote.book}',
                ),
              ),
            ExplainedValue(
              value:
                  'If both were accepted, \$100 would return about \$${returned.toStringAsFixed(2)} either way (${_signedPercent(opportunity.roi)}).',
              title: 'Arbitrage return',
              body: 'The stakes are sized so each listed result returns the same amount. The percentage is the leftover divided by the combined stake. It disappears if either bet is rejected, the line moves, or the rules do not match. A snapshot is not a live offer.',
            ),
            if (opportunity.sameBook)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Both prices are at ${opportunity.legs.first.quote.book}. One book can refuse the second bet.',
                ),
              ),
            if (opportunity.tieNotPriced)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: ToolNote(
                  'This moneyline has no draw price. A tie can refund the bets or leave a side unpaid, depending on the house rules.',
                ),
              ),
            if (opportunity.wholeNumberLine)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: ToolNote(
                  'A whole-number line can push. A push returns that stake, so the pictured return does not happen.',
                ),
              ),
            if (opportunity.rulesUnverified)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: ToolNote(unverifiedRulesNote),
              ),
          ],
        ),
      ),
    );
  }

  Widget _middleCard(MiddleOpportunity middle) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(middle.matchup, style: const TextStyle(color: Colors.white54)),
          Text(
            middle.market,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '${middle.first.selection.label} at ${americanLabel(middle.first.decimal)} · ${middle.first.book}',
          ),
          Text(
            '${middle.second.selection.label} at ${americanLabel(middle.second.decimal)} · ${middle.second.book}',
          ),
          const SizedBox(height: 8),
          ExplainedValue(
            value: middle.window,
            title: 'Middle window',
            body: middleWindowExplanation(middle),
          ),
          const SizedBox(height: 8),
          Text(middlePayoffSummary(middle)),
          if (middle.pushPossible)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: ToolNote(
                'A whole-number line can push. A push returns that stake instead of winning or losing it.',
              ),
            ),
          if (middle.rulesUnverified)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: ToolNote(unverifiedRulesNote),
            ),
        ],
      ),
    ),
  );
}

class _MovementScreen extends StatefulWidget {
  const _MovementScreen({
    required this.board,
    required this.now,
    required this.books,
    required this.backendConnected,
    required this.history,
    required this.stamp,
  });

  final OddsBoard board;
  final DateTime now;
  final Set<String>? books;
  final bool backendConnected;
  final Future<List<OddsQuote>> Function(Selection selection) history;
  final String Function(DateTime time) stamp;

  @override
  State<_MovementScreen> createState() => _MovementScreenState();
}

class _MovementScreenState extends State<_MovementScreen> {
  String? selectionKey;
  Future<List<BookLineMove>>? moves;

  List<Selection> get selections {
    final quotes = usableSnapshotQuotes(
      widget.board.quotes,
      widget.now,
      books: widget.books,
      events: widget.board.events,
      fetchedAt: widget.board.fetchedAt,
    );
    final byKey = <String, Selection>{};
    for (final quote in quotes) {
      byKey[quote.selection.key] = quote.selection;
    }
    final values = byKey.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final options = selections;
    final selected = options.where((s) => s.key == selectionKey).firstOrNull;
    final event = selected == null
        ? null
        : widget.board.events
              .where((e) => e.id == selected.eventId)
              .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Line movement'),
        Text(
          'Snapshot on screen: ${widget.stamp(widget.board.fetchedAt)}. Not a live stream.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const ToolNote(
          'Movement is the difference between snapshots this computer has already saved. The first saved price is not the opening line. The latest saved price is not the closing line. Opening this screen does not request new odds.',
        ),
        const SizedBox(height: 16),
        if (!widget.backendConnected)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Connect the local backend to read saved snapshots. Demonstration mode is one sample, so there is no earlier price to compare.',
              ),
            ),
          )
        else if (options.isEmpty)
          Text(
            snapshotEmptyReason(
                  widget.board,
                  widget.now,
                  books: widget.books,
                ) ??
                'No open selections in this snapshot.',
          )
        else ...[
          DropdownButtonFormField<String>(
            key: ValueKey('move-${selected?.key}-${options.length}'),
            initialValue: selected?.key ?? options.first.key,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Selection'),
            items: [
              for (final selection in options)
                DropdownMenuItem(
                  value: selection.key,
                  child: Text(selection.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() {
              selectionKey = value;
              moves = null;
            }),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final selection = options
                  .where((s) => s.key == (selectionKey ?? options.first.key))
                  .first;
              setState(() => moves = widget.history(selection).then(lineMoves));
            },
            child: const Text('Show saved snapshots'),
          ),
          const SizedBox(height: 16),
          if (event != null)
            Text(
              '${event.away} at ${event.home}',
              style: const TextStyle(color: Colors.white54),
            ),
          if (moves != null)
            FutureBuilder<List<BookLineMove>>(
              future: moves,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Saved snapshots could not be read. No replacement history was created.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  );
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'No stored observations for this selection yet. The next scheduled snapshot can be compared with this one.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final row in rows)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.book,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ExplainedValue(
                                value: row.samples < 2
                                    ? 'One saved snapshot: ${americanLabel(row.latestDecimal)}'
                                    : '${americanLabel(row.firstDecimal)} on ${widget.stamp(row.firstAt)} → ${americanLabel(row.latestDecimal)} on ${widget.stamp(row.latestAt)}',
                                title: 'Saved price change',
                                body:
                                    'A shorter price means this side became more expensive at that book. A longer price means it became cheaper. ${row.samples} saved ${row.samples == 1 ? 'snapshot' : 'snapshots'}. None of these times is automatically the open or the close.',
                              ),
                              if (row.samples > 1) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 56,
                                  width: double.infinity,
                                  child: CustomPaint(
                                    painter: _MovePainter(
                                      row.firstDecimal,
                                      row.latestDecimal,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ],
    );
  }
}

class _MovePainter extends CustomPainter {
  _MovePainter(this.first, this.latest);
  final double first, latest;
  @override
  void paint(Canvas canvas, Size size) {
    final low = math.min(first, latest);
    final high = math.max(first, latest);
    double y(double value) => high == low
        ? size.height / 2
        : size.height - 8 - (value - low) / (high - low) * (size.height - 16);
    final paint = Paint()
      ..color = toolMint
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(8, y(first)),
      Offset(size.width - 8, y(latest)),
      paint,
    );
    canvas.drawCircle(Offset(8, y(first)), 4, Paint()..color = toolMint);
    canvas.drawCircle(
      Offset(size.width - 8, y(latest)),
      4,
      Paint()..color = toolMint,
    );
  }

  @override
  bool shouldRepaint(covariant _MovePainter oldDelegate) =>
      oldDelegate.first != first || oldDelegate.latest != latest;
}

class _ParlayScreen extends StatefulWidget {
  const _ParlayScreen();
  @override
  State<_ParlayScreen> createState() => _ParlayScreenState();
}

class _LegFields {
  _LegFields()
    : label = TextEditingController(text: 'Leg'),
      odds = TextEditingController(text: '-110'),
      chance = TextEditingController();
  final TextEditingController label, odds, chance;
  void dispose() {
    label.dispose();
    odds.dispose();
    chance.dispose();
  }
}

class _ParlayScreenState extends State<_ParlayScreen> {
  final legs = [_LegFields(), _LegFields()];
  final ticket = TextEditingController();
  final joint = TextEditingController();
  bool sameGame = false;

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final leg in legs) {
      leg.dispose();
    }
    ticket.dispose();
    joint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? problem;
    ParlayPrice? price;
    try {
      final inputs = <ParlayLegInput>[];
      for (final leg in legs) {
        final decimal = _american(leg.odds.text);
        if (decimal == null) {
          throw ArgumentError(
            'Enter American odds of +100 or longer, or −100 or shorter, for every leg.',
          );
        }
        final chance = _percent(leg.chance.text);
        inputs.add(
          ParlayLegInput(
            label: leg.label.text.trim().isEmpty
                ? 'Leg'
                : leg.label.text.trim(),
            decimal: decimal,
            winProbability: chance,
          ),
        );
      }
      price = priceParlay(
        legs: inputs,
        sameGame: sameGame,
        jointWinProbability: sameGame ? _percent(joint.text) : null,
        offeredDecimal: _american(ticket.text),
      );
    } on ArgumentError catch (error) {
      problem = error.message?.toString();
    } catch (_) {
      problem = 'Check the odds and the win chances.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Parlay price'),
        const ToolNote(
          'Multiply the leg prices to see the unrelated-events ticket. A same-game ticket is priced differently because the legs move together, so this screen will not pretend that multiplying win chances is a same-game fair price.',
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < legs.length; i++) ...[
          Text(
            'Leg ${i + 1}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _fields(context, [
            _box(
              'Description',
              legs[i].label,
              numeric: false,
              onChanged: _refresh,
            ),
            _box('American odds', legs[i].odds, onChanged: _refresh),
            _box(
              'Win chance % (optional)',
              legs[i].chance,
              onChanged: _refresh,
            ),
          ]),
          if (legs.length > 2)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  final removed = legs.removeAt(i);
                  setState(() {});
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => removed.dispose(),
                  );
                },
                child: const Text('Remove leg'),
              ),
            ),
          const SizedBox(height: 8),
        ],
        TextButton.icon(
          onPressed: () => setState(
            () => legs.add(_LegFields()..label.text = 'Leg ${legs.length + 1}'),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add a leg'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('These legs are in the same game'),
          subtitle: const Text(
            'Turn this on for a same-game parlay. The fair price then comes only from a win chance you type for the whole ticket.',
          ),
          value: sameGame,
          onChanged: (value) => setState(() => sameGame = value),
        ),
        _fields(context, [
          _box(
            'Sportsbook ticket price, American (optional)',
            ticket,
            onChanged: _refresh,
          ),
          if (sameGame)
            _box(
              'Your chance the whole ticket wins %',
              joint,
              onChanged: _refresh,
            ),
        ]),
        const SizedBox(height: 16),
        if (problem != null)
          Text(problem, style: const TextStyle(color: Colors.orangeAccent))
        else if (price != null)
          _parlayResult(price),
        const SizedBox(height: 16),
        const ResponsibleLine(),
      ],
    );
  }

  Widget _parlayResult(ParlayPrice price) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExplainedValue(
            value:
                'Multiplying the leg prices: ${americanLabel(price.multipliedDecimal)}',
            title: 'Multiplied ticket price',
            body: 'This is the leg prices multiplied together. Use it when each leg is a separate bet at its own price. A same-game parlay is usually offered as one different price. Type that price above if you have it.',
            style: const TextStyle(fontSize: 18, color: toolMint),
          ),
          if (price.usesTypedTicketPrice)
            Text(
              'Using the ticket price you typed: ${americanLabel(price.offeredDecimal)}',
            ),
          const SizedBox(height: 8),
          Text(
            'Break-even chance at the price used below: ${(100 / price.offeredDecimal).toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 8),
          if (price.basis == 'unavailable')
            Text(
              sameGame
                  ? 'Fair price unavailable. Same-game legs are related, so the win chances are not multiplied. Type one chance for the whole ticket if you want a what-if.'
                  : 'Fair price unavailable until every leg has a win chance. Those chances are yours, not a model.',
            )
          else ...[
            ExplainedValue(
              value:
                  'Fair price: ${americanLabel(price.fairDecimal!)} · ${_signedPercent(price.expectedValuePerUnit!)} per \$1',
              title: 'Parlay fair price',
              body: price.basis == 'unrelated-legs'
                  ? 'The fair price multiplies the win chances you typed. That is right only when the legs do not affect each other. The profit figure uses that assumption and the ticket price. It is not a recommendation.'
                  : 'This fair price uses the single win chance you typed for the whole ticket. It is your assumption. The app does not have a same-game model, and it does not multiply related chances.',
            ),
          ],
        ],
      ),
    ),
  );
}

class _StakeScreen extends StatefulWidget {
  const _StakeScreen();
  @override
  State<_StakeScreen> createState() => _StakeScreenState();
}

class _StakeScreenState extends State<_StakeScreen> {
  final odds = TextEditingController(text: '-110');
  final chance = TextEditingController(text: '55');
  final push = TextEditingController(text: '0');
  final bankroll = TextEditingController(text: '1000');

  @override
  void dispose() {
    odds.dispose();
    chance.dispose();
    push.dispose();
    bankroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? problem;
    StakeSuggestion? stake;
    double? bank;
    try {
      final decimal = _american(odds.text);
      final win = _percent(chance.text);
      final tie = _percent(push.text) ?? 0;
      if (decimal == null || win == null || win >= 1) {
        throw ArgumentError(
          'Enter American odds and a win chance greater than 0 and less than 100.',
        );
      }
      final amount = double.tryParse(bankroll.text.trim());
      if (amount != null && (!amount.isFinite || amount < 0)) {
        throw ArgumentError('Bankroll cannot be negative.');
      }
      bank = amount;
      stake = kellyStake(decimal: decimal, win: win, push: tie);
    } on ArgumentError catch (error) {
      problem = error.message?.toString();
    } catch (_) {
      problem =
          'Check the odds and the chances. They must add up to 100% or less.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Stake size'),
        const ToolNote(
          'Kelly is a stake that grows a bankroll fastest when the win chance is right. When the chance is wrong, full Kelly is too big. The win chance below is one you typed. This app does not know the true chance.',
        ),
        const SizedBox(height: 16),
        _fields(context, [
          _box('American odds', odds, onChanged: () => setState(() {})),
          _box('Win chance %', chance, onChanged: () => setState(() {})),
          _box('Push chance %', push, onChanged: () => setState(() {})),
          _box('Bankroll', bankroll, onChanged: () => setState(() {})),
        ]),
        const SizedBox(height: 16),
        if (problem != null)
          Text(problem, style: const TextStyle(color: Colors.orangeAccent))
        else if (stake != null)
          _stakeResult(stake, bank),
        const SizedBox(height: 16),
        const ResponsibleLine(),
      ],
    );
  }

  Widget _stakeResult(StakeSuggestion stake, double? bank) {
    String line(String name, double fraction) {
      final percent = formatPlainPercent(fraction);
      final units = (fraction / 0.01).toStringAsFixed(2);
      if (bank == null) return '$name: $percent of bankroll · $units units';
      return '$name: ${_money(bank * fraction)} · $percent of bankroll · $units units';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExplainedValue(
              value: stake.edgeIsPositive
                  ? 'At this win chance, the price is ${_signedPercent(stake.expectedValuePerUnit)} per \$1.'
                  : 'At this win chance, the price is not better than break-even, so the stake is \$0.',
              title: 'Kelly stake',
              body: 'Full Kelly uses your win chance, the price, and any push chance. Half and quarter Kelly are smaller on purpose. One unit here means 1% of the bankroll. The stake is a share of the bankroll and stays within it. None of these figures is a recommendation.',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(line('Full Kelly', stake.fraction)),
            Text(line('Half Kelly', stake.half)),
            Text(line('Quarter Kelly', stake.quarter)),
            if (stake.fraction > 0.25)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: ToolNote(
                  'Full Kelly is more than a quarter of the bankroll. That is aggressive when the win chance is uncertain. The quarter-Kelly line is the calmer of the three.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PropHistoryScreen extends StatefulWidget {
  const _PropHistoryScreen({required this.loadPlayers});
  final Future<PlayerStatsDataset> Function() loadPlayers;
  @override
  State<_PropHistoryScreen> createState() => _PropHistoryScreenState();
}

class _PropHistoryScreenState extends State<_PropHistoryScreen> {
  late Future<PlayerStatsDataset> future = widget.loadPlayers();
  final search = TextEditingController();
  final line = TextEditingController();
  final opponent = TextEditingController();
  String? playerId;
  String metric = 'receiving_yards';
  LineSide side = LineSide.over;
  String window = 'Last 5';

  static const metrics = <(String, String)>[
    ('passing_yards', 'Passing yards'),
    ('passing_tds', 'Passing touchdowns'),
    ('rushing_yards', 'Rushing yards'),
    ('rushing_tds', 'Rushing touchdowns'),
    ('receiving_yards', 'Receiving yards'),
    ('receiving_tds', 'Receiving touchdowns'),
    ('receptions', 'Receptions'),
    ('targets', 'Targets'),
  ];

  @override
  void dispose() {
    search.dispose();
    line.dispose();
    opponent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlayerStatsDataset>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Prop history'),
            const Text(
              'The saved statistics could not be loaded. Try again to reopen the local snapshot.',
            ),
            TextButton(
              onPressed: () => setState(() => future = widget.loadPlayers()),
              child: const Text('Try again'),
            ),
          ],
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      return _loaded(snapshot.data!);
    },
  );

  Widget _loaded(PlayerStatsDataset dataset) {
    final players = <String, PlayerGame>{};
    for (final row in dataset.rows) {
      final previous = players[row.playerId];
      if (previous == null || row.date.isAfter(previous.date)) {
        players[row.playerId] = row;
      }
    }
    final query = search.text.trim().toLowerCase();
    final matches = players.values.where((player) {
      if (query.isEmpty) return false;
      return player.name.toLowerCase().contains(query) ||
          player.team.toLowerCase() == query;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
    final selected = playerId == null ? null : players[playerId!];
    final season = (dataset.metadata['currentSeason'] as num?)?.toInt();
    final retrieved = dataset.metadata['retrievedAt']?.toString();
    final parsedLine = double.tryParse(line.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Prop history'),
        ToolNote(
          'Recorded box scores in the bundled snapshot${retrieved == null ? '' : ', retrieved ${retrieved.substring(0, retrieved.length >= 10 ? 10 : retrieved.length)}'}. A past clear rate is a description of those games, not a forecast. Games missing the stat are skipped, not counted as misses.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: search,
          decoration: const InputDecoration(
            labelText: 'Search player or team abbreviation',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        for (final player in matches.take(8))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${player.name} · ${player.team} · ${player.position}'),
            selected: player.playerId == playerId,
            onTap: () => setState(() => playerId = player.playerId),
          ),
        if (matches.length > 8)
          const ToolNote('Keep typing to narrow the list.'),
        if (selected == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Search for a player to see recorded clears.'),
          )
        else ...[
          const SizedBox(height: 8),
          Text(
            selected.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('metric-$metric'),
            initialValue: metric,
            decoration: const InputDecoration(labelText: 'Stat'),
            items: [
              for (final item in metrics)
                DropdownMenuItem(value: item.$1, child: Text(item.$2)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => metric = value);
            },
          ),
          const SizedBox(height: 8),
          _fields(context, [
            _box('Line, such as 64.5', line, onChanged: () => setState(() {})),
            _box(
              'Opponent abbreviation, such as KC',
              opponent,
              numeric: false,
              onChanged: () => setState(() {}),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Over'),
                selected: side == LineSide.over,
                onSelected: (_) => setState(() => side = LineSide.over),
              ),
              ChoiceChip(
                label: const Text('Under'),
                selected: side == LineSide.under,
                onSelected: (_) => setState(() => side = LineSide.under),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (parsedLine == null)
            const Text('Enter a line to count how often the stat cleared it.')
          else
            _rates(dataset, selected, parsedLine, season),
        ],
      ],
    );
  }

  Widget _rates(
    PlayerStatsDataset dataset,
    PlayerGame selected,
    double parsedLine,
    int? season,
  ) {
    final rows = dataset.rows;
    final rates = <HitRate>[
      hitRate(
        label: 'Last 5',
        games: propGames(rows, selected.playerId, limit: 5),
        metric: metric,
        line: parsedLine,
        side: side,
      ),
      hitRate(
        label: 'Last 10',
        games: propGames(rows, selected.playerId, limit: 10),
        metric: metric,
        line: parsedLine,
        side: side,
      ),
      hitRate(
        label: 'Last 20',
        games: propGames(rows, selected.playerId, limit: 20),
        metric: metric,
        line: parsedLine,
        side: side,
      ),
      hitRate(
        label: season == null ? 'Season' : '$season regular season',
        games: propGames(rows, selected.playerId, season: season),
        metric: metric,
        line: parsedLine,
        side: side,
      ),
      if (opponent.text.trim().isEmpty)
        const HitRate(
          label: 'Versus opponent',
          games: 0,
          hits: 0,
          misses: 0,
          pushes: 0,
          missing: 0,
          samples: [],
        )
      else
        hitRate(
          label: 'Versus ${opponent.text.trim().toUpperCase()}',
          games: propGames(rows, selected.playerId, opponent: opponent.text),
          metric: metric,
          line: parsedLine,
          side: side,
        ),
    ];
    final shown =
        rates.where((rate) => rate.label == window).firstOrNull ?? rates.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ToolNote(
          'Last 5, 10, and 20 are the newest recorded regular-season games and can cross seasons. The season row is that season only. Postseason games stay out of these counts.',
        ),
        const SizedBox(height: 8),
        for (final rate in rates)
          ListTile(
            contentPadding: EdgeInsets.zero,
            selected: rate.label == shown.label,
            onTap: () => setState(() => window = rate.label),
            title: ExplainedValue(
              value: _rateSentence(rate),
              title: 'Clear rate',
              body: 'Clears divided by games that recorded this stat. A push ties the line and is not a clear. Games with no recorded value are skipped. Five games are five games, not a prediction of the next one.',
            ),
          ),
        const SizedBox(height: 8),
        Text(shown.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (shown.label == 'Versus opponent' && opponent.text.trim().isEmpty)
          const Text('Type an opponent abbreviation, such as KC.')
        else if (shown.games == 0)
          const Text('No matching regular-season games in this snapshot.')
        else
          for (final sample in shown.samples)
            Text(
              '${sample.game.date.toIso8601String().substring(0, 10)} vs ${sample.game.opponent}: ${sample.value ?? '—'} · ${sample.outcome}',
            ),
      ],
    );
  }

  String _rateSentence(HitRate rate) {
    if (rate.label == 'Versus opponent' && opponent.text.trim().isEmpty) {
      return 'Versus opponent: type an abbreviation';
    }
    if (rate.games == 0) return '${rate.label}: no games in this snapshot';
    if (rate.clearRate == null) {
      return '${rate.label}: ${rate.games} games, stat not recorded';
    }
    return '${rate.label}: ${rate.hits} of ${rate.observed} cleared (${(rate.clearRate! * 100).toStringAsFixed(0)}%) · ${rate.pushes} push · ${rate.missing} missing';
  }
}

class ResponsibleLine extends StatelessWidget {
  const ResponsibleLine({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      responsibleGamblingNote,
      style: EdgeType.label.copyWith(height: 1.45),
    ),
  );
}

Widget _title(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(text, style: EdgeType.title),
);

Widget _snapshotBanner(MarketScan scan, String Function(DateTime) stamp) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Snapshot as of ${stamp(scan.snapshotAt)}. Not a live stream.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (scan.demo)
          const Text(
            'Sample prices. The arithmetic is real; the odds are not.',
            style: TextStyle(color: Colors.white60),
          ),
      ],
    );

Widget _fields(BuildContext context, List<Widget> children) => LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < 700) {
      return Column(
        children: [
          for (final child in children) ...[child, const SizedBox(height: 12)],
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final child in children) SizedBox(width: 240, child: child),
      ],
    );
  },
);

Widget _box(
  String label,
  TextEditingController controller, {
  bool numeric = true,
  VoidCallback? onChanged,
}) => TextField(
  key: ObjectKey(controller),
  controller: controller,
  decoration: InputDecoration(labelText: label),
  keyboardType: numeric
      ? const TextInputType.numberWithOptions(decimal: true, signed: true)
      : TextInputType.text,
  onChanged: onChanged == null ? null : (_) => onChanged(),
);

String _fairAmerican(double probability) {
  if (probability <= 0 || probability >= 1) return 'unavailable';
  return americanLabel(1 / probability);
}

double? _american(String text) {
  if (text.trim().isEmpty) return null;
  final parsed = double.tryParse(text.trim());
  if (parsed == null) return null;
  try {
    return americanToDecimal(parsed);
  } catch (_) {
    return null;
  }
}

double? _percent(String text) {
  if (text.trim().isEmpty) return null;
  final parsed = double.tryParse(text.trim());
  if (parsed == null || !parsed.isFinite) return null;
  return parsed / 100;
}

String formatSignedPercent(double value) {
  if (!value.isFinite) return 'unavailable';
  final tenths = (value * 1000).round();
  if (tenths == 0) return '0.0%';
  final digits = (tenths.abs() / 10).toStringAsFixed(1);
  return tenths > 0 ? '+$digits%' : '-$digits%';
}

String _signedPercent(double value) => formatSignedPercent(value);

/// Stake share of bankroll. No leading plus: a stake is not a signed edge.
String formatPlainPercent(double value) {
  if (!value.isFinite) return 'unavailable';
  final tenths = (value * 1000).round();
  if (tenths == 0) return '0.0%';
  final digits = (tenths.abs() / 10).toStringAsFixed(1);
  return tenths < 0 ? '-$digits%' : '$digits%';
}

String _money(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign\$${value.abs().toStringAsFixed(2)}';
}

Future<PlayerStatsDataset> _loadBundledPlayers() async {
  final json = await rootBundle.loadString('assets/nfl-player-stats.json');
  return compute(_decodePlayers, json);
}

PlayerStatsDataset _decodePlayers(String json) => PlayerStatsDataset.fromJson(
  Map<String, dynamic>.from(jsonDecode(json.replaceFirst('\uFEFF', ''))),
);
