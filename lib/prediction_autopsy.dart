import 'package:flutter/material.dart';

import 'data/research_store.dart';
import 'domain/research.dart';
import 'domain/autopsy.dart';

class PredictionAutopsy extends StatefulWidget {
  const PredictionAutopsy({
    super.key,
    required this.records,
    required this.store,
  });
  final List<SavedResearch> records;
  final ResearchStore store;
  @override
  State<PredictionAutopsy> createState() => _PredictionAutopsyState();
}

class _PredictionAutopsyState extends State<PredictionAutopsy> {
  Map<String, ResearchReview> reviews = {};
  String? selectedKey, error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.store.loadReviews();
      if (mounted) setState(() => reviews = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Outcome reviews could not be loaded. Existing files are intact.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> review(SavedResearch r) async {
    final previous = reviews[researchId(r)];
    final source = TextEditingController(
      text: previous?.source ?? 'Manual entry',
    );
    final notes = TextEditingController(text: previous?.notes ?? '');
    var outcome = previous?.outcome ?? ResearchOutcome.win;
    var confirmed = false;
    String? validation;
    final result = await showDialog<ResearchReview>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            r.context.demo ? 'Review a practice prediction' : 'Record outcome',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r.title}\n${r.context.label}'),
                  const SizedBox(height: 12),
                  const Text(
                    'The saved prediction stays unchanged. This is a manual assessment, not a verified result feed.',
                  ),
                  DropdownButtonFormField<ResearchOutcome>(
                    initialValue: outcome,
                    decoration: const InputDecoration(
                      labelText: 'Selection result',
                    ),
                    items: ResearchOutcome.values
                        .map(
                          (o) => DropdownMenuItem(
                            value: o,
                            child: Text(
                              o == ResearchOutcome.voided
                                  ? 'Void / cancelled'
                                  : o.name.toUpperCase(),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => update(() => outcome = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: source,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Result source / reference',
                      hintText:
                          'e.g. official final score or settlement reference',
                    ),
                  ),
                  TextField(
                    controller: notes,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'What changed?',
                      hintText: 'Which assumptions held up? Which were wrong? Include evidence, not just whether the bet won.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: (v) => update(() => confirmed = v!),
                    title: Text(
                      r.context.demo
                          ? 'This is a practice outcome for demonstration research.'
                          : 'I checked that this exact selection has settled under its stated rules.',
                    ),
                  ),
                  if (validation != null)
                    Text(
                      validation!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!confirmed || source.text.trim().isEmpty) {
                  update(
                    () => validation = 'Confirm the outcome and provide a source or reference.',
                  );
                  return;
                }
                Navigator.pop(
                  ctx,
                  ResearchReview(
                    researchKey: researchId(r),
                    outcome: outcome,
                    recordedAt: DateTime.now().toUtc(),
                    source: source.text.trim(),
                    notes: notes.text.trim(),
                  ),
                );
              },
              child: Text(previous == null ? 'Save review' : 'Save correction'),
            ),
          ],
        ),
      ),
    );
    source.dispose();
    notes.dispose();
    if (result == null) return;
    try {
      await widget.store.saveReview(result);
      if (mounted) {
        setState(() {
          reviews = {...reviews, result.researchKey: result};
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'The review was not saved. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = AutopsySummary(widget.records, reviews);
    final r =
        widget.records.where((r) => researchId(r) == selectedKey).firstOrNull ??
        widget.records.firstOrNull;
    final result = r == null ? null : reviews[researchId(r)];
    final futureGame =
        r != null &&
        !r.context.demo &&
        (r.context.event == null ||
            !DateTime.now().toUtc().isAfter(r.context.event!.startsAt));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Prediction Autopsy',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Return to your original reasoning after the game. A win alone does not prove the forecast was good.',
            ),
            const SizedBox(height: 12),
            Text(
              '${summary.reviewed} of ${summary.total} snapshots reviewed · ${summary.scored} scored pregame selections',
            ),
            Text(
              summary.meanError == null
                  ? 'Forecast accuracy: not enough eligible reviewed research.'
                  : 'Mean probability error: ${summary.meanError!.toStringAsFixed(4)} (0 is best; 1 is worst).',
            ),
            Text(
              '${summary.demo} demonstration snapshots excluded from accuracy. ${summary.late} snapshots without a pregame timestamp excluded.',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('How accuracy is counted'),
              children: [
                const Text(
                  'Only the earliest non-demo, pregame snapshot for each exact selection is considered, whether or not it has been reviewed. Later revisions cannot replace it to improve the score. Voids are excluded. Error is half the sum of squared errors for win, loss and push probabilities (0–1); with no push probability it matches binary Brier error. Outcomes are manually entered and unverified. Different selections from the same game can be correlated; this is a diagnostic, not proof of a betting edge. All snapshots remain visible, including those without bets. Closing-line value requires a verified closing quote and is not calculated here.',
                ),
              ],
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
            if (loading)
              const LinearProgressIndicator()
            else if (r == null)
              const Text(
                'Save a research snapshot to begin. Demo snapshots can be reviewed as practice.',
              )
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('${widget.records.length}-${researchId(r)}'),
                initialValue: researchId(r),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Prediction to review',
                ),
                items: [
                  for (final item in {
                    for (final v in widget.records) researchId(v): v,
                  }.values)
                    DropdownMenuItem(
                      value: researchId(item),
                      child: Text(
                        '${item.title} · ${item.savedAt.toLocal()}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => selectedKey = v),
              ),
              const SizedBox(height: 12),
              Text(
                'Saved win chance ${(r.assumptions.probability * 100).toStringAsFixed(1)}% · push ${(r.assumptions.push * 100).toStringAsFixed(1)}%',
              ),
              Text(
                r.thesis.isEmpty
                    ? 'No original research notes.'
                    : 'Original reasoning: ${r.thesis}',
              ),
              if (result != null) ...[
                const Divider(),
                Text(
                  'Outcome: ${result.outcome.name.toUpperCase()} · ${r.context.demo ? 'practice' : 'manual, unverified'}',
                ),
                Text(
                  'Recorded ${result.recordedAt.toLocal()} · ${result.source}',
                ),
                Text(
                  'Review: ${result.notes.isEmpty ? 'No review notes.' : result.notes}',
                ),
                Text(
                  forecastError(r, result.outcome) == null
                      ? 'Void: excluded from probability error.'
                      : '${r.context.demo ? 'Practice ' : ''}probability error: ${forecastError(r, result.outcome)!.toStringAsFixed(4)}',
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: futureGame || error != null ? null : () => review(r),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  result == null ? 'Review outcome' : 'Correct review',
                ),
              ),
              if (futureGame)
                const Text(
                  'Available after the scheduled start; confirm settlement before recording.',
                ),
            ],
          ],
        ),
      ),
    );
  }
}
