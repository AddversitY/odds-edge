import 'package:flutter/material.dart';

import 'domain/research.dart';

/// Compares immutable snapshots from the same fixed teaching exercise.
class ResearchComparison extends StatefulWidget {
  const ResearchComparison({super.key, required this.records});
  final List<SavedResearch> records;

  @override
  State<ResearchComparison> createState() => _ResearchComparisonState();
}

class _ResearchComparisonState extends State<ResearchComparison> {
  SavedResearch? selectedA, selectedB;

  String percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
  String delta(double value) =>
      '${value.abs() < .00001
          ? ''
          : value > 0
          ? '+'
          : '−'}${value.abs().toStringAsFixed(1)} pp';

  @override
  Widget build(BuildContext context) {
    if (widget.records.length < 2) {
      return const Text(
        'Compare your reasoning: save two snapshots to see what changed.',
      );
    }
    final a = widget.records.contains(selectedA)
        ? selectedA!
        : widget.records[1];
    final b = widget.records.contains(selectedB)
        ? selectedB!
        : widget.records.first;
    final aa = a.assumptions;
    final bb = b.assumptions;
    final flipped = (a.ev > 0) != (b.ev > 0);
    final sameSelection = a.context.identity == b.context.identity;
    final rows = <(String, double, double, bool)>[
      ('Recent performance', aa.performance, bb.performance, false),
      ('Player availability', aa.availability, bb.availability, false),
      ('Home field / environment', aa.environment, bb.environment, false),
      ('Baseline win chance', aa.baseProbability, bb.baseProbability, true),
      ('Push probability', aa.push, bb.push, true),
      ('Assumed win probability', aa.probability, bb.probability, true),
      ('Hypothetical EV', a.ev, b.ev, true),
    ];
    Widget selector(String label, SavedResearch value, bool first) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<SavedResearch>(
          key: ValueKey(
            '$label-${widget.records.length}-${widget.records.indexOf(value)}',
          ),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (var i = 0; i < widget.records.length; i++)
              DropdownMenuItem(
                value: widget.records[i],
                child: Text(
                  '#${widget.records.length - i} · ${widget.records[i].title} · ${widget.records[i].savedAt.toLocal().toString().split('.').first}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (record) => setState(() {
            // Keep the other selection stable when newer records arrive.
            selectedA = first ? record : a;
            selectedB = first ? b : record;
          }),
        ),
        const SizedBox(height: 8),
        Text(value.thesis.isEmpty ? 'No research notes.' : value.thesis),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Compare saved research', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Text(
          '${a.context.label} · A price ${a.context.price.toStringAsFixed(2)} / B price ${b.context.price.toStringAsFixed(2)} decimal. Changes are B minus A. pp means percentage points. User assumptions, not validated forecasts.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final left = selector('Snapshot A', a, true);
            final right = selector('Snapshot B', b, false);
            if (constraints.maxWidth < 650) {
              return Column(
                children: [left, const SizedBox(height: 16), right],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 24),
                Expanded(child: right),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (!sameSelection)
          const Text(
            'Different selections cannot be compared as the same bet.',
          ),
        if (sameSelection)
          for (final row in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.$1),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        Text('A: ${row.$4 ? percent(row.$2) : delta(row.$2)}'),
                        Text('B: ${row.$4 ? percent(row.$3) : delta(row.$3)}'),
                        Text(
                          'Change: ${delta((row.$3 - row.$2) * (row.$4 ? 100 : 1))}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        Text(
          !sameSelection
              ? 'Choose snapshots of the exact same selection.'
              : identical(a, b)
              ? 'You selected the same snapshot twice. Choose another to compare.'
              : flipped
              ? 'The EV conclusion changed: one snapshot is positive and the other is not.'
              : 'The EV conclusion did not cross the break-even point.',
        ),
        const SizedBox(height: 8),
        const Text(
          'A higher estimate is not evidence of a better prediction. Differences may reflect assumptions or captured prices. No forecast accuracy is measured here. Saved originals stay unchanged.',
          style: TextStyle(color: Colors.white60, height: 1.5),
        ),
      ],
    );
  }
}
