import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../domain/odds.dart';
import '../theme/edge_theme.dart';
import '../theme/reveal.dart';
import 'coach_widgets.dart';

/// The comparison a person sees before opening a game.
/// One word, then the two numbers being compared. Nothing else.
class CoachLineSummary extends StatelessWidget {
  const CoachLineSummary({super.key, required this.line});

  final CoachLine line;

  @override
  Widget build(BuildContext context) {
    final verdict = line.flagged ? 'Differs from books' : 'Close to the books';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Coach's Line",
          style: EdgeType.label.copyWith(
            color: EdgeColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          verdict,
          style: EdgeType.title.copyWith(color: EdgeColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text('Our number: ${line.ourSpread}', style: EdgeType.body),
        Text(
          line.booksSpread == null
              ? 'The books: no spread in this snapshot.'
              : 'The books: ${line.booksSpread}',
          style: EdgeType.body,
        ),
        const SizedBox(height: 8),
        Text(
          'Shown for comparison, not a pick.',
          style: EdgeType.label.copyWith(color: EdgeColors.textSecondary),
        ),
      ],
    );
  }
}

class CoachLineCard extends StatelessWidget {
  const CoachLineCard({super.key, required this.line});

  final CoachLine line;

  @override
  Widget build(BuildContext context) {
    final cover = line.favoriteCover == null
        ? (line.homeCoverProbability == null
              ? 'Cover chance needs a spread in this snapshot.'
              : 'Chance the home team covers ${percentLabel(line.homeCoverProbability!)}')
        : 'Chance the favorite covers ${percentLabel(line.favoriteCover!)}';
    final over = line.overProbability == null
        ? 'Over chance needs a total in this snapshot.'
        : 'Chance the over hits ${percentLabel(line.overProbability!)}';
    final edges = [
      line.homeSpreadEdge,
      line.awaySpreadEdge,
      line.overEdge,
      line.underEdge,
    ].whereType<SideEdge>();
    return CoachCard(
      child: Reveal(
        verdict: CoachLineSummary(line: line),
        reasons: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cover, style: EdgeType.body),
            const SizedBox(height: 6),
            Text(over, style: EdgeType.body),
            const SizedBox(height: 6),
            Text(line.edgeReason, style: EdgeType.body),
            const SizedBox(height: 6),
            Text(
              'This is our number compared with the books. It is a comparison, not a pick.',
              style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
            ),
          ],
        ),
        math: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Our total: ${line.ourTotal}', style: EdgeType.body),
            Text(
              line.booksTotal == null
                  ? 'The books: no total in this snapshot.'
                  : 'The books: ${line.booksTotal}',
              style: EdgeType.body,
            ),
            const SizedBox(height: 8),
            for (final edge in edges)
              if (edge.quote != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${edge.label} · best price ${edge.quote!.book} ${americanLabel(edge.quote!.decimal)}'
                    '${edge.expectedProfit == null ? '' : ' · ${signedPercent(edge.expectedProfit!)} if our chance is right'}',
                    style: EdgeType.body.copyWith(
                      color: EdgeColors.textSecondary,
                    ),
                  ),
                ),
            Text(
              'The mark appears when our number and the books differ by at least '
              '${line.settings.spreadPoints.toStringAsFixed(1)} points, or the best price '
              'is at least ${(line.settings.minExpectedValue * 100).toStringAsFixed(0)}% '
              'ahead of our chance.',
              style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
