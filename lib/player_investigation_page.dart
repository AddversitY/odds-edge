import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/research_store.dart';
import 'domain/odds.dart';
import 'domain/player_investigation.dart';
import 'domain/player_simulation.dart';
import 'domain/player_stats.dart';

class PlayerInvestigationPage extends StatefulWidget {
  const PlayerInvestigationPage({
    super.key,
    required this.player,
    required this.games,
    required this.metadata,
    required this.store,
    this.initialStep = 0,
    this.initialRecord,
  });
  final PlayerGame player;
  final List<PlayerGame> games;
  final Map<String, dynamic> metadata;
  final ResearchStore store;
  final int initialStep;
  final PlayerInvestigation? initialRecord;
  @override
  State<PlayerInvestigationPage> createState() =>
      _PlayerInvestigationPageState();
}

class _PlayerInvestigationPageState extends State<PlayerInvestigationPage> {
  final line = TextEditingController(text: '249.5');
  final price = TextEditingController(text: '-110');
  final book = TextEditingController(), thesis = TextEditingController();
  late String metric;
  late DateTime cutoff;
  DateTime? target;
  int step = 0, window = 20;
  int seed = 42, trials = 10000;
  bool over = true, saving = false;
  double workload = 1, efficiency = 1;
  String message = '';
  List<PlayerInvestigation> records = [];
  Map<String, PlayerInvestigationReview> reviews = {};
  static const mint = Color(0xff7ce7c0);

  @override
  void initState() {
    super.initState();
    step = widget.initialStep;
    metric = widget.player.position == 'QB'
        ? 'passing_yards'
        : widget.player.position == 'RB' || widget.player.position == 'FB'
        ? 'rushing_yards'
        : 'receiving_yards';
    cutoff = DateTime.parse('${widget.metadata['cutoff']}T00:00:00Z');
    final typical = PlayerStatWindow(
      playerGames(widget.games, widget.player.playerId).take(20).toList(),
    ).average(metric);
    line.text = typical == null ? '49.5' : '${typical.floor()}.5';
    final restored = widget.initialRecord;
    if (restored != null) {
      metric = restored.scenario.metric;
      cutoff = restored.cutoff;
      target = restored.targetDate;
      line.text = restored.scenario.line.toString();
      over = restored.scenario.over;
      workload = restored.scenario.workload;
      efficiency = restored.scenario.efficiency;
      seed = restored.scenario.seed;
      trials = restored.scenario.trials;
      window = -1;
      price.text =
          (restored.scenario.price >= 2
                  ? (restored.scenario.price - 1) * 100
                  : -100 / (restored.scenario.price - 1))
              .toString();
      book.text = restored.book;
      thesis.text = restored.thesis;
    }
    load();
  }

