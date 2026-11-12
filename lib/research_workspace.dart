import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/research_store.dart';
import 'domain/assistant.dart';
import 'domain/research.dart';
import 'domain/odds.dart';
import 'research_comparison.dart';
import 'prediction_autopsy.dart';

class ResearchWorkspace extends StatefulWidget {
  const ResearchWorkspace({
    super.key,
    this.store,
    this.initialContext,
    this.calculator,
    this.assistant,
    this.teamEvidence = const [],
    this.playerEvidence = const [],
  });
  final ResearchStore? store;
  final ResearchContext? initialContext;
  final Widget? calculator;
  final Future<AssistantReply> Function(AssistantRequest request)? assistant;
  final List<Map<String, dynamic>> teamEvidence, playerEvidence;
  @override
  State<ResearchWorkspace> createState() => _ResearchWorkspaceState();
}

class _ResearchWorkspaceState extends State<ResearchWorkspace> {
  late final ResearchStore store = widget.store ?? ResearchStore();
  ResearchAssumptions assumptions = const ResearchAssumptions();
  late ResearchContext subject =
      widget.initialContext ?? const ResearchContext();
  final thesis = TextEditingController(), name = TextEditingController();
  final question = TextEditingController();
  AssistantNote? assistantNote;
  String assistantStatus = '';
  bool asking = false;
  int askGeneration = 0;
  List<SavedResearch> saved = [];
  String query = '', message = '', draftStatus = 'Loading research…';
  bool busy = true, ready = false, library = false;
  Timer? debounce;
  int revision = 0;
  String pct(double value) => '${(value * 100).toStringAsFixed(1)}%';
  double get ev => assumptions.evAt(subject.price);
  bool get sensitive =>
      ev > 0 &&
      assumptions.scenarios.any(
        (s) =>
            expectedValue(
              subject.price,
              s.probability,
              push: assumptions.push,
            ) <=
            0,
      );
  String get takeaway => ev <= 0
      ? 'Your assumptions do not suggest value at this price.'
      : sensitive
      ? 'Assumption-sensitive: a lower win chance removes the apparent value.'
      : 'Positive in these stress tests. Forecast reliability is still untested.';
  SavedResearch snapshot() => SavedResearch(
    savedAt: DateTime.now().toUtc(),
    name: name.text.trim(),
    thesis: thesis.text.trim(),
    assumptions: assumptions,
    context: subject,
    assistant: assistantNote,
  );
  void applyAssumptions(ResearchAssumptions next) {
    if (jsonEncode(next.toJson()) != jsonEncode(assumptions.toJson())) {
      assistantNote = null;
      assistantStatus = '';
      asking = false;
      askGeneration++;
    }
    assumptions = next;
  }

