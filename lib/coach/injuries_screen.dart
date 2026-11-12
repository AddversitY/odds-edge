import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/injury_report.dart';
import '../domain/matchup.dart';
import '../domain/nfl_teams.dart';
import '../domain/odds.dart';
import '../domain/prop_history.dart';
import '../theme/edge_theme.dart';
import 'coach_widgets.dart';

Future<InjuryReport> loadStoredInjuryReport() async {
  final json = await rootBundle.loadString('assets/nfl-matchup.json');
  return compute(_storedInjuries, json);
}

InjuryReport _storedInjuries(String json) {
  final decoded = jsonDecode(json.replaceFirst('\uFEFF', ''));
  if (decoded is! Map) {
    throw const FormatException('Stored injuries could not be read.');
  }
  return InjuryReport.fromMatchup(
    MatchupContext.fromJson(Map<String, dynamic>.from(decoded)),
  );
}

class InjuriesScreen extends StatelessWidget {
  const InjuriesScreen({
    super.key,
    required this.now,
    required this.events,
    this.report,
    this.onOpenGame,
    this.onOpenMarket,
  });

  final InjuryReport? report;
  final DateTime now;
  final List<SportEvent> events;
  final ValueChanged<String>? onOpenGame;
  final ValueChanged<String>? onOpenMarket;

  @override
  Widget build(BuildContext context) {
    final shown = report;
    if (shown == null) {
      return const Center(child: Text('Checking the injury report.'));
    }
    final teams = <String, List<InjuryEntry>>{};
    for (final entry in shown.entries) {
      teams.putIfAbsent(entry.team, () => []).add(entry);
    }
    final order = teams.keys.toList()
      ..sort((a, b) {
        final left = nflClubName(a) ?? a;
        final right = nflClubName(b) ?? b;
        return left.compareTo(right);
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const SectionLabel('INJURIES'),
        const SizedBox(height: 8),
        Text(shown.freshness(now), style: EdgeType.title),
        const SizedBox(height: 8),
        Text(shown.notice, style: EdgeType.body),
        const SizedBox(height: 16),
        if (shown.changes.isEmpty)
          const Text(
            'No status has changed since the last check.',
            style: EdgeType.body,
          )
        else ...[
          const SectionLabel('JUST CHANGED'),
          const SizedBox(height: 8),
          for (final change in shown.changes) ...[
            _ChangeCard(
              change: change,
              events: events,
              now: now,
              onOpenGame: onOpenGame,
              onOpenMarket: onOpenMarket,
            ),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 8),
        if (order.isEmpty)
          const Text(
            'No Out, Doubtful, or Questionable players in this report.',
          )
        else
          for (final team in order) ...[
            Text(nflClubName(team) ?? team, style: EdgeType.title),
            const SizedBox(height: 8),
            for (final entry in teams[team]!) ...[
              _EntryCard(
                entry: entry,
                events: events,
                now: now,
                onOpenGame: onOpenGame,
                onOpenMarket: onOpenMarket,
              ),
              const SizedBox(height: 10),
            ],
          ],
        const SizedBox(height: 8),
        const Text(
          'ESPN is unofficial. NFL.com is the league\'s report. nflverse compiles that report and is shared under CC BY 4.0. Odds Edge is not affiliated with ESPN, the NFL, or nflverse. This page does not use the odds feed.',
          style: EdgeType.label,
        ),
      ],
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({
    required this.change,
    required this.events,
    required this.now,
    this.onOpenGame,
    this.onOpenMarket,
  });

  final InjuryChange change;
  final List<SportEvent> events;
  final DateTime now;
  final ValueChanged<String>? onOpenGame;
  final ValueChanged<String>? onOpenMarket;

  @override
  Widget build(BuildContext context) {
    final entry = change.entry;
    return Container(
      key: const Key('injury-change'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EdgeColors.warn.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(EdgeSpace.radius),
        border: Border.all(color: EdgeColors.warn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(change.summary, style: EdgeType.body),
          if (entry != null) ...[
            const SizedBox(height: 6),
            Text(_impactLine(entry), style: EdgeType.body),
            const SizedBox(height: 4),
            Text(_sourceLine(entry, now), style: EdgeType.label),
            _links(
              entry: entry,
              events: events,
              onOpenGame: onOpenGame,
              onOpenMarket: onOpenMarket,
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.events,
    required this.now,
    this.onOpenGame,
    this.onOpenMarket,
  });

  final InjuryEntry entry;
  final List<SportEvent> events;
  final DateTime now;
  final ValueChanged<String>? onOpenGame;
  final ValueChanged<String>? onOpenMarket;

  @override
  Widget build(BuildContext context) {
    final color = entry.outLike ? EdgeColors.bad : EdgeColors.warn;
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.player,
                  style: EdgeType.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                entry.status,
                style: EdgeType.label.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (entry.position.isNotEmpty) entry.position,
              if (entry.injury.isNotEmpty) entry.injury,
            ].join(' · '),
            style: EdgeType.label,
          ),
          const SizedBox(height: 6),
          Text(_impactLine(entry), style: EdgeType.body),
          const SizedBox(height: 4),
          Text(_sourceLine(entry, now), style: EdgeType.label),
          _links(
            entry: entry,
            events: events,
            onOpenGame: onOpenGame,
            onOpenMarket: onOpenMarket,
          ),
        ],
      ),
    );
  }
}

String _impactLine(InjuryEntry entry) {
  final impact = injuryImpact(entry.position, entry.status);
  if (impact != null) return impact.line;
  return '${entry.position.isEmpty ? 'Player' : entry.position} ${entry.status.toLowerCase()}: the effect on a prop is not mapped.';
}

String _sourceLine(InjuryEntry entry, DateTime now) {
  final agrees = entry.agrees.isEmpty
      ? ''
      : ' · ${entry.agrees.join(' and ')} agrees';
  final differs = entry.differs == null ? '' : ' · ${entry.differs}';
  final when = entry.updatedAt == null
      ? ''
      : ' · ${updatedAgo(entry.updatedAt!, now)}';
  return '${entry.sourceLabel}$when$agrees$differs';
}

Widget _links({
  required InjuryEntry entry,
  required List<SportEvent> events,
  ValueChanged<String>? onOpenGame,
  ValueChanged<String>? onOpenMarket,
}) {
  SportEvent? game;
  for (final event in events) {
    if (sameClub(event.away, entry.team) || sameClub(event.home, entry.team)) {
      game = event;
      break;
    }
  }
  final impact = injuryImpact(entry.position, entry.status);
  final markets = impact?.markets ?? const <String>[];
  if (game == null && markets.isEmpty) return const SizedBox.shrink();
  return Wrap(
    spacing: 8,
    children: [
      if (game != null)
        TextButton(
          onPressed: onOpenGame == null ? null : () => onOpenGame(game!.id),
          child: Text('${game.away} at ${game.home}'),
        ),
      for (final market in markets.take(2))
        TextButton(
          onPressed: onOpenMarket == null ? null : () => onOpenMarket(market),
          child: Text(_marketLabel(market)),
        ),
    ],
  );
}

String _marketLabel(String market) => switch (market) {
  'spreads' => 'Spread',
  'h2h' => 'Moneyline',
  'totals' => 'Total',
  _ => propMarketLabels[market] ?? market,
};