  Future<void> load() async {
    try {
      final saved = await widget.store.loadInvestigations();
      final outcomes = await widget.store.loadInvestigationReviews();
      if (mounted) {
        setState(() {
          records = saved;
          reviews = outcomes;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Saved investigations could not be loaded. Existing files are intact.',
        );
      }
    }
  }

  @override
  void dispose() {
    line.dispose();
    price.dispose();
    book.dispose();
    thesis.dispose();
    super.dispose();
  }

  List<PlayerGame> get available =>
      playerGames(widget.games, widget.player.playerId, through: cutoff);
  List<PlayerGame> get evidence {
    final rows = available;
    if (window == -1) {
      return widget.initialRecord?.games
              .where((g) => !g.date.isAfter(cutoff))
              .toList() ??
          rows;
    }
    return window == 0
        ? rows
              .where(
                (g) =>
                    g.season ==
                    (widget.metadata['currentSeason'] as num).toInt(),
              )
              .toList()
        : rows.take(window).toList();
  }

  PlayerScenario? get scenario {
    try {
      final s = PlayerScenario(
        metric: metric,
        line: double.parse(line.text),
        price: americanToDecimal(double.parse(price.text)),
        over: over,
        workload: workload,
        efficiency: efficiency,
        seed: seed,
        trials: trials,
      );
      s.validate();
      return s;
    } catch (_) {
      return null;
    }
  }

  String number(num? n, [int digits = 1]) =>
      n == null ? '—' : n.toStringAsFixed(digits);
  String pct(double? n) => n == null ? '—' : '${(n * 100).toStringAsFixed(1)}%';
  String date(DateTime n) => n.toIso8601String().substring(0, 10);
  bool futureTarget(DateTime? target) {
    final today = DateTime.now();
    return target != null &&
        target.isAfter(DateTime.utc(today.year, today.month, today.day));
  }

  Widget panel(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  Widget gap() => const SizedBox(height: 16);

  Future<void> chooseCutoff() async {
    final last = DateTime.parse('${widget.metadata['cutoff']}T00:00:00Z');
    final first = widget.games
        .map((g) => g.date)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final selected = await showDatePicker(
      context: context,
      initialDate: cutoff,
      firstDate: first,
      lastDate: last,
    );
    if (selected != null) {
      setState(() {
        cutoff = DateTime.utc(selected.year, selected.month, selected.day);
        if (target != null && !target!.isAfter(cutoff)) target = null;
      });
    }
  }

  Future<void> chooseTarget() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate:
          target ??
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      firstDate: cutoff.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 2),
    );
    if (selected != null) {
      setState(
        () =>
            target = DateTime.utc(selected.year, selected.month, selected.day),
      );
    }
  }

  Future<void> save() async {
    final s = scenario;
    if (s == null ||
        !PlayerSimulation(evidence, s).available ||
        thesis.text.trim().isEmpty) {
      setState(
        () => message = 'Enter a valid line and American odds, use at least 5 recorded game pairs, and write your reasoning.',
      );
      return;
    }
    setState(() => saving = true);
    try {
      final r = PlayerInvestigation(
        savedAt: DateTime.now().toUtc(),
        playerId: widget.player.playerId,
        playerName: widget.player.name,
        scenario: s,
        games: evidence,
        cutoff: cutoff,
        source: widget.metadata['source']?.toString() ?? 'nflverse',
        sourceRetrievedAt:
            widget.metadata['retrievedAt']?.toString() ?? 'not supplied',
        sourceDigest:
            widget.initialRecord?.sourceDigest ??
            jsonEncode(widget.metadata['sourceFiles'] ?? []),
        sourceUrl:
            widget.initialRecord?.sourceUrl ??
            widget.metadata['sourceUrl']?.toString() ??
            '',
        license:
            widget.initialRecord?.license ??
            widget.metadata['license']?.toString() ??
            '',
        licenseUrl:
            widget.initialRecord?.licenseUrl ??
            widget.metadata['licenseUrl']?.toString() ??
            '',
        book: book.text.trim(),
        thesis: thesis.text.trim(),
        targetDate: target,
      );
      await widget.store.saveInvestigation(r);
      if (mounted) {
        setState(() {
          records = [r, ...records];
          step = 3;
          message = 'Prediction saved with frozen evidence and assumptions. You can return here to review it.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'The prediction was not saved. Your inputs are still on screen.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> review(PlayerInvestigation r) async {
    final previous = reviews[r.id];
    final actual = TextEditingController(
      text: previous?.actualYards?.toString() ?? '',
    );
    final volume = TextEditingController(
      text: previous?.actualVolume?.toString() ?? '',
    );
    final source = TextEditingController(text: previous?.source ?? '');
    final notes = TextEditingController(text: previous?.notes ?? '');
    var voided = previous?.voided ?? false, confirmed = false;
    String? error;
    final result = await showDialog<PlayerInvestigationReview>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Review the prediction'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.title),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter the final result for this exact player, game and settlement rules. Results are manual and unverified.',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Void / cancelled'),
                    value: voided,
                    onChanged: (v) => update(() => voided = v),
                  ),
                  if (!voided) ...[
                    TextField(
                      controller: actual,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Final yards',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: volume,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'Actual ${playerYardageMarkets[r.scenario.metric]!.$3.toLowerCase()} (optional)',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: source,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Result source / reference',
                    ),
                  ),
                  TextField(
                    controller: notes,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'What held up? What was wrong?',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: (v) => update(() => confirmed = v!),
                    title: const Text(
                      'I checked the settled result and exact game.',
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
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
                try {
                  if (!confirmed) {
                    throw const FormatException('Confirm the result');
                  }
                  final value = PlayerInvestigationReview.fromJson(
                    PlayerInvestigationReview(
                      id: r.id,
                      recordedAt: DateTime.now().toUtc(),
                      source: source.text.trim(),
                      notes: notes.text.trim(),
                      actualYards: voided ? null : double.tryParse(actual.text),
                      actualVolume: voided || volume.text.trim().isEmpty
                          ? null
                          : double.parse(volume.text),
                      voided: voided,
                    ).toJson(),
                  );
                  Navigator.pop(ctx, value);
                } catch (_) {
                  update(
                    () => error =
                        'Check the result values, source and confirmation.',
                  );
                }
              },
              child: const Text('Save outcome'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog route finishes its closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    actual.dispose();
    volume.dispose();
    source.dispose();
    notes.dispose();
    if (result == null) return;
    try {
      await widget.store.saveInvestigationReview(result);
      if (mounted) setState(() => reviews = {...reviews, result.id: result});
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'The outcome could not be saved. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = scenario;
    final simulation = s == null ? null : PlayerSimulation(evidence, s);
    return Scaffold(
      appBar: AppBar(title: const Text('Investigate a bet')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in [
                    'Evidence',
                    'Simulate',
                    'Save',
                    'Review',
                  ].asMap().entries)
                    ChoiceChip(
                      key: ValueKey('investigation-step-${entry.key}'),
                      label: Text('${entry.key + 1}. ${entry.value}'),
                      selected: step == entry.key,
                      onSelected: (_) => setState(() => step = entry.key),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1050),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.player.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(color: mint),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Check the evidence. Test what could change it. Save the reasoning.',
                        ),
                        gap(),
                        if (message.isNotEmpty) ...[
                          Text(message, style: const TextStyle(color: mint)),
                          gap(),
                        ],
                        if (step == 0) ...evidenceView(s),
                        if (step == 1) ...simulationView(simulation),
                        if (step == 2) ...saveView(simulation),
                        if (step == 3) ...reviewView(),
                        gap(),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            if (step > 0)
                              OutlinedButton(
                                onPressed: () => setState(() => step--),
                                child: const Text('Back'),
                              ),
                            if (step < 2)
                              FilledButton(
                                onPressed: () => setState(() => step++),
                                child: Text(
                                  step == 0
                                      ? 'Test scenarios'
                                      : 'Save the reasoning',
                                ),
                              ),
                          ],
                        ),
                        gap(),
                        const Text(
                          'Research tool · historical scenario replay · manual prices · no automatic live API requests',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> evidenceView(PlayerScenario? s) {
    final form = PlayerFormEvidence(evidence, metric);
    final recent = PlayerStatWindow(form.recent),
        earlier = PlayerStatWindow(form.earlier);
    return [
      panel('Define the question', [
        const Text(
          'Choose the exact yardage selection and enter the price you see. Starting line and odds are examples, not a sportsbook quote. Replace them with your own selection. This does not fetch sportsbook prices.',
        ),
        gap(),
        DropdownButtonFormField<String>(
          key: ValueKey('investigation-metric-$metric'),
          initialValue: metric,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Statistic'),
          items: playerYardageMarkets.entries
              .map(
                (m) => DropdownMenuItem(value: m.key, child: Text(m.value.$1)),
              )
              .toList(),
          onChanged: (v) => setState(() {
            metric = v!;
            workload = 1;
            efficiency = 1;
          }),
        ),
        gap(),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Over'),
              selected: over,
              onSelected: (_) => setState(() => over = true),
            ),
            ChoiceChip(
              label: const Text('Under'),
              selected: !over,
              onSelected: (_) => setState(() => over = false),
            ),
          ],
        ),
        gap(),
        TextField(
          key: const Key('investigation-line'),
          controller: line,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Exact line / threshold',
            helperText: 'Different thresholds are different selections.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        gap(),
        TextField(
          key: const Key('investigation-price'),
          controller: price,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'American odds',
            helperText: 'For example −110 or +125. Manually entered, not verified live.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        gap(),
        TextField(
          controller: book,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Sportsbook / price source (optional)',
          ),
        ),
        if (s == null)
          const Text(
            'Enter a line from 0 to 1000 and American odds of at least +100 or at most −100.',
            style: TextStyle(color: Colors.orangeAccent),
          ),
      ]),
      gap(),
      panel('Is the recent trend meaningful?', [
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: window,
          decoration: const InputDecoration(labelText: 'Evidence window'),
          items: [
            if (window == -1)
              const DropdownMenuItem(
                value: -1,
                child: Text('Frozen saved sample'),
              ),
            DropdownMenuItem(value: 20, child: Text('Last 20 recorded games')),
            DropdownMenuItem(value: 10, child: Text('Last 10 recorded games')),
            DropdownMenuItem(value: 0, child: Text('Current season')),
          ],
          onChanged: (v) => setState(() => window = v!),
        ),
        gap(),
        TextButton.icon(
          onPressed: chooseCutoff,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text('Evidence through ${date(cutoff)}'),
        ),
        Text(
          '${evidence.length} regular-season records. Last 3 are compared with the separate earlier ${form.earlier.length} records.',
        ),
        gap(),
        metricRow(
          'Yards per game',
          recent.average(metric),
          earlier.average(metric),
        ),
        metricRow(
          '${playerYardageMarkets[metric]!.$3} per game',
          recent.average(form.volumeMetric),
          earlier.average(form.volumeMetric),
        ),
        metricRow(
          'Yards per opportunity',
          form.rate(form.recent),
          form.rate(form.earlier),
        ),
        gap(),
        Text(form.interpretation, style: const TextStyle(color: mint)),
        if (form.recentWithoutLargest != null) ...[
          gap(),
          Text(
            'Without the highest-yardage recent game: ${number(form.recentWithoutLargest)} yards/game across the other 2 games.',
          ),
          const Text(
            'This outlier check is descriptive; two games are not enough to establish a forecast.',
          ),
        ],
        const Text(
          'Descriptive 10% comparison, not a significance test. Three games are a small sample. No injury, snap share, opponent-strength or weather adjustment is implied.',
        ),
        gap(),
        for (final g in form.recent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${date(g.date)} · ${g.team} vs ${g.opponent}'),
            subtitle: Text(
              '${number(g.stats[metric])} yards · ${number(g.stats[form.volumeMetric], 0)} ${playerYardageMarkets[metric]!.$3.toLowerCase()}',
            ),
          ),
        ExpansionTile(
          key: const PageStorageKey('investigation-evidence-source'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Sources and limitations'),
          children: [
            SelectableText(
              '${widget.metadata['source']}\n${widget.metadata['sourceUrl']}\n${widget.metadata['license']} · ${widget.metadata['licenseUrl']}\nRetrieved ${widget.metadata['retrievedAt']}',
            ),
            const Text(
              'Bundled retrospective records can contain later corrections. Filtering game dates is not strict point-in-time replay. Missing player rows do not establish a reason for absence. Source records stay separate from scenario assumptions.',
            ),
          ],
        ),
        if (s != null)
          ExpansionTile(
            key: const PageStorageKey('investigation-hit-rates'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Historical hit rates at this exact line'),
            children: [
              const Text(
                'Raw historical results, not a forecast. The line is held fixed across games; it is not claimed to be the sportsbook line offered at those times.',
              ),
              hitRate('Last 3', form.recent, s),
              hitRate('Earlier comparison sample', form.earlier, s),
              for (final year in [
                (widget.metadata['currentSeason'] as num).toInt(),
                ...previous3CompletedYears(
                  (widget.metadata['currentSeason'] as num).toInt(),
                ),
              ])
                hitRate(
                  '$year season through cutoff',
                  available.where((g) => g.season == year).toList(),
                  s,
                ),
            ],
          ),
      ]),
    ];
  }

  Widget metricRow(String label, num? recent, num? earlier) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('Last 3: ${number(recent)} · earlier sample: ${number(earlier)}'),
      ],
    ),
  );
  Widget hitRate(String label, List<PlayerGame> rows, PlayerScenario s) {
    final observed = rows.where((g) => g.stats[s.metric] != null).toList();
    final wins = observed
        .where(
          (g) => s.over
              ? g.stats[s.metric]! > s.line
              : g.stats[s.metric]! < s.line,
        )
        .length;
    final pushes = observed
        .where((g) => (g.stats[s.metric]! - s.line).abs() < 1e-9)
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$label: $wins/${observed.length} wins · $pushes pushes · ${observed.isEmpty ? 'no observations' : pct(wins / observed.length)}',
        ),
      ),
    );
  }

  List<Widget> simulationView(PlayerSimulation? sim) => [
    panel('What would have to happen?', [
      const Text(
        'Change opportunity and efficiency assumptions. Each replay samples a whole historical game pair, keeping that game’s yardage and workload together.',
      ),
      gap(),
      Text('Workload: ${(workload * 100).round()}% of sampled game'),
      Slider(
        key: const Key('investigation-workload'),
        value: workload,
        min: .5,
        max: 1.5,
        divisions: 20,
        label: '${(workload * 100).round()}%',
        onChanged: (v) => setState(() => workload = v),
      ),
      Text('Efficiency: ${(efficiency * 100).round()}% of sampled game'),
      Slider(
        key: const Key('investigation-efficiency'),
        value: efficiency,
        min: .7,
        max: 1.3,
        divisions: 12,
        label: '${(efficiency * 100).round()}%',
        onChanged: (v) => setState(() => efficiency = v),
      ),
      TextButton(
        onPressed: () => setState(() {
          workload = 1;
          efficiency = 1;
        }),
        child: const Text('Reset scenario assumptions'),
      ),
      if (sim == null)
        const Text('Define a valid selection and price in Evidence first.')
      else if (!sim.available)
        Text(
          'At least 5 games with both yardage and opportunity, including some recorded opportunity, are required. ${sim.sampleSize} available; ${sim.excluded} incomplete or inconsistent pairs excluded.',
        )
      else ...[
        gap(),
        Text(
          '${sim.scenario.over ? 'Over' : 'Under'} ${sim.scenario.line} · ${sim.scenario.label} · ${americanLabel(sim.scenario.price)}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        Text(
          'Conditional replay win rate: ${pct(sim.winProbability)} · push ${pct(sim.pushProbability)}',
        ),
        Text(
          'Conditional EV: ${pct(sim.ev)} per unit · break-even win probability with these pushes ${pct((1 - sim.pushProbability!) / sim.scenario.price)}',
        ),
        Text('Conditional fair decimal price: ${number(sim.fairDecimal, 2)}'),
        gap(),
        Text(
          'Simulated yards: median ${number(sim.percentile(.5))} · 10th–90th percentile ${number(sim.percentile(.1))}–${number(sim.percentile(.9))}',
        ),
        const Text(
          'This is a scenario outcome range, not a confidence interval.',
        ),
        gap(),
        histogram(sim),
        gap(),
        Text(
          '${sim.scenario.trials} seeded replays from ${sim.sampleSize} actual game pairs; ${sim.excluded} pairs excluded. More replays do not create more historical evidence.',
        ),
        const Text(
          'This empirical resampling model is unvalidated for future prediction. It does not account for opponent, injury, role changes or game state. Zero sampled losses do not establish certainty. EV is conditional on this replay distribution.',
        ),
        gap(),
        const Text(
          'Does the conclusion survive less favorable assumptions?',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        for (final item in stress(sim))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.$1),
            subtitle: Text(
              'Workload ${(item.$2.scenario.workload * 100).round()}% · efficiency ${(item.$2.scenario.efficiency * 100).round()}% · conditional win ${pct(item.$2.winProbability)} · EV ${pct(item.$2.ev)}',
            ),
          ),
        Text(
          sim.ev! > 0 && stress(sim).any((s) => s.$2.ev! <= 0)
              ? 'Assumption-sensitive: one of these changes removes the positive EV.'
              : sim.ev! > 0
              ? 'Positive across these tested scenarios; future reliability remains unvalidated.'
              : 'The current assumptions do not show positive conditional EV.',
          style: const TextStyle(color: mint),
        ),
      ],
    ]),
  ];
  List<(String, PlayerSimulation)> stress(PlayerSimulation sim) => [
    (
      sim.scenario.over ? '15% lower workload' : '15% higher workload',
      PlayerSimulation(
        evidence,
        sim.scenario.copyWith(
          workload: (workload * (sim.scenario.over ? 0.85 : 1.15)).clamp(
            .5,
            1.5,
          ),
        ),
      ),
    ),
    (
      sim.scenario.over ? '10% lower efficiency' : '10% higher efficiency',
      PlayerSimulation(
        evidence,
        sim.scenario.copyWith(
          efficiency: (efficiency * (sim.scenario.over ? 0.9 : 1.1)).clamp(
            .7,
            1.3,
          ),
        ),
      ),
    ),
    (
      'Both changes',
      PlayerSimulation(
        evidence,
        sim.scenario.copyWith(
          workload: (workload * (sim.scenario.over ? 0.85 : 1.15)).clamp(
            .5,
            1.5,
          ),
          efficiency: (efficiency * (sim.scenario.over ? 0.9 : 1.1)).clamp(
            .7,
            1.3,
          ),
        ),
      ),
    ),
  ];
  Widget histogram(PlayerSimulation sim) {
    final low = sim.draws.first, high = sim.draws.last, span = high - low;
    final bins = List<int>.filled(12, 0);
    for (final d in sim.draws) {
      bins[span == 0 ? 0 : ((d - low) / span * 11).floor().clamp(0, 11)]++;
    }
    final top = bins.reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        SizedBox(
          height: 95,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final n in bins)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: top == 0 ? 0 : 90 * n / top,
                      decoration: BoxDecoration(
                        color: mint.withValues(alpha: .7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(
          '${number(low)} ← replay yardage distribution → ${number(high)}',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  List<Widget> saveView(PlayerSimulation? sim) => [
    panel('Freeze the prediction', [
      const Text(
        'Save the exact historical inputs, model version, scenario, manually entered price and your reasoning. Future edits create another snapshot.',
      ),
      gap(),
      TextField(
        key: const Key('investigation-thesis'),
        controller: thesis,
        maxLength: 1000,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Why might this hold up? What could invalidate it?',
        ),
      ),
      gap(),
      TextButton.icon(
        onPressed: chooseTarget,
        icon: const Icon(Icons.event_outlined),
        label: Text(
          target == null
              ? 'Add the game date (optional)'
              : 'Intended game date: ${date(target!)}',
        ),
      ),
      const Text(
        'The date is entered by you, not verified against a sportsbook event. Without a verified kickoff and quote, this remains a manually recorded research exercise.',
      ),
      gap(),
      if (sim != null && sim.available)
        Text(
          'Frozen conditional win ${pct(sim.winProbability)} · EV ${pct(sim.ev)} · ${sim.sampleSize} game pairs',
        ),
      gap(),
      FilledButton.icon(
        key: const Key('save-investigation'),
        onPressed: saving ? null : save,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(saving ? 'Saving…' : 'Save prediction'),
      ),
    ]),
  ];
  List<Widget> reviewView() {
    final selected = records
        .where((r) => r.playerId == widget.player.playerId)
        .toList();
    return [
      panel('Learn from the outcome', [
        const Text(
          'Compare final production with the frozen projection and opportunity assumptions. A single win or loss cannot establish forecast skill. Manual results are unverified.',
        ),
        gap(),
        if (selected.isEmpty)
          const Text(
            'No saved predictions for this player yet. Save one after testing a scenario.',
          ),
        for (final r in selected)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Saved ${r.savedAt.toLocal()} · ${r.targetDate == null ? 'game date not recorded' : date(r.targetDate!)}',
                    ),
                    Text(
                      '${r.book.isEmpty ? 'No sportsbook recorded' : r.book} · ${americanLabel(r.scenario.price)} · manually entered price, not verified',
                    ),
                    Text('Original reasoning: ${r.thesis}'),
                    Text(
                      'Frozen conditional win ${pct(r.simulation.winProbability)} · EV ${pct(r.simulation.ev)}',
                    ),
                    Text(
                      '${r.games.length} frozen records · evidence through ${date(r.cutoff)} · $playerSimulationVersion',
                    ),
                    if (reviews[r.id] case final review?) ...[
                      const Divider(),
                      Text(
                        '${review.outcome(r.scenario)} · ${review.voided ? 'void' : '${number(review.actualYards)} final yards'} · ${review.source}',
                      ),
                      Text(
                        'Reviewed ${review.recordedAt.toLocal()} · ${review.notes}',
                      ),
                      Text(
                        'Probability error ${number(review.probabilityError(r.simulation), 4)} (0 best, 1 worst; manual diagnostic)',
                      ),
                      if (review.actualVolume != null)
                        Text(
                          'Opportunity: ${number(review.actualVolume)} actual vs ${number((r.simulation.averageVolume ?? 0) * r.scenario.workload)} assumed mean',
                        ),
                    ],
                    gap(),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: futureTarget(r.targetDate)
                              ? null
                              : () => review(r),
                          child: Text(
                            reviews.containsKey(r.id)
                                ? 'Correct outcome'
                                : 'Record outcome',
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: const JsonEncoder.withIndent('  ')
                                    .convert(r.toJson()),
                              ),
                            );
                            if (mounted) {
                              setState(
                                () => message = 'Frozen prediction JSON copied. Full backups are also available in Proof Lab.',
                              );
                            }
                          },
                          child: const Text('Copy frozen report'),
                        ),
                      ],
                    ),
                    if (futureTarget(r.targetDate))
                      const Text(
                        'Outcome review opens on the entered game date; final settlement still needs your confirmation.',
                      ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    ];
  }
}

