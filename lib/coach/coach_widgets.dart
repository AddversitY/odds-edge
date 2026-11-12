import 'package:flutter/material.dart';

import '../domain/hit_rate.dart';
import '../domain/odds.dart';
import '../explained_number.dart';

const coachMint = Color(0xFF7CE7C0);
const coachPanel = Color(0xF0121A24);

/// Green at 60% and above, amber from 45%, red below. A display choice for
/// a counted rate, explained in the tooltip. It is not a pick.
Color hitRateColor(double? rate) {
  if (rate == null) return Colors.white38;
  if (rate >= 0.6) return const Color(0xFF3DDC97);
  if (rate >= 0.45) return const Color(0xFFE6C15A);
  return const Color(0xFFFF7B7B);
}

class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.child, this.onDoubleTap});
  final Widget child;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onDoubleTap: onDoubleTap,
    child: Card(
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: coachMint,
      fontSize: 11,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w700,
    ),
  );
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: coachMint.withValues(alpha: .18),
      labelStyle: TextStyle(
        color: selected ? coachMint : Colors.white70,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class ChanceBar extends StatelessWidget {
  const ChanceBar({
    super.key,
    required this.fraction,
    required this.label,
  });

  /// Null hides the fill and says the chance is unavailable.
  final double? fraction;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = fraction;
    final shown = value != null && value.isFinite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            Text(
              shown ? '${(value * 100).toStringAsFixed(1)}%' : '—',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: shown ? value.clamp(0, 1).toDouble() : 0,
            backgroundColor: const Color(0xFF243041),
            color: coachMint,
          ),
        ),
      ],
    );
  }
}

class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.kicker,
    required this.value,
    required this.title,
    required this.body,
    this.valueColor,
  });

  final String kicker, value, title, body;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E141C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF243041)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kicker,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          ExplainedValue(
            value: value,
            title: title,
            body: body,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: valueColor ?? Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}

class HitChip extends StatelessWidget {
  const HitChip({super.key, required this.label, required this.rate});
  final String label;
  final HitRate? rate;

  @override
  Widget build(BuildContext context) {
    final clear = rate?.clearRate;
    final text = clear == null ? '—' : '${(clear * 100).round()}%';
    final detail = rate == null
        ? '$label is not available.'
        : rate!.observed == 0
        ? '$label: no recorded stat in this window.'
        : '$label: ${rate!.hits} of ${rate!.observed} cleared'
              '${rate!.missing == 0 ? '' : ', ${rate!.missing} missing and not counted as misses'}. '
              'Green is 60% or more, amber is 45% to 60%, red is under 45%. That is a count, not a prediction.';
    return Tooltip(
      message: detail,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0E141C),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$label $text',
          style: TextStyle(
            color: hitRateColor(clear),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class StatBars extends StatelessWidget {
  const StatBars({super.key, required this.samples, required this.line});
  final List<HitSample> samples;
  final double line;

  @override
  Widget build(BuildContext context) {
    final shown = samples.where((sample) => sample.value != null).toList();
    if (shown.isEmpty) {
      return const Text(
        'No recorded stat for this line, so there is no game chart.',
        style: TextStyle(color: Colors.white60),
      );
    }
    // Hit-rate samples are newest first. The chart reads oldest to newest.
    final chronological = shown.reversed.toList();
    final recent = chronological.length > 10
        ? chronological.sublist(chronological.length - 10)
        : chronological;
    var peak = line.abs();
    for (final sample in recent) {
      final value = sample.value!.toDouble().abs();
      if (value > peak) peak = value;
    }
    if (peak <= 0) peak = 1;
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final sample in recent)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message:
                      '${sample.game.date.toIso8601String().substring(0, 10)} vs ${sample.game.opponent}: ${sample.value} (${sample.outcome})',
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: (sample.value!.toDouble().abs() / peak)
                          .clamp(0.04, 1),
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: sample.outcome == 'hit'
                              ? const Color(0xFF3DDC97)
                              : sample.outcome == 'miss'
                              ? const Color(0xFFFF7B7B)
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
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

class OddsHistoryChart extends StatelessWidget {
  const OddsHistoryChart({super.key, required this.quotes});
  final List<OddsQuote> quotes;

  @override
  Widget build(BuildContext context) {
    final points = [...quotes]
      ..sort((a, b) => a.collectedAt.compareTo(b.collectedAt));
    if (points.length < 2) {
      return const Text(
        'No odds-over-time chart yet. That needs at least two saved snapshots of this exact prop. Nothing is drawn in its place.',
        style: TextStyle(color: Colors.white60, height: 1.4),
      );
    }
    return SizedBox(
      height: 120,
      width: double.infinity,
      child: CustomPaint(
        painter: _OddsPainter(points),
      ),
    );
  }
}

class _OddsPainter extends CustomPainter {
  _OddsPainter(this.quotes);
  final List<OddsQuote> quotes;

  @override
  void paint(Canvas canvas, Size size) {
    final values = quotes.map((quote) => quote.decimal).toList();
    var low = values.reduce((a, b) => a < b ? a : b);
    var high = values.reduce((a, b) => a > b ? a : b);
    if ((high - low).abs() < 0.01) {
      low -= 0.05;
      high += 0.05;
    }
    final paint = Paint()
      ..color = coachMint
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < quotes.length; i++) {
      final x = quotes.length == 1 ? 0.0 : size.width * i / (quotes.length - 1);
      final y =
          size.height -
          ((quotes[i].decimal - low) / (high - low)) * (size.height - 8) -
          4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OddsPainter oldDelegate) =>
      oldDelegate.quotes != quotes;
}

String money(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign\$${value.abs().toStringAsFixed(2)}';
}
