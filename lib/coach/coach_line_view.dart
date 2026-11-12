import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../domain/odds.dart';
import 'coach_widgets.dart';

class CoachLineSummary extends StatelessWidget {
  const CoachLineSummary({super.key, required this.line, this.compact = true});

  final CoachLine line;
  final bool compact;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Coach's Line",
          style: TextStyle(
            color: coachMint,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text('Our number: ${line.ourSpread}'),
        Text(
          line.booksSpread == null
              ? 'The books: no spread in this snapshot.'
              : 'The books: ${line.booksSpread}',
        ),
        Text('Our total: ${line.ourTotal}'),
        Text(
          line.booksTotal == null
              ? 'The books: no total in this snapshot.'
              : 'The books: ${line.booksTotal}',
        ),
        Text(cover, style: const TextStyle(color: Colors.white70)),
        Text(over, style: const TextStyle(color: Colors.white70)),
        if (!compact && line.flagged) ...[
          const SizedBox(height: 6),
          const _EdgeBadge(),
          const SizedBox(height: 4),
          Text(line.edgeReason, style: const TextStyle(height: 1.35)),
        ],
      ],
    );
  }
}

class _EdgeBadge extends StatelessWidget {
  const _EdgeBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: coachMint.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      'Edge',
      style: TextStyle(
        color: coachMint,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class CoachLineCard extends StatelessWidget {
  const CoachLineCard({super.key, required this.line});

  final CoachLine line;

  @override
  Widget build(BuildContext context) {
    final edges = [
      line.homeSpreadEdge,
      line.awaySpreadEdge,
      line.overEdge,
      line.underEdge,
    ].whereType<SideEdge>();
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoachLineSummary(line: line, compact: false),
          const SizedBox(height: 8),
          for (final edge in edges)
            if (edge.quote != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${edge.label} · best price ${edge.quote!.book} ${americanLabel(edge.quote!.decimal)}'
                  '${edge.expectedProfit == null ? '' : ' · ${signedPercent(edge.expectedProfit!)} if our chance is right'}',
                  style: const TextStyle(color: Colors.white70, height: 1.3),
                ),
              ),
          const SizedBox(height: 4),
          Text(
            'An Edge means our number and the books differ by at least '
            '${line.settings.spreadPoints.toStringAsFixed(1)} points, or the best price '
            'is at least ${(line.settings.minExpectedValue * 100).toStringAsFixed(0)}% '
            'ahead of our chance. It is a comparison, not a promise.',
            style: const TextStyle(color: Colors.white60, height: 1.35),
          ),
        ],
      ),
    );
  }
}
