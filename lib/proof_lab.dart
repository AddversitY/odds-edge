import 'package:flutter/material.dart';

import 'data/research_store.dart';
import 'domain/research.dart';
import 'domain/odds.dart';
import 'research_comparison.dart';

class ProofLab extends StatefulWidget {
  const ProofLab({super.key, this.store});
  final ResearchStore? store;
  @override
  State<ProofLab> createState() => _ProofLabState();
}

class _ProofLabState extends State<ProofLab> {
  ResearchAssumptions assumptions = const ResearchAssumptions();
  late final ResearchStore store = widget.store ?? ResearchStore();
  final thesis = TextEditingController();
  List<SavedResearch> saved = [];
  bool busy = true;
  String? failure, message;
  String percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final records = await store.load();
      if (mounted) setState(() => saved = records);
    } catch (_) {
      if (mounted) {
        setState(
          () => failure = 'Saved research could not be read. Existing files have been left intact.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    // Freeze the assumptions at the moment of saving, before any asynchronous IO.
    final record = SavedResearch(
      savedAt: DateTime.now().toUtc(),
      thesis: thesis.text.trim(),
      assumptions: assumptions,
    );
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await store.save(record);
      if (mounted) {
        setState(() {
          saved = [record, ...saved];
          message = 'Research saved on this device.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Save failed. Your changes are still on screen; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    thesis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DETROIT AT GREEN BAY · DEMO',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.4,
            color: Colors.amber,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Is +125 a good price for Detroit?',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'Invented matchup and assumptions. Explore how the math works; these are not validated forecasts or live odds.',
          style: TextStyle(color: Colors.white60, height: 1.6),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            metric(
              'Assumed chance to win',
              percent(assumptions.probability),
              accent,
            ),
            metric('Hypothetical EV', percent(assumptions.ev), accent),
            metric(
              'Chance needed to break even',
              percent(1 / ResearchAssumptions.decimalOdds),
              Colors.white,
            ),
            metric(
              'Fair odds from assumptions',
              americanLabel(1 / assumptions.probability),
              Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, size) {
            final controls = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '01  Adjust your assumptions',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 10),
                adjustment(
                  'Recent performance',
                  assumptions.performance,
                  (v) => ResearchAssumptions(
                    performance: v,
                    availability: assumptions.availability,
                    environment: assumptions.environment,
                  ),
                ),
                adjustment(
                  'Player availability',
                  assumptions.availability,
                  (v) => ResearchAssumptions(
                    performance: assumptions.performance,
                    availability: v,
                    environment: assumptions.environment,
                  ),
                ),
                adjustment(
                  'Home field / environment',
                  assumptions.environment,
                  (v) => ResearchAssumptions(
                    performance: assumptions.performance,
                    availability: assumptions.availability,
                    environment: v,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    assumptions = const ResearchAssumptions();
                    message = null;
                  }),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset assumptions'),
                ),
              ],
            );
            final sensitivity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '02  Check what could change',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 14),
                for (final scenario in assumptions.scenarios)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${scenario.name}: ${percent(scenario.ev)} EV'),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: scenario.ev.abs().clamp(0, .5) / .5,
                          color: scenario.ev > 0 ? accent : Colors.orangeAccent,
                          backgroundColor: Colors.white10,
                        ),
                      ],
                    ),
                  ),
                Text(
                  assumptions.sensitive
                      ? 'Assumption-sensitive: these alternatives change the sign of EV.'
                      : assumptions.ev <= 0
                      ? 'No positive EV under your baseline assumptions.'
                      : 'Positive in these illustrative scenarios; this does not establish a reliable edge.',
                  style: TextStyle(
                    color: assumptions.sensitive ? Colors.orangeAccent : accent,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'These examples lower the assumed win chance. Bars show the size of EV, not confidence.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            );
            if (size.maxWidth < 750) {
              return Column(
                children: [controls, const SizedBox(height: 22), sensitivity],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: controls),
                const SizedBox(width: 36),
                Expanded(child: sensitivity),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('How this is calculated'),
          children: const [
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Source: synthetic teaching fixture. Frozen baseline: 48%. Fixed sample decimal price: 2.25 (+125). '
                'Probability = baseline + your three percentage-point adjustments, capped to 1–99%. '
                'EV per unit = probability × 2.25 − 1. This exercise assumes no push. '
                'Illustrative model: illustrative-additive-v1. Calibration, sample size, historical accuracy and model uncertainty are unavailable. '
                'Your overrides never alter the frozen example baseline or price.',
                style: TextStyle(color: Colors.white60, height: 1.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('03  Save your thinking', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 14),
        TextField(
          controller: thesis,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Research notes',
            hintText: 'What is your theory, and what would change your mind?',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy || failure != null ? null : save,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(busy ? 'Please wait…' : 'Save research snapshot'),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message!),
          ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              failure!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Saved on this device only · demonstration research',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 24),
        ResearchComparison(records: saved),
        const SizedBox(height: 24),
        Text(
          'Saved research (${saved.length})',
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 10),
        if (saved.isEmpty)
          const Text(
            'Save your first hypothesis, then change assumptions and compare.',
            style: TextStyle(color: Colors.white60),
          ),
        for (final record in saved.take(20))
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '${percent(record.assumptions.probability)} assumed · ${percent(record.assumptions.ev)} hypothetical EV',
            ),
            subtitle: Text(
              '${record.savedAt.toLocal().toString().split('.').first} · demonstration',
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    record.thesis.isEmpty
                        ? 'No research notes.'
                        : record.thesis,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Performance ${record.assumptions.performance} pp · availability ${record.assumptions.availability} pp · environment ${record.assumptions.environment} pp',
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  assumptions = record.assumptions;
                  thesis.text = record.thesis;
                  message = 'Loaded a saved copy for exploration. The saved snapshot is unchanged.';
                }),
                child: const Text('Explore a copy'),
              ),
            ],
          ),
        if (saved.length > 20)
          const Text(
            'Showing the latest 20 snapshots. Earlier records remain stored.',
          ),
      ],
    );
  }

  Widget metric(String label, String value, Color color) => Container(
    width: 190,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0F1520),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: .06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 30,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
  Widget adjustment(
    String label,
    double value,
    ResearchAssumptions Function(double) update,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text('$label: ${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} pp'),
      Slider(
        label: '${value.toStringAsFixed(1)} pp',
        semanticFormatterCallback: (v) =>
            '${v.toStringAsFixed(1)} percentage points',
        value: value,
        min: -10,
        max: 10,
        divisions: 40,
        onChanged: (v) => setState(() {
          assumptions = update(v);
          message = null;
        }),
      ),
    ],
  );
}
