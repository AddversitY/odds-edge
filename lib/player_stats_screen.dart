import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain/player_stats.dart';

const _mint = Color(0xff7ee6b5);

PlayerStatsDataset _decodePlayerSnapshot(String json) =>
    PlayerStatsDataset.fromJson(
      Map<String, dynamic>.from(jsonDecode(json.replaceFirst('\uFEFF', ''))),
    );

class PlayerStatsScreen extends StatefulWidget {
  const PlayerStatsScreen({super.key, this.source, this.onInvestigate});

  final Future<Map<String, dynamic>>? source;
  final void Function(PlayerGame, List<PlayerGame>, Map<String, dynamic>)?
  onInvestigate;

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  late Future<PlayerStatsDataset> bundle = _load();
  String query = '', position = 'All', period = 'REG';
  String? selectedId, selectedGroup;
  int selectedSeason = 0; // Latest recorded appearances can span seasons.
  bool averages = false;
  PlayerStatsDataset? indexedDataset;
  final Map<String, List<PlayerGame>> rowsByPlayer = {};
  final Map<String, PlayerGame> players = {};
  List<PlayerGame> allPlayers = [];
  List<String> positions = [];
  DateTime? latestDate;

  void _index(PlayerStatsDataset dataset) {
    if (identical(indexedDataset, dataset)) return;
    indexedDataset = dataset;
    rowsByPlayer.clear();
    players.clear();
    latestDate = null;
    for (final row in dataset.rows) {
      rowsByPlayer.putIfAbsent(row.playerId, () => []).add(row);
      final previous = players[row.playerId];
      if (previous == null || row.date.isAfter(previous.date)) {
        players[row.playerId] = row;
      }
      if (latestDate == null || row.date.isAfter(latestDate!)) {
        latestDate = row.date;
      }
    }
    allPlayers = players.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    positions = allPlayers.map((p) => p.position).toSet().toList()..sort();
  }

