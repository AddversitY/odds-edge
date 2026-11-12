import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'coach/ask_coach.dart';
import 'coach/games_screen.dart';
import 'coach/home_screen.dart';
import 'coach/sharp_view.dart';
import 'coach/model_screen.dart';
import 'coach/my_bets_screen.dart';
import 'coach/parlays_screen.dart';
import 'coach/props_screen.dart';
import 'data/demo.dart';
import 'data/demo_lines.dart';
import 'data/repository.dart';
import 'domain/coach_board.dart';
import 'domain/coach_model.dart';
import 'domain/odds.dart';
import 'domain/public_sharp.dart';
import 'research_workspace.dart';
import 'data/research_store.dart';
import 'domain/research.dart';
import 'historical_evidence.dart';
import 'player_stats_screen.dart';
import 'player_investigation_page.dart';
import 'domain/player_stats.dart';
import 'tools_page.dart';
import 'theme/edge_theme.dart';

void main() => runApp(const OddsEdgeApp());

class OddsEdgeApp extends StatelessWidget {
  const OddsEdgeApp({super.key, this.researchStore});
  final ResearchStore? researchStore;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Odds Edge',
    debugShowCheckedModeBanner: false,
    theme: edgeTheme(),
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
  OddsBoard? propBoard;
  OddsBoard? sharpBoard;
  Map<String, List<LineSnapshot>> lineHistory = const {};
  PublicFeed publicFeed = PublicFeed.unavailable;
  Timer? timer;
  int page = 0;
  int shell = 0;
  int lastResearchPage = 1;
  String? eventId, selectionKey;
  String market = 'h2h';
  Set<String>? enabledBooks;
  bool backend = false, loading = false, scenario = false;
  CoachModel? coachModel;
  bool edgeEdited = false;
  EdgeSettings edgeSettings = const EdgeSettings(
    spreadPoints: 2.5,
    totalPoints: 2.5,
    minExpectedValue: 0.02,
  );
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
  static const navShells = [0, 2, 1, 3, 4];
  static const navLabels = ['Home', 'Games', 'Props', 'Parlays', 'Bets'];
  static const navIcons = [
    Icons.home_outlined,
    Icons.sports_football_outlined,
    Icons.person_outline,
    Icons.receipt_long_outlined,
    Icons.bookmark_outline,
  ];
  static const researchPages = [1, 4, 3];
  static const researchNames = ['Matchups', 'Players', 'Proof Lab'];
  bool get inResearch => researchPages.contains(page);
  bool get inMore => shell == 5;
  int get navIndex {
    final index = navShells.indexOf(shell);
    return index < 0 ? 0 : index;
  }

  String get screenTitle {
    if (!inMore) return navLabels[navIndex];
    return switch (page) {
      2 => 'Odds',
      5 => 'Tools',
      6 => "Coach's model",
      7 => 'More',
      8 => 'Public vs sharp',
      4 => 'Players',
      1 => 'Matchups',
      3 => 'Proof Lab',
      _ => 'More',
    };
  }

  void navigateTo(int next) => setState(() {
    page = next;
    shell = 5;
    if (inResearch) lastResearchPage = next;
    if (next != 3) researchContext = null;
  });

  void openShell(int index) => setState(() => shell = index);

