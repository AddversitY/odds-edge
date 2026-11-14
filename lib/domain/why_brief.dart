import 'coach_board.dart';
import 'hit_rate.dart';
import 'injury_report.dart';
import 'matchup.dart';
import 'parlay_value.dart';
import 'prop_history.dart';
import 'value_check.dart';

enum WhyFactKind { price, defense, injuries, script, sharp, leg, fit }

class WhyFact {
  const WhyFact({required this.kind, required this.label, required this.text});

  final WhyFactKind kind;
  final String label, text;
}

class AlternativeNote {
  const AlternativeNote({required this.title, required this.body});

  final String title, body;
}

/// What the Why layer shows. The long numbers stay in The math.
class WhyBrief {
  const WhyBrief({
    required this.line,
    this.facts = const [],
    this.bars = const [],
    this.lineValue,
    this.seasonAverage,
    this.hitLabel,
    this.seasonLabel,
    this.alternative,
  });

  final String line;
  final List<WhyFact> facts;

  /// Oldest to newest. Empty when this is not a player prop.
  final List<HitSample> bars;
  final double? lineValue, seasonAverage;
  final String? hitLabel, seasonLabel;
  final AlternativeNote? alternative;

  bool get hasChart => bars.isNotEmpty || hitLabel != null;
}

/// One sentence. The counts and the cents stay in the rows and in The math.
String verdictLine(ValueVerdict verdict, {bool modelUnproven = false}) {
  final caution = modelUnproven
      ? ', using Coach\'s Line, which lost money in its past test'
      : '';
  if (verdict.ourChance == null && verdict.breakEven == null) {
    return 'Pass. There is no open price to judge$caution.';
  }
  if (verdict.ourChance == null) {
    return 'Pass. There isn\'t a chance on file, so this is not called a bet$caution.';
  }
  final profit = verdict.expectedValue;
  if (profit != null && profit.abs() < 0.0005) {
    return 'Pass. At our chance, this price only breaks even$caution.';
  }
  return switch (verdict.word) {
    ValueWord.bet =>
      'Review. Our chance is high enough that this price expects to make money$caution.',
    ValueWord.lean =>
      'Thin margin. The price is only a little better than fair$caution.',
    ValueWord.skip =>
      profit == null
          ? 'Pass. The price could not be compared with our chance$caution.'
          : verdict.overpriced
          ? 'Pass. The price is short of our chance$caution.'
          : 'Pass. At our chance, this price does not pay enough$caution.',
  };
}

String priceText(ValueVerdict verdict) {
  final ours = verdict.ourChance == null
      ? 'not enough to say'
      : percentLabel(verdict.ourChance!);
  final fair = verdict.fairChance == null
      ? 'not posted'
      : percentLabel(verdict.fairChance!);
  return 'Ours $ours · Fair $fair';
}

String defenseText(DefenseAllow? defense) {
  if (defense == null) return 'No rank in the stored games.';
  final recent = defense.recent.isEmpty
      ? ''
      : ' · recently ${defense.recent.map((value) => value.toStringAsFixed(0)).join(', ')}';
  return 'Rank ${defense.rank} of ${defense.teams} · ${defense.perGame.toStringAsFixed(0)} a game$recent';
}

String storedInjuryText(List<RelevantInjury> injuries) {
  if (injuries.isEmpty) return 'Nobody listed who changes this.';
  return injuries
      .take(3)
      .map(
        (item) =>
            '${item.injury.player} ${item.injury.position} ${item.injury.status}',
      )
      .join(' · ');
}

String liveInjuryText({
  required InjuryReport? report,
  required String market,
  required String playerName,
  String? playerTeam,
  String? opponent,
  List<RelevantInjury> stored = const [],
}) {
  final entries = report?.entries;
  if (entries == null || entries.isEmpty) return storedInjuryText(stored);
  final hits = [
    for (final entry in entries)
      if (injuryAffectsProp(
        entry,
        market: market,
        playerName: playerName,
        playerTeam: playerTeam,
        opponent: opponent,
      ))
        entry,
  ];
  if (hits.isEmpty) return 'Nobody listed who changes this.';
  final names = hits
      .take(3)
      .map((entry) => '${entry.player} ${entry.position} ${entry.status}')
      .join(' · ');
  final more = hits.length > 3 ? ' · +${hits.length - 3} more' : '';
  return '$names$more · ${hits.first.sourceLabel}';
}

