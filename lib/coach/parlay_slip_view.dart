import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/history.dart';
import '../domain/injury_report.dart';
import '../domain/matchup.dart';
import '../domain/odds.dart';
import '../domain/parlay_slip.dart';
import '../domain/parlay_value.dart';
import '../domain/prop_history.dart';
import '../domain/value_check.dart';
import '../theme/edge_theme.dart';
import '../ui/value_check.dart';
import '../ui/wordmark.dart';
import 'prop_pricing.dart';

class ParlaySlipView extends StatefulWidget {
  const ParlaySlipView({
    super.key,
    required this.slip,
    required this.board,
    required this.now,
    this.directory,
    this.context,
    this.injuries,
    this.scores = const [],
    this.enabledBooks,
    this.onAddLeg,
  });

  final ParlaySlipController slip;
  final OddsBoard board;
  final DateTime now;
  final PlayerDirectory? directory;
  final MatchupContext? context;
  final InjuryReport? injuries;
  final List<HistoricalGame> scores;
  final Set<String>? enabledBooks;
  final VoidCallback? onAddLeg;

  @override
  State<ParlaySlipView> createState() => _ParlaySlipViewState();
}

class _ParlaySlipViewState extends State<ParlaySlipView> {
  late final TextEditingController stake = TextEditingController(
    text: widget.slip.slip.stake.toStringAsFixed(2),
  );
  String? stakeError;

  @override
  void initState() {
    super.initState();
    widget.slip.addListener(_changed);
  }

