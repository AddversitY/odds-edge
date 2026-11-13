import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/nfl_assets.dart';
import '../domain/closing_value.dart';
import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../domain/hit_rate.dart';
import '../domain/odds.dart';
import '../domain/player_stats.dart';
import '../domain/prop_clv.dart';
import '../domain/prop_history.dart';
import '../domain/prop_model.dart';
import '../domain/prop_projection.dart';
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
    this.comparison,
  });

  final CoachModel? model;
  final DateTime now;
  final Map<String, List<LineSnapshot>> lineHistory;
  final List<SportEvent> events;
  final bool examplePrices;
  final Future<PlayerStatsDataset> Function()? loadPlayers;

  /// When set, the screen does not recompute the prop test.
  final PropReport? propReport;

  /// When set with [propReport], the usage comparison is not recomputed.
  final PropModelComparison? comparison;

  @override
  State<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends State<ReportCardScreen> {
  PropReport? report;
  PropModelComparison? comparison;
  PropClv clv = PropClv.empty;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final ready = widget.propReport;
    if (ready != null) {
      report = ready;
      comparison = widget.comparison;
      clv = propClosingValue(widget.lineHistory);
      loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await (widget.loadPlayers ?? loadBundledNflPlayers)();
      final scores = await loadBundledHistoryGames();
      final matchup = await loadBundledMatchup();
      final next = comparePropModels(
        data.rows,
        scores: scores,
        matchup: matchup,
      );
      final index = usageIndexFor(
        data.rows,
        scores: scores,
        matchup: matchup,
      );
      final closing = propClosingValue(
        widget.lineHistory,
        overChance: (player, market, line, at, earlier) {
          final metric = propStatMetrics[market];
          final id = index.onlyId(player);
          if (metric == null || id == null) return null;
          return projectProp(
            index: index,
            playerId: id,
            metric: metric,
            line: line,
            side: LineSide.over,
            beforeSeason: at.toUtc().year,
            beforeWeek: 1,
            beforeDate: at,
            market: earlier,
          )?.chance;
        },
      );
      if (!mounted) return;
      setState(() {
        report = next.record;
        comparison = next;
        clv = closing;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'The prop test could not be read.';
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            const SectionLabel('REPORT CARD'),
            const SizedBox(height: 8),
            if (widget.examplePrices) ...[
              const ExamplePill(),
              const SizedBox(height: 8),
            ],
            _Headline(game: game),
            const SizedBox(height: 16),
            _GameTiles(game: game),
            const SizedBox(height: 22),
            Text(
              'We said vs it happened',
              style: EdgeType.title.copyWith(
                fontFamily: EdgeFont.display,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 8),
            _Calibration(game: game),
            const SizedBox(height: 22),
            Text(
              'Prop chance',
              style: EdgeType.title.copyWith(
                fontFamily: EdgeFont.display,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 8),
            _PropTiles(prop: prop, loading: loading, error: error),
            const SizedBox(height: 8),
            Text(
              _propLine(prop),
              style: EdgeType.label.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 22),
            Text(
              'Record vs usage',
              style: EdgeType.title.copyWith(
                fontFamily: EdgeFont.display,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 8),
            _VersionCompare(
              comparison: comparison,
              loading: loading,
              clv: clv,
            ),
            const SizedBox(height: 22),
            Text(
              'Closes',
              style: EdgeType.title.copyWith(
                fontFamily: EdgeFont.display,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(_closeLine(closing), style: EdgeType.body),
            const SizedBox(height: 8),
            _HowWeTested(
              game: game,
              prop: prop,
              closing: closing,
              comparison: comparison,
            ),
            const SizedBox(height: 20),
            Text(
              'Comparison, not a pick.',
              textAlign: TextAlign.center,
              style: EdgeType.label.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: EdgeColors.textTertiary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              responsibleGamblingNote,
              textAlign: TextAlign.center,
              style: EdgeType.label.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: EdgeColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.game});
  final BacktestReport? game;

  @override
  Widget build(BuildContext context) {
    final loaded = game != null;
    final edge = game?.hasEdge ?? false;
    final color = !loaded
        ? EdgeColors.textTertiary
        : edge
        ? EdgeColors.good
        : EdgeColors.warn;
    final chip = !loaded
        ? 'Not loaded'
        : edge
        ? 'Past edge'
        : 'No edge';
    final title = !loaded
        ? 'Game model: not loaded'
        : edge
        ? 'Game model: past edge'
        : 'Game model: no edge yet';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(title, style: EdgeType.display.copyWith(fontSize: 28)),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            chip,
            style: EdgeType.label.copyWith(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _GameTiles extends StatelessWidget {
  const _GameTiles({required this.game});
  final BacktestReport? game;

  @override
  Widget build(BuildContext context) {
    if (game == null) {
      return const _Tile(label: 'Hit rate', value: '—');
    }
    final hit = game!.hitRate;
    return _TileGrid(
      tiles: [
        _Tile(
          label: 'Hit rate',
          value: hit == null ? '—' : percentLabel(hit),
          foot: hit == null
              ? null
              : _VersusBar(
                  value: hit,
                  mark: game!.breakEvenHitRate,
                  markLabel:
                      '${percentLabel(game!.breakEvenHitRate)} to break even',
                ),
        ),
        _Tile(
          label: 'Return',
          value: game!.roi == null ? '—' : signedPercent(game!.roi!),
        ),
        _Tile(label: 'Games tested', value: _count(game!.games)),
        _Tile(
          label: 'Closer than the close',
          value: game!.clvBeatRate == null
              ? '—'
              : percentLabel(game!.clvBeatRate!),
        ),
      ],
    );
  }
}

class _Calibration extends StatelessWidget {
  const _Calibration({required this.game});
  final BacktestReport? game;

  @override
  Widget build(BuildContext context) {
    final bins = [
      for (final bin in game?.calibration ?? const <CalibrationBin>[])
        if (bin.games > 0) bin,
    ];
    if (bins.isEmpty) {
      return const Text('No calibration stored.', style: EdgeType.body);
    }
    CalibrationBin? sure;
    for (final bin in bins) {
      if (bin.from >= 0.6) sure = bin;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: EdgeColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: EdgeColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
            child: SizedBox(
              key: const Key('calibration-chart'),
              height: 220,
              width: double.infinity,
              child: CustomPaint(painter: _CalibrationPainter(bins)),
            ),
          ),
        ),
        if (sure != null) ...[
          const SizedBox(height: 8),
          Text(
            'When it was sure, it said ${percentLabel(sure.predicted)} and covered ${percentLabel(sure.actual)}.',
            style: EdgeType.label.copyWith(
              fontWeight: FontWeight.w500,
              color: EdgeColors.warn,
            ),
          ),
        ],
      ],
    );
  }
}

class _CalibrationPainter extends CustomPainter {
  _CalibrationPainter(this.bins);
  final List<CalibrationBin> bins;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const bottom = 22.0;
    final plot = Rect.fromLTWH(
      left,
      8,
      size.width - left - 4,
      size.height - bottom - 8,
    );
    final grid = Paint()
      ..color = EdgeColors.border
      ..strokeWidth = 1;
    final diagonal = Paint()
      ..color = EdgeColors.textTertiary
      ..strokeWidth = 1.5;
    for (final mark in [0.0, 0.5, 1.0]) {
      final y = plot.bottom - mark * plot.height;
      final x = plot.left + mark * plot.width;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.top),
      diagonal,
    );
    final maxGames = bins.map((bin) => bin.games).reduce(math.max);
    for (final bin in bins) {
      final dx = plot.left + bin.predicted.clamp(0, 1) * plot.width;
      final dy = plot.bottom - bin.actual.clamp(0, 1) * plot.height;
      final share = maxGames == 0 ? 0.5 : bin.games / maxGames;
      final radius = 5 + 8 * math.sqrt(share);
      final off = (bin.predicted - bin.actual).abs() >= 0.05;
      canvas.drawCircle(
        Offset(dx, dy),
        radius,
        Paint()
          ..color = (off ? EdgeColors.warn : EdgeColors.accent).withValues(
            alpha: .9,
          ),
      );
    }
    _label(canvas, '0', Offset(plot.left, size.height - 2));
    _label(canvas, '50', Offset(plot.center.dx, size.height - 2), center: true);
    _label(canvas, '100', Offset(plot.right, size.height - 2), center: true);
  }

  void _label(Canvas canvas, String text, Offset at, {bool center = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: EdgeColors.textTertiary,
          fontSize: 10,
          fontFamily: EdgeFont.sans,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center ? at.dx - painter.width / 2 : at.dx;
    painter.paint(canvas, Offset(dx, at.dy - painter.height));
  }

  @override
  bool shouldRepaint(covariant _CalibrationPainter oldDelegate) =>
      oldDelegate.bins != bins;
}

class _PropTiles extends StatelessWidget {
  const _PropTiles({
    required this.prop,
    required this.loading,
    required this.error,
  });

  final PropReport? prop;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Text('Scoring past box scores.', style: EdgeType.body);
    }
    if (prop == null) {
      return Text(error ?? 'Prop test is blank.', style: EdgeType.body);
    }
    final brier = prop!.brier;
    return _TileGrid(
      tiles: [
        _Tile(
          label: 'Brier',
          value: brier == null ? '—' : brier.toStringAsFixed(3),
          foot: brier == null
              ? null
              : _VersusBar(
                  value: brier,
                  mark: prop!.baselineBrier,
                  lowerIsBetter: true,
                  markLabel:
                      'Coin flip ${prop!.baselineBrier.toStringAsFixed(3)}',
                ),
        ),
        _Tile(label: 'Player-games', value: _count(prop!.scored)),
        _Tile(
          label: 'Log loss',
          value: prop!.logLoss == null
              ? '—'
              : prop!.logLoss!.toStringAsFixed(3),
        ),
        _Tile(label: 'Players', value: _count(prop!.players)),
      ],
    );
  }
}

class _VersionCompare extends StatelessWidget {
  const _VersionCompare({
    required this.comparison,
    required this.loading,
    required this.clv,
  });

  final PropModelComparison? comparison;
  final bool loading;
  final PropClv clv;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Text('Scoring the usage projection.', style: EdgeType.body);
    }
    final face = comparison;
    if (face == null) {
      return const Text(
        'Usage model was not scored in this view.',
        style: EdgeType.body,
      );
    }
    final adopted = face.adopted;
    final color = adopted ? EdgeColors.accent : EdgeColors.textTertiary;
    final record = face.pairedRecord;
    final usage = face.usage;
    return Column(
      key: const Key('prop-v2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                adopted ? 'Version 2 is the chance' : 'Version 2 was not adopted',
                style: EdgeType.title.copyWith(fontSize: 18),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                adopted ? 'In use' : 'Not used',
                style: EdgeType.label.copyWith(
                  color: adopted ? EdgeColors.accent : EdgeColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _TileGrid(
          tiles: [
            _Tile(
              label: 'Record Brier',
              value: record.brier == null ? '—' : record.brier!.toStringAsFixed(3),
            ),
            _Tile(
              label: 'Usage Brier',
              value: usage.brier == null ? '—' : usage.brier!.toStringAsFixed(3),
            ),
            _Tile(
              label: 'Record log loss',
              value: record.logLoss == null
                  ? '—'
                  : record.logLoss!.toStringAsFixed(3),
            ),
            _Tile(
              label: 'Usage log loss',
              value: usage.logLoss == null
                  ? '—'
                  : usage.logLoss!.toStringAsFixed(3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          adopted
              ? 'Lower Brier and log loss on the fair line. Not a sportsbook test.'
              : 'Did not beat the record on the fair line.',
          style: EdgeType.label.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        for (final row in _bucketRows(record, usage)) ...[
          Text(
            row.label,
            style: EdgeType.label.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Record ${row.record}',
                  style: EdgeType.label.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: EdgeColors.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Usage ${row.usage}',
                  textAlign: TextAlign.right,
                  style: EdgeType.label.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: EdgeColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        Text(
          clv.sentence,
          style: EdgeType.label.copyWith(fontWeight: FontWeight.w500, height: 1.35),
        ),
      ],
    );
  }
}

String _bucket(CalibrationBin bin) {
  final from = (bin.from * 100).round();
  if (bin.to >= 1) return '$from%+';
  return '$from–${(bin.to * 100).round()}%';
}

String _bucketHit(CalibrationBin? bin) {
  if (bin == null || bin.games == 0) return '—';
  return '${(bin.actual * 100).round()}% of ${bin.games}';
}

class _BucketRow {
  const _BucketRow(this.label, this.record, this.usage);
  final String label, record, usage;
}

List<_BucketRow> _bucketRows(ChanceBoard record, ChanceBoard usage) {
  final rows = <_BucketRow>[];
  for (final bin in record.calibration) {
    CalibrationBin? match;
    for (final row in usage.calibration) {
      if (row.from == bin.from && row.to == bin.to) match = row;
    }
    if (bin.games == 0 && (match == null || match.games == 0)) continue;
    rows.add(_BucketRow(_bucket(bin), _bucketHit(bin), _bucketHit(match)));
  }
  return rows;
}

class _HowWeTested extends StatefulWidget {
  const _HowWeTested({
    required this.game,
    required this.prop,
    required this.closing,
    required this.comparison,
  });

  final BacktestReport? game;
  final PropReport? prop;
  final ClosingSummary closing;
  final PropModelComparison? comparison;

  @override
  State<_HowWeTested> createState() => _HowWeTestedState();
}

class _HowWeTestedState extends State<_HowWeTested> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final prop = widget.prop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          key: const Key('how-we-tested'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 36),
            alignment: Alignment.centerLeft,
            foregroundColor: EdgeColors.accent,
          ),
          onPressed: () => setState(() => open = !open),
          child: Text(open ? 'Hide how we tested' : 'How we tested'),
        ),
        if (open) ...[
          if (game != null) Text(game.plainEnglish, style: EdgeType.label),
          if (prop != null) ...[
            const SizedBox(height: 10),
            Text(prop.plainEnglish, style: EdgeType.label),
            const SizedBox(height: 8),
            Text(prop.notTested, style: EdgeType.label),
          ],
          if (widget.comparison != null) ...[
            const SizedBox(height: 10),
            Text(widget.comparison!.sentence, style: EdgeType.label),
          ],
          const SizedBox(height: 10),
          Text(widget.closing.plainEnglish, style: EdgeType.label),
        ],
      ],
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.foot});

  final String label;
  final String value;
  final Widget? foot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: EdgeType.label.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: EdgeColors.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: EdgeType.number.copyWith(fontSize: 28)),
            if (foot != null) ...[const SizedBox(height: 8), foot!],
          ],
        ),
      ),
    );
  }
}