  Future<PlayerStatsDataset> _load() async {
    if (widget.source != null) {
      return PlayerStatsDataset.fromJson(await widget.source!);
    }
    final json = await rootBundle.loadString('assets/nfl-player-stats.json');
    return compute(_decodePlayerSnapshot, json);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlayerStatsDataset>(
    future: bundle,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Player statistics are unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'The saved statistics could not be loaded. Try again to reopen the local data snapshot.',
              ),
              TextButton.icon(
                onPressed: () => setState(() => bundle = _load()),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final dataset = snapshot.data!;
      if (dataset.rows.isEmpty) {
        return _card(
          const Text(
            'No individual game statistics are included in this snapshot yet. Team results are available in NFL matchups.',
          ),
        );
      }
      _index(dataset);
      final currentSeason =
          (dataset.metadata['currentSeason'] as num?)?.toInt() ??
          dataset.rows.map((g) => g.season).reduce((a, b) => a > b ? a : b);
      final previousYears = previous3CompletedYears(currentSeason);
      final years = [currentSeason, ...previousYears];
      if (selectedSeason != 0 && !years.contains(selectedSeason)) {
        selectedSeason = 0;
      }
      selectedId ??=
          allPlayers
              .where((p) => p.name.toLowerCase() == 'jared goff')
              .firstOrNull
              ?.playerId ??
          allPlayers.first.playerId;
      final selected = players[selectedId] ?? allPlayers.first;
      final normalizedQuery = query.trim().toLowerCase();
      final matches = allPlayers
          .where(
            (p) =>
                (position == 'All' || p.position == position) &&
                '${p.name} ${p.team} ${p.position}'.toLowerCase().contains(
                  normalizedQuery,
                ),
          )
          .toList();
      final playerRows = rowsByPlayer[selected.playerId]!;
      final history = playerGames(
        playerRows,
        selected.playerId,
        seasonType: period,
      );
      final games = playerGames(
        playerRows,
        selected.playerId,
        season: selectedSeason == 0 ? null : selectedSeason,
        seasonType: period,
      );
      final recent = lastPlayerGames(
        playerRows,
        selected.playerId,
        count: 3,
        season: selectedSeason == 0 ? null : selectedSeason,
        seasonType: period,
      );
      final groups = _groupsFor(selected.position, history);
      if (!groups.any((g) => g.name == selectedGroup)) {
        selectedGroup = groups.first.name;
      }
      final group = groups.firstWhere((g) => g.name == selectedGroup);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Player explorer',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Individual game logs, recent form, and three completed seasons in one place.',
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth >= 650
                            ? constraints.maxWidth - 202
                            : constraints.maxWidth,
                        child: TextField(
                          key: const Key('player-search'),
                          decoration: const InputDecoration(
                            labelText: 'Find a player',
                            hintText: 'Player name or team',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) => setState(() => query = value),
                        ),
                      ),
                      SizedBox(
                        width: constraints.maxWidth >= 650
                            ? 190
                            : constraints.maxWidth,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey('player-position-$position'),
                          initialValue: position,
                          decoration: const InputDecoration(
                            labelText: 'Position',
                          ),
                          items: ['All', ...positions]
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p == 'All' ? 'All positions' : p),
                                ),
                              )
                              .toList(),
                          onChanged: (p) => setState(() => position = p!),
                        ),
                      ),
                    ],
                  ),
                ),
                if (normalizedQuery.isNotEmpty || position != 'All') ...[
                  const SizedBox(height: 12),
                  Text(
                    '${matches.length} matching players${matches.length > 20 ? ' · showing 20, refine your search' : ''}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No matches. Try a shorter name or choose All positions.',
                      ),
                    ),
                  for (final p in matches.take(20))
                    ListTile(
                      key: ValueKey('player-result-${p.playerId}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        selected.playerId == p.playerId
                            ? Icons.check_circle
                            : Icons.person_outline,
                        color: _mint,
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                        '${p.position} · ${p.team} · latest recorded team',
                      ),
                      onTap: () => setState(() {
                        selectedId = p.playerId;
                        selectedGroup = null;
                      }),
                    ),
                ] else ...[
                  const SizedBox(height: 10),
                  Text(
                    'Search ${allPlayers.length} players or choose a position.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected.name,
                  key: const Key('selected-player-name'),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(color: _mint, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${selected.position} · ${selected.team} · team at latest recorded appearance',
                ),
                if (widget.onInvestigate != null &&
                    [
                      'QB',
                      'RB',
                      'FB',
                      'WR',
                      'TE',
                    ].contains(selected.position)) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('start-player-investigation'),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      widget.onInvestigate!(
                        selected,
                        playerRows,
                        dataset.metadata,
                      );
                    },
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Investigate a bet'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Evidence → scenarios → saved prediction → outcome review',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        key: ValueKey('player-season-$selectedSeason'),
                        initialValue: selectedSeason,
                        decoration: const InputDecoration(
                          labelText: 'Recent-game scope',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('Latest available'),
                          ),
                          ...years.map(
                            (year) => DropdownMenuItem(
                              value: year,
                              child: Text(
                                year == currentSeason
                                    ? '$year · current'
                                    : '$year',
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => selectedSeason = v!),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: period,
                        decoration: const InputDecoration(
                          labelText: 'Game type',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'REG',
                            child: Text('Regular season'),
                          ),
                          DropdownMenuItem(
                            value: 'POST',
                            child: Text('Postseason'),
                          ),
                        ],
                        onChanged: (v) => setState(() => period = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('player-totals'),
                      label: const Text('Totals'),
                      selected: !averages,
                      onSelected: (_) => setState(() => averages = false),
                    ),
                    ChoiceChip(
                      key: const Key('player-averages'),
                      label: const Text('Per-game averages'),
                      selected: averages,
                      onSelected: (_) => setState(() => averages = true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in groups)
                      ChoiceChip(
                        label: Text(g.name),
                        selected: selectedGroup == g.name,
                        onSelected: (_) =>
                            setState(() => selectedGroup = g.name),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.insights, color: _mint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Last 3 games',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${selectedSeason == 0 ? 'Latest available' : selectedSeason} · ${period == 'REG' ? 'regular season' : 'postseason'} · ${recent.length} recorded ${recent.length == 1 ? 'appearance' : 'appearances'}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (recent.isEmpty)
                  const Text(
                    'No recorded games in this scope and game type. Choose another season or player.',
                  )
                else ...[
                  if (recent.length < 3)
                    Text(
                      'Only ${recent.length} recorded ${recent.length == 1 ? 'game is' : 'games are'} available; no empty games are added.',
                    ),
                  _statTiles(
                    PlayerStatWindow(recent),
                    group.metrics,
                    comparison: PlayerStatWindow(games),
                    comparisonLabel: selectedSeason == 0
                        ? 'available'
                        : 'season',
                  ),
                  const SizedBox(height: 12),
                  for (final game in recent) _gameCard(game, group.metrics),
                ],
                const SizedBox(height: 10),
                Text(
                  selectedSeason == 0
                      ? 'Latest available can cross season boundaries. Recent averages are compared with all available games for this player and game type, including these recent games. Differences describe past results and are not predictions.'
                      : 'Recent and season averages are per recorded game; the season includes these recent games. Differences describe past results and are not predictions.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This window counts recorded appearances, not NFL weeks. Byes and games without a player row are skipped; a missing row does not identify the reason for an absence. Check each game’s date for recency.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$currentSeason · current season',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Partial season through the available data snapshot.',
                  style: TextStyle(color: Colors.white70),
                ),
                _seasonSummary(
                  playerRows,
                  selected.playerId,
                  currentSeason,
                  group.metrics,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Previous 3 seasons',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth < 720
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 24) / 3;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final year in previousYears)
                    SizedBox(
                      width: width,
                      child: _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$year season',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            _seasonSummary(
                              playerRows,
                              selected.playerId,
                              year,
                              group.metrics,
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _card(
            ExpansionTile(
              key: PageStorageKey(
                'player-log-${selected.playerId}-$selectedSeason-$period',
              ),
              tilePadding: EdgeInsets.zero,
              title: Text(
                '${selectedSeason == 0 ? 'Available game log' : '$selectedSeason full game log'} (${games.length})',
              ),
              subtitle: const Text(
                'Newest first · historical teams and opponents',
              ),
              children: [
                if (games.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No recorded appearances for this selection.'),
                  ),
                for (final game in games) _gameCard(game, group.metrics),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            ExpansionTile(
              key: const PageStorageKey('player-data-coverage'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Data sources and coverage'),
              subtitle: Text(
                'Snapshot · latest recorded game ${_date(latestDate!)}',
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Source: ${dataset.metadata['source'] ?? 'nflverse player game statistics'}',
                      ),
                      if (dataset.metadata['sourceUrl'] != null)
                        SelectableText('${dataset.metadata['sourceUrl']}'),
                      Text(
                        'Retrieved: ${dataset.metadata['retrievedAt'] ?? 'not supplied'}',
                      ),
                      Text(
                        'Data cutoff: ${dataset.metadata['cutoff'] ?? _date(latestDate!)}',
                      ),
                      Text(
                        'License: ${dataset.metadata['license'] ?? 'See the bundled source attribution.'}',
                      ),
                      if (dataset.metadata['licenseUrl'] != null)
                        SelectableText('${dataset.metadata['licenseUrl']}'),
                      if (dataset.metadata['coverage'] != null)
                        Text('Coverage: ${dataset.metadata['coverage']}'),
                      if (dataset.metadata['changes'] != null)
                        Text(
                          'Changes to source: ${dataset.metadata['changes']}',
                        ),
                      const SizedBox(height: 10),
                      const Text(
                        'Historical statistics are a bundled retrospective snapshot, not a live feed. These are recorded box-score statistics, not betting forecasts. Player data availability varies by position and season.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A dash means a statistic is not recorded. Totals use recorded values only. Per-game averages divide by the number of games with that statistic; each tile shows its coverage. Recorded zeroes count as observations.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _seasonSummary(
    List<PlayerGame> rows,
    String id,
    int year,
    List<_Metric> metrics, {
    bool compact = false,
  }) {
    final games = playerGames(rows, id, season: year, seasonType: period);
    if (games.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'No recorded appearances. This may predate the player’s career or fall outside source coverage.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          '${games.length} recorded games · ${games.map((g) => g.team).toSet().join(', ')}',
        ),
        _statTiles(PlayerStatWindow(games), metrics, compact: compact),
      ],
    );
  }

  Widget _statTiles(
    PlayerStatWindow window,
    List<_Metric> metrics, {
    bool compact = false,
    PlayerStatWindow? comparison,
    String comparisonLabel = 'season',
  }) => metrics.isEmpty
      ? const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No individual statistics are recorded for this position in the available box scores.',
          ),
        )
      : Padding(
          padding: const EdgeInsets.only(top: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 660
                  ? 3
                  : constraints.maxWidth >= 360 && !compact
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _mint.withValues(alpha: .055),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _mint.withValues(alpha: .15),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metric.label,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _number(
                                averages
                                    ? window.average(metric.key)
                                    : window.total(metric.key),
                                average: averages,
                              ),
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w600,
                                color: _mint,
                              ),
                            ),
                            Text(
                              '${averages ? 'avg' : 'total'} · ${window.observed(metric.key)}/${window.gamesCount} games recorded',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                            if (comparison != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Recent avg ${_number(window.average(metric.key), average: true)} · $comparisonLabel avg ${_number(comparison.average(metric.key), average: true)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${comparisonLabel == 'season' ? 'Season' : 'Available'} coverage ${comparison.observed(metric.key)}/${comparison.gamesCount} games',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );

  Widget _gameCard(PlayerGame game, List<_Metric> metrics) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 5),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Week ${game.week} · ${game.team} vs ${game.opponent}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          _date(game.date),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final metric in metrics)
              Text('${metric.label}: ${_number(game.stats[metric.key])}'),
          ],
        ),
      ],
    ),
  );

  Widget _card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _number(num? value, {bool average = false}) => value == null
      ? '—'
      : average || value % 1 != 0
      ? value.toStringAsFixed(1)
      : value.toInt().toString();
}

