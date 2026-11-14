import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/edge_gap.dart';
import '../domain/history.dart';
import '../domain/hit_rate.dart';
import '../domain/injury_report.dart';
import '../domain/matchup.dart';
import '../domain/odds.dart';
import '../domain/parlay_slip.dart';
import '../domain/prop_history.dart';
import '../domain/why_brief.dart';
import '../theme/edge_theme.dart';
import '../ui/prop_breakdown.dart';
import '../ui/value_check.dart';
import '../ui/wordmark.dart';
import 'coach_widgets.dart';
import 'prop_pricing.dart';
import 'value_view.dart';
import 'why_view.dart';

class PropDetailScreen extends StatefulWidget {
  const PropDetailScreen({
    super.key,
    required this.card,
    required this.cards,
    required this.board,
    required this.now,
    this.directory,
    this.context,
    this.injuries,
    this.history,
    this.scores = const [],
    this.slip,
  });

  final PropCardModel card;
  final List<PropCardModel> cards;
  final OddsBoard board;
  final DateTime now;
  final PlayerDirectory? directory;
  final MatchupContext? context;
  final InjuryReport? injuries;
  final Future<List<OddsQuote>> Function(Selection selection)? history;
  final List<HistoricalGame> scores;
  final ParlaySlipController? slip;

  @override
  State<PropDetailScreen> createState() => _PropDetailScreenState();
}

class _PropDetailScreenState extends State<PropDetailScreen> {
  late PropCardModel card = widget.card;
  int window = 1;
  String? blockNote;

  @override
  void initState() {
    super.initState();
    widget.slip?.addListener(_onSlip);
  }

