import 'package:flutter/material.dart';

import '../data/nfl_assets.dart';
import '../domain/closing_value.dart';
import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../domain/odds.dart';
import '../domain/player_stats.dart';
import '../domain/prop_report.dart';
import '../domain/public_sharp.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../ui/wordmark.dart';
import 'coach_widgets.dart';

class ReportCardScreen extends StatefulWidget {
  const ReportCardScreen({
    super.key,
    required this.model,
    required this.now,
    required this.lineHistory,
    required this.events,
    this.examplePrices = false,
    this.loadPlayers,
    this.propReport,
  });

  final CoachModel? model;
  final DateTime now;
  final Map<String, List<LineSnapshot>> lineHistory;
  final List<SportEvent> events;
  final bool examplePrices;
  final Future<PlayerStatsDataset> Function()? loadPlayers;

  /// When set, the screen does not recompute the prop test.
  final PropReport? propReport;

  @override
  State<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends State<ReportCardScreen> {
  PropReport? report;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final ready = widget.propReport;
    if (ready != null) {
      report = ready;
      loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await (widget.loadPlayers ?? loadBundledNflPlayers)();
      final next = walkForwardPropChance(data.rows);
      if (!mounted) return;
      setState(() {
        report = next;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'The prop test could not be read from the box scores.';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.model?.backtest;
    final prop = report;
    final closing = summarizeLineHistory(
      history: widget.lineHistory,
      events: widget.events,
      now: widget.now,
      example: widget.examplePrices,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          key: const Key('report-card'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SectionLabel('REPORT CARD'),
            const SizedBox(height: 8),
            if (widget.examplePrices) ...[
              const ExamplePill(),
              const SizedBox(height: 8),
            ],
            Text(
              _headline(game, prop),
              style: EdgeType.display.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 10),
            Text(
              'A difference from the books is a comparison. Nothing on this card is a pick.',
              style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
            ),
            const SizedBox(height: 20),
            const Text("Coach's Line", style: EdgeType.title),
            const SizedBox(height: 8),
            _game(game),
            const SizedBox(height: 20),
            const Text('When the model was sure', style: EdgeType.title),
            const SizedBox(height: 6),
            Text(
              'Each row is the cover chance Coach\'s Line published, and how often that side actually covered. A coin flip scores a Brier of 0.250. Lower is a better forecast.',
              style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
            ),
            const SizedBox(height: 8),
            _calibration(game),
            const SizedBox(height: 20),
            const Text('Prop chance', style: EdgeType.title),
            const SizedBox(height: 8),
            _prop(prop),
            const SizedBox(height: 20),
            const Text('Closing-line value', style: EdgeType.title),
            const SizedBox(height: 8),
            CoachCard(child: Text(closing.plainEnglish, style: EdgeType.body)),
            const SizedBox(height: 16),
            const ToolNote(
              'Sharp signals and models do not guarantee outcomes. This card publishes the past test, including when it lost money. It is not a recommendation to bet.',
            ),
            const SizedBox(height: 8),
            const ToolNote(responsibleGamblingNote),
          ],
        ),
      ),
    );
  }

  Widget _game(BacktestReport? game) {
    if (game == null) {
      return const CoachCard(
        child: Text(
          "Coach's Line could not be read. No game-model number is filled in.",
          style: EdgeType.body,
        ),
      );
    }
    final hit = game.hitRate == null ? '—' : percentLabel(game.hitRate!);
    final profit = game.roi == null ? '—' : signedPercent(game.roi!);
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(game.plainEnglish, style: EdgeType.body),
          const SizedBox(height: 12),
          _stat(
            'Every spread',
            '$hit · ${game.wins}–${game.losses} · ${game.decided} decided · $profit',
          ),
          _stat(
            'Differs by 2.5+',
            '${game.flaggedHitRate == null ? '—' : percentLabel(game.flaggedHitRate!)} of ${game.flaggedDecided} · ${game.flaggedRoi == null ? '—' : signedPercent(game.flaggedRoi!)}',
          ),
          _stat(
            'Every total',
            '${game.totalsHitRate == null ? '—' : percentLabel(game.totalsHitRate!)} · ${game.totalsRoi == null ? '—' : signedPercent(game.totalsRoi!)}',
          ),
          _stat(
            'Closer than the close',
            '${game.clvBeatRate == null ? '—' : percentLabel(game.clvBeatRate!)} of ${game.clvGames} · us ${game.meanModelError?.toStringAsFixed(1) ?? '—'} pts, market ${game.meanMarketError?.toStringAsFixed(1) ?? '—'}',
          ),
          const SizedBox(height: 8),
          Text(
            'Brier ${game.brier == null ? '—' : game.brier!.toStringAsFixed(3)}. The closer-than-the-close line is not a bettor\'s closing-line value. The history file only has the close, not the number from earlier in the week.',
            style: EdgeType.label,
          ),
        ],
      ),
    );
  }

  Widget _calibration(BacktestReport? game) {
    final bins = game?.calibration ?? const <CalibrationBin>[];
    if (bins.isEmpty) {
      return const CoachCard(
        child: Text(
          'No calibration table is stored with this model file.',
          style: EdgeType.body,
        ),
      );
    }
    CalibrationBin? confident;
    for (final bin in bins) {
      if (bin.from >= 0.6 && bin.games > 0) confident = bin;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoachCard(child: Column(children: [for (final bin in bins) _bin(bin)])),
        if (confident != null) ...[
          const SizedBox(height: 8),
          Text(
            'In the ${confident.games} games where the model said ${percentLabel(confident.from)} or higher, it predicted ${percentLabel(confident.predicted)} and the side covered ${percentLabel(confident.actual)}. The model was overconfident. That row is why a big gap with the books is not treated as a pick.',
            style: EdgeType.body.copyWith(color: EdgeColors.warn),
          ),
        ],
      ],
    );
  }

  Widget _bin(CalibrationBin bin) {
    final label = bin.to >= 0.99
        ? '${percentLabel(bin.from)} or higher'
        : '${percentLabel(bin.from)} to ${percentLabel(bin.to)}';
    final value = bin.games == 0
        ? 'No games'
        : '${bin.games} games · said ${percentLabel(bin.predicted)} · hit ${percentLabel(bin.actual)}';
    return _stat(label, value, emphasize: bin.from >= 0.6 && bin.games > 0);
  }

  Widget _prop(PropReport? prop) {
    if (loading) {
      return const CoachCard(
        child: Text(
          'Scoring the prop chance on past box scores.',
          style: EdgeType.body,
        ),
      );
    }
    if (prop == null) {
      return CoachCard(
        child: Text(error ?? 'The prop test is blank.', style: EdgeType.body),
      );
    }
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prop.plainEnglish, style: EdgeType.body),
          const SizedBox(height: 12),
          _stat(
            'Sportsbook prices',
            prop.usedSportsbookPrices ? 'Used' : 'Not used',
          ),
          _stat(
            'Brier',
            prop.brier == null
                ? '—'
                : '${prop.brier!.toStringAsFixed(3)} · coin flip ${prop.baselineBrier.toStringAsFixed(3)}',
          ),
          _stat(
            'Log loss',
            prop.logLoss == null
                ? '—'
                : '${prop.logLoss!.toStringAsFixed(3)} · coin flip ${prop.baselineLogLoss.toStringAsFixed(3)}',
          ),
          _stat('Edge', prop.hasEdge ? 'Past edge' : 'No edge'),
          const SizedBox(height: 8),
          Text(prop.notTested, style: EdgeType.label),
          if (prop.calibration.any((bin) => bin.games > 0)) ...[
            const SizedBox(height: 12),
            for (final bin in prop.calibration)
              if (bin.games > 0) _bin(bin),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: EdgeType.label.copyWith(fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: EdgeType.body.copyWith(
                fontFamily: EdgeFont.display,
                fontSize: 16,
                color: emphasize ? EdgeColors.warn : EdgeColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _headline(BacktestReport? game, PropReport? prop) {
  final gameLine = game == null
      ? "Coach's Line is not loaded."
      : game.hasEdge
      ? "Coach's Line showed an edge on the past test."
      : "Coach's Line has no edge. It hit ${game.hitRate == null ? 'an unknown share' : percentLabel(game.hitRate!)} against the spread and ${game.roi == null ? 'an unknown return' : 'returned ${signedPercent(game.roi!)}'}.";
  if (prop == null) {
    return '$gameLine The prop chance is still being scored.';
  }
  if (prop.scored == 0) {
    return '$gameLine The prop chance has no scored games in this file.';
  }
  return '$gameLine The prop chance was not tested against a sportsbook price, and this card does not call it an edge.';
}
