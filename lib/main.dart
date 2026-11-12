import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data/demo.dart';
import 'data/repository.dart';
import 'domain/odds.dart';
import 'research_workspace.dart';
import 'data/research_store.dart';
import 'domain/research.dart';
import 'historical_evidence.dart';
import 'player_stats_screen.dart';
import 'player_investigation_page.dart';
import 'domain/player_stats.dart';
import 'tools_page.dart';

const mint = Color(0xFF7CE7C0);
const panel = Color(0xF212211E);

void main() => runApp(const OddsEdgeApp());

class OddsEdgeApp extends StatelessWidget {
  const OddsEdgeApp({super.key, this.researchStore});
  final ResearchStore? researchStore;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Odds Edge',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0C111A),
      fontFamily: 'Segoe UI',
      colorScheme: ColorScheme.fromSeed(
        seedColor: mint,
        brightness: Brightness.dark,
        primary: mint,
        surface: panel,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF101620),
        contentPadding: EdgeInsets.all(18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Color(0xFF293343)),
        ),
      ),
      cardTheme: const CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: Color(0xFF242E3C)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      dividerColor: const Color(0xFF242E3C),
    ),
    home: EdgeWorkspace(researchStore: researchStore),
  );
}

class EdgeWorkspace extends StatefulWidget {
  const EdgeWorkspace({super.key, this.researchStore});
  final ResearchStore? researchStore;
  @override
  State<EdgeWorkspace> createState() => _EdgeWorkspaceState();
}

class _EdgeWorkspaceState extends State<EdgeWorkspace> {
  late OddsBoard board;
  Timer? timer;
  int page = 0;
  int lastResearchPage = 1;
  String? eventId, selectionKey;
  String market = 'h2h';
  Set<String>? enabledBooks;
  bool backend = false, loading = false, scenario = false;
  double win = .55;
  String? error;
  String? preferenceNotice;
  late final researchStore = widget.researchStore ?? ResearchStore();
  ResearchContext? researchContext;
  int researchLaunch = 0;
  final repository = BackendRepository(
    const String.fromEnvironment(
      'ODDS_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8787',
    ),
  );
  static const workspaceNames = [
    'Overview',
    'Research',
    'Odds comparison',
    'Tools',
  ];
  static const workspaceIcons = [
    Icons.grid_view_rounded,
    Icons.query_stats_rounded,
    Icons.compare_arrows_rounded,
    Icons.handyman_outlined,
  ];
  static const phoneLabels = ['Home', 'Research', 'Odds', 'Tools'];
  static const researchPages = [1, 4, 3];
  static const researchNames = ['Matchups', 'Players', 'Proof Lab'];
  bool get inResearch => researchPages.contains(page);
  int get workspaceIndex => switch (page) {
    0 => 0,
    2 => 2,
    5 => 3,
    _ => 1,
  };

  void navigateTo(int next) => setState(() {
    page = next;
    if (inResearch) lastResearchPage = next;
    if (next != 3) researchContext = null;
  });

  void openWorkspace(int index) => navigateTo(switch (index) {
    1 => lastResearchPage,
    2 => 2,
    3 => 5,
    _ => 0,
  });

