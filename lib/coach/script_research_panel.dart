import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/game_script_simulation.dart';
import '../domain/history.dart';
import '../domain/injury_report.dart';
import '../domain/matchup.dart';
import '../domain/odds.dart';
import '../domain/player_stats.dart';
import '../domain/prop_history.dart';
import '../theme/edge_theme.dart';
import '../ui/parlay_validation.dart';
import 'prop_pricing.dart';

typedef _Request = ({
  List<ScriptLeg> legs,
  List<SportEvent> events,
  List<PlayerGame> players,
  List<HistoricalGame> games,
  int season,
});
ScriptSimulation _run(_Request request) => simulateGameScripts(
  legs: request.legs,
  events: request.events,
  players: request.players,
  games: request.games,
  beforeSeason: request.season,
);

/// A research calculation only. It never saves a placed wager or its result.
class ScriptResearchPanel extends StatefulWidget {
  const ScriptResearchPanel({
    super.key,
    required this.legs,
    required this.cards,
    required this.board,
    required this.directory,
    required this.scores,
    required this.now,
    required this.context,
    required this.injuries,
    required this.onResult,
    required this.onQuote,
    required this.onReplace,
  });
  final List<ShownProp> legs;
  final List<PropCardModel> cards;
  final OddsBoard board;
  final PlayerDirectory? directory;
  final List<HistoricalGame> scores;
  final DateTime now;
  final MatchupContext? context;
  final InjuryReport? injuries;
  final ValueChanged<double> onResult;
  final ValueChanged<double?> onQuote;
  final void Function(String old, String replacement) onReplace;
  @override
  State<ScriptResearchPanel> createState() => _ScriptResearchPanelState();
}

class _ScriptResearchPanelState extends State<ScriptResearchPanel> {
  ScriptSimulation? result;
  ShownProp? swap;
  bool running = false;
  String? error, quoteError;
  final quote = TextEditingController();
  @override
  void dispose() {
    quote.dispose();
    super.dispose();
  }

