import 'package:flutter/material.dart';

import '../domain/hit_rate.dart';
import '../domain/value_check.dart';
import '../theme/edge_theme.dart';
import '../theme/reveal.dart';

Color valueWordColor(ValueVerdict verdict) => switch (verdict.word) {
  ValueWord.bet => EdgeColors.good,
  ValueWord.lean => EdgeColors.warn,
  ValueWord.skip =>
    verdict.overpriced ? EdgeColors.bad : EdgeColors.textSecondary,
};

/// One word, then Why, then The math. Nothing else is on the surface.
class ValueView extends StatelessWidget {
  const ValueView({
    super.key,
    required this.verdict,
    this.caption,
    this.extraWhy,
    this.extraMath,
  });

  final ValueVerdict verdict;
  final Widget? caption;
  final Widget? extraWhy;
  final Widget? extraMath;

  @override
  Widget build(BuildContext context) {
    return Reveal(
      verdict: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verdict.wordLabel,
            style: EdgeType.display.copyWith(color: valueWordColor(verdict)),
          ),
          ?caption,
        ],
      ),
      reasons: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(verdict.why, style: EdgeType.body),
          ?extraWhy,
        ],
      ),
      math: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(verdict.math, style: EdgeType.body),
          ?extraMath,
        ],
      ),
    );
  }
}

/// Recorded games, oldest to newest, with the betting line across them.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.samples, required this.line});

  final List<HitSample> samples;
  final double line;

  @override
  Widget build(BuildContext context) {
    final shown = samples
        .where((sample) => sample.value != null)
        .toList()
        .reversed
        .toList();
    if (shown.isEmpty) {
      return Text(
        'No recorded stat for this line, so there is no game chart.',
        style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
      );
    }
    final recent = shown.length > 10 ? shown.sublist(shown.length - 10) : shown;
    var peak = line.abs();
    var floor = 0.0;
    for (final sample in recent) {
      final value = sample.value!.toDouble();
      if (value.abs() > peak) peak = value.abs();
      if (value < floor) floor = value;
    }
    if (peak <= floor) peak = floor + 1;
    final span = peak - floor;
    return SizedBox(
      height: 176,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final lineY =
                    constraints.maxHeight *
                    (1 - ((line - floor) / span).clamp(0, 1));
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: lineY,
                      child: Container(
                        height: 2,
                        color: EdgeColors.textSecondary,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final sample in recent)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Tooltip(
                                message:
                                    '${sample.game.date.toIso8601String().substring(0, 10)} vs ${sample.game.opponent}: ${sample.value}',
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        ((sample.value!.toDouble() - floor) /
                                                span)
                                            .clamp(0.04, 1),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: sample.outcome == 'hit'
                                            ? EdgeColors.good
                                            : sample.outcome == 'miss'
                                            ? EdgeColors.bad
                                            : EdgeColors.textTertiary,
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
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Each bar is a recorded game, oldest to newest. The line across them is ${line.toStringAsFixed(1)}. Green cleared it, red missed.',
            style: EdgeType.label,
          ),
        ],
      ),
    );
  }
}