String gameInjuryText(InjuryReport? report, String away, String home) {
  final entries = report?.entries;
  if (entries == null || entries.isEmpty) {
    return 'No injury report is loaded for this game.';
  }
  final hits = [
    for (final entry in entries)
      if ((sameClub(entry.team, away) || sameClub(entry.team, home)) &&
          injuryImpact(entry.position, entry.status) != null)
        entry,
  ];
  if (hits.isEmpty) return 'Nobody listed who changes this game.';
  final names = hits
      .take(3)
      .map((entry) => '${entry.player} ${entry.position} ${entry.status}')
      .join(' · ');
  final more = hits.length > 3 ? ' · +${hits.length - 3} more' : '';
  return '$names$more · ${hits.first.sourceLabel}';
}

String sharpText(double? pinnacle) => pinnacle == null
    ? 'Pinnacle is not in this snapshot.'
    : 'Pinnacle ${percentLabel(pinnacle)} after the fee.';

AlternativeNote? alternativeNote(String? text) {
  if (text == null) return null;
  final body = text.trim();
  if (body.isEmpty) return null;
  final title = body.startsWith('No better')
      ? 'No better price'
      : body.startsWith('The same line')
      ? 'Better price'
      : body.startsWith('A different line')
      ? 'A different line'
      : body.startsWith('A different leg')
      ? 'A different leg'
      : 'Another option';
  return AlternativeNote(title: title, body: body);
}

WhyBrief buildPropBrief({
  required ValueVerdict verdict,
  required double line,
  required LineSide side,
  required String market,
  required String player,
  PropWindows? windows,
  MatchupCard? matchup,
  String? teamName,
  double? teamSpread,
  double? total,
  InjuryReport? injuries,
  String? playerTeam,
  String? opponent,
  bool modelUnproven = false,
}) {
  final sideName = side == LineSide.over ? 'Over' : 'Under';
  final recent = _preferredRecent(windows);
  final season = windows?.season;
  final chartSource =
      _withGames(windows?.last10) ??
      _withGames(windows?.last5) ??
      _withGames(season);
  return WhyBrief(
    line: verdictLine(verdict, modelUnproven: modelUnproven),
    bars: _bars(chartSource),
    lineValue: line,
    seasonAverage: _average(season),
    hitLabel: _countLabel(sideName, recent, seasonWindow: false),
    seasonLabel: _countLabel(sideName, season, seasonWindow: true),
    facts: [
      WhyFact(
        kind: WhyFactKind.price,
        label: 'Price',
        text: priceText(verdict),
      ),
      WhyFact(
        kind: WhyFactKind.defense,
        label: 'Defense',
        text: defenseText(matchup?.defense),
      ),
      WhyFact(
        kind: WhyFactKind.injuries,
        label: 'Injuries',
        text: liveInjuryText(
          report: injuries,
          market: market,
          playerName: player,
          playerTeam: playerTeam,
          opponent: opponent,
          stored: matchup?.injuries ?? const [],
        ),
      ),
      WhyFact(
        kind: WhyFactKind.script,
        label: 'Game script',
        text: scriptBrief(
          teamName: teamName == null || teamName.isEmpty
              ? 'This team'
              : teamName,
          teamSpread: teamSpread,
          total: total,
          market: market,
        ),
      ),
    ],
    alternative: alternativeNote(verdict.alternative),
  );
}

WhyBrief buildSideBrief({
  required ValueVerdict verdict,
  required String injuryText,
  required String scriptText,
  required String sharpLine,
  bool modelUnproven = false,
}) {
  return WhyBrief(
    line: verdictLine(verdict, modelUnproven: modelUnproven),
    facts: [
      WhyFact(
        kind: WhyFactKind.price,
        label: 'Price',
        text: priceText(verdict),
      ),
      WhyFact(kind: WhyFactKind.injuries, label: 'Injuries', text: injuryText),
      WhyFact(kind: WhyFactKind.script, label: 'Game script', text: scriptText),
      WhyFact(kind: WhyFactKind.sharp, label: 'Sharp', text: sharpLine),
    ],
    alternative: alternativeNote(verdict.alternative),
  );
}

