import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/coach_line_v2.dart';
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
    final books = line.booksSpread == null
        ? 'The books: no spread in this snapshot.'
        : 'The books: ${line.booksSpread}';
    final headline = line.marketFirst
        ? (line.booksSpread ?? 'No spread')
        : line.ourSpread;
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
        if (line.marketFirst)
          Text(line.marketSource, style: EdgeType.label)
        else
          const Text('Our number', style: EdgeType.label),
        Text(
          headline,
          style: EdgeType.display.copyWith(fontSize: 32, height: 1.05),
        ),
        const SizedBox(height: 6),
        Text(
          line.marketFirst ? 'Our number: ${line.ourSpread}' : books,
          style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
        ),
        if (!line.marketFirst) ...[
          const SizedBox(height: 2),
          Text('Our number: ${line.ourSpread}', style: EdgeType.body),
        ],
        const SizedBox(height: 8),
        if (line.flagged)
          const Text(
            'The past test of this number lost money. A wider gap is still only a comparison.',
            style: EdgeType.label,
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
        verdict: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoachLineSummary(line: line),
            if (line.breakdown != null) ...[
              const SizedBox(height: 14),
              HowWeGotThis(line: line),
            ],
          ],
        ),
        reasons: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cover, style: EdgeType.body),
            const SizedBox(height: 6),
            Text(over, style: EdgeType.body),
            const SizedBox(height: 6),
            Text(line.edgeReason, style: EdgeType.body),
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

class HowWeGotThis extends StatelessWidget {
  const HowWeGotThis({super.key, required this.line});

  final CoachLine line;

  @override
  Widget build(BuildContext context) {
    final breakdown = line.breakdown;
    if (breakdown == null) return const SizedBox.shrink();
    final start = spreadLabel(
      line.away.name,
      line.home.name,
      breakdown.marketMargin,
    );
    final end = spreadLabel(
      line.away.name,
      line.home.name,
      breakdown.finalMargin,
    );
    final totalStart = breakdown.marketTotal?.toStringAsFixed(1);
    final totalEnd = breakdown.finalTotal?.toStringAsFixed(1);
    return Column(
      key: const Key('how-we-got-this'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.breakdownIsLive ? 'How we got this' : 'How version 2 was tested',
          style: EdgeType.label.copyWith(
            color: EdgeColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (!line.breakdownIsLive) ...[
          const SizedBox(height: 4),
          Text(
            'Tested, not the number above.',
            style: EdgeType.label.copyWith(color: EdgeColors.textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        _LineBlock(
          title: 'Spread',
          start: start,
          end: end,
          nudges: breakdown.spread,
        ),
        if (totalStart != null && totalEnd != null) ...[
          const SizedBox(height: 8),
          _LineBlock(
            title: 'Total',
            start: totalStart,
            end: totalEnd,
            nudges: breakdown.total,
          ),
        ],
      ],
    );
  }
}

class _LineBlock extends StatelessWidget {
  const _LineBlock({
    required this.title,
    required this.start,
    required this.end,
    required this.nudges,
  });

  final String title;
  final String start;
  final String end;
  final List<LineNudge> nudges;

  @override
  Widget build(BuildContext context) {
    final shown = nudges.where((nudge) => nudge.points.abs() >= 0.05).toList();
    final hidden = nudges.length - shown.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: EdgeType.label.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Market start  $start', style: EdgeType.body),
            const SizedBox(height: 8),
            for (final nudge in shown) _NudgeBar(nudge: nudge),
            if (hidden > 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('No other changes', style: EdgeType.label),
              ),
            Text(
              'Our line  $end',
              style: EdgeType.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _NudgeBar extends StatelessWidget {
  const _NudgeBar({required this.nudge});

  final LineNudge nudge;

  @override
  Widget build(BuildContext context) {
    final text = signedNumber(nudge.points);
    final note = nudge.label == 'Weather' ? nudge.detail : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                nudge.label,
                maxLines: 1,
                softWrap: false,
                style: EdgeType.body.copyWith(fontSize: 15, height: 1.2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 12,
                  child: CustomPaint(painter: _SignedBarPainter(nudge.points)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: EdgeType.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note,
                style: EdgeType.label.copyWith(
                  color: EdgeColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SignedBarPainter extends CustomPainter {
  _SignedBarPainter(this.points);
  final double points;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final axis = Paint()
      ..color = EdgeColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), axis);
    canvas.drawLine(Offset(mid, 0), Offset(mid, size.height), axis);
    if (points.abs() < 0.05) return;
    final reach = (points.abs() / 2.5).clamp(0.0, 1.0);
    final width = reach * (size.width / 2);
    final rect = points > 0
        ? Rect.fromLTWH(mid, 1, width, size.height - 2)
        : Rect.fromLTWH(mid - width, 1, width, size.height - 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = points > 0 ? EdgeColors.accent : EdgeColors.warn,
    );
  }

  @override
  bool shouldRepaint(covariant _SignedBarPainter oldDelegate) =>
      oldDelegate.points != points;
}