/// A short bar with the measured value filled in and a tick at the mark.
class _VersusBar extends StatelessWidget {
  const _VersusBar({
    required this.value,
    required this.mark,
    required this.markLabel,
    this.lowerIsBetter = false,
  });

  final double value;
  final double mark;
  final String markLabel;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final behind = lowerIsBetter ? value > mark : value < mark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 8,
          width: double.infinity,
          child: CustomPaint(
            painter: _VersusPainter(
              value: value,
              mark: mark,
              color: behind ? EdgeColors.warn : EdgeColors.good,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          markLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: EdgeType.label.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: EdgeColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _VersusPainter extends CustomPainter {
  _VersusPainter({
    required this.value,
    required this.mark,
    required this.color,
  });

  final double value;
  final double mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final low = math.min(value, mark);
    final high = math.max(value, mark);
    final pad = math.max(high - low, 1e-6) * 0.7;
    final min = low - pad;
    final max = high + pad;
    final span = max - min;
    double x(double v) => ((v - min) / span).clamp(0.0, 1.0) * size.width;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 3, size.width, 6),
      const Radius.circular(99),
    );
    canvas.drawRRect(track, Paint()..color = EdgeColors.surfaceHigh);
    final fill = math.min(x(value), size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height / 2 - 3, fill, 6),
        const Radius.circular(99),
      ),
      Paint()..color = color,
    );
    final tick = x(mark);
    canvas.drawLine(
      Offset(tick, 0),
      Offset(tick, size.height),
      Paint()
        ..color = EdgeColors.text
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _VersusPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.mark != mark;
}

String _propLine(PropReport? prop) {
  if (prop == null) return 'Scoring past box scores.';
  if (prop.scored == 0) return 'No scored games in this file.';
  if (!prop.usedSportsbookPrices) {
    return 'Not yet tested against sportsbook prices.';
  }
  return 'Tested against sportsbook prices.';
}

String _closeLine(ClosingSummary closing) {
  if (closing.games == 0) return 'No closes saved yet.';
  if (!closing.closed) return 'Prices moved. Games have not started.';
  final average = closing.averageSpreadPoints;
  final points = average == null ? '' : ' · ${signedNumber(average)} pts';
  return 'Beat the later number on ${closing.beatTheLaterNumber} of ${closing.compared}$points.';
}

String _count(int value) {
  final text = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) out.write(',');
    out.write(text[i]);
  }
  return out.toString();
}