class PlayerInvestigationLibrary extends StatelessWidget {
  const PlayerInvestigationLibrary({super.key, required this.store});
  final ResearchStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved predictions')),
    body: FutureBuilder<List<PlayerInvestigation>>(
      future: store.loadInvestigations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Predictions could not be loaded. Existing files are intact.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No player predictions saved yet. Choose Investigate a bet on Overview to begin.',
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: rows.length,
          separatorBuilder: (_, i) => const SizedBox(height: 12),
          itemBuilder: (ctx, index) {
            final r = rows[index];
            return Card(
              child: ListTile(
                title: Text(r.title),
                subtitle: Text(
                  '${r.savedAt.toLocal()} · manual price · ${r.games.length} frozen game records',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerInvestigationPage(
                      player: r.games.first,
                      games: r.games,
                      store: store,
                      initialStep: 3,
                      initialRecord: r,
                      metadata: {
                        'cutoff': r.cutoff.toIso8601String().substring(0, 10),
                        'currentSeason': r.games
                            .map((g) => g.season)
                            .reduce((a, b) => a > b ? a : b),
                        'source': r.source,
                        'retrievedAt': r.sourceRetrievedAt,
                        'sourceUrl': r.sourceUrl,
                        'license': r.license,
                        'licenseUrl': r.licenseUrl,
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
