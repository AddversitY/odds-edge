import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../domain/market_math.dart';
import '../domain/odds.dart';
import '../domain/parlay_value.dart';
import '../domain/value_check.dart';
import '../domain/why_brief.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import 'coach_widgets.dart';
import 'value_view.dart';
import 'why_view.dart';

class ParlaysScreen extends StatefulWidget {
  const ParlaysScreen({
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
  State<ParlaysScreen> createState() => _ParlaysScreenState();
}

class _ParlaysScreenState extends State<ParlaysScreen> {
  ParlayFilter filter = const ParlayFilter();

  @override
  Widget build(BuildContext context) {
    final slate = summarizeSlate(
      widget.board,
      widget.now,
      books: widget.enabledBooks,
      filter: filter,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const SectionLabel('PARLAYS'),
        const SizedBox(height: 8),
        const Text(
          'Each leg is judged on its own, then the ticket is judged together. Legs in different games have their chances multiplied. Legs in the same game move together, so those chances are not just multiplied. A same-game payout says estimated unless you paste the payout from a slip.',
          style: EdgeType.body,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _filters,
            icon: const Icon(Icons.tune),
            label: const Text('How these tickets are built'),
          ),
        ),
        const SizedBox(height: 16),
        if (slate.parlays.isEmpty)
          const CoachCard(
            child: Text(
              'No ticket fits these filters. A cross-game ticket needs the same book to have priced at least two different games.',
              style: EdgeType.body,
            ),
          )
        else
          for (final parlay in slate.parlays) ...[
            _ParlayCard(ticket: _ticketFor(parlay, slate.scan)),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 8),
        const SectionLabel('SAME GAME'),
        const SizedBox(height: 8),
        const Text(
          'Same-game payouts below are estimated. They are not a price a book posted.',
          style: EdgeType.body,
        ),
        const SizedBox(height: 12),
        ..._sameGame(slate.scan),
        const SizedBox(height: 8),
        const ToolNote(responsibleGamblingNote),
      ],
    );
  }

