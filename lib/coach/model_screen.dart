import 'package:flutter/material.dart';

import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../explained_number.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("COACH'S MODEL"),
        const SizedBox(height: 8),
        const Text(
          'A strength number for each NFL team, then a simple chance the favorite covers and the over hits. It is built from past seasons. It is not a tip.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 12),
        const Text('How it works', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 6),
        const Text(
          'Each team gets a strength number from how the offense and the defense have played. The stat is EPA per play, from nflverse play-by-play: about how many points a play added, compared with an average play. Newer games count more. A game from about six weeks ago counts half as much. A short sample is pulled back toward average so one blowout cannot rewrite a team.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 8),
        Text(
          'Our spread is the home strength minus the away strength, plus home field. Home field was fit from the same past games'
          '${loaded.homeFieldAdvantage.isFinite ? ' and came out at ${loaded.homeFieldAdvantage.toStringAsFixed(1)} points' : ''}. '
          'It is not a number typed in to make the results look better. The ranking table below is before home field. Home field is added only on a game.',
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 8),
        const Text(
          'The chance a team covers, and the chance the over hits, come from a two-outcome model called logistic regression. It is intentionally small. It looks at both teams: offensive strength, defensive strength, the last few games, days of rest, how often plays succeed, how often a play goes 20 yards or more, how often the ball is given away, and a count of players listed Out. It then compares our number with the line on the screen. Injuries are only that count, from the free nflverse injury report. The report is not the final inactive list, and a missing week is stored as zero. It does not know which stars are out.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 16),
        const Text('Team strength', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          'Points versus an average team on a neutral field, through ${loaded.asOf ?? 'the last completed game'}. Higher is better. Offense and defense are split the same way. A positive defense number means the defense has been giving up less than average.',
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        const SizedBox(height: 8),
        CoachCard(
          child: Column(
            children: [
              const Row(
                children: [
                  SizedBox(width: 28, child: Text('#', style: TextStyle(color: Colors.white54))),
                  Expanded(child: Text('Team', style: TextStyle(color: Colors.white54))),
                  SizedBox(width: 52, child: Text('Str', textAlign: TextAlign.right, style: TextStyle(color: Colors.white54))),
                  SizedBox(width: 52, child: Text('Off', textAlign: TextAlign.right, style: TextStyle(color: Colors.white54))),
                  SizedBox(width: 52, child: Text('Def', textAlign: TextAlign.right, style: TextStyle(color: Colors.white54))),
                ],
              ),
              const SizedBox(height: 6),
              for (final team in loaded.teams)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(width: 28, child: Text('${team.rank}')),
                      Expanded(child: Text(team.name, overflow: TextOverflow.ellipsis)),
                      SizedBox(
                        width: 52,
                        child: Text(
                          signedNumber(team.strengthPoints),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(signedNumber(team.offensePoints), textAlign: TextAlign.right),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(signedNumber(team.defensePoints), textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('When to show an Edge', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          'Show the badge when our number and the books differ by at least ${settings.spreadPoints.toStringAsFixed(1)} points.',
          style: const TextStyle(height: 1.35),
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
          style: const TextStyle(height: 1.35),
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
          'The past results below used a 2.5 point gap. Moving this slider only changes the badge on the games. It does not rewrite the past test.',
          style: TextStyle(color: Colors.white60, height: 1.35),
        ),
        const SizedBox(height: 16),
        const Text('How it did on past seasons', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 4),
        Text(report.method, style: const TextStyle(color: Colors.white70, height: 1.35)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat('Seasons', report.seasonSpan),
            _Stat('Games', '${report.games}'),
            _Stat(
              'Hit rate',
              report.hitRate == null ? '—' : percentLabel(report.hitRate!),
            ),
            _Stat('Profit at -110', report.roi == null ? '—' : signedPercent(report.roi!)),
            _Stat(
              'Closer than the close',
              report.clvBeatRate == null ? '—' : percentLabel(report.clvBeatRate!),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(report.plainEnglish, style: const TextStyle(height: 1.4)),
        if (report.favoriteHitRate != null || report.homeHitRate != null) ...[
          const SizedBox(height: 8),
          Text(
            'For a baseline on the same games: the favorite covered '
            '${report.favoriteHitRate == null ? 'an unknown share' : percentLabel(report.favoriteHitRate!)} '
            'and the home team covered '
            '${report.homeHitRate == null ? 'an unknown share' : percentLabel(report.homeHitRate!)}.',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          report.hasEdge
              ? 'The past test beat a coin-flip at the usual -110 price by enough that it is worth saying out loud. It can still lose.'
              : 'The past test does not show an edge. Read the numbers above as the result, not as a reason to bet.',
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
        ),
        const SizedBox(height: 12),
        const ToolNote(
          'Sharp signals and models do not guarantee outcomes. A number that disagreed with the books last season can lose this week. This is research on past games, not a recommendation to bet.',
        ),
        const SizedBox(height: 8),
        const ToolNote(responsibleGamblingNote),
        const SizedBox(height: 12),
        Text(
          'Source: ${loaded.source.name}. ${loaded.source.license}. ${loaded.source.changes}',
          style: const TextStyle(color: Colors.white60, height: 1.4),
        ),
        if (loaded.source.url.isNotEmpty)
          SelectableText(
            loaded.source.url,
            style: const TextStyle(color: Colors.white60),
          ),
        if (loaded.source.licenseUrl.isNotEmpty)
          SelectableText(
            loaded.source.licenseUrl,
            style: const TextStyle(color: Colors.white60),
          ),
        const Text(
          'The license text shipped with the app is assets/NFLVERSE-LICENSE.md. Odds Edge is not affiliated with nflverse.',
          style: TextStyle(color: Colors.white60, height: 1.4),
        ),
      ],
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
      color: const Color(0xFF121A24),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF242E3C)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