  @override
  void didUpdateWidget(PropDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slip != widget.slip) {
      oldWidget.slip?.removeListener(_onSlip);
      widget.slip?.addListener(_onSlip);
    }
  }

  @override
  void dispose() {
    widget.slip?.removeListener(_onSlip);
    super.dispose();
  }

  void _onSlip() {
    if (mounted) setState(() {});
  }

  ShownProp get shown => showProp(
    card: card,
    cards: widget.cards,
    directory: widget.directory,
    context: widget.context,
    board: widget.board,
    now: widget.now,
    injuries: widget.injuries,
    scores: widget.scores,
  );

  @override
  Widget build(BuildContext context) {
    final face = shown;
    final verdict = face.verdict;
    final quote = card.best;
    final windows = face.windows;
    final rates = [
      windows?.last5,
      windows?.last10,
      windows?.headToHead,
      windows?.season,
    ];
    final selected = rates[window.clamp(0, rates.length - 1)];
    final stats = sampleStats(
      selected?.samples.map((sample) => sample.value) ?? const [],
    );
    final injuries = _injuries(face);
    final held = widget.slip?.slip.contains(card.id) ?? false;
    return Scaffold(
      key: const Key('prop-detail'),
      backgroundColor: EdgeColors.background,
      appBar: AppBar(
        title: Text(
          card.player,
          style: EdgeType.title.copyWith(
            fontFamily: EdgeFont.display,
            fontSize: 20,
          ),
        ),
        actions: [
          if (card.demo || widget.board.demo) const ExamplePill(),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: quote == null
              ? const EmptyNote(
                  'No open price in this snapshot, so this prop cannot be added.',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (blockNote != null) ...[
                      Text(
                        blockNote!,
                        style: EdgeType.label.copyWith(color: EdgeColors.warn),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton(
                      key: const Key('add-to-parlay'),
                      onPressed: () => _toggleSlip(held),
                      child: Text(
                        held ? 'Remove from parlay' : 'Add to parlay',
                      ),
                    ),
                  ],
                ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (propMeta(face).isNotEmpty)
            Text(propMeta(face), style: EdgeType.label),
          if (card.otherSide != null) ...[
            const SizedBox(height: 10),
            _SideSwitch(
              over: card.lineSide == LineSide.over,
              onChanged: _toggle,
            ),
          ],
          if (face.badge != null) ...[
            const SizedBox(height: 8),
            InjuryBadgePill(
              label: face.badge!.label,
              severe: face.badge!.severe,
            ),
          ],
          const SizedBox(height: 12),
          _PriceHero(card: card, quote: quote, now: widget.now),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EdgeColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EdgeColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Price check', style: EdgeType.label),
                    ),
                    WordPill(
                      word: verdict.word,
                      overpriced: verdict.overpriced,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ValueCheck(
                  word: verdict.word,
                  overpriced: verdict.overpriced,
                  ourChance: verdict.ourChance,
                  bookChance: verdict.breakEven,
                  ourLabel: 'Model estimate',
                  bookLabel: 'Price requires',
                  compact: true,
                  note: 'Model estimate; no demonstrated betting edge.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _EvidenceSummary(
            face: face,
            average: stats.average,
            observed: stats.count,
          ),
          const SizedBox(height: 12),
          _ResearchSection(
            title: 'Performance',
            initiallyExpanded: true,
            children: [
              const SizedBox(height: 18),
              _SectionHead(
                title: 'Hit rate',
                trailing: windows?.seasonYear == null
                    ? null
                    : '${windows!.seasonYear}',
              ),
              const SizedBox(height: 8),
              EdgeSegments(
                labels: const ['L5', 'L10', 'H2H', 'Season'],
                index: window,
                onChanged: (index) => setState(() => window = index),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatReadout('Avg', stats.average),
                  const SizedBox(width: 16),
                  _StatReadout('Median', stats.median),
                  const Spacer(),
                  Text(
                    stats.count == 0
                        ? 'No games'
                        : '${stats.count} ${stats.count == 1 ? 'game' : 'games'}',
                    style: EdgeType.label,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _HitBoard(
                samples: selected?.samples ?? const [],
                line: card.line,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Green cleared the line. Red missed.',
                      style: EdgeType.label,
                    ),
                  ),
                  IconButton(
                    tooltip: 'How these windows are counted',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _countNote(windows?.note),
                    icon: const Icon(Icons.info_outline, size: 20),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ResearchSection(
            title: 'Matchup and availability',
            children: [
              const SizedBox(height: 18),
              const _SectionHead(title: 'Matchup'),
              const SizedBox(height: 8),
              _MatchupMeter(
                defense: face.value.matchup?.defense,
                note: face.note,
              ),
              const SizedBox(height: 18),
              _SectionHead(
                title: 'Injuries',
                trailing: widget.injuries?.freshness(widget.now),
              ),
              const SizedBox(height: 8),
              if (widget.injuries == null)
                const EmptyNote(
                  'No injury report is loaded. Nothing was filled in.',
                )
              else if (injuries.isEmpty)
                const EmptyNote(
                  'No Out or Questionable player in this report is tied to this prop.',
                )
              else
                for (final entry in injuries) ...[
                  _InjuryRow(entry: entry),
                  const SizedBox(height: 8),
                ],
            ],
          ),
          const SizedBox(height: 12),
          _ResearchSection(
            title: 'Price comparison',
            children: [
              Text(
                verdict.fairChance == null
                    ? "Market no-vig chance unavailable."
                    : "Market no-vig chance: ${(verdict.fairChance! * 100).toStringAsFixed(1)}%",
                style: EdgeType.label,
              ),
              const SizedBox(height: 10),
              const _SectionHead(title: 'Prices'),
              const SizedBox(height: 8),
              if (card.bookRows.isEmpty)
                const EmptyNote('No open price for this side.')
              else
                for (var i = 0; i < card.bookRows.length; i++)
                  _BookRow(
                    row: card.bookRows[i],
                    best: i == 0,
                    now: widget.now,
                  ),
              const SizedBox(height: 16),
              const _SectionHead(title: 'Odds over time'),
              const SizedBox(height: 8),
              if (widget.history == null)
                const EmptyNote(
                  'Price history is collected by the local backend. Nothing is drawn in its place.',
                )
              else
                FutureBuilder<List<OddsQuote>>(
                  future: widget.history!(card.side),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LinearProgressIndicator();
                    }
                    if (snapshot.hasError) {
                      return const EmptyNote(
                        'Saved price history could not be read.',
                      );
                    }
                    return OddsHistoryChart(quotes: snapshot.data ?? const []);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _ResearchSection(
            title: 'Model and math',
            children: [
              if (face.projection != null) ...[
                const SizedBox(height: 12),
                PropBreakdown(projection: face.projection!),
              ],
              const SizedBox(height: 4),
              ValueView(
                headline: false,
                verdict: verdict,
                whyBody: WhyBriefView(
                  brief: buildPropBrief(
                    verdict: verdict,
                    line: card.line,
                    side: card.lineSide,
                    market: card.market,
                    player: card.player,
                    windows: windows,
                    matchup: face.value.matchup,
                    teamName: clubNickname(windows?.team),
                    teamSpread: face.teamSpread,
                    total: face.total,
                    injuries: widget.injuries,
                    playerTeam: windows?.team,
                    opponent: face.opponent,
                  ),
                ),
                extraMath: face.value.matchup == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              face.value.matchup!.snapLine,
                              style: EdgeType.body,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              face.value.matchup!.credit,
                              style: EdgeType.label,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Comparison, not a pick.',
            textAlign: TextAlign.center,
            style: EdgeType.label.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: EdgeColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  List<InjuryEntry> _injuries(ShownProp face) {
    final report = widget.injuries;
    if (report == null) return const [];
    return [
      for (final entry in report.entries)
        if (injuryAffectsProp(
          entry,
          market: card.market,
          playerName: card.player,
          playerTeam: face.windows?.team,
          opponent: face.opponent,
        ))
          entry,
    ];
  }

  void _toggle() {
    final other = card.otherSide;
    if (other == null) return;
    final match = widget.cards.where((item) => item.side.key == other.key);
    if (match.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The other side is not in this snapshot, so it was not switched.',
          ),
        ),
      );
      return;
    }
    setState(() {
      card = match.first;
      blockNote = null;
    });
  }

  void _toggleSlip(bool held) {
    final slip = widget.slip;
    if (slip == null) return;
    if (held) {
      slip.remove(card.id);
      setState(() => blockNote = null);
      return;
    }
    for (final key in slip.slip.selectionKeys) {
      final heldCard = widget.cards.where((item) => item.id == key);
      if (heldCard.isEmpty) continue;
      if (oppositeSides(heldCard.first.side, card.side)) {
        setState(() {
          blockNote = 'This is the other side of a leg already on the slip. It was not added.';
        });
        return;
      }
    }
    setState(() => blockNote = null);
    slip.add(card.id);
  }

  void _countNote(String? detail) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EdgeColors.surface,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Text(
          detail ?? 'Each bar is one recorded game, oldest to newest. Green cleared the line. Red missed. A missing stat is skipped.',
          style: EdgeType.body,
        ),
      ),
    );
  }
}

class _SideSwitch extends StatelessWidget {
  const _SideSwitch({required this.over, required this.onChanged});

  final bool over;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip('Over', over, over ? null : onChanged),
        const SizedBox(width: 8),
        _chip('Under', !over, over ? onChanged : null),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback? onTap) {
    return Material(
      color: selected ? EdgeColors.accent : EdgeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: EdgeType.label.copyWith(
              color: selected ? EdgeColors.onAccent : EdgeColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceHero extends StatelessWidget {
  const _PriceHero({
    required this.card,
    required this.quote,
    required this.now,
  });
  final PropCardModel card;
  final OddsQuote? quote;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shortPropLine(card),
              style: EdgeType.title.copyWith(
                fontFamily: EdgeFont.display,
                fontSize: 18,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                quote == null ? '—' : americanLabel(quote!.decimal),
                style: EdgeType.number.copyWith(fontSize: 22),
              ),
              Text(
                priceBlurb(card),
                style: EdgeType.label.copyWith(fontSize: 11),
              ),
              if (quote != null)
                Text(
                  '${quote!.demo ? 'Example' : 'Saved'} · ${priceAge(quote!.sourceAt, now)}',
                  style: EdgeType.label.copyWith(fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResearchSection extends StatelessWidget {
  const _ResearchSection({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: EdgeColors.surface,
      border: Border.all(color: EdgeColors.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: ExpansionTile(
      key: PageStorageKey('prop-section-$title'),
      title: Text(title, style: EdgeType.title.copyWith(fontSize: 18)),
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ],
    ),
  );
}

class _EvidenceSummary extends StatelessWidget {
  const _EvidenceSummary({
    required this.face,
    required this.average,
    required this.observed,
  });
  final ShownProp face;
  final double? average;
  final int observed;

  @override
  Widget build(BuildContext context) {
    final mean = average;
    final supports =
        mean != null &&
        (face.card.lineSide == LineSide.over
            ? mean > face.card.line
            : mean < face.card.line);
    final support = mean == null
        ? 'No recorded average is available for the selected window.'
        : 'The average in $observed recorded games was ${mean.toStringAsFixed(1)}, ${mean > face.card.line
              ? 'above'
              : mean < face.card.line
              ? 'below'
              : 'on'} this line.';
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Evidence at a glance',
            style: EdgeType.title.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          Text(
            supports ? 'Supports this side' : 'Selected sample',
            style: EdgeType.label,
          ),
          Text(support, style: EdgeType.body),
          const SizedBox(height: 12),
          Text('Reasons for caution', style: EdgeType.label),
          Text(
            observed < 10
                ? 'Only $observed recorded games in this window. A short sample is not a forecast.'
                : 'Past clear rates do not establish the chance of the next game.',
            style: EdgeType.body,
          ),
          if (!supports && mean != null)
            const Text(
              'The recorded average does not support the selected side.',
              style: EdgeType.body,
            ),
          if (face.badge != null)
            const Text(
              'Check player availability before relying on a projection.',
              style: EdgeType.body,
            ),
        ],
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: EdgeType.title.copyWith(
            fontFamily: EdgeFont.display,
            fontSize: 20,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Flexible(
            child: Text(
              trailing!,
              textAlign: TextAlign.right,
              style: EdgeType.label.copyWith(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _StatReadout extends StatelessWidget {
  const _StatReadout(this.label, this.value);
  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value == null ? '—' : value!.toStringAsFixed(1),
          style: EdgeType.number.copyWith(fontSize: 18),
        ),
        Text(
          label.toUpperCase(),
          style: EdgeType.label.copyWith(
            fontSize: 10,
            letterSpacing: 0.6,
            color: EdgeColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _HitBoard extends StatelessWidget {
  const _HitBoard({required this.samples, required this.line});
  final List<HitSample> samples;
  final double line;

  @override
  Widget build(BuildContext context) {
    final recorded = samples.where((sample) => sample.value != null).toList();
    if (recorded.isEmpty) {
      return const EmptyNote(
        'No recorded stat in this window, so there is no chart.',
      );
    }
    final chronological = recorded.reversed.toList();
    final trimmed = chronological.length > 10;
    final shown = trimmed
        ? chronological.sublist(chronological.length - 10)
        : chronological;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LineChart(samples: shown.reversed.toList(), line: line),
        if (trimmed)
          Text(
            'Latest 10 of ${chronological.length} recorded games.',
            style: EdgeType.label,
          ),
      ],
    );
  }
}

class _MatchupMeter extends StatelessWidget {
  const _MatchupMeter({required this.defense, required this.note});
  final DefenseAllow? defense;
  final MatchupNote? note;

  @override
  Widget build(BuildContext context) {
    if (defense == null) {
      return const EmptyNote(
        'No defensive rank. The stored games did not have this stat against that team.',
      );
    }
    final span = (defense!.teams - 1).clamp(1, 100);
    final place = ((defense!.rank - 1) / span).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ordinal(defense!.rank)} of ${defense!.teams}',
            style: EdgeType.number.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 2),
          Text(
            '${defense!.statLabel} · ${defense!.perGame.toStringAsFixed(1)} a game',
            style: EdgeType.label,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 18,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final x = place * (constraints.maxWidth - 14);
                return Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: const LinearGradient(
                            colors: [
                              EdgeColors.bad,
                              EdgeColors.warn,
                              EdgeColors.good,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: x,
                      top: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: EdgeColors.text,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: EdgeColors.background,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            children: [
              Text('Tough', style: EdgeType.label),
              Spacer(),
              Text('Favorable', style: EdgeType.label),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!.text, style: EdgeType.body.copyWith(fontSize: 15)),
          ],
        ],
      ),
    );
  }
}

class _InjuryRow extends StatelessWidget {
  const _InjuryRow({required this.entry});
  final InjuryEntry entry;

  @override
  Widget build(BuildContext context) {
    final severe = entry.outLike;
    final color = severe ? EdgeColors.bad : EdgeColors.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: .16),
            child: Text(
              playerInitials(entry.player),
              style: EdgeType.label.copyWith(
                fontSize: 11,
                color: EdgeColors.text,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.player,
                  style: EdgeType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  [
                    entry.position,
                    entry.team,
                    if (entry.injury.isNotEmpty) entry.injury,
                  ].where((part) => part.isNotEmpty).join(' · '),
                  style: EdgeType.label.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            entry.status.toUpperCase(),
            style: EdgeType.label.copyWith(
              color: color,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.row, required this.best, required this.now});
  final BookPriceRow row;
  final bool best;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.quote.book,
                        style: EdgeType.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (best) ...[
                      const SizedBox(width: 8),
                      Text(
                        'BEST',
                        style: EdgeType.label.copyWith(
                          color: EdgeColors.accent,
                          fontSize: 10,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${row.quote.demo ? 'Sample' : 'Saved'} · ${priceAge(row.quote.sourceAt, now)}',
                  style: EdgeType.label.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            americanLabel(row.quote.decimal),
            style: EdgeType.number.copyWith(fontSize: 16),
          ),
        ],
      ),
    );
  }
}