  void openMore() => setState(() {
    shell = 5;
    page = 7;
    researchContext = null;
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
      color: EdgeColors.background,
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
    lineHistory = demoLineHistory(board);
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
    unawaited(loadCoachModel());
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
    repository.close();
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
      if (backend) {
        unawaited(loadProps());
        unawaited(loadSharp());
        unawaited(loadLineContext());
      } else {
        setState(() {
          lineHistory = demoLineHistory(next);
          publicFeed = PublicFeed.unavailable;
        });
      }
      if (onDemand || coachModel == null) unawaited(loadCoachModel());
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

  Future<void> loadProps({bool refresh = false}) async {
    if (!backend) {
      if (mounted) setState(() => propBoard = null);
      return;
    }
    try {
      final next = await repository.props(refresh: refresh);
      if (mounted) setState(() => propBoard = next);
    } catch (_) {
      if (mounted) {
        setState(() {
          propBoard = OddsBoard(
            events: const [],
            quotes: const [],
            fetchedAt: now,
            notices: const [
              'Player-prop prices could not be loaded. No stand-in prices were added.',
            ],
          );
        });
      }
    }
  }

  OddsBoard get propSource {
    if (!backend || board.demo) return board;
    final props = propBoard;
    if (props == null) {
      return OddsBoard(
        events: board.events,
        quotes: const [],
        fetchedAt: board.fetchedAt,
        notices: const ['Player-prop prices have not been saved yet.'],
      );
    }
    return OddsBoard(
      events: props.events.isEmpty ? board.events : props.events,
      quotes: props.quotes,
      fetchedAt: props.fetchedAt,
      demo: props.demo,
      notices: props.notices,
    );
  }

  Future<void> loadSharp() async {
    if (!backend || board.demo) {
      if (mounted) setState(() => sharpBoard = null);
      return;
    }
    try {
      final next = await repository.sharp();
      if (mounted) setState(() => sharpBoard = next);
    } catch (_) {
      if (mounted) setState(() => sharpBoard = null);
    }
  }

  Future<void> loadLineContext() async {
    try {
      final lines = parseLineSlate(await repository.lineSlate());
      final splits = PublicFeed.parse(await repository.publicSplits());
      if (!mounted || !backend) return;
      setState(() {
        lineHistory = lines;
        publicFeed = splits;
      });
    } catch (_) {
      if (!mounted || !backend) return;
      setState(() => publicFeed = PublicFeed.unavailable);
    }
  }

  /// The odds board plus Pinnacle spreads and totals, when a live
  /// snapshot has them. Sample mode already includes Pinnacle.
  OddsBoard get pricedBoard {
    final sharp = sharpBoard;
    if (!backend || board.demo || sharp == null || sharp.quotes.isEmpty) {
      return board;
    }
    return OddsBoard(
      events: board.events,
      quotes: [...board.quotes, ...sharp.quotes],
      fetchedAt: board.fetchedAt,
      notices: [...board.notices, ...sharp.notices],
    );
  }

  Future<void> loadCoachModel() async {
    CoachModel? next;
    if (backend) {
      try {
        next = CoachModel.fromJson(await repository.coachModel());
      } catch (_) {
        next = null;
      }
    }
    if (next == null) {
      try {
        next = await loadBundledCoachModel();
      } catch (_) {
        next = coachModel;
      }
    }
    if (!mounted || next == null) return;
    setState(() {
      coachModel = next;
      if (!edgeEdited) edgeSettings = next!.settings;
    });
  }

  List<CoachLine> get coachLines {
    final model = coachModel;
    if (model == null) return const [];
    final lines = <CoachLine>[];
    for (final event in pricedBoard.events) {
      final line = model.lineFor(
        event,
        pricedBoard.quotes,
        settings: edgeSettings,
        books: enabledBooks,
      );
      if (line != null) lines.add(line);
    }
    return lines;
  }

  CoachBrief? coachBrief() {
    final slate = summarizeSlate(board, now, books: enabledBooks);
    final play = slate.topPlays.where((item) => item.quote.decimal > 1);
    if (play.isEmpty) return null;
    final first = play.first;
    final lines = coachLines;
    final edged = [
      for (final line in lines)
        if (line.flagged) line,
    ];
    final shown = (edged.isEmpty ? lines : edged).take(8).toList();
    final modelNote = shown.isEmpty ? '' : ' ${shown.first.askCoachSentence}';
    final backtest = coachModel?.backtest.plainEnglish ?? '';
    var note =
        '${first.explanation} Price ${americanLabel(first.quote.decimal)} at ${first.quote.book}. ${priceAge(first.quote.sourceAt, now)}. ${board.demo ? 'Sample prices.' : 'Saved snapshot.'}$modelNote';
    if (note.length > 500) note = note.substring(0, 500);
    return CoachBrief(
      label: first.title,
      matchup: first.subtitle,
      price: first.quote.decimal,
      demo: first.quote.demo || board.demo,
      identity: first.quote.selection.key,
      note: note,
      teamEvidence: [
        for (final line in shown) line.evidence(),
        if (backtest.isNotEmpty)
          {
            'source': "Coach's Line backtest",
            'hasEdge': coachModel?.backtest.hasEdge ?? false,
            'summary': backtest.length > 500
                ? backtest.substring(0, 500)
                : backtest,
          },
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Scaffold(
        backgroundColor: EdgeColors.background,
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Material(
                  color: EdgeColors.surface,
                  child: SizedBox(
                    width: 220,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          brand(),
                          const SizedBox(height: 28),
                          for (var i = 0; i < navLabels.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                selected: !inMore && shell == navShells[i],
                                selectedColor: EdgeColors.accent,
                                selectedTileColor: EdgeColors.accent.withValues(
                                  alpha: .12,
                                ),
                                leading: Icon(navIcons[i]),
                                title: Text(navLabels[i]),
                                onTap: () => openShell(navShells[i]),
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
                          Expanded(
                            child: Text(
                              wide ? screenTitle : 'Odds Edge',
                              overflow: TextOverflow.ellipsis,
                              style: EdgeType.body.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          badge(
                            !wide
                                ? (board.demo ? 'DEMO' : 'FEED')
                                : shell == 5 && page == 4
                                ? 'HISTORICAL STATS'
                                : board.demo
                                ? 'DEMONSTRATION'
                                : 'PROVIDER FEED',
                            shell == 5 && page == 4
                                ? mint
                                : board.demo
                                ? EdgeColors.warn
                                : EdgeColors.accent,
                          ),
                          TextButton(
                            key: const Key('more-menu'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              backgroundColor: inMore
                                  ? EdgeColors.accent.withValues(alpha: .16)
                                  : null,
                            ),
                            onPressed: openMore,
                            child: const Text('More'),
                          ),
                          TextButton(
                            key: const Key('ask-coach'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () => showAskCoach(
                              context,
                              brief: backend && error == null
                                  ? coachBrief()
                                  : null,
                              ask: backend && error == null
                                  ? repository.assistant
                                  : null,
                            ),
                            child: const Text('Ask Coach'),
                          ),
                          if (!(shell == 5 && page == 4))
                            IconButton(
                              tooltip: 'Refresh odds',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
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
                    if (shell == 5 && inResearch) researchTabs(),
                    Expanded(
                      child: shell == 5 ? legacyPage(wide) : coachPage(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBarTheme(
                data: inMore
                    ? NavigationBarThemeData(
                        indicatorColor: Colors.transparent,
                        iconTheme: WidgetStateProperty.all(
                          const IconThemeData(
                            color: EdgeColors.textSecondary,
                            size: 24,
                          ),
                        ),
                        labelTextStyle: WidgetStateProperty.all(
                          EdgeType.label.copyWith(
                            fontSize: 13,
                            color: EdgeColors.textSecondary,
                          ),
                        ),
                      )
                    : const NavigationBarThemeData(),
                child: NavigationBar(
                  selectedIndex: navIndex,
                  onDestinationSelected: (index) => openShell(navShells[index]),
                  destinations: [
                    for (var i = 0; i < navLabels.length; i++)
                      NavigationDestination(
                        icon: Icon(navIcons[i]),
                        label: navLabels[i],
                      ),
                  ],
                ),
              ),
      );
    },
  );

  Widget coachPage() => switch (shell) {
    0 => HomeScreen(
      board: board,
      now: now,
      stamp: stamp,
      enabledBooks: enabledBooks,
    ),
    1 => PropsScreen(
      board: propSource,
      now: now,
      store: researchStore,
      enabledBooks: enabledBooks,
      history: backend && error == null
          ? (selection) => repository.history(selection)
          : null,
    ),
    2 => GamesScreen(
      board: pricedBoard,
      now: now,
      enabledBooks: enabledBooks,
      model: coachModel,
      settings: edgeSettings,
      lineHistory: lineHistory,
      publicSplits: publicFeed.splits,
      sampleHistory: board.demo && !backend,
    ),
    3 => ParlaysScreen(
      board: pricedBoard,
      now: now,
      enabledBooks: enabledBooks,
      model: coachModel,
      settings: edgeSettings,
    ),
    4 => MyBetsScreen(
      store: researchStore,
      board: board,
      now: now,
      books: enabledBooks,
    ),
    _ => const SizedBox(),
  };

  Widget libraryMenu() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    children: [
      const Text('More', style: EdgeType.title),
      const SizedBox(height: 8),
      const Text(
        'Odds, research, tools, and the model. Each one is listed here only.',
        style: EdgeType.body,
      ),
      const SizedBox(height: 16),
      _libraryRow(
        'Public vs sharp',
        'Where the line moved, and where the public is when we are allowed to show it.',
        () => navigateTo(8),
      ),
      _libraryRow(
        'Odds comparison',
        'The same bet at every book in this snapshot.',
        () => navigateTo(2),
      ),
      _libraryRow(
        'Research',
        'Matchups, players, and Proof Lab.',
        () => navigateTo(lastResearchPage),
      ),
      _libraryRow(
        'Tools',
        'Best price, middles, movement, stake size, and prop history.',
        () => setState(() {
          shell = 5;
          page = 5;
          researchContext = null;
        }),
      ),
      _libraryRow(
        "Coach's model",
        'Team strength, and how the past test turned out.',
        () => setState(() {
          shell = 5;
          page = 6;
          researchContext = null;
        }),
      ),
      _libraryRow(
        'Saved predictions',
        'Predictions you already saved on this device.',
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerInvestigationLibrary(store: researchStore),
          ),
        ),
      ),
    ],
  );

  Widget _libraryRow(String title, String subtitle, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: ListTile(
            title: Text(
              title,
              style: EdgeType.body.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle, style: EdgeType.label),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      );

  Widget legacyPage(bool wide) {
    if (page == 7) return libraryMenu();
    if (page == 8) {
      return PublicSharpScreen(
        board: pricedBoard,
        now: now,
        lineHistory: lineHistory,
        publicSplits: publicFeed.splits,
        sample: board.demo && !backend,
      );
    }
    if (page == 3) {
      return ResearchWorkspace(
        key: ValueKey(researchLaunch),
        store: researchStore,
        initialContext: researchContext,
        calculator: const ProbabilityCalculator(),
        assistant: backend && error == null ? repository.assistant : null,
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 30 : 16),
      key: PageStorageKey(page),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (page != 4 && page != 8) ...[
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
              PlayerStatsScreen(onInvestigate: investigatePlayer)
            else if (page == 6)
              ModelScreen(
                model: coachModel,
                settings: edgeSettings,
                onPoints: (value) => setState(() {
                  edgeEdited = true;
                  edgeSettings = edgeSettings.copyWith(
                    spreadPoints: value,
                    totalPoints: value,
                  );
                }),
                onMinExpectedValue: (value) => setState(() {
                  edgeEdited = true;
                  edgeSettings = edgeSettings.copyWith(minExpectedValue: value);
                }),
              )
            else if (page == 5)
              ToolsPage(
                key: const Key('tools-page'),
                board: board,
                now: now,
                enabledBooks: enabledBooks,
                backendConnected: backend && error == null,
                store: researchStore,
                stamp: stamp,
                history: (selection) => backend && error == null
                    ? repository.history(selection)
                    : Future.value(const []),
              )
            else
              const SizedBox(),
            const SizedBox(height: 30),
            if (page != 4 && page != 8)
              const Text(
                'Prices are observations, not guaranteed offers. Confirm the exact line and rules with the operator.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

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
                        propBoard = null;
                        sharpBoard = null;
                        lineHistory = const {};
                        publicFeed = PublicFeed.unavailable;
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
              ? "Sample NFL prices. Coach's Line, when it is loaded, uses real past seasons. These prices are not a live book."
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
                    onPressed: () => openShell(5),
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
                shell = 5;
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
      shell = 5;
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
          ),
          const SizedBox(height: 12),
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
