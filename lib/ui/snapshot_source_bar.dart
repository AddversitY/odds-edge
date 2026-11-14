import 'package:flutter/material.dart';

import '../data/published_snapshot.dart';
import '../domain/eastern.dart';
import '../theme/edge_theme.dart';

class SnapshotSourceBar extends StatelessWidget {
  const SnapshotSourceBar({
    super.key,
    required this.published,
    required this.loading,
    required this.snapshot,
    required this.error,
    required this.now,
    required this.onSwitch,
    required this.onRefresh,
  });
  final bool published, loading;
  final PublishedSnapshot? snapshot;
  final String? error;
  final DateTime now;
  final VoidCallback onSwitch, onRefresh;

  @override
  Widget build(BuildContext context) {
    final stale = snapshot?.stale(now) ?? false;
    final status = !published
        ? 'Invented prices and matchups'
        : loading
        ? 'Updating schedule…'
        : error != null
        ? 'Update failed${snapshot == null
              ? ''
              : stale
              ? ' · outdated schedule'
              : ' · saved schedule'}'
        : snapshot == null
        ? 'Schedule unavailable'
        : stale
        ? 'Schedule snapshot is outdated'
        : 'Updated ${formatEastern(snapshot!.scheduleAt)}';
    final details = Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            published ? 'NFL schedule · prices unavailable' : 'Sample props',
            style: EdgeType.label.copyWith(color: EdgeColors.accent),
          ),
          Text(
            status,
            style: EdgeType.label.copyWith(
              fontSize: 11,
              color: error != null || stale
                  ? EdgeColors.warn
                  : EdgeColors.textSecondary,
            ),
          ),
        ],
      ),
    );
    final controls = <Widget>[
      TextButton(
        key: const Key('switch-snapshot-mode'),
        onPressed: onSwitch,
        child: Text(published ? 'Sample props' : 'Actual games'),
      ),
      if (published && error != null)
        IconButton(
          tooltip: 'Reload published schedule',
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      IconButton(
        tooltip: 'About this data',
        icon: const Icon(Icons.info_outline, size: 20),
        onPressed: () => _showDetails(context),
      ),
    ];
    return Material(
      color: EdgeColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600 &&
                MediaQuery.textScalerOf(context).scale(1) > 1.2) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  Wrap(alignment: WrapAlignment.end, children: controls),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                ...controls,
              ],
            );
          },
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About this preview', style: EdgeType.title),
                const SizedBox(height: 12),
                const Text(
                  'Actual games use a published NFL schedule snapshot. Sportsbook prices are not connected. The separate sample mode contains invented matchups and prices for exploring the interface.',
                  style: EdgeType.body,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Historical player box scores and model reports have their own cutoffs. They are not live roster or injury confirmations. The simulator is experimental and has no demonstrated betting edge.',
                  style: EdgeType.body,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Schedule: nflverse · CC BY 4.0. Changes may occur after the snapshot. Scheduled refreshes run twice daily; no continuous odds feed.',
                  style: EdgeType.label,
                ),
                if (snapshot != null)
                  Text(
                    'Schedule fetched ${formatEastern(snapshot!.scheduleAt, year: true)}',
                    style: EdgeType.label,
                  ),
                const SelectableText(
                  'https://github.com/nflverse/nflverse-data\nhttps://creativecommons.org/licenses/by/4.0/',
                  style: EdgeType.label,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
