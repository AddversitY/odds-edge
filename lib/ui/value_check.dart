import 'package:flutter/material.dart';

import '../domain/edge_gap.dart';
import '../domain/value_check.dart';
import '../theme/edge_theme.dart';

Color wordColor(ValueWord word, {bool overpriced = false}) => switch (word) {
  ValueWord.bet => EdgeColors.good,
  ValueWord.lean => EdgeColors.warn,
  ValueWord.skip => overpriced ? EdgeColors.bad : EdgeColors.textSecondary,
};

/// Our chance against the book's no-vig chance, with the gap drawn as a
/// rail. This is the mark on every prop, every leg, and the ticket.
class ValueCheck extends StatelessWidget {
  const ValueCheck({
    super.key,
    required this.word,
    required this.ourChance,
    required this.bookChance,
    this.ourLabel = 'Our chance',
    this.bookLabel = "Book's no-vig",
    this.note,
    this.compact = false,
    this.overpriced = false,
  });

  final ValueWord word;
  final double? ourChance;
  final double? bookChance;
  final String ourLabel;
  final String bookLabel;
  final String? note;
  final bool compact;
  final bool overpriced;

  @override
  Widget build(BuildContext context) {
    final gap = edgePoints(ourChance, bookChance);
    final color = wordColor(word, overpriced: overpriced);
    final numberSize = compact ? 18.0 : 26.0;
    return Column(
      key: const Key('value-check'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Row(
            children: [
              Text(
                'VALUE CHECK',
                style: EdgeType.label.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.1,
                  color: EdgeColors.textTertiary,
                ),
              ),
              const Spacer(),
              _GapChip(label: edgePointsLabel(gap), color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _word(word),
            style: EdgeType.display.copyWith(
              fontSize: 32,
              color: color,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _Chance(
                value: chanceLabel(ourChance),
                label: ourLabel,
                color: ourChance == null ? EdgeColors.textSecondary : color,
                size: numberSize,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Chance(
                value: chanceLabel(bookChance),
                label: bookLabel,
                color: EdgeColors.text,
                size: numberSize,
              ),
            ),
            if (compact) ...[
              const SizedBox(width: 8),
              _GapChip(label: edgePointsLabel(gap), color: color),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: compact ? 8 : 10,
          width: double.infinity,
          child: CustomPaint(
            painter: _RailPainter(
              our: ourChance,
              book: bookChance,
              color: color,
            ),
          ),
        ),
        if (note != null && note!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            note!,
            style: EdgeType.label.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: EdgeColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  static String _word(ValueWord word) => switch (word) {
    ValueWord.bet => 'Bet',
    ValueWord.lean => 'Lean',
    ValueWord.skip => 'Skip',
  };
}

class WordPill extends StatelessWidget {
  const WordPill({super.key, required this.word, this.overpriced = false});

  final ValueWord word;
  final bool overpriced;

  @override
  Widget build(BuildContext context) {
    final color = wordColor(word, overpriced: overpriced);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        ValueCheck._word(word),
        style: EdgeType.label.copyWith(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GapChip extends StatelessWidget {
  const _GapChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: EdgeType.number.copyWith(
          fontFamily: EdgeFont.sans,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _Chance extends StatelessWidget {
  const _Chance({
    required this.value,
    required this.label,
    required this.color,
    required this.size,
  });

  final String value;
  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: EdgeType.number.copyWith(fontSize: size, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: EdgeType.label.copyWith(
            fontSize: 9,
            height: 1.15,
            letterSpacing: 0.2,
            color: EdgeColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.our, required this.book, required this.color});

  final double? our;
  final double? book;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height),
    );
    canvas.drawRRect(
      track,
      Paint()..color = Colors.white.withValues(alpha: .08),
    );
    final ours = our;
    if (ours == null) return;
    final fillWidth = (ours.clamp(0.0, 1.0)) * size.width;
    if (fillWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, fillWidth, size.height),
          Radius.circular(size.height),
        ),
        Paint()..color = color.withValues(alpha: .9),
      );
    }
    final books = book;
    if (books == null) return;
    final x = (books.clamp(0.0, 1.0)) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 1.2, -2, 2.4, size.height + 4),
        const Radius.circular(2),
      ),
      Paint()..color = EdgeColors.text,
    );
  }

  @override
  bool shouldRepaint(covariant _RailPainter oldDelegate) =>
      oldDelegate.our != our ||
      oldDelegate.book != book ||
      oldDelegate.color != color;
}

class EdgeSegments extends StatelessWidget {
  const EdgeSegments({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: i == index ? EdgeColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(i),
                    child: SizedBox(
                      height: 36,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              labels[i],
                              style: EdgeType.label.copyWith(
                                color: i == index
                                    ? EdgeColors.onAccent
                                    : EdgeColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Text(text, style: EdgeType.body),
    );
  }
}
