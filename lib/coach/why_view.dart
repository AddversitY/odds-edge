import 'package:flutter/material.dart';

import '../domain/hit_rate.dart';
import '../domain/why_brief.dart';
import '../theme/edge_theme.dart';

/// The scannable Why: one sentence, a small chart when there are games,
/// short labeled rows, then a better price on its own card.
class WhyBriefView extends StatelessWidget {
  const WhyBriefView({super.key, required this.brief});

  final WhyBrief brief;

  @override
  Widget build(BuildContext context) {
    final alternative = brief.alternative;
    return Column(
      key: const Key('why-brief'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(brief.line, style: EdgeType.body),
        if (brief.hasChart) ...[
          const SizedBox(height: 12),
          RecentFormChart(
            samples: brief.bars,
            line: brief.lineValue,
            seasonAverage: brief.seasonAverage,
            hitLabel: brief.hitLabel,
            seasonLabel: brief.seasonLabel,
          ),
        ],
        if (brief.facts.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final fact in brief.facts) WhyFactRow(fact: fact),
        ],
        if (alternative != null) ...[
          const SizedBox(height: 4),
          AlternativeCard(note: alternative),
        ],
      ],
    );
  }
}

class WhyFactRow extends StatelessWidget {
  const WhyFactRow({super.key, required this.fact});

  final WhyFact fact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(fact.kind), size: 22, color: EdgeColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fact.label,
                  style: EdgeType.label.copyWith(
                    color: EdgeColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(fact.text, style: EdgeType.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _icon(WhyFactKind kind) => switch (kind) {
  WhyFactKind.price => Icons.sell_outlined,
  WhyFactKind.defense => Icons.shield_outlined,
  WhyFactKind.injuries => Icons.healing_outlined,
  WhyFactKind.script => Icons.route_outlined,
  WhyFactKind.sharp => Icons.balance_outlined,
  WhyFactKind.leg => Icons.checklist_outlined,
  WhyFactKind.fit => Icons.link,
};

class AlternativeCard extends StatelessWidget {
  const AlternativeCard({super.key, required this.note});

  final AlternativeNote note;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('why-alternative'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EdgeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(EdgeSpace.radius),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title,
            style: EdgeType.label.copyWith(
              color: EdgeColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(note.body, style: EdgeType.body),
        ],
      ),
    );
  }
}

/// Last games, oldest to newest, with the betting line across them.
/// The blue bar, when present, is the season average.
class RecentFormChart extends StatelessWidget {
  const RecentFormChart({
    super.key,
    required this.samples,
    required this.line,
    this.seasonAverage,
    this.hitLabel,
    this.seasonLabel,
  });

  final List<HitSample> samples;
  final double? line, seasonAverage;
  final String? hitLabel, seasonLabel;

  @override
  Widget build(BuildContext context) {
    final numbers = [
      for (final sample in samples)
        if (sample.value != null) sample.value!.toDouble(),
    ];
    final average = seasonAverage;
    if (numbers.isEmpty && average == null) {
      return Text(
        hitLabel ?? 'No recorded games for this line.',
        style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
      );
    }
    var peak = 0.0;
    var floor = 0.0;
    for (final value in [...numbers, ?average, ?line]) {
      if (value > peak) peak = value;
      if (value < floor) floor = value;
    }
    if (peak <= floor) peak = floor + 1;
    final span = peak - floor;
    final mark = line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 112,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final lineY = mark == null
                  ? null
                  : constraints.maxHeight *
                        (1 - ((mark - floor) / span).clamp(0, 1));
              return Stack(
                children: [
                  if (lineY != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: lineY,
                      child: Container(
                        height: 2,
                        color: EdgeColors.textSecondary,
                      ),
                    ),
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < samples.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Tooltip(
                                message:
                                    '${samples[i].game.date.toIso8601String().substring(0, 10)} vs ${samples[i].game.opponent}: ${samples[i].value}',
                                child: _bar(
                                  value: samples[i].value?.toDouble(),
                                  floor: floor,
                                  span: span,
                                  color: samples[i].outcome == 'hit'
                                      ? EdgeColors.good
                                      : samples[i].outcome == 'miss'
                                      ? EdgeColors.bad
                                      : EdgeColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        if (average != null)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Tooltip(
                                message:
                                    'Season average ${average.toStringAsFixed(1)}',
                                child: _bar(
                                  key: const Key('season-bar'),
                                  value: average,
                                  floor: floor,
                                  span: span,
                                  color: EdgeColors.accent,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        if (hitLabel != null) Text(hitLabel!, style: EdgeType.label),
        if (seasonLabel != null) Text(seasonLabel!, style: EdgeType.label),
        Text(
          average == null
              ? 'Green cleared the line. Red missed. Gray is a push.'
              : 'Green cleared the line. Red missed. The blue bar is the season average.',
          style: EdgeType.label,
        ),
      ],
    );
  }

  Widget _bar({
    Key? key,
    required double? value,
    required double floor,
    required double span,
    required Color color,
  }) {
    final amount = value;
    if (amount == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        key: key,
        widthFactor: 1,
        heightFactor: ((amount - floor) / span).clamp(0.04, 1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
