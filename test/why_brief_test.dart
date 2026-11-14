import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/why_view.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/parlay_value.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_history.dart';
import 'package:odds_edge/domain/value_check.dart';
import 'package:odds_edge/domain/why_brief.dart';
import 'package:odds_edge/theme/edge_theme.dart';

void main() {
  PlayerGame game(int week, num yards) => PlayerGame(
    playerId: 'allen',
    name: 'Josh Allen',
    position: 'QB',
    team: 'BUF',
    opponent: 'KC',
    season: 2026,
    week: week,
    date: DateTime.utc(2026, 9, week),
    seasonType: 'REG',
    stats: {'passing_yards': yards},
  );

  HitRate rate(String label, List<int> weeks, List<num> yards) => hitRate(
    label: label,
    games: [for (var i = 0; i < weeks.length; i++) game(weeks[i], yards[i])],
    metric: 'passing_yards',
    line: 249.5,
    side: LineSide.over,
  );

  const verdict = ValueVerdict(
    word: ValueWord.skip,
    why: 'A long paragraph that used to be the whole reason.',
    math: 'Our chance is 40%. The price needs 52% to break even.',
    ourChance: 0.40,
    fairChance: 0.52,
    breakEven: 0.52,
    expectedValue: -0.08,
    alternative: 'A different line, 199.5, is the better price.',
    overpriced: true,
  );

  test('a prop Why is a sentence, a chart, four rows, and a card', () {
    final brief = buildPropBrief(
      verdict: verdict,
      line: 249.5,
      side: LineSide.over,
      market: 'player_pass_yds',
      player: 'Josh Allen',
      teamName: 'Buffalo Bills',
      teamSpread: -3.5,
      total: 47.5,
      windows: PropWindows(
        note: 'Recorded games.',
        last5: rate('last 5', [5, 4, 3, 2, 1], [260, 260, 260, 260, 100]),
        last10: rate(
          'last 10',
          [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
          [260, 260, 100, 260, 260, 260, 260, 260, 260, 100],
        ),
        season: rate('season', [2, 1], [260, 260]),
      ),
    );

    expect(brief.line, startsWith('Pass. The price is short'));
    expect(brief.line, isNot(contains('long paragraph')));
    expect(brief.hitLabel, 'Over in 4 of last 5');
    expect(brief.seasonLabel, 'Season: Over in 2 of 2');
    expect(brief.bars.map((sample) => sample.game.week), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
    expect(brief.facts.map((fact) => fact.label), [
      'Price',
      'Defense',
      'Injuries',
      'Game script',
    ]);
    expect(brief.facts.first.text, contains('Ours 40.0%'));
    expect(brief.facts[1].text, 'No rank in the stored games.');
    expect(brief.facts[2].text, 'Nobody listed who changes this.');
    expect(brief.facts[3].text, contains('Favored by 3.5'));
    expect(brief.alternative?.title, 'A different line');
    expect(brief.alternative?.body, contains('199.5'));
  });

  test('a ticket Why is one row per leg plus how they fit', () {
    final leg = TicketLegValue(
      input: TicketLegInput(
        label: 'Josh Allen over 249.5',
        eventId: 'buf-kc',
        market: 'player_pass_yds',
        outcome: 'Over',
        decimal: 1.91,
        ourChance: 0.40,
      ),
      verdict: verdict,
    );
    final ticket = TicketValue(
      word: ValueWord.skip,
      why: 'The old paragraph.',
      math: 'The ticket math.',
      legs: [leg, leg],
      payoutDecimal: 3.6,
      payoutEstimated: true,
      sameGame: true,
      joint: 0.22,
      independent: 0.16,
    );
    final brief = buildTicketBrief(ticket);

    expect(brief.line, startsWith('Pass.'));
    expect(brief.line, contains('estimate'));
    expect(brief.facts, hasLength(3));
    expect(brief.facts[0].label, 'Josh Allen over 249.5');
    expect(brief.facts[0].text, contains('Pass'));
    expect(brief.facts[0].text, contains('Ours 40.0%'));
    expect(brief.facts.last.label, 'How the legs fit together');
    expect(brief.facts.last.text, contains('move together'));
    expect(brief.facts.last.text, contains('22.0%'));
    expect(brief.bars, isEmpty);
  });

  testWidgets('the recent-game bars have a height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: WhyBriefView(
            brief: WhyBrief(
              line: 'Pass. The price is short of our chance.',
              bars: [
                HitSample(game: game(1, 100), value: 100, outcome: 'miss'),
                HitSample(game: game(2, 260), value: 260, outcome: 'hit'),
              ],
              lineValue: 249.5,
              seasonAverage: 180,
              hitLabel: 'Over in 1 of last 2',
            ),
          ),
        ),
      ),
    );
    final bar = tester.getSize(find.byKey(const Key('season-bar')));
    expect(bar.height, greaterThan(20));
    expect(bar.width, greaterThan(4));
  });

  test('separate games say the chances multiply', () {
    final ticket = TicketValue(
      word: ValueWord.lean,
      why: 'old',
      math: 'math',
      legs: const [],
      payoutDecimal: 2,
      payoutEstimated: false,
      sameGame: false,
      joint: 0.31,
    );
    expect(legsFitNote(ticket), contains('multiply'));
    expect(ticketVerdictLine(ticket), startsWith('Thin margin.'));
  });
}
