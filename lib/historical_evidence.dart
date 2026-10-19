import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain/history.dart';

class HistoricalEvidence extends StatefulWidget {
  const HistoricalEvidence({super.key, this.source});
  final Future<Map<String, dynamic>>? source;
  @override
  State<HistoricalEvidence> createState() => _HistoricalEvidenceState();
}

class _HistoricalEvidenceState extends State<HistoricalEvidence> {
  late final Future<Map<String, dynamic>> bundle =
      widget.source ??
      rootBundle
          .loadString('assets/nfl-history.json')
          .then(
            (s) => Map<String, dynamic>.from(
              jsonDecode(s.replaceFirst('\uFEFF', '')),
            ),
          );
  String teamA = 'DET', teamB = 'GB';
  int season = 2026, beforeWeek = 6;
  int recentCount = 3; // 0 means calendar weeks; 3/4 means played games.
  String number(double? n) => n == null ? '—' : n.toStringAsFixed(1);
  Widget card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: bundle,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text(
          'Historical evidence could not be loaded. No replacement statistics generated.',
        );
      }
      if (!snapshot.hasData) {
        return const LinearProgressIndicator();
      }
      final data = snapshot.data!;
      final games = (data['games'] as List)
          .map((j) => HistoricalGame.fromJson(j))
          .toList();
      final teams = games.expand((g) => [g.home, g.away]).toSet().toList()
        ..sort();
      final years = games.map((g) => g.season).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
      final maxWeek = games
          .where((g) => g.season == season)
          .map((g) => g.week)
          .reduce((a, b) => a > b ? a : b);
      final benchmark = HistoricalBenchmark(games);
      Widget picker(
        String label,
        String selected,
        ValueChanged<String> onChanged,
      ) => SizedBox(
        width: 160,
        child: DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: InputDecoration(labelText: label),
          items: teams
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) => setState(() => onChanged(v!)),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Season story. Recent form.',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Compare season form with the last 3 or 4 played games. Switch to NFL weeks when you want a calendar-based view.',
                ),
                const Text(
                  'Real final scores · retrospective evidence · independent of the demo odds above',
                  style: TextStyle(color: Colors.amber),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    picker('Team A', teamA, (v) => teamA = v),
                    picker('Team B', teamB, (v) => teamB = v),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('season-$season'),
                        initialValue: season,
                        decoration: const InputDecoration(labelText: 'Season'),
                        items: years
                            .map(
                              (y) =>
                                  DropdownMenuItem(value: y, child: Text('$y')),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          season = v!;
                          beforeWeek =
                              games
                                  .where((g) => g.season == season)
                                  .map((g) => g.week)
                                  .reduce((a, b) => a > b ? a : b) +
                              1;
                        }),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('week-$season-$beforeWeek'),
                        initialValue: beforeWeek,
                        decoration: const InputDecoration(
                          labelText: 'Analyze before week',
                        ),
                        items: [
                          for (var w = 1; w <= maxWeek + 1; w++)
                            DropdownMenuItem(
                              value: w,
                              child: Text(w == 19 ? '19 (full season)' : '$w'),
                            ),
                        ],
                        onChanged: (v) => setState(() => beforeWeek = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in [3, 4, 0])
                      ChoiceChip(
                        label: Text(
                          n == 0 ? 'Last 3 NFL weeks' : 'Last $n games',
                        ),
                        selected: recentCount == n,
                        onSelected: (_) => setState(() => recentCount = n),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Only completed games before week $beforeWeek are used. ${recentCount == 0 ? 'Recent window: NFL weeks ${beforeWeek - 3 < 1 ? 1 : beforeWeek - 3}–${beforeWeek - 1}.' : 'Recent window: last $recentCount played games in this season; byes are skipped.'} Latest NFL week: ${beforeWeek - 1}. Small samples are shown as available, never filled with zeros.',
                ),
                Text(
                  'Downloaded ${data['retrievedAt'].toString().substring(0, 10)}. $season data currently ends in week $maxWeek; the most recent week may be incomplete. This is a bundled snapshot, not a live feed.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final a = teamPanel(games, teamA);
              final b = teamPanel(games, teamB);
              return c.maxWidth < 750
                  ? Column(children: [a, const SizedBox(height: 16), b])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: a),
                        const SizedBox(width: 16),
                        Expanded(child: b),
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          card(
            Column(
              children: [
                ExpansionTile(
                  key: const PageStorageKey('history-trend-help'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('How the trend labels work'),
                  children: [
                    const Text(
                      'Compare average scoring margin (points scored minus allowed) in weeks 1–3 against your selected recent window: 3 games, 4 games, or 3 NFL weeks. A change greater than +3 points is called improving; below −3 is declining; otherwise broadly stable. This descriptive threshold is not a statistical significance test. Labels require non-overlapping windows and at least two games in each. Opponent strength, injuries and weather are not adjusted for. Small samples are noisy; trends do not by themselves establish betting value.',
                    ),
                  ],
                ),
                ExpansionTile(
                  key: const PageStorageKey('history-source'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Test a simple historical baseline'),
                  children: [
                    Text(
                      'Freeze home-win rate from 2022–2024 (${benchmark.trainingCount} non-tied games); evaluate it on 2025 (${benchmark.testCount} non-tied games). Ties are excluded.',
                    ),
                    if (benchmark.probability != null)
                      Text(
                        'Frozen home-win chance ${(benchmark.probability! * 100).toStringAsFixed(1)}% · 2025 Brier error ${benchmark.brier!.toStringAsFixed(4)}. A 50/50 forecast scores 0.2500; lower error is better.',
                      ),
                    const Text(
                      'Educational chronological holdout, not a validated betting model. No team factors or prices are used; no profitability is demonstrated.',
                    ),
                  ],
                ),
                ExpansionTile(
                  key: const PageStorageKey('history-benchmark'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Sources and limitations'),
                  children: [
                    SelectableText(
                      'Source: ${data['source']}\n${data['sourceUrl']}\nAttribution: nflverse contributors · ${data['license']}\n${data['licenseUrl']}\nRetrieved: ${data['retrievedAt']}\nChanges: ${data['changes']}\nSHA-256: ${data['sourceSha256']}\nNo affiliation or endorsement. Later game results are excluded by the selected cutoff, but the source may contain historical corrections. This is not strict point-in-time replay. No historical odds, injuries, player-level stats, or publication timestamps are included.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
  Widget teamPanel(List<HistoricalGame> games, String team) {
    final all = TeamWindow(
      gamesBeforeWeek(games, team, season, beforeWeek),
      team,
    );
    final recent = TeamWindow(
      recentCount == 0
          ? gamesBeforeWeek(games, team, season, beforeWeek, lastWeeks: 3)
          : recentGames(games, team, season, beforeWeek, recentCount),
      team,
    );
    final latest = TeamWindow(
      gamesBeforeWeek(games, team, season, beforeWeek, lastWeeks: 1),
      team,
    );
    final start = TeamWindow(gamesBeforeWeek(games, team, season, 4), team);
    final enough =
        start.games.length >= 2 &&
        recent.games.length >= 2 &&
        recent.games.every((g) => g.week > 3);
    final delta = enough ? recent.margin! - start.margin! : null;
    final trend = delta == null
        ? 'Not enough separate weeks to label a trend'
        : delta > 3
        ? 'Improving scoring margin'
        : delta < -3
        ? 'Declining scoring margin'
        : 'Broadly stable scoring margin';
    Widget window(String title, TeamWindow w) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            '${w.games.length} games · ${w.wins}W ${w.losses}L ${w.ties}T',
            style: const TextStyle(color: Colors.white70),
          ),
          if (w.games.isEmpty)
            const Text('No completed game in this window (bye or unavailable).')
          else
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('${number(w.pointsFor)} scored / game'),
                Text('${number(w.pointsAgainst)} allowed / game'),
                Text('${number(w.margin)} margin / game'),
              ],
            ),
        ],
      ),
    );
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            team,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
          ),
          Text(trend, style: const TextStyle(color: Color(0xFF7CE7C0))),
          if (delta != null)
            Text(
              '${delta > 0 ? '+' : ''}${number(delta)} points/game vs first three weeks; descriptive only.',
            ),
          window('Season to date', all),
          const Divider(),
          window(
            recentCount == 0
                ? 'Last three NFL weeks'
                : 'Last $recentCount played games',
            recent,
          ),
          ExpansionTile(
            key: PageStorageKey(
              'recent-games-$team-$season-$beforeWeek-$recentCount',
            ),
            tilePadding: EdgeInsets.zero,
            title: Text('Games in this window (${recent.games.length})'),
            children: [
              for (final g in recent.games.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Week ${g.week} · ${g.away} ${g.awayScore} at ${g.home} ${g.homeScore}',
                  ),
                  subtitle: Text(
                    '${g.date.toIso8601String().substring(0, 10)} · ${recent.own(g) > recent.opponent(g)
                        ? 'Win'
                        : recent.own(g) < recent.opponent(g)
                        ? 'Loss'
                        : 'Tie'} · ${recent.own(g) - recent.opponent(g)} margin',
                  ),
                ),
            ],
          ),
          const Divider(),
          window('Latest NFL week', latest),
          const Divider(),
          window(
            'Most recent played game',
            TeamWindow(recentGames(games, team, season, beforeWeek, 1), team),
          ),
          ExpansionTile(
            key: PageStorageKey('game-trend-$team-$season-$beforeWeek'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Game-by-game trend'),
            children: [
              for (final g in all.games)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Week ${g.week} · ${g.away} ${g.awayScore} at ${g.home} ${g.homeScore}',
                      ),
                      Text(
                        '${g.date.toIso8601String().substring(0, 10)} · $team margin ${all.own(g) - all.opponent(g)}',
                      ),
                      LinearProgressIndicator(
                        value:
                            (all.own(g) - all.opponent(g)).abs().clamp(0, 50) /
                            50,
                        color: all.own(g) >= all.opponent(g)
                            ? const Color(0xFF7CE7C0)
                            : Colors.orangeAccent,
                      ),
                      ExpansionTile(
                        key: PageStorageKey(
                          'entering-form-$team-${g.season}-${g.week}',
                        ),
                        title: const Text('Team form entering this game'),
                        children: [
                          for (final t in [g.away, g.home])
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(priorSummary(games, t, g)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String priorSummary(
    List<HistoricalGame> games,
    String team,
    HistoricalGame g,
  ) {
    final season = TeamWindow(
      gamesBeforeWeek(games, team, g.season, g.week),
      team,
    );
    final recent = TeamWindow(
      gamesBeforeWeek(games, team, g.season, g.week, lastWeeks: 3),
      team,
    );
    final latest = TeamWindow(
      gamesBeforeWeek(games, team, g.season, g.week, lastWeeks: 1),
      team,
    );
    final played = [
      for (final count in [3, 4])
        TeamWindow(recentGames(games, team, g.season, g.week, count), team),
    ];
    return '$team before week ${g.week}:\nSeason ${season.games.length} games, ${number(season.margin)} average margin\nLast 3 played games: ${played[0].games.length} available, ${number(played[0].margin)} margin\nLast 4 played games: ${played[1].games.length} available, ${number(played[1].margin)} margin\nLast 3 weeks ${recent.games.length} games, ${number(recent.margin)} margin\nLast week ${latest.games.length} games, ${number(latest.margin)} margin. This game and later games are excluded.';
  }
}
