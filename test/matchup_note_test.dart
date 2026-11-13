import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/prop_pricing.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/matchup.dart';

void main() {
  DefenseAllow defense(int rank) => DefenseAllow(
    team: 'Cincinnati Bengals',
    rank: rank,
    teams: 32,
    perGame: 20,
    games: 8,
    recent: const [18, 22],
    statLabel: 'QB',
  );

  test(
    'a 32-team rank is tough through 10, even through 22, and soft from 23',
    () {
      expect(defenseBand(1, 32), DefenseBand.tough);
      expect(defenseBand(10, 32), DefenseBand.tough);
      expect(defenseBand(11, 32), DefenseBand.even);
      expect(defenseBand(22, 32), DefenseBand.even);
      expect(defenseBand(23, 32), DefenseBand.soft);
      expect(defenseBand(32, 32), DefenseBand.soft);
    },
  );

  test('the note follows the rank, then the side of the bet', () {
    final softUnder = matchupNote(
      defense: defense(29),
      position: 'QB',
      side: LineSide.under,
    );
    expect(
      softUnder!.text,
      'Bengals 29th vs QB · a soft front, which works against the under',
    );
    expect(softUnder.text, isNot(contains('strong front')));
    expect(softUnder.tone, MatchupTone.tough);

    final softOver = matchupNote(
      defense: DefenseAllow(
        team: 'Dallas Cowboys',
        rank: 30,
        teams: 32,
        perGame: 20,
        games: 8,
        recent: const [18, 22],
        statLabel: 'RB',
      ),
      position: 'RB',
      side: LineSide.over,
    );
    expect(softOver!.text, 'Cowboys 30th vs RB · a soft front for the over');
    expect(softOver.tone, MatchupTone.favorable);

    final toughOver = matchupNote(
      defense: defense(5),
      position: 'WR',
      side: LineSide.over,
    );
    expect(toughOver!.text, contains('a tough front for the over'));
    expect(toughOver.tone, MatchupTone.tough);

    final toughUnder = matchupNote(
      defense: defense(5),
      position: 'WR',
      side: LineSide.under,
    );
    expect(toughUnder!.text, contains('which helps the under'));
    expect(toughUnder.tone, MatchupTone.favorable);

    final even = matchupNote(
      defense: defense(16),
      position: 'QB',
      side: LineSide.under,
    );
    expect(even!.text, contains('an even matchup'));
    expect(even.tone, MatchupTone.even);
  });
}