class _Metric {
  const _Metric(this.key, this.label);
  final String key, label;
}

class _StatGroup {
  const _StatGroup(this.name, this.metrics);
  final String name;
  final List<_Metric> metrics;
}

const _passing = _StatGroup('Passing', [
  _Metric('passing_yards', 'Passing yards'),
  _Metric('passing_tds', 'Passing TDs'),
  _Metric('completions', 'Completions'),
  _Metric('attempts', 'Pass attempts'),
  _Metric('passing_interceptions', 'Interceptions thrown'),
  _Metric('sacks_suffered', 'Sacks taken'),
]);
const _rushing = _StatGroup('Rushing', [
  _Metric('rushing_yards', 'Rushing yards'),
  _Metric('carries', 'Carries'),
  _Metric('rushing_tds', 'Rushing TDs'),
  _Metric('rushing_fumbles_lost', 'Rushing fumbles lost'),
]);
const _receiving = _StatGroup('Receiving', [
  _Metric('receiving_yards', 'Receiving yards'),
  _Metric('receptions', 'Receptions'),
  _Metric('targets', 'Targets'),
  _Metric('receiving_tds', 'Receiving TDs'),
  _Metric('receiving_yards_after_catch', 'Yards after catch'),
  _Metric('receiving_fumbles_lost', 'Receiving fumbles lost'),
]);
const _kicking = _StatGroup('Kicking', [
  _Metric('fg_made', 'Field goals made'),
  _Metric('fg_att', 'Field goal attempts'),
  _Metric('pat_made', 'Extra points made'),
  _Metric('pat_att', 'Extra point attempts'),
]);
const _defense = _StatGroup('Defense', [
  _Metric('def_tackles_solo', 'Solo tackles'),
  _Metric('def_tackle_assists', 'Assisted tackles'),
  _Metric('def_sacks', 'Sacks'),
  _Metric('def_interceptions', 'Interceptions'),
  _Metric('def_fumbles_forced', 'Forced fumbles'),
  _Metric('def_pass_defended', 'Passes defended'),
  _Metric('def_tds', 'Defensive TDs'),
]);
const _punting = _StatGroup('Punting', [
  _Metric('pt_att', 'Punts'),
  _Metric('pt_yards', 'Punting yards'),
]);

List<_StatGroup> _groupsFor(String position, List<PlayerGame> history) {
  final preferred = switch (position) {
    'QB' => [_passing, _rushing, _receiving],
    'RB' || 'FB' => [_rushing, _receiving],
    'WR' || 'TE' => [_receiving, _rushing],
    'K' => [_kicking],
    'P' => [_punting],
    'C' ||
    'G' ||
    'T' ||
    'OL' ||
    'OT' ||
    'OG' ||
    'LS' => [const _StatGroup('Available statistics', [])],
    _ => [_defense, _passing, _rushing, _receiving, _kicking],
  };
  final available = preferred
      .where(
        (group) => history.any(
          (g) => group.metrics.any((m) => g.stats[m.key] != null),
        ),
      )
      .toList();
  return available.isEmpty ? [preferred.first] : available;
}
