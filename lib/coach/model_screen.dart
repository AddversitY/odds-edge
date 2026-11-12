import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../theme/reveal.dart';
import 'coach_widgets.dart';

class ModelScreen extends StatelessWidget {
  const ModelScreen({
    super.key,
    required this.model,
    required this.settings,
    required this.onPoints,
    required this.onMinExpectedValue,
  });

  final CoachModel? model;
  final EdgeSettings settings;
  final ValueChanged<double> onPoints;
  final ValueChanged<double> onMinExpectedValue;

  @override
  Widget build(BuildContext context) {
    final loaded = model;
    if (loaded == null) {
      return const CoachCard(
        child: Text(
          "Coach's model could not be read. The games stay up, and no number is filled in for it.",
          style: TextStyle(height: 1.4),
        ),
      );
    }
    final report = loaded.backtest;
    final verdict = report.hasEdge ? 'Past edge' : 'No edge';
    final hit = report.hitRate == null ? '—' : percentLabel(report.hitRate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("COACH'S MODEL"),
        const SizedBox(height: 12),
        Reveal(
          verdict: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                verdict,
                style: EdgeType.display.copyWith(
                  color: report.hasEdge
                      ? EdgeColors.good
                      : EdgeColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(hit, style: EdgeType.title),
              Text('Hit rate on the past test', style: EdgeType.label),
              const SizedBox(height: 12),
              Text(report.plainEnglish, style: EdgeType.body),
            ],
          ),
          reasons: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Each team gets a strength number from how the offense and the defense have played. The stat is EPA per play, from nflverse play-by-play: about how many points a play added, compared with an average play. Newer games count more. A game from about six weeks ago counts half as much. A short sample is pulled back toward average so one blowout cannot rewrite a team.',
                style: EdgeType.body,
              ),
              SizedBox(height: 12),
              Text(
                'The chance a team covers, and the chance the over hits, come from a small model. It looks at both teams, recent games, rest, and a count of players listed Out. It then compares our number with the line on the screen. The injury report is not the final inactive list. Weather is not in the model. It is not a tip.',
                style: EdgeType.body,
              ),
            ],
          ),
          math: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Our spread is the home strength minus the away strength, plus home field. Home field was fit from the same past games'
                '${loaded.homeFieldAdvantage.isFinite ? ' and came out at ${loaded.homeFieldAdvantage.toStringAsFixed(1)} points' : ''}. '
                'The ranking list is before home field. Home field is added only on a game.',
                style: EdgeType.body,
              ),
              const SizedBox(height: 12),
              Text(
                report.method,
                style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Stat('Seasons', report.seasonSpan),
                  _Stat('Games', '${report.games}'),
                  _Stat(
                    'Profit at -110',
                    report.roi == null ? '—' : signedPercent(report.roi!),
                  ),
                  _Stat(
                    'Closer than the close',
                    report.clvBeatRate == null
                        ? '—'
                        : percentLabel(report.clvBeatRate!),
                  ),
                ],
              ),
              if (report.favoriteHitRate != null ||
                  report.homeHitRate != null) ...[
                const SizedBox(height: 8),
                Text(
                  'For a baseline on the same games: the favorite covered '
                  '${report.favoriteHitRate == null ? 'an unknown share' : percentLabel(report.favoriteHitRate!)} '
                  'and the home team covered '
                  '${report.homeHitRate == null ? 'an unknown share' : percentLabel(report.homeHitRate!)}.',
                  style: EdgeType.body.copyWith(
                    color: EdgeColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Team strength', style: EdgeType.title),
        const SizedBox(height: 6),
        Text(
          'Points versus an average team, through ${loaded.asOf ?? 'the last completed game'}. Higher is better. Tap a team for offense and defense.',
          style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
        ),
        const SizedBox(height: 8),
        CoachCard(
          child: Column(
            children: [for (final team in loaded.teams) _TeamRow(team: team)],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'When the number differs from the books',
          style: EdgeType.title,
        ),
        const SizedBox(height: 8),
        Text(
          'Mark the game when our number and the books differ by at least ${settings.spreadPoints.toStringAsFixed(1)} points. The mark is a comparison, not a pick.',
          style: EdgeType.body,
        ),
        Slider(
          value: settings.spreadPoints.clamp(1, 7).toDouble(),
          min: 1,
          max: 7,
          divisions: 12,
          label: settings.spreadPoints.toStringAsFixed(1),
          onChanged: onPoints,
        ),
        Text(
          'Or when the best price would make at least ${(settings.minExpectedValue * 100).toStringAsFixed(0)}% profit per dollar if our chance were right.',
          style: EdgeType.body,
        ),
        Slider(
          value: settings.minExpectedValue.clamp(0, 0.1).toDouble(),
          min: 0,
          max: 0.1,
          divisions: 10,
          label: '${(settings.minExpectedValue * 100).toStringAsFixed(0)}%',
          onChanged: onMinExpectedValue,
        ),
        const Text(
          'The past results above used a 2.5 point gap. Moving this slider only changes the badge on the games. It does not rewrite the past test.',
          style: EdgeType.label,
        ),
        const SizedBox(height: 16),
        const ToolNote(
          'Sharp signals and models do not guarantee outcomes. A number that disagreed with the books last season can lose this week. This is research on past games, not a recommendation to bet.',
        ),
        const SizedBox(height: 8),
        const ToolNote(responsibleGamblingNote),
        const SizedBox(height: 12),
        Text(
          'Source: ${loaded.source.name}. ${loaded.source.license}. ${loaded.source.changes}',
          style: EdgeType.label,
        ),
        if (loaded.source.url.isNotEmpty)
          SelectableText(loaded.source.url, style: EdgeType.label),
        if (loaded.source.licenseUrl.isNotEmpty)
          SelectableText(loaded.source.licenseUrl, style: EdgeType.label),
        const Text(
          'The license text shipped with the app is assets/NFLVERSE-LICENSE.md. Odds Edge is not affiliated with nflverse.',
          style: EdgeType.label,
        ),
      ],
    );
  }
}

class _TeamRow extends StatefulWidget {
  const _TeamRow({required this.team});
  final TeamStrength team;

  @override
  State<_TeamRow> createState() => _TeamRowState();
}

class _TeamRowState extends State<_TeamRow> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    return InkWell(
      onTap: () => setState(() => open = !open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text('${team.rank}', style: EdgeType.label),
                ),
                Expanded(
                  child: Text(
                    team.name,
                    style: EdgeType.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  signedNumber(team.strengthPoints),
                  style: EdgeType.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (open) ...[
              const SizedBox(height: 6),
              Text(
                'Offense ${signedNumber(team.offensePoints)} · Defense ${signedNumber(team.defensePoints)}. A positive defense number means the defense has been giving up less than average.',
                style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: 148,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: EdgeColors.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: EdgeColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: EdgeType.label),
        const SizedBox(height: 4),
        Text(value, style: EdgeType.body.copyWith(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
