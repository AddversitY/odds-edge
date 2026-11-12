import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/market_math.dart';
import '../domain/odds.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../theme/reveal.dart';
import 'coach_widgets.dart';

class ParlaysScreen extends StatefulWidget {
  const ParlaysScreen({
    super.key,
    required this.board,
    required this.now,
    this.enabledBooks,
  });

  final OddsBoard board;
  final DateTime now;
  final Set<String>? enabledBooks;

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
          'Tickets built from this snapshot. Each one uses a single sportsbook and legs from different games. The chance multiplies the fee-free prices only when the games are unrelated.',
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
              'No ticket fits these filters. A ticket needs the same book to have priced at least two different games. Same-game legs are left off, because this app will not pretend those chances multiply.',
              style: EdgeType.body,
            ),
          )
        else
          for (final parlay in slate.parlays) ...[
            _ParlayCard(parlay: parlay, now: widget.now),
            const SizedBox(height: 12),
          ],
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
}

class _ParlayCard extends StatelessWidget {
  const _ParlayCard({required this.parlay, required this.now});
  final ParlaySuggestion parlay;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final price = parlay.price;
    final fair = price.fairProbability;
    final edge = price.expectedValuePerUnit;
    final verdict = fair == null ? 'Unavailable' : percentLabel(fair);
    return CoachCard(
      child: Reveal(
        verdict: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              parlay.demo ? '${parlay.book} · sample prices' : parlay.book,
              style: EdgeType.label,
            ),
            const SizedBox(height: 6),
            Text(verdict, style: EdgeType.display),
            Text(
              fair == null ? 'Real chance unavailable' : 'Chance if the games are unrelated',
              style: EdgeType.label,
            ),
          ],
        ),
        reasons: Text(parlay.plainEnglish, style: EdgeType.body),
        math: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ticket price ${americanLabel(price.offeredDecimal)}'
              '${edge == null ? '' : ' · expected profit ${signedPercent(edge)} per dollar'}',
              style: EdgeType.body,
            ),
            const SizedBox(height: 8),
            for (final leg in parlay.legs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${leg.label}\n${leg.matchup} · ${leg.quote.book} ${americanLabel(leg.quote.decimal)} · ${priceAge(leg.quote.sourceAt, now)}',
                  style: EdgeType.body,
                ),
              ),
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
                    content: Text('Minimum odds must look like +150 or -110, or be left blank.'),
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
