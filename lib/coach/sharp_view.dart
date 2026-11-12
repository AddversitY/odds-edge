import 'package:flutter/material.dart';

import '../domain/odds.dart';
import '../domain/public_sharp.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import 'coach_widgets.dart';

/// One scannable Sharp row. The line under it is the open-to-now move.
/// Tap for the steam, the first books, the Pinnacle gap, and the public side.
class SharpWhyRow extends StatefulWidget {
  const SharpWhyRow({super.key, required this.read});

  final SharpRead read;

  @override
  State<SharpWhyRow> createState() => _SharpWhyRowState();
}

class _SharpWhyRowState extends State<SharpWhyRow> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final read = widget.read;
    return Semantics(
      button: true,
      label:
          'Sharp. ${read.oneLine}. ${read.sparklineLabel} Signal, not a pick.',
      child: Material(
        color: EdgeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: EdgeSpace.tap),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 50,
                        child: Text(
                          'Sharp',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: EdgeColors.accent,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          read.oneLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: EdgeType.label.copyWith(
                            color: EdgeColors.text,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      LineSparkline(
                        points: read.sparkline,
                        label: read.sparklineLabel,
                      ),
                    ],
                  ),
                ),
                if (open) ...[
                  const SizedBox(height: 8),
                  for (final line in read.detail) ...[
                    Text(line, style: EdgeType.body),
                    const SizedBox(height: 8),
                  ],
                  Text(read.publicLine, style: EdgeType.body),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Open-to-now home spread. Higher numbers sit higher. One color, not a grade.
class LineSparkline extends StatelessWidget {
  const LineSparkline({super.key, required this.points, required this.label});

  final List<double> points;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const SizedBox(width: 56, height: 28);
    }
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 56,
        height: 28,
        child: CustomPaint(painter: _SparkPainter(points)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points);
  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    var low = points.first;
    var high = points.first;
    for (final point in points) {
      if (point < low) low = point;
      if (point > high) high = point;
    }
    if ((high - low).abs() < 0.01) {
      low -= 1;
      high += 1;
    }
    final paint = Paint()
      ..color = EdgeColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? size.width / 2
          : size.width * i / (points.length - 1);
      final y =
          size.height -
          ((points[i] - low) / (high - low)) * (size.height - 6) -
          3;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.points != points;
}

/// Games with the clearest sharp signals, and the public side when we have it.
class PublicSharpScreen extends StatelessWidget {
  const PublicSharpScreen({
    super.key,
    required this.board,
    required this.now,
    this.lineHistory = const {},
    this.publicSplits = const [],
    this.sample = false,
  });

  final OddsBoard board;
  final DateTime now;
  final Map<String, List<LineSnapshot>> lineHistory;
  final List<PublicSplit> publicSplits;
  final bool sample;

  @override
  Widget build(BuildContext context) {
    final reads = readSlate(
      events: board.events,
      history: lineHistory,
      currentQuotes: board.quotes,
      publicSplits: publicSplits,
      sample: sample,
      now: now,
      pricesAt: board.fetchedAt,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text('Public vs sharp', style: EdgeType.title),
        const SizedBox(height: 8),
        Text(
          sample
              ? 'Sample line history, so you can see the screen. Not a live market. Sharp side is how Pinnacle and the other books moved. Public ticket and money percentages are not available. These are signals, not picks.'
              : publicSplits.isEmpty
              ? 'Sharp side is how Pinnacle and the other books moved in the line we already saved. Public ticket and money percentages are not available. These are signals, not picks.'
              : 'Sharp side is how Pinnacle and the other books moved. Public percentages are shown only from a source that allows it. These are signals, not picks.',
          style: EdgeType.body,
        ),
        const SizedBox(height: 16),
        if (reads.isEmpty)
          const CoachCard(child: Text('No games in this snapshot.'))
        else
          for (final read in reads) ...[
            CoachCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${read.away} at ${read.home}', style: EdgeType.title),
                  const SizedBox(height: 12),
                  SharpWhyRow(read: read),
                  const SizedBox(height: 8),
                  Text(
                    'Public',
                    style: EdgeType.label.copyWith(color: EdgeColors.accent),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    read.publicLine == publicSplitsUnavailableNotice
                        ? 'Ticket % and money % are not available.'
                        : read.publicLine,
                    style: EdgeType.body,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 8),
        const ToolNote(
          'A signal describes the saved line. It is not a pick and it is not a promise.',
        ),
      ],
    );
  }
}