  Future<void> _filters() async {
    final books = <String, String>{};
    for (final quote in widget.board.quotes) {
      books[quote.bookId] = quote.book;
    }
    final next = await showModalBottomSheet<ParlayFilter>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ParlayFilters(filter: filter, books: books),
    );
    if (next != null) setState(() => filter = next);
  }

  TicketValue _ticketFor(ParlaySuggestion parlay, MarketScan scan) {
    final books = _booksBySelection(
      widget.board,
      widget.now,
      widget.enabledBooks,
    );
    return priceTicket(
      [for (final leg in parlay.legs) _legInput(leg, scan, parlay.bookId)],
      booksByLeg: [
        for (final leg in parlay.legs)
          books[leg.quote.selection.key] ?? const [],
      ],
    );
  }

  TicketLegInput _legInput(ParlayLegView leg, MarketScan scan, String bookId) {
    SportEvent? event;
    for (final item in widget.board.events) {
      if (item.id == leg.eventId) event = item;
    }
    final line = event == null
        ? null
        : widget.model?.lineFor(
            event,
            widget.board.quotes,
            settings: widget.settings,
            books: widget.enabledBooks,
          );
    final chance = _modelChance(line, leg.quote.selection);
    final other = _paired(scan, leg.quote.selection);
    return TicketLegInput(
      label: leg.label,
      eventId: leg.eventId,
      market: leg.market,
      outcome: leg.quote.selection.outcome,
      decimal: leg.quote.decimal,
      point: leg.quote.selection.point,
      ourChance: chance,
      otherDecimal: _otherDecimal(widget.board, leg, bookId),
      consensusFair: leg.fairProbability,
      source: "Coach's Line",
      modelUnproven: chance != null,
      sameLine: _otherBooks(widget.board, widget.now, leg, bookId, chance),
      otherLegs: other == null
          ? const []
          : [
              ValueInput(
                label: other.selection.label,
                ourChance: _modelChance(line, other.selection),
                decimal: other.best?.decimal,
                consensusFair: other.fairProbability,
                source: "Coach's Line",
                modelUnproven: _modelChance(line, other.selection) != null,
              ),
            ],
    );
  }

  List<Widget> _sameGame(MarketScan scan) {
    final tickets = <TicketValue>[];
    for (final event in widget.board.events) {
      final line = widget.model?.lineFor(
        event,
        widget.board.quotes,
        settings: widget.settings,
        books: widget.enabledBooks,
      );
      if (line == null) continue;
      final spreads = scan.markets.where(
        (market) =>
            market.eventId == event.id &&
            market.market == 'spreads' &&
            market.complete,
      );
      final totals = scan.markets.where(
        (market) =>
            market.eventId == event.id &&
            market.market == 'totals' &&
            market.complete,
      );
      if (spreads.isEmpty || totals.isEmpty) continue;
      final spread = _preferredSide(spreads.first, line);
      final total = _preferredSide(totals.first, line);
      if (spread?.best == null || total?.best == null) continue;
      if (spread!.best!.bookId != total!.best!.bookId) {
        final shared = _sharedBook(spread, total);
        if (shared == null) continue;
        tickets.add(
          priceTicket([
            _sideInput(event, spread, shared.$1, line),
            _sideInput(event, total, shared.$2, line),
          ]),
        );
      } else {
        tickets.add(
          priceTicket([
            _sideInput(event, spread, spread.best!, line),
            _sideInput(event, total, total.best!, line),
          ]),
        );
      }
      if (tickets.length == 4) break;
    }
    if (tickets.isEmpty) {
      return const [
        CoachCard(
          child: Text(
            'No same-game ticket yet. That needs a spread and a total in this snapshot, and Coach\'s Line on the game.',
            style: EdgeType.body,
          ),
        ),
      ];
    }
    return [
      for (final ticket in tickets) ...[
        _ParlayCard(ticket: ticket),
        const SizedBox(height: 12),
      ],
    ];
  }

  PricedSide? _preferredSide(PricedMarket market, CoachLine line) {
    PricedSide? best;
    for (final side in market.sides) {
      final chance = _modelChance(line, side.selection);
      final price = side.best?.decimal;
      if (chance == null || price == null) continue;
      final profit = expectedValue(price, chance);
      final current = best == null
          ? null
          : expectedValue(
              best.best!.decimal,
              _modelChance(line, best.selection)!,
            );
      if (best == null || (current != null && profit > current)) best = side;
    }
    return best ?? (market.sides.isEmpty ? null : market.sides.first);
  }

  (OddsQuote, OddsQuote)? _sharedBook(PricedSide spread, PricedSide total) {
    final spreadQuotes = widget.board.quotes.where(
      (quote) =>
          quote.selection.key == spread.selection.key &&
          quote.status != 'suspended',
    );
    for (final left in spreadQuotes) {
      for (final right in widget.board.quotes) {
        if (right.bookId == left.bookId &&
            right.selection.key == total.selection.key) {
          return (left, right);
        }
      }
    }
    return null;
  }

  TicketLegInput _sideInput(
    SportEvent event,
    PricedSide side,
    OddsQuote quote,
    CoachLine line,
  ) {
    final chance = _modelChance(line, side.selection);
    return TicketLegInput(
      label: '${event.away} at ${event.home}: ${side.selection.label}',
      eventId: event.id,
      market: side.selection.market,
      outcome: side.selection.outcome,
      decimal: quote.decimal,
      point: side.selection.point,
      ourChance: chance,
      consensusFair: side.fairProbability,
      source: "Coach's Line",
      modelUnproven: chance != null,
    );
  }
}