String ticketVerdictLine(TicketValue ticket) {
  TicketLegValue? skipped;
  for (final leg in ticket.legs) {
    if (leg.verdict.word == ValueWord.skip) {
      skipped = leg;
      break;
    }
  }
  final estimate = ticket.payoutEstimated
      ? ', and the same-game payout is an estimate'
      : '';
  if (skipped != null) {
    return 'Pass. ${skipped.input.label} is not a price to build on, so the ticket is a skip$estimate.';
  }
  return switch (ticket.word) {
    ValueWord.bet =>
      'Review. The ticket expects to make money if our chances are right$estimate.',
    ValueWord.lean =>
      'Thin margin. The ticket is only a little better than fair$estimate.',
    ValueWord.skip =>
      'Pass. At our chances, this ticket does not pay enough$estimate.',
  };
}

String legVerdictText(TicketLegValue leg) {
  final verdict = leg.verdict;
  final ours = verdict.ourChance == null
      ? 'No chance on file'
      : 'Ours ${percentLabel(verdict.ourChance!)}';
  final fair = verdict.fairChance == null
      ? 'Fair not posted'
      : 'Fair ${percentLabel(verdict.fairChance!)}';
  return '${verdict.wordLabel} · $ours · $fair';
}

String legsFitNote(TicketValue ticket) {
  if (ticket.sameGame) {
    if (ticket.joint != null && ticket.independent != null) {
      return 'These legs share a game, so they move together. '
          'Together the chance is ${percentLabel(ticket.joint!)}. '
          'If the legs were separate games it would be ${percentLabel(ticket.independent!)}.';
    }
    return 'These legs share a game, so they move together. The chances are not just multiplied.';
  }
  if (ticket.joint != null) {
    return 'The games are different, so the chances multiply to ${percentLabel(ticket.joint!)}.';
  }
  return 'The games are different, so the chances would multiply. A missing chance leaves that blank.';
}

WhyBrief buildTicketBrief(TicketValue ticket) {
  return WhyBrief(
    line: ticketVerdictLine(ticket),
    facts: [
      for (final leg in ticket.legs)
        WhyFact(
          kind: WhyFactKind.leg,
          label: leg.input.label,
          text: legVerdictText(leg),
        ),
      WhyFact(
        kind: WhyFactKind.fit,
        label: 'How the legs fit together',
        text: legsFitNote(ticket),
      ),
    ],
  );
}

HitRate? _withGames(HitRate? rate) {
  if (rate == null || rate.samples.every((sample) => sample.value == null)) {
    return null;
  }
  return rate;
}

HitRate? _preferredRecent(PropWindows? windows) {
  final last5 = windows?.last5;
  if (last5 != null && last5.observed > 0) return last5;
  final last10 = windows?.last10;
  if (last10 != null && last10.observed > 0) return last10;
  return null;
}

String? _countLabel(String side, HitRate? rate, {required bool seasonWindow}) {
  if (rate == null || rate.observed == 0) {
    return seasonWindow ? null : 'No recorded games in this window.';
  }
  if (seasonWindow) return 'Season: $side in ${rate.hits} of ${rate.observed}';
  return '$side in ${rate.hits} of last ${rate.observed}';
}

List<HitSample> _bars(HitRate? rate) {
  if (rate == null) return const [];
  final withValue = [
    for (final sample in rate.samples)
      if (sample.value != null) sample,
  ];
  if (withValue.isEmpty) return const [];
  final newest = withValue.length > 10 ? withValue.sublist(0, 10) : withValue;
  return newest.reversed.toList();
}

double? _average(HitRate? rate) {
  if (rate == null) return null;
  final values = [
    for (final sample in rate.samples)
      if (sample.value != null) sample.value!.toDouble(),
  ];
  if (values.isEmpty) return null;
  return values.reduce((total, value) => total + value) / values.length;
}
