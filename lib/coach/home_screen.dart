import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/coach_board.dart';
import '../domain/odds.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../theme/reveal.dart';
import 'coach_widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.board,
    required this.now,
    required this.stamp,
    this.enabledBooks,
  });

  final OddsBoard board;
  final DateTime now;
  final String Function(DateTime time) stamp;
  final Set<String>? enabledBooks;

  @override
  Widget build(BuildContext context) {
    final slate = summarizeSlate(board, now, books: enabledBooks);
    final longer = slate.topPlays.where((play) => play.longerThanTheBooks);
    final closest = slate.topPlays;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const SectionLabel('TODAY'),
        const SizedBox(height: 8),
        Text(
          'Snapshot as of ${stamp(board.fetchedAt)}',
          style: EdgeType.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          board.demo
              ? 'These are sample prices, not a sportsbook. Nothing here is a pick.'
              : 'Saved prices, not a live stream. Nothing here is a pick.',
          style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
        ),
        const SizedBox(height: 24),
        const SectionLabel('CHECK MY SLIP'),
        const SizedBox(height: 8),
        const _SlipBox(),
        const SizedBox(height: 24),
        const SectionLabel('CLOSEST PRICES'),
        const SizedBox(height: 8),
        Text(
          longer.isEmpty
              ? 'No price in this snapshot pays more than the books\' fee-free chance. The closest gaps are below. They are not plays.'
              : 'A price is listed when it pays more than the books\' fee-free chance. That is a comparison of the snapshot, not a model and not a recommendation.',
          style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (closest.isEmpty)
          const CoachCard(
            child: Text(
              'No two-sided price in this snapshot, so there is nothing to compare.',
              style: EdgeType.body,
            ),
          )
        else
          for (final play in closest) ...[
            CoachCard(
              child: Reveal(
                verdict: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      play.longerThanTheBooks ? 'Longer' : 'Shorter',
                      style: EdgeType.title.copyWith(
                        color: play.longerThanTheBooks
                            ? EdgeColors.good
                            : EdgeColors.warn,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(play.title, style: EdgeType.body.copyWith(fontWeight: FontWeight.w700)),
                    Text(play.subtitle, style: EdgeType.label),
                    const SizedBox(height: 8),
                    Text(
                      '${play.quote.book} ${americanLabel(play.quote.decimal)}',
                      style: EdgeType.title,
                    ),
                    Text(
                      '${play.quote.demo ? 'Sample' : 'Saved'} · ${priceAge(play.quote.sourceAt, now)}',
                      style: EdgeType.label,
                    ),
                  ],
                ),
                reasons: Text(
                  play.longerThanTheBooks
                      ? 'This price pays more than the books\' fee-free chance. Not a tip.'
                      : 'This price pays less than the books\' fee-free chance. Shown because it is among the closest, not because it is a play.',
                  style: EdgeType.body,
                ),
                math: Text(
                  'Expected profit if that chance is right: ${signedPercent(play.expectedProfit)} per dollar.',
                  style: EdgeType.body,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _SlipBox extends StatefulWidget {
  const _SlipBox();
  @override
  State<_SlipBox> createState() => _SlipBoxState();
}

class _SlipBoxState extends State<_SlipBox> {
  final legs = [TextEditingController(), TextEditingController()];
  final chances = [TextEditingController(), TextEditingController()];

  @override
  void dispose() {
    for (final controller in [...legs, ...chances]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? message;
    try {
      final parsed = <SlipLeg>[];
      for (var i = 0; i < legs.length; i++) {
        final text = legs[i].text.trim();
        if (text.isEmpty) continue;
        final odds = int.tryParse(text);
        if (odds == null) {
          throw ArgumentError('Leg ${i + 1} needs American odds such as -110 or +150.');
        }
        final chanceText = chances[i].text.trim();
        double? chance;
        if (chanceText.isNotEmpty) {
          final percent = double.tryParse(chanceText);
          if (percent == null || percent <= 0 || percent >= 100) {
            throw ArgumentError(
              'Leg ${i + 1} chance must be greater than 0 and less than 100, or left blank.',
            );
          }
          chance = percent / 100;
        }
        parsed.add(SlipLeg(decimal: americanToDecimal(odds), winProbability: chance));
      }
      if (parsed.length >= 2) {
        message = checkSlip(parsed).plainEnglish;
      } else if (parsed.length == 1) {
        message = 'Add a second leg. A parlay needs at least two prices.';
      } else {
        message =
            'Type the American odds on each leg. You will see the break-even rate. Enter a chance for every leg if you want the real chance. This box will not guess it.';
      }
    } on ArgumentError catch (error) {
      message = error.message ?? 'Those odds could not be priced.';
    }
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Check a ticket you already have',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < legs.length; i++) ...[
            TextField(
              controller: legs[i],
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+-]'))],
              decoration: InputDecoration(labelText: 'Leg ${i + 1} American odds'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: chances[i],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Leg ${i + 1} chance you believe, % (optional)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
          ],
          Text(message ?? '', style: const TextStyle(height: 1.4)),
          const SizedBox(height: 8),
          const ToolNote(responsibleGamblingNote),
        ],
      ),
    );
  }
}