double? _modelChance(CoachLine? line, Selection selection) {
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

PricedSide? _paired(MarketScan scan, Selection selection) {
  for (final market in scan.markets) {
    if (market.eventId != selection.eventId ||
        market.market != selection.market) {
      continue;
    }
    for (final side in market.sides) {
      if (side.selection.key == selection.key) {
        for (final other in market.sides) {
          if (other.selection.key != selection.key) return other;
        }
      }
    }
  }
  return null;
}

double? _otherDecimal(OddsBoard board, ParlayLegView leg, String bookId) {
  for (final quote in board.quotes) {
    if (quote.bookId != bookId || quote.selection.eventId != leg.eventId) {
      continue;
    }
    if (quote.selection.market != leg.market ||
        quote.selection.outcome == leg.quote.selection.outcome) {
      continue;
    }
    if (quote.selection.point != leg.quote.selection.point) continue;
    return quote.decimal;
  }
  return null;
}

List<ValueInput> _otherBooks(
  OddsBoard board,
  DateTime now,
  ParlayLegView leg,
  String bookId,
  double? chance,
) {
  final inputs = <ValueInput>[];
  for (final quote in usableSnapshotQuotes(
    board.quotes,
    now,
    events: board.events,
    fetchedAt: board.fetchedAt,
  )) {
    if (quote.bookId == bookId ||
        quote.selection.key != leg.quote.selection.key) {
      continue;
    }
    inputs.add(
      ValueInput(
        label: '${quote.book} ${leg.label}',
        ourChance: chance,
        decimal: quote.decimal,
        otherDecimal: _otherDecimal(board, leg, quote.bookId),
        consensusFair: leg.fairProbability,
        source: "Coach's Line",
        modelUnproven: chance != null,
      ),
    );
  }
  return inputs;
}

Map<String, List<BookLegPrice>> _booksBySelection(
  OddsBoard board,
  DateTime now,
  Set<String>? books,
) {
  final map = <String, List<BookLegPrice>>{};
  for (final quote in usableSnapshotQuotes(
    board.quotes,
    now,
    books: books,
    events: board.events,
    fetchedAt: board.fetchedAt,
  )) {
    if (!parlayMarkets.contains(quote.selection.market)) continue;
    map
        .putIfAbsent(quote.selection.key, () => [])
        .add(
          BookLegPrice(
            bookId: quote.bookId,
            book: quote.book,
            decimal: quote.decimal,
          ),
        );
  }
  return map;
}

class _ParlayCard extends StatelessWidget {
  const _ParlayCard({required this.ticket});
  final TicketValue ticket;

  @override
  Widget build(BuildContext context) {
    final payout = ticket.payoutEstimated ? 'Estimated payout' : 'Payout';
    return CoachCard(
      child: ValueView(
        verdict: ValueVerdict(
          word: ticket.word,
          why: ticket.why,
          math: ticket.math,
          ourChance: ticket.joint,
          expectedValue: ticket.expectedValue,
          overpriced:
              ticket.word == ValueWord.skip &&
              ticket.expectedValue != null &&
              ticket.expectedValue! < 0,
        ),
        caption: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '$payout ${americanLabel(ticket.payoutDecimal)}'
            '${ticket.bestBook == null ? '' : ' · Best book: ${ticket.bestBook}'}',
            style: EdgeType.title,
          ),
        ),
        whyBody: WhyBriefView(brief: buildTicketBrief(ticket)),
        extraMath: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            for (final leg in ticket.legs) ...[
              Text(leg.input.label, style: EdgeType.label),
              const SizedBox(height: 4),
              Text(leg.verdict.math, style: EdgeType.body),
              if (leg.verdict.alternative != null) ...[
                const SizedBox(height: 4),
                Text(leg.verdict.alternative!, style: EdgeType.body),
              ],
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParlayFilters extends StatefulWidget {
  const _ParlayFilters({required this.filter, required this.books});
  final ParlayFilter filter;
  final Map<String, String> books;
  @override
  State<_ParlayFilters> createState() => _ParlayFiltersState();
}

class _ParlayFiltersState extends State<_ParlayFilters> {
  late String? book;
  late int legs;
  late Set<String> markets;
  late final TextEditingController minOdds;

  @override
  void initState() {
    super.initState();
    book = widget.filter.bookId;
    legs = widget.filter.legs;
    markets = {...widget.filter.markets};
    minOdds = TextEditingController(
      text: widget.filter.minAmerican?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    minOdds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: true,
      children: [
        const Text(
          'How these tickets are built',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const ToolNote(
          'One sportsbook per ticket. Two or three legs, each from a different game. '
          'For each game the builder keeps the side whose price is furthest above that book\'s fee-free chance. '
          'Same-game parlays are not built. The house cut is the gap between the multiplied fee-free chance and the break-even rate of the ticket price.',
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
        const Text('Number of legs'),
        Wrap(
          children: [
            for (final count in const [2, 3])
              FilterPill(
                label: '$count',
                selected: legs == count,
                onTap: () => setState(() => legs = count),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Markets'),
        Wrap(
          children: [
            for (final market in const ['h2h', 'spreads', 'totals'])
              FilterChip(
                label: Text(marketNames[market] ?? market),
                selected: markets.contains(market),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    markets.add(market);
                  } else if (markets.length > 1) {
                    markets.remove(market);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: minOdds,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: 'Minimum American odds (optional)',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final text = minOdds.text.trim();
            int? minimum;
            if (text.isNotEmpty) {
              minimum = int.tryParse(text);
              if (minimum == null || minimum.abs() < 100) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Minimum odds must look like +150 or -110, or be left blank.',
                    ),
                  ),
                );
                return;
              }
            }
            Navigator.pop(
              context,
              ParlayFilter(
                bookId: book,
                legs: legs,
                markets: markets,
                minAmerican: minimum,
              ),
            );
          },
          child: const Text('Show tickets'),
        ),
      ],
    ),
  );
}