  AssistantRequest assistantRequest(String mode) => AssistantRequest(
    mode: mode,
    question: question.text.trim(),
    selection: {
      'label': subject.label,
      'matchup': subject.matchup,
      'price': subject.price,
      'demo': subject.demo,
      'identity': subject.identity,
    },
    quote: subject.quote?.toJson(),
    event: subject.event?.toJson(),
    assumptions: assumptions.toJson(),
    teamEvidence: widget.teamEvidence,
    playerEvidence: widget.playerEvidence,
  );
  Future<void> ask(String mode) async {
    if (!ready || asking) return;
    final generation = ++askGeneration;
    if (widget.assistant == null) {
      setState(() {
        assistantNote = null;
        assistantStatus = 'assistant unavailable\nConnect the local backend to ask. This app does not contact the model itself.';
      });
      return;
    }
    setState(() {
      asking = true;
      assistantStatus = '';
    });
    try {
      final reply = await widget.assistant!(assistantRequest(mode));
      if (!mounted || generation != askGeneration) return;
      if (!reply.available) {
        setState(() {
          assistantNote = null;
          assistantStatus =
              '${reply.answer.trim().isEmpty ? 'assistant unavailable' : reply.answer.trim()}\nSaved odds, notes, and assumptions were not changed.';
        });
        return;
      }
      setState(() {
        assistantNote = AssistantNote(
          generatedAt: DateTime.now().toUtc(),
          mode: mode,
          question: question.text.trim(),
          answer: reply.answer,
          cited: reply.cited,
        );
        assistantStatus = '';
      });
      changed();
    } catch (_) {
      if (mounted && generation == askGeneration) {
        setState(() {
          assistantNote = null;
          assistantStatus = 'assistant unavailable\nSaved odds, notes, and assumptions were not changed.';
        });
      }
    } finally {
      if (mounted && generation == askGeneration) {
        setState(() => asking = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    name.addListener(changed);
    thesis.addListener(changed);
    load();
  }

  Future<void> load() async {
    try {
      saved = await store.load();
      final draft = await store.loadDraft(
        selectionKey: widget.initialContext?.identity,
      );
      if (!mounted) return;
      if (draft != null &&
          (widget.initialContext == null ||
              draft.context.identity == subject.identity)) {
        restore(draft);
        subject = widget.initialContext ?? subject;
      } else if (widget.initialContext != null) {
        assumptions = const ResearchAssumptions(
          performance: 0,
          availability: 0,
          environment: 0,
          baseProbability: .5,
        );
      }
      draftStatus = 'Draft saves automatically';
      if (store.warnings.isNotEmpty) message = store.warnings.join('\n');
      ready = true;
    } catch (_) {
      message = 'Some local research could not be loaded. Existing files are intact. Export a backup before recovery.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void restore(SavedResearch r) {
    assumptions = r.assumptions;
    subject = r.context;
    assistantNote = r.assistant;
    assistantStatus = '';
    question.text = r.assistant?.question ?? '';
    name.text = r.name;
    thesis.text = r.thesis;
  }

  void changed() {
    if (!ready) return;
    revision++;
    debounce?.cancel();
    setState(() => draftStatus = 'Saving draft…');
    debounce = Timer(const Duration(milliseconds: 350), persistDraft);
  }

  Future<void> persistDraft() async {
    final version = revision;
    try {
      await store.saveDraft(snapshot());
      if (mounted && version == revision) {
        setState(() => draftStatus = 'Draft saved on this device');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => draftStatus =
              'Draft save failed. Keep this screen open and retry.',
        );
      }
    }
  }

  Future<void> save() async {
    final record = snapshot();
    setState(() => busy = true);
    try {
      await store.save(record);
      await persistDraft();
      if (mounted) {
        setState(() {
          saved = [record, ...saved];
          message = 'Snapshot saved. Open Research library to compare.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Save failed. Your work is still on screen.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    if (ready) {
      final record = snapshot();
      unawaited(store.saveDraft(record).catchError((Object _) {}));
    }
    name.dispose();
    thesis.dispose();
    question.dispose();
    super.dispose();
  }

  Future<void> export() async {
    try {
      final path = await store.backup();
      final json = await store.exportJson();
      if (!mounted) return;
      setState(() => message = 'Backup saved: $path');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Research backup'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'An exact file backup preserves damaged entries too. Copy the portable export to move readable snapshots to another device. The portable export also includes the bet log from Tools.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(path),
                  const SizedBox(height: 12),
                  SelectableText(json, maxLines: 6),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Copy export'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Backup failed. Original research was not changed.',
        );
      }
    }
  }

  Future<void> import() async {
    final input = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore exported research'),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: input,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Paste an Odds Edge export. Existing research is kept.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    input.dispose();
    if (text == null) return;
    try {
      final count = await store.importJson(text);
      final records = await store.load();
      if (mounted) {
        setState(() {
          saved = records;
          message =
              'Imported $count snapshots. Duplicates skipped; originals kept.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Import failed. Use an unmodified Odds Edge export; existing research is kept.',
        );
      }
    }
  }

  Widget assistantPanel() {
    final canAsk = ready && !asking && !busy;
    final included = [
      subject.quote == null
          ? 'demonstration selection'
          : 'frozen quote and selection',
      'your assumptions',
      if (widget.teamEvidence.isNotEmpty) 'team evidence',
      if (widget.playerEvidence.isNotEmpty) 'player evidence',
    ].join(', ');
    final missing = [
      if (widget.teamEvidence.isEmpty)
        'No team evidence is attached, so team statistics cannot be supplied.',
      if (widget.playerEvidence.isEmpty) 'No player evidence is attached, so player statistics cannot be supplied.',
    ].join(' ');
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Explain / challenge this research',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI-generated',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Commentary from the research assistant. It is kept separate from your notes and assumptions. It is not a fact, a forecast, or a guarantee.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text('Included inputs: $included. $missing'.trim()),
          const SizedBox(height: 12),
          TextField(
            controller: question,
            maxLength: 500,
            maxLines: 3,
            enabled: ready && !asking,
            decoration: const InputDecoration(
              labelText: 'Question (optional)',
              hintText:
                  'Ask about these inputs only. Example: what is missing?',
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: canAsk ? () => ask('explain') : null,
                child: const Text('Explain this research'),
              ),
              OutlinedButton(
                onPressed: canAsk ? () => ask('challenge') : null,
                child: const Text('Challenge this research'),
              ),
            ],
          ),
          if (asking) ...[
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
            const SizedBox(height: 8),
            const Text('thinking…'),
            const Text(
              'A reasoning reply can take a minute. Only the inputs on this screen are being used.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (assistantStatus.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(assistantStatus),
          ],
          if (assistantNote != null) ...[
            const SizedBox(height: 12),
            AssistantCommentary(
              note: assistantNote!,
              demonstrationSelection: subject.quote == null,
            ),
          ],
        ],
      ),
    );
  }

  Widget adjustment(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> update,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text('$label: ${value.toStringAsFixed(1)}${max == 10 ? ' pp' : '%'}'),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: ((max - min) * 2).round(),
        label: value.toStringAsFixed(1),
        onChanged: ready
            ? (v) {
                setState(() => update(v));
                changed();
              }
            : null,
      ),
    ],
  );
  Widget panel(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final matching = saved
        .where((r) => r.context.identity == subject.identity)
        .toList();
    final filtered = saved
        .where(
          (r) => '${r.title} ${r.thesis} ${r.context.matchup}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    final quote = subject.quote;
    return Column(
      children: [
        Container(
          color: const Color(0xF20B1720),
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${subject.label} · ${americanLabel(subject.price)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                takeaway,
                style: TextStyle(
                  color: ev <= 0 || sensitive ? Colors.orangeAccent : accent,
                ),
              ),
              Text(
                '${pct(assumptions.probability)} assumed · ${pct(ev)} hypothetical EV · ${subject.demo ? 'DEMO' : 'CAPTURED QUOTE'}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: const Text('Explore'),
                      selected: !library,
                      onSelected: (_) => setState(() => library = false),
                    ),
                    ChoiceChip(
                      label: Text('Research library (${saved.length})'),
                      selected: library,
                      onSelected: (_) => setState(() => library = true),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SelectableText(message),
                  ),
                if (!library) ...[
                  panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.matchup,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          quote == null
                              ? 'Is +125 a good price for Detroit?'
                              : 'Investigate ${subject.label}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          quote == null
                              ? 'Invented matchup and assumptions. Demonstration only.'
                              : '${quote.book} · ${quote.demo ? 'sample' : 'captured'} price. This saved observation is not a current offer.',
                        ),
                        const Text(
                          'Probabilities are your assumptions, not validated forecasts. Adjustments are illustrative percentage-point changes.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        if (quote != null)
                          ExpansionTile(
                            title: const Text(
                              'Price source and exact selection',
                            ),
                            tilePadding: EdgeInsets.zero,
                            children: [
                              SelectableText(
                                'Provider: ${quote.provider}\nSource: ${quote.sourceAt.toUtc()}\nCollected: ${quote.collectedAt.toUtc()}\nStatus at capture: ${quote.status}\nPeriod: ${quote.selection.period}\nRules: ${quote.selection.rules}\nExact selection: ${quote.selection.key}',
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 24,
                          runSpacing: 12,
                          children: [
                            Text(
                              'Break-even: ${pct((1 - assumptions.push) / subject.price)}',
                            ),
                            Text(
                              'Fair odds: ${americanLabel((1 - assumptions.push) / assumptions.probability)}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, size) {
                      final controls = panel(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '01  Adjust your assumptions',
                              style: TextStyle(fontSize: 18),
                            ),
                            adjustment(
                              'Baseline win chance',
                              assumptions.baseProbability * 100,
                              1,
                              99,
                              (v) => applyAssumptions(
                                assumptions.copyWith(baseProbability: v / 100),
                              ),
                            ),
                            adjustment(
                              'Recent performance',
                              assumptions.performance,
                              -10,
                              10,
                              (v) => applyAssumptions(
                                assumptions.copyWith(performance: v),
                              ),
                            ),
                            adjustment(
                              'Player availability',
                              assumptions.availability,
                              -10,
                              10,
                              (v) => applyAssumptions(
                                assumptions.copyWith(availability: v),
                              ),
                            ),
                            adjustment(
                              'Home field / environment',
                              assumptions.environment,
                              -10,
                              10,
                              (v) => applyAssumptions(
                                assumptions.copyWith(environment: v),
                              ),
                            ),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text('Push / refund assumption'),
                              children: [
                                adjustment(
                                  'Push probability',
                                  assumptions.push * 100,
                                  0,
                                  50,
                                  (v) => applyAssumptions(
                                    assumptions.copyWith(push: v / 100),
                                  ),
                                ),
                                const Text(
                                  'Use only if the market rules refund this outcome. Win probability is capped so win + push cannot exceed 100%.',
                                ),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: ready
                                  ? () {
                                      setState(
                                        () => applyAssumptions(
                                          subject.quote == null
                                              ? const ResearchAssumptions()
                                              : const ResearchAssumptions(
                                                  performance: 0,
                                                  availability: 0,
                                                  environment: 0,
                                                  baseProbability: .5,
                                                ),
                                        ),
                                      );
                                      changed();
                                    }
                                  : null,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset assumptions'),
                            ),
                          ],
                        ),
                      );
                      final stress = panel(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '02  Check what could change',
                              style: TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 18),
                            for (final s in assumptions.scenarios)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${s.name}: ${pct(expectedValue(subject.price, s.probability, push: assumptions.push))} EV',
                                    ),
                                    const SizedBox(height: 8),
                                    SignedEvBar(
                                      value: expectedValue(
                                        subject.price,
                                        s.probability,
                                        push: assumptions.push,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const Text(
                              'Loss ← 0 → Gain',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const Text(
                              'Fixed −100% to +100% scale (longer values clipped). Illustrative stress tests, not confidence intervals.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                      return size.maxWidth < 750
                          ? Column(
                              children: [
                                controls,
                                const SizedBox(height: 16),
                                stress,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: controls),
                                const SizedBox(width: 16),
                                Expanded(child: stress),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 16),
                  assistantPanel(),
                  const SizedBox(height: 16),
                  panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '03  Save your thinking',
                          style: TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: name,
                          maxLength: 100,
                          enabled: ready,
                          decoration: const InputDecoration(
                            labelText: 'Research name',
                            hintText: 'e.g. Lower-pace scenario',
                          ),
                        ),
                        TextField(
                          controller: thesis,
                          maxLength: 1000,
                          maxLines: 3,
                          enabled: ready,
                          decoration: const InputDecoration(
                            labelText: 'Research notes',
                            hintText: 'What supports your theory? What would change your mind?',
                          ),
                        ),
                        Text(
                          draftStatus,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: busy || !ready ? null : save,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Save research snapshot'),
                        ),
                      ],
                    ),
                  ),
                  ExpansionTile(
                    title: const Text('How this is calculated'),
                    children: [
                      Text(
                        'Probability = your baseline plus three adjustments, capped to 1–99% and at most 100% minus push probability. EV = win × (decimal price − 1) − loss. Fair decimal odds = (1 − push) / win. Model ${ResearchAssumptions.modelVersion}; calibration and predictive accuracy are unvalidated. Stress tests subtract 4, 7 and 9 percentage points from the win chance.',
                      ),
                    ],
                  ),
                ] else ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: export,
                        icon: const Icon(Icons.download),
                        label: const Text('Backup / export'),
                      ),
                      TextButton.icon(
                        onPressed: import,
                        icon: const Icon(Icons.upload),
                        label: const Text('Restore export'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search research',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 16),
                  ResearchComparison(records: matching),
                  const SizedBox(height: 20),
                  PredictionAutopsy(
                    key: ValueKey(saved.length),
                    records: saved,
                    store: store,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'All saved research',
                    style: TextStyle(fontSize: 20),
                  ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No matching research. Save a snapshot in Explore to begin.',
                      ),
                    ),
                  for (final r in filtered)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Card(
                        child: ExpansionTile(
                          title: Text(r.title),
                          subtitle: Text(
                            '${r.context.label} · ${americanLabel(r.context.price)} · ${pct(r.ev)} hypothetical EV\n${r.savedAt.toLocal()}',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.thesis.isEmpty ? 'No notes.' : r.thesis,
                                  ),
                                  if (r.assistant != null) ...[
                                    const SizedBox(height: 12),
                                    AssistantCommentary(
                                      note: r.assistant!,
                                      demonstrationSelection:
                                          r.context.quote == null,
                                    ),
                                  ],
                                  TextButton(
                                    onPressed: () async {
                                      if (ready) {
                                        await store.saveDraft(snapshot());
                                      }
                                      if (!mounted) return;
                                      setState(() {
                                        restore(r);
                                        library = false;
                                        message = 'Exploring a copy. The saved original is unchanged.';
                                      });
                                      changed();
                                    },
                                    child: const Text('Explore a copy'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (widget.calculator != null)
                  ExpansionTile(
                    title: const Text('Standalone odds and EV calculator'),
                    children: [widget.calculator!],
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AssistantCommentary extends StatelessWidget {
  const AssistantCommentary({
    super.key,
    required this.note,
    required this.demonstrationSelection,
  });
  final AssistantNote note;
  final bool demonstrationSelection;
  @override
  Widget build(BuildContext context) {
    final labels = note.cited
        .map(
          (id) => id == 'frozen_quote' && demonstrationSelection
              ? 'Demonstration selection'
              : (assistantInputLabels[id] ?? id),
        )
        .join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI-generated',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const Text(
          'Separate from your notes and assumptions. Not a fact or a forecast.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SelectableText(note.answer),
        const SizedBox(height: 8),
        Text(
          note.cited.isEmpty
              ? 'Cited inputs: none identified.'
              : 'Cited inputs: $labels',
        ),
        const SizedBox(height: 4),
        const Text(
          'Not a recommendation. No outcome is guaranteed.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class SignedEvBar extends StatelessWidget {
  const SignedEvBar({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Expected value ${(value * 100).toStringAsFixed(1)} percent',
    child: SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            Positioned(
              left: value < 0
                  ? c.maxWidth / 2 * (1 - value.abs().clamp(0, 1))
                  : c.maxWidth / 2,
              width: c.maxWidth / 2 * value.abs().clamp(0, 1),
              top: 2,
              bottom: 2,
              child: ColoredBox(
                color: value < 0
                    ? Colors.orangeAccent
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            Positioned(
              left: c.maxWidth / 2,
              top: 0,
              bottom: 0,
              width: 1,
              child: const ColoredBox(color: Colors.white70),
            ),
          ],
        ),
      ),
    ),
  );
}