  void investigatePlayer(
    PlayerGame player,
    List<PlayerGame> games,
    Map<String, dynamic> metadata,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerInvestigationPage(
          player: player,
          games: games,
          metadata: metadata,
          store: researchStore,
        ),
      ),
    );
  }

  Widget researchTabs() => DefaultTabController(
    key: ValueKey('research-tabs-$page'),
    length: researchPages.length,
    initialIndex: researchPages.indexOf(page),
    child: Material(
      color: const Color(0xE6091718),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: mint,
          unselectedLabelColor: Colors.white60,
          indicatorColor: mint,
          labelPadding: const EdgeInsets.symmetric(horizontal: 18),
          onTap: (index) => navigateTo(researchPages[index]),
          tabs: [for (final label in researchNames) Tab(text: label)],
        ),
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    board = demoBoard(DateTime.now().toUtc());
    eventId = board.events.first.id;
    researchStore
        .loadBooks()
        .then((books) {
          if (mounted) setState(() => enabledBooks = books);
        })
        .catchError((Object _) {
          if (mounted) {
            setState(
              () => preferenceNotice =
                  'Saved sportsbook preferences could not be read.',
            );
          }
        });
    // Re-evaluate freshness even if no successful network request arrives.
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (backend && !loading) {
        refresh();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool onDemand = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = backend
          ? await repository.board(refresh: onDemand)
          : demoBoard(DateTime.now().toUtc());
      if (!mounted) return;
      setState(() {
        board = next;
        if (!board.events.any((e) => e.id == eventId)) {
          eventId = board.events.isEmpty ? null : board.events.first.id;
          selectionKey = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Backend could not be reached. Retained observations are excluded from best-price results. Retry or explicitly select demo mode.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  NflEvent? get event => board.events.where((e) => e.id == eventId).firstOrNull;
  List<Selection> get selections {
    final result = <String, Selection>{};
    for (final q in board.quotes) {
      if (q.selection.eventId == eventId && q.selection.market == market) {
        result[q.selection.key] = q.selection;
      }
    }
    return result.values.toList();
  }

  Selection? get selection =>
      selections.where((s) => s.key == selectionKey).firstOrNull ??
      selections.firstOrNull;
  DateTime get now => DateTime.now().toUtc();
  bool get inPlay => event != null && !event!.startsAt.isAfter(now);
  String stamp(DateTime time) =>
      '${time.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first} UTC';
  String quoteFreshness(OddsQuote quote) {
    if (error != null) return 'connection lost';
    final value = quote.freshness(now, inPlay: inPlay);
    if (!board.demo && value == 'stale') return 'snapshot';
    return value;
  }

  bool canResearch(OddsQuote quote) =>
      error == null &&
      (quote.eligible(now, inPlay: inPlay) ||
          quoteFreshness(quote) == 'snapshot');
  String pct(double p) => '${(p * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/nfl-field.png',
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              excludeFromSemantics: true,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xD908151B), Color(0x55081712)],
                ),
              ),
            ),
            SafeArea(
              child: Row(
                children: [
                  if (wide)
                    Material(
                      color: const Color(0xE6091718),
                      child: SizedBox(
                        width: 230,
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              brand(),
                              const SizedBox(height: 36),
                              const Text(
                                'WORKSPACE',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.5,
                                  color: Colors.white54,
                                ),
                              ),
                              const SizedBox(height: 16),
                              for (var i = 0; i < workspaceNames.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    selected: workspaceIndex == i,
                                    selectedColor: mint,
                                    selectedTileColor: mint.withValues(
                                      alpha: .10,
                                    ),
                                    leading: Icon(workspaceIcons[i], size: 20),
                                    title: Text(workspaceNames[i]),
                                    onTap: () => openWorkspace(i),
                                  ),
                                ),
                              const Spacer(),
                              const Divider(),
                              const SizedBox(height: 12),
                              const Text(
                                'Research with clarity.\nNFL preview',
                                style: TextStyle(
                                  color: Colors.white54,
                                  height: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (wide) const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: wide ? 30 : 16,
                            vertical: 18,
                          ),
                          child: Row(
                            children: [
                              if (!wide) ...[
                                brand(),
                                const Spacer(),
                              ] else ...[
                                Text(
                                  workspaceNames[workspaceIndex],
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const Spacer(),
                              ],
                              badge(
                                page == 4
                                    ? 'HISTORICAL STATS'
                                    : board.demo
                                    ? (wide ? 'DEMONSTRATION' : 'DEMO')
                                    : (wide ? 'PROVIDER FEED' : 'FEED'),
                                page == 4
                                    ? mint
                                    : board.demo
                                    ? Colors.amber
                                    : mint,
                              ),
                              const SizedBox(width: 8),
                              if (page != 4)
                                IconButton(
                                  tooltip: 'Refresh odds',
                                  onPressed: loading
                                      ? null
                                      : () => refresh(onDemand: true),
                                  icon: loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        if (inResearch) researchTabs(),
                        Expanded(
                          child: page == 3
                              ? ResearchWorkspace(
                                  key: ValueKey(researchLaunch),
                                  store: researchStore,
                                  initialContext: researchContext,
                                  calculator: const ProbabilityCalculator(),
                                  assistant: backend
                                      ? repository.assistant
                                      : null,
                                )
                              : SingleChildScrollView(
                                  padding: EdgeInsets.all(wide ? 30 : 16),
                                  key: PageStorageKey(page),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 1400,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (page != 3 && page != 4) ...[
                                          sourcePanel(),
                                          const SizedBox(height: 26),
                                        ],
                                        if (page == 0)
                                          overview()
                                        else if (page == 1)
                                          matchups()
                                        else if (page == 2)
                                          comparison()
                                        else if (page == 4)
                                          PlayerStatsScreen(
                                            onInvestigate: investigatePlayer,
                                          )
                                        else if (page == 5)
                                          ToolsPage(
                                            key: const Key('tools-page'),
                                            board: board,
                                            now: now,
                                            enabledBooks: enabledBooks,
                                            backendConnected:
                                                backend && error == null,
                                            store: researchStore,
                                            stamp: stamp,
                                            history: (selection) => backend
                                                ? repository.history(selection)
                                                : Future.value(const []),
                                          )
                                        else
                                          const SizedBox(),
                                        const SizedBox(height: 30),
                                        if (page != 4)
                                          const Text(
                                            'Prices are observations, not guaranteed offers. Confirm the exact line and rules with the operator.',
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: workspaceIndex,
                onDestinationSelected: openWorkspace,
                destinations: [
                  for (var i = 0; i < workspaceNames.length; i++)
                    NavigationDestination(
                      icon: Icon(workspaceIcons[i]),
                      label: phoneLabels[i],
                    ),
                ],
              ),
      );
    },
  );

  Widget brand() => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.stacked_line_chart, color: mint, size: 28),
      SizedBox(width: 8),
      Text(
        'ODDS EDGE',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 14,
          letterSpacing: 1.0,
        ),
      ),
    ],
  );
  Widget badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: .8,
      ),
    ),
  );
  Widget heading(String eyebrow, String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          color: mint,
          letterSpacing: 2,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        title,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: const TextStyle(color: Colors.white60, height: 1.6),
      ),
      const SizedBox(height: 24),
    ],
  );
  Widget box(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  );
  Widget sourcePanel() => box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              board.demo ? Icons.info_outline : Icons.sensors,
              color: board.demo ? Colors.amber : mint,
            ),
            Text(
              board.demo
                  ? 'Sample prices. Real comparison logic.'
                  : 'Connected to the odds backend',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      setState(() {
                        backend = !backend;
                        error = null;
                        selectionKey = null;
                        // Clear old data when changing sources; never mix demo and real quotes.
                        board = OddsBoard(
                          events: [],
                          quotes: [],
                          fetchedAt: now,
                          demo: !backend,
                        );
                      });
                      await refresh();
                    },
              child: Text(
                backend ? 'Use demonstration' : 'Connect local backend',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Snapshot as of ${stamp(board.fetchedAt)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          board.demo
              ? 'Synthetic NFL fixtures and odds · no live feed or predictive model connected. This sample is a snapshot, not a live stream.'
              : 'These odds are a saved snapshot, not a live stream. A quote counts as current only when the sportsbook time and our collection time are both within 120 seconds before kickoff or 20 seconds after kickoff.',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        if (preferenceNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              preferenceNotice!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        for (final notice in board.notices)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              notice,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
      ],
    ),
  );

  Widget overview() {
    final eligible = board.quotes.where((q) {
      final e = board.events
          .where((e) => e.id == q.selection.eventId)
          .firstOrNull;
      return error == null &&
          q.eligible(now, inPlay: e != null && !e.startsAt.isAfter(now));
    }).length;
    final showingSnapshot =
        !board.demo && eligible == 0 && board.quotes.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'YOUR RESEARCH DESK',
          'Does your betting idea hold up?',
          'Investigate the evidence, test what could change it, and learn from the outcome.',
        ),
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Start with one question.',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                'Has a player’s recent production changed because of opportunity or efficiency? Compare the evidence, replay scenarios, and save your prediction.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const Key('investigate-bet'),
                    onPressed: () => navigateTo(4),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Investigate a bet'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PlayerInvestigationLibrary(store: researchStore),
                      ),
                    ),
                    child: const Text('Review saved predictions'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openWorkspace(3),
                    icon: const Icon(Icons.handyman_outlined),
                    label: const Text('Price, parlays, and bet log'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Player yardage research · real historical records · manually entered prices · unvalidated scenario replay',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (_, c) => Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              metric(
                'NFL MATCHUPS',
                '${board.events.length}',
                'Available in this feed',
                c.maxWidth,
              ),
              metric(
                'SPORTSBOOKS',
                '${board.quotes.map((q) => q.bookId).toSet().length}',
                'Coverage varies by market',
                c.maxWidth,
              ),
              metric(
                board.demo
                    ? 'ELIGIBLE DEMO QUOTES'
                    : showingSnapshot
                    ? 'SNAPSHOT QUOTES'
                    : 'CURRENT QUOTES',
                showingSnapshot
                    ? '${board.quotes.where((q) => q.status == 'open').length}'
                    : '$eligible',
                showingSnapshot
                    ? 'Saved snapshot, not a live stream'
                    : 'Stale and suspended excluded',
                c.maxWidth,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Explore the slate',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => page = 2),
              child: const Text('Compare odds →'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final e in board.events)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: gameCard(e),
          ),
        if (board.events.isEmpty)
          box(
            const Text(
              'No verified NFL events received. Check the backend connection.',
            ),
          ),
        const SizedBox(height: 14),
        box(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A repeatable research process',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text(
                'Investigate evidence → test assumptions → save a prediction → review the result',
                style: TextStyle(color: mint, height: 1.8),
              ),
              SizedBox(height: 10),
              Text(
                'Historical game pairs support conditional player-yardage replay. Odds comparison and the manual probability calculator remain available. Predictive model accuracy has not been validated.',
                style: TextStyle(color: Colors.white60, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget metric(String label, String value, String caption, double width) =>
      SizedBox(
        width: width > 700 ? (width - 28) / 3 : width,
        child: box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white54,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(value, style: const TextStyle(fontSize: 36, color: mint)),
              Text(
                caption,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      );
  Widget gameCard(NflEvent e) => box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          board.demo ? 'NFL · SAMPLE FIXTURE' : 'NFL · ${stamp(e.startsAt)}',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${e.away}\n${e.home}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                height: 1.7,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                eventId = e.id;
                selectionKey = null;
                page = 2;
              }),
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: const Text('Explore prices'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget eventPicker() => DropdownButtonFormField<String>(
    initialValue: eventId,
    key: ValueKey('event-$eventId-${board.events.length}'),
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'NFL matchup'),
    items: board.events
        .map(
          (e) => DropdownMenuItem(
            value: e.id,
            child: Text(
              '${e.away} at ${e.home}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: (value) => setState(() {
      eventId = value;
      selectionKey = null;
    }),
  );

  void investigate(OddsQuote quote) {
    final selectedEvent = board.events
        .where((e) => e.id == quote.selection.eventId)
        .firstOrNull;
    if (selectedEvent == null) return;
    setState(() {
      researchContext = ResearchContext(quote: quote, event: selectedEvent);
      researchLaunch++;
      page = 3;
      lastResearchPage = 3;
    });
  }

  Widget matchups() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'MATCHUP EXPLORER',
        'The game behind the number.',
        'Start with the market. Add validated matchup evidence as data becomes available.',
      ),
      eventPicker(),
      const SizedBox(height: 20),
      if (event != null) gameCard(event!),
      const SizedBox(height: 16),
      const HistoricalEvidence(),
      const SizedBox(height: 16),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Evidence availability', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            for (final label in [
              'Opponent-adjusted efficiency',
              'Quarterback and offensive-line availability',
              'Weather, pace, and game script',
              'Validated win / cover probabilities',
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.hourglass_empty,
                  size: 20,
                  color: Colors.white38,
                ),
                title: Text(label),
                subtitle: const Text(
                  'Not connected — no statistical claims generated',
                ),
              ),
            FilledButton(
              onPressed: () => setState(() => page = 2),
              child: const Text('Open sportsbook comparison'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget comparison() {
    final s = selection;
    final rows =
        s == null
              ? <OddsQuote>[]
              : comparableQuotes(board.quotes, s, books: enabledBooks)
          ..sort((a, b) => b.decimal.compareTo(a.decimal));
    final liveBest = s == null || error != null
        ? null
        : bestQuote(board.quotes, s, now, books: enabledBooks, inPlay: inPlay);
    final snapshotBest = s == null || error != null
        ? null
        : bestSnapshotQuote(board.quotes, s, now, books: enabledBooks);
    final best = liveBest ?? snapshotBest;
    final pricedFromSnapshot = liveBest == null && snapshotBest != null;
    final active = rows.where(
      (q) => error == null && q.eligible(now, inPlay: inPlay),
    );
    final spread = priceSpread(active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'MULTI-SPORTSBOOK INTELLIGENCE',
          'Same selection. Better perspective.',
          'Compare exact lines. Inspect freshness. Keep price differences separate from predictive edge.',
        ),
        eventPicker(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in {
              'h2h': 'Moneyline',
              'spreads': 'Spread / alternate',
              'totals': 'Total',
              'player_pass_yds': 'Passing yards',
            }.entries)
              ChoiceChip(
                label: Text(m.value),
                selected: market == m.key,
                onSelected: (_) => setState(() {
                  market = m.key;
                  selectionKey = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (s != null)
          DropdownButtonFormField<String>(
            key: ValueKey('selection-${s.key}'),
            initialValue: s.key,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Exact selection · different thresholds stay separate',
            ),
            items: selections
                .map(
                  (v) => DropdownMenuItem(
                    value: v.key,
                    child: Text(v.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => selectionKey = v),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: bookFilters,
              icon: const Icon(Icons.tune, size: 18),
              label: Text(
                'My accessible books${enabledBooks == null ? '' : ' (${enabledBooks!.length})'}',
              ),
            ),
            const Text(
              'Self-selected access · jurisdiction not verified',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            TextButton.icon(
              onPressed: s == null ? null : () => showHistory(s),
              icon: const Icon(Icons.timeline),
              label: const Text('Movement history'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (s == null)
          box(
            const Text(
              'No verified selections for this market. Props and alternate lines depend on provider coverage.',
            ),
          )
        else ...[
          box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  best == null
                      ? 'No eligible best price'
                      : pricedFromSnapshot
                      ? 'Best price in this snapshot   ${americanLabel(best.decimal)}'
                      : '${board.demo ? 'Best demo price' : 'Best observed price'}   ${americanLabel(best.decimal)}',
                  style: const TextStyle(
                    fontSize: 24,
                    color: mint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  best == null
                      ? 'Stale, suspended, unverified, and inaccessible quotes cannot win a live badge.'
                      : pricedFromSnapshot
                      ? '${best.book} · ${s.label} · snapshot price, not a live offer'
                      : '${best.book} · ${s.label} · ${pct(impliedProbability(best.decimal))} break-even probability',
                ),
                const SizedBox(height: 8),
                Text(
                  'Snapshot as of ${stamp(board.fetchedAt)}. Not a live stream.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Up to \$${(spread * 100).toStringAsFixed(2)} difference in profit on a \$100 winning bet · ${active.length} books compared',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rules: ${s.rules.replaceAll('_', ' ')} · ${s.period.replaceAll('_', ' ')}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: best == null ? null : () => investigate(best),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Investigate in Proof Lab'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (MediaQuery.sizeOf(context).width < 700)
            ...rows.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: box(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              q.book,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            americanLabel(q.decimal),
                            style: const TextStyle(fontSize: 24, color: mint),
                          ),
                        ],
                      ),
                      Text(
                        '${pct(impliedProbability(q.decimal))} break-even · ${quoteFreshness(q)}',
                      ),
                      Text(
                        'Profit on \$100 win: \$${((q.decimal - 1) * 100).toStringAsFixed(2)}',
                      ),
                      ExpansionTile(
                        key: PageStorageKey(
                          'quote-details-${q.bookId}-${q.selection.key}',
                        ),
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Timestamps and calculation'),
                        children: [
                          Text(
                            'Source ${stamp(q.sourceAt)}\nCollected ${stamp(q.collectedAt)}\nProvider ${q.provider}\n${scenario ? 'Scenario EV ${pct(expectedValue(q.decimal, win))}' : 'MODEL EV: unavailable'}',
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: canResearch(q) ? () => investigate(q) : null,
                        child: const Text('Research this price'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            box(
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  headingTextStyle: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                  columns: [
                    for (final label in [
                      'SPORTSBOOK',
                      'ODDS',
                      'IMPLIED',
                      'VS BEST¹',
                      'STATUS',
                      'SOURCE UPDATED (UTC)',
                      'COLLECTED (UTC)',
                      scenario ? 'SCENARIO EV²' : 'MODEL EV',
                      'RESEARCH',
                    ])
                      DataColumn(label: Text(label)),
                  ],
                  rows: rows.map((q) {
                    final status = quoteFreshness(q);
                    final eligible =
                        error == null && q.eligible(now, inPlay: inPlay);
                    return DataRow(
                      selected: identical(q, best),
                      cells: [
                        DataCell(
                          Text(
                            '${q.book}${q.bookId == best?.bookId ? '  ★' : ''}',
                          ),
                        ),
                        DataCell(
                          Text(
                            americanLabel(q.decimal),
                            style: TextStyle(
                              color: eligible ? mint : Colors.white38,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(Text(pct(impliedProbability(q.decimal)))),
                        DataCell(
                          Text(
                            !eligible || best == null
                                ? '—'
                                : (q.decimal - best.decimal).toStringAsFixed(3),
                          ),
                        ),
                        DataCell(
                          badge(
                            status.toUpperCase(),
                            eligible
                                ? mint
                                : status == 'snapshot'
                                ? Colors.amber
                                : Colors.orangeAccent,
                          ),
                        ),
                        DataCell(Text(stamp(q.sourceAt))),
                        DataCell(Text(stamp(q.collectedAt))),
                        DataCell(
                          Text(
                            scenario && eligible
                                ? pct(expectedValue(q.decimal, win))
                                : '—',
                          ),
                        ),
                        DataCell(
                          IconButton(
                            tooltip: 'Research this price',
                            onPressed: canResearch(q)
                                ? () => investigate(q)
                                : null,
                            icon: const Icon(Icons.science_outlined),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            '¹ Difference in decimal payout per unit staked. ² Hypothetical, zero-push scenario; not a validated model.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Explore a hypothetical probability'),
            subtitle: Text(
              scenario
                  ? 'Your assumed win probability: ${pct(win)}. No model confidence implied.'
                  : 'Model EV is unavailable until a probability model is validated.',
            ),
            value: scenario,
            onChanged: (v) => setState(() => scenario = v),
          ),
          if (scenario)
            Slider(
              value: win,
              min: .01,
              max: .99,
              divisions: 98,
              label: pct(win),
              onChanged: (v) => setState(() => win = v),
            ),
        ],
      ],
    );
  }

  Future<void> bookFilters() async {
    final books = <String, String>{
      for (final q in board.quotes) q.bookId: q.book,
    };
    final chosen = {...enabledBooks ?? books.keys.toSet()};
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Books you can access'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select operators you can use in your state or country. Legal availability is not verified. Choices are saved on this device.',
                  ),
                  for (final entry in books.entries)
                    CheckboxListTile(
                      title: Text(entry.value),
                      value: chosen.contains(entry.key),
                      onChanged: (v) => update(() {
                        v == true
                            ? chosen.add(entry.key)
                            : chosen.remove(entry.key);
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => enabledBooks = chosen);
                researchStore.saveBooks(chosen).catchError((Object _) {
                  if (mounted) {
                    setState(
                      () => preferenceNotice = 'Could not save sportsbook preferences. Please retry.',
                    );
                  }
                });
                Navigator.pop(context);
              },
              child: const Text('Apply filters'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showHistory(Selection s) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Collected odds history'),
        content: SizedBox(
          width: 650,
          child: FutureBuilder<List<OddsQuote>>(
            future: backend
                ? repository.history(s)
                : Future.value(<OddsQuote>[]),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'History unavailable. No replacement history has been generated.',
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final values = snapshot.data!;
              final groups = <String, List<OddsQuote>>{};
              for (final q in values) {
                groups.putIfAbsent(q.bookId, () => []).add(q);
              }
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.label),
                    const SizedBox(height: 12),
                    const Text(
                      'Only snapshots collected by this installation. The first observation is not necessarily the market opening price. No closing price is inferred.',
                    ),
                    const SizedBox(height: 18),
                    if (values.isEmpty)
                      const Text(
                        'No stored observations yet. Connect the backend and allow multiple successful collection cycles.',
                      ),
                    for (final group in groups.entries) ...[
                      const SizedBox(height: 16),
                      Text(group.value.first.book),
                      Text(
                        '${stamp(group.value.first.collectedAt)} → ${stamp(group.value.last.collectedAt)}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 70,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: MovementPainter(group.value),
                        ),
                      ),
                      Text(
                        'First observed ${americanLabel(group.value.first.decimal)} → latest ${americanLabel(group.value.last.decimal)} · ${group.value.length} samples',
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class ProbabilityCalculator extends StatefulWidget {
  const ProbabilityCalculator({super.key});
  @override
  State<ProbabilityCalculator> createState() => _ProbabilityCalculatorState();
}

class _ProbabilityCalculatorState extends State<ProbabilityCalculator> {
  final odds = TextEditingController(text: '-110');
  final probability = TextEditingController(text: '55');
  final push = TextEditingController(text: '0');
  final stake = TextEditingController(text: '100');
  @override
  void dispose() {
    for (final c in [odds, probability, push, stake]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double? decimal, ev, fair;
    String? validation;
    try {
      decimal = americanToDecimal(double.parse(odds.text));
      final p = double.parse(probability.text) / 100;
      final tie = double.parse(push.text) / 100;
      final amount = double.parse(stake.text);
      if (!amount.isFinite || amount <= 0) throw ArgumentError();
      ev = expectedValue(decimal, p, push: tie) * amount;
      fair = p > 0 && p + tie < 1 ? (1 - tie) / p : null;
    } catch (_) {
      validation = 'Enter valid odds (≥+100 or ≤−100), a positive stake, and probabilities totaling at most 100%.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            field('American odds', odds),
            field('Win probability (%)', probability),
            field('Push probability (%)', push),
            field('Stake (units)', stake),
          ],
        ),
        const SizedBox(height: 26),
        if (validation != null)
          Text(validation, style: const TextStyle(color: Colors.orangeAccent))
        else ...[
          Text(
            'Break-even with no push: ${(100 / decimal!).toStringAsFixed(2)}%',
            style: const TextStyle(fontSize: 22, color: mint),
          ),
          const SizedBox(height: 12),
          Text(
            'Expected net result per bet: ${ev!.toStringAsFixed(2)} units',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 12),
          Text(
            'Fair price from your assumptions: ${fair == null ? 'boundary probability; no finite standard price' : americanLabel(fair)}',
          ),
          const SizedBox(height: 12),
          const Text(
            'EV = P(win) × profit − P(loss) × stake. A push returns your stake. A positive EV estimate depends entirely on the probability you supplied.',
            style: TextStyle(color: Colors.white60, height: 1.6),
          ),
        ],
      ],
    );
  }

  Widget field(String label, TextEditingController controller) => SizedBox(
    width: 210,
    child: TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onChanged: (_) => setState(() {}),
    ),
  );
}

class MovementPainter extends CustomPainter {
  MovementPainter(this.quotes);
  final List<OddsQuote> quotes;
  @override
  void paint(Canvas canvas, Size size) {
    if (quotes.isEmpty) return;
    final minValue = quotes.map((q) => q.decimal).reduce(math.min);
    final maxValue = quotes.map((q) => q.decimal).reduce(math.max);
    final start = quotes.first.collectedAt.millisecondsSinceEpoch;
    final elapsed = math.max(
      1,
      quotes.last.collectedAt.millisecondsSinceEpoch - start,
    );
    final path = Path();
    for (var i = 0; i < quotes.length; i++) {
      final x =
          (quotes[i].collectedAt.millisecondsSinceEpoch - start) /
              elapsed *
              (size.width - 8) +
          4;
      final y = maxValue == minValue
          ? size.height / 2
          : size.height -
                8 -
                (quotes[i].decimal - minValue) /
                    (maxValue - minValue) *
                    (size.height - 16);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = mint);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = mint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant MovementPainter oldDelegate) => true;
}