  Future<void> run() async {
    setState(() {
      running = true;
      error = null;
    });
    try {
      final legs = widget.legs.map(scriptLegFor).toList();
      if (legs.any((l) => l == null) || widget.directory == null) {
        throw ArgumentError(
          'Every leg needs a supported workload projection and a matching recorded club.',
        );
      }
      final selected = widget.board.events
          .where((e) => legs.any((l) => l!.eventId == e.id))
          .toList();
      final seasons = selected
          .map((e) => e.startsAt.year - (e.startsAt.month <= 2 ? 1 : 0))
          .toList();
      seasons.sort();
      if (seasons.isEmpty) throw ArgumentError('The event is missing.');
      final next = await compute(_run, (
        legs: legs.cast<ScriptLeg>(),
        events: selected,
        players: widget.directory!.data.rows,
        games: widget.scores,
        season: seasons.first,
      ));
      if (!mounted) return;
      final weakest = widget.legs[next.weakest];
      ShownProp? alternative;
      final memo = PropPricingMemo();
      for (final card in widget.cards) {
        if (card.id == weakest.card.id ||
            widget.legs.any((l) => l.card.id == card.id) ||
            card.side.eventId != weakest.card.side.eventId ||
            card.player != weakest.card.player ||
            card.market != weakest.card.market ||
            card.lineSide != weakest.card.lineSide ||
            card.best == null) {
          continue;
        }
        final candidate = showProp(
          card: card,
          cards: widget.cards,
          directory: widget.directory,
          context: widget.context,
          board: widget.board,
          now: widget.now,
          injuries: widget.injuries,
          scores: widget.scores,
          memo: memo,
        );
        final chance = candidate.verdict.ourChance;
        if (chance != null &&
            chance > (weakest.verdict.ourChance ?? 1) &&
            chance > (alternative?.verdict.ourChance ?? 0)) {
          alternative = candidate;
        }
      }
      setState(() {
        result = next;
        swap = alternative;
      });
      widget.onResult(next.joint);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => error = '${e.message}');
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'The simulation could not finish. No combined chance was filled in.',
        );
      }
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  String pct(double p) => '${(p * 100).toStringAsFixed(1)}%';
  String name(int i) =>
      '${widget.legs[i].card.player} ${shortPropLine(widget.legs[i].card)}';
  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Explore the ticket', style: EdgeType.title),
            const SizedBox(height: 8),
            const Text(
              'Experimental · 10,000 seeded game-script draws. Prior seasons only for correlations. No demonstrated betting edge.',
              style: EdgeType.label,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: running ? null : run,
              icon: running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.science_outlined),
              label: Text(
                running
                    ? 'Simulating…'
                    : r == null
                    ? 'Run simulation'
                    : 'Run again',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: EdgeType.body),
              ),
            if (r != null) ...[
              const SizedBox(height: 16),
              Text(
                'Together ${pct(r.joint)}  ·  Multiplied ${pct(r.independent)}',
                style: EdgeType.body,
              ),
              if (r.training.any(
                (m) => [
                  for (var i = 6; i < m.features.length; i++)
                    for (var j = 6; j < i; j++) m.pairs[i][j],
                ].any((n) => n < scriptMinimumPairs),
              ))
                const Text(
                  'Limited paired history: some dependencies default to independence.',
                  style: EdgeType.label,
                ),
              Text(
                'Simulation noise: 95% interval ${pct(r.lower)}–${pct(r.upper)}. This excludes model uncertainty.',
                style: EdgeType.label,
              ),
              const SizedBox(height: 12),
              Text(
                'Lowest individual estimate: ${name(r.weakest)} (${pct(widget.legs[r.weakest].verdict.ourChance!)}).',
                style: EdgeType.body,
              ),
              const SizedBox(height: 8),
              Text(
                r.failureLegs.isEmpty
                    ? 'No failed draws in this run.'
                    : 'Most common losing pattern: ${r.failureLegs.map(name).join(' + ')} missed; ${pct(r.failurePatternShare)} of losing draws.',
                style: EdgeType.body,
              ),
              if (swap != null)
                TextButton(
                  onPressed: () => widget.onReplace(
                    widget.legs[r.weakest].card.id,
                    swap!.card.id,
                  ),
                  child: Text(
                    'Try ${shortPropLine(swap!.card)} · ${americanLabel(swap!.card.best!.decimal)}',
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No higher-chance alternate line is available for this leg in this snapshot.',
                    style: EdgeType.label,
                  ),
                ),
              if (swap != null)
                const Text(
                  'A higher individual chance can mean a lower payout. Re-run after replacing; this is not a recommendation.',
                  style: EdgeType.label,
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Method and data', style: EdgeType.label),
                children: [
                  const Text(
                    'Draw order: game margin and total → team pass/rush → player stats. These are statistical latent scripts, not play-by-play or yardage-conserving game forecasts. Player curves preserve the displayed market-shrunk chances; receptions use a count distribution.',
                    style: EdgeType.label,
                  ),
                  for (final model in r.training)
                    Text(
                      'Seasons before ${model.beforeSeason} · ${model.trainingGames} aligned games. Pair counts: ${[for (var i = 6; i < model.features.length; i++)
                        for (var j = 6; j < i; j++) model.pairs[i][j]].join(', ')}. Fewer than 12 paired games revert to independence. Correlations shrink by n/(n+40), cap at ±0.65; covariance repair scale ${model.psdScale.toStringAsFixed(2)}.',
                      style: EdgeType.label,
                    ),
                  const Text(
                    'Seed 1729. Whole-number push lines and unsupported stats are excluded. Separate games are independent. No sportsbook profitability test.',
                    style: EdgeType.label,
                  ),
                ],
              ),
              const ParlayValidation(),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: quote,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Book ticket price (decimal, optional)',
                hintText: 'For example, 4.20',
                errorText: quoteError,
                helperText: 'Same exact legs. No bet or result is recorded.',
                helperMaxLines: 2,
              ),
              onChanged: (text) {
                final value = double.tryParse(text.trim());
                final valid = value != null && value.isFinite && value > 1;
                setState(
                  () => quoteError = text.trim().isEmpty || valid
                      ? null
                      : 'Enter decimal odds greater than 1.',
                );
                widget.onQuote(valid ? value : null);
              },
            ),
          ],
        ),
      ),
    );
  }
}