  @override
  void didUpdateWidget(ParlaySlipView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slip != widget.slip) {
      oldWidget.slip.removeListener(_changed);
      widget.slip.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.slip.removeListener(_changed);
    stake.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool _hasOppositeSides(List<ShownProp> legs) {
    for (var i = 0; i < legs.length; i++) {
      for (var j = i + 1; j < legs.length; j++) {
        if (oppositeSides(legs[i].card.side, legs[j].card.side)) return true;
      }
    }
    return false;
  }

  double? get _stake {
    final value = double.tryParse(stake.text.trim());
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final cards = propCards(
      widget.board,
      widget.now,
      books: widget.enabledBooks,
    );
    final byId = {for (final card in cards) card.id: card};
    final legs = <ShownProp>[];
    final missing = <String>[];
    for (final key in widget.slip.slip.selectionKeys) {
      final card = byId[key];
      if (card == null) {
        missing.add(key);
        continue;
      }
      legs.add(
        showProp(
          card: card,
          cards: cards,
          directory: widget.directory,
          context: widget.context,
          board: widget.board,
          now: widget.now,
          injuries: widget.injuries,
          scores: widget.scores,
        ),
      );
    }
    final opposed = _hasOppositeSides(legs);
    TicketValue? ticket;
    String? ticketError;
    if (opposed) {
      ticketError = 'Two legs are the over and the under of the same line. Remove one. A combined chance is not shown for that pair.';
    } else if (legs.length >= 2 && legs.every((leg) => leg.card.best != null)) {
      try {
        ticket = priceTicket(
          [for (final leg in legs) ticketLegFor(leg)],
          booksByLeg: [
            for (final leg in legs)
              [
                for (final row in leg.card.bookRows)
                  BookLegPrice(
                    bookId: row.quote.bookId,
                    book: row.quote.book,
                    decimal: row.quote.decimal,
                  ),
              ],
          ],
        );
      } on ArgumentError catch (error) {
        ticketError = error.message?.toString();
      }
    }
    final dollars = _stake;
    final returns = ticket == null || dollars == null
        ? null
        : dollars * ticket.payoutDecimal;
    return Column(
      key: const Key('parlay-slip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'Parlay',
                overflow: TextOverflow.ellipsis,
                style: EdgeType.title.copyWith(
                  fontFamily: EdgeFont.display,
                  fontSize: 26,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.board.demo) const ExamplePill(),
            if (widget.slip.slip.length > 0)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: widget.slip.clear,
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (legs.isEmpty && missing.isEmpty)
          const EmptyNote(
            'No legs yet. Open a prop and add it. Prices are not invented to fill a ticket.',
          )
        else ...[
          if (ticket != null)
            _TicketSummary(ticket: ticket, returns: returns, stake: dollars),
          if (ticket == null && legs.length == 1)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: EmptyNote(
                'Add a second leg. A parlay needs at least two prices.',
              ),
            ),
          if (ticketError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EmptyNote(ticketError),
            ),
          for (final leg in legs) ...[
            _LegTile(
              shown: leg,
              onRemove: () => widget.slip.remove(leg.card.id),
            ),
            const SizedBox(height: 8),
          ],
          for (final key in missing) ...[
            EmptyNote(
              'A leg is no longer in this snapshot, so its price was left off. Remove it.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => widget.slip.remove(key),
                child: const Text('Remove missing leg'),
              ),
            ),
          ],
        ],
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: widget.onAddLeg,
          icon: const Icon(Icons.add),
          label: const Text('Add a leg'),
        ),
        if (ticket != null) ...[
          _CorrelationNote(ticket: ticket),
          const SizedBox(height: 8),
          _StakeRow(
            controller: stake,
            error: stakeError,
            returns: returns,
            estimated: ticket.payoutEstimated,
            onChanged: (value) {
              final parsed = double.tryParse(value.trim());
              setState(() {
                stakeError = parsed == null || parsed <= 0
                    ? 'Enter a stake greater than 0.'
                    : null;
              });
              if (parsed != null && parsed > 0) {
                widget.slip.setSlip(widget.slip.slip.withStake(parsed));
              }
            },
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        Text(
          widget.board.demo
              ? 'Example data · each leg is checked on its own, then the ticket · not a pick'
              : 'Each leg is checked on its own, then the ticket · not a pick',
          textAlign: TextAlign.center,
          style: EdgeType.label.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: EdgeColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _TicketSummary extends StatelessWidget {
  const _TicketSummary({
    required this.ticket,
    required this.returns,
    required this.stake,
  });

  final TicketValue ticket;
  final double? returns;
  final double? stake;

  @override
  Widget build(BuildContext context) {
    final payoutName = ticket.payoutEstimated ? 'Estimated payout' : 'Payout';
    double? implied;
    try {
      implied = impliedProbability(ticket.payoutDecimal);
    } on ArgumentError {
      implied = null;
    }
    final book = ticket.bestBook;
    final stakeText = stake == null ? null : '\$${stake!.toStringAsFixed(2)}';
    final returnText = returns == null
        ? null
        : '\$${returns!.toStringAsFixed(2)}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ticket.legs.length} ${ticket.legs.length == 1 ? 'leg' : 'legs'}'
            '${ticket.sameGame ? ' · same game' : ' · separate games'}',
            style: EdgeType.label,
          ),
          const SizedBox(height: 4),
          Text(
            americanLabel(ticket.payoutDecimal),
            style: EdgeType.display.copyWith(fontSize: 36),
          ),
          Text(
            '$payoutName${book == null ? '' : ' · $book'}'
            '${stakeText == null || returnText == null ? '' : ' · $stakeText returns $returnText'}',
            style: EdgeType.label,
          ),
          const SizedBox(height: 14),
          ValueCheck(
            word: ticket.word,
            ourChance: ticket.joint,
            bookChance: implied,
            ourLabel: 'Our combined chance',
            bookLabel: "Payout's implied chance",
            overpriced:
                ticket.word == ValueWord.skip &&
                ticket.expectedValue != null &&
                ticket.expectedValue! < 0,
            note: ticket.sameGame
                ? 'Same-game chances are not just multiplied. ${ticket.payoutEstimated ? 'The payout is estimated.' : ''}'
                : 'These games are separate, so the chances multiply.',
          ),
        ],
      ),
    );
  }
}

class _LegTile extends StatelessWidget {
  const _LegTile({required this.shown, required this.onRemove});
  final ShownProp shown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final card = shown.card;
    final quote = card.best;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      card.player,
                      style: EdgeType.title.copyWith(
                        fontFamily: EdgeFont.display,
                        fontSize: 17,
                      ),
                    ),
                    WordPill(
                      word: shown.verdict.word,
                      overpriced: shown.verdict.overpriced,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove leg',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (propMeta(shown).isNotEmpty)
            Text(propMeta(shown), style: EdgeType.label.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  shortPropLine(card),
                  style: EdgeType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    quote == null ? '—' : americanLabel(quote.decimal),
                    style: EdgeType.number.copyWith(fontSize: 16),
                  ),
                  Text(
                    quote?.book ?? 'No open price',
                    style: EdgeType.label.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueCheck(
            compact: true,
            word: shown.verdict.word,
            overpriced: shown.verdict.overpriced,
            ourChance: shown.verdict.ourChance,
            bookChance: shown.verdict.fairChance,
            bookLabel: shown.bookChanceLabel,
          ),
        ],
      ),
    );
  }
}

class _CorrelationNote extends StatelessWidget {
  const _CorrelationNote({required this.ticket});
  final TicketValue ticket;

  @override
  Widget build(BuildContext context) {
    final same = ticket.sameGame;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (same ? EdgeColors.warn : EdgeColors.good).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        same
            ? 'Same game. These legs can move together, so the combined chance is not the legs multiplied. The payout stays labeled estimated unless a book posts the parlay price.'
            : 'Separate games. The combined chance is the legs multiplied. A second prop from one of these games would be flagged, and that payout would say estimated.',
        style: EdgeType.label.copyWith(
          fontWeight: FontWeight.w500,
          height: 1.35,
          color: EdgeColors.text,
        ),
      ),
    );
  }
}

class _StakeRow extends StatelessWidget {
  const _StakeRow({
    required this.controller,
    required this.onChanged,
    required this.estimated,
    this.error,
    this.returns,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool estimated;
  final String? error;
  final double? returns;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'If you put in',
              prefixText: '\$',
              errorText: error,
              isDense: true,
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                estimated ? 'Estimated payout' : 'It pays',
                style: EdgeType.label.copyWith(fontSize: 12),
              ),
              Text(
                returns == null ? '—' : '\$${returns!.toStringAsFixed(2)}',
                style: EdgeType.number.copyWith(
                  fontSize: 22,
                  color: EdgeColors.good,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
