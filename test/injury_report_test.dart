import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/injury_report.dart';
import 'package:odds_edge/domain/matchup.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 18);

  InjuryEntry player({
    required String name,
    required String team,
    required String position,
    required String status,
    String sourceId = 'espn',
    String sourceLabel = 'ESPN, unofficial',
    DateTime? updatedAt,
  }) => InjuryEntry(
    player: name,
    team: team,
    position: position,
    status: status,
    sourceId: sourceId,
    sourceLabel: sourceLabel,
    official: sourceId == 'nfl',
    fetchedAt: now,
    updatedAt: updatedAt,
  );

  test('a receiver who is out lowers passing yards', () {
    expect(injuryImpact('WR', 'Out')!.line, 'WR out: lowers QB passing yards.');
    expect(
      injuryImpact('wr', 'Questionable')!.line,
      'WR questionable: may lower QB passing yards if he sits.',
    );
    expect(injuryImpact('K', 'Out')!.markets, isEmpty);
    expect(injuryImpact('CB', 'Out')!.line, contains('opponent receiving'));
    expect(injuryImpact('OL', 'Doubtful')!.line, contains('rushing'));
    expect(normalizeInjuryStatus('Active'), isNull);
    expect(normalizeInjuryStatus('IR'), 'Injured Reserve');
  });

  test('ESPN keeps listed players and drops Active', () {
    final entries = parseEspnInjuries({
      'injuries': [
        {
          'displayName': 'Buffalo Bills',
          'injuries': [
            {
              'status': 'Out',
              'date': '2026-11-12T17:00:00Z',
              'athlete': {
                'displayName': 'Star Receiver',
                'position': {'abbreviation': 'WR'},
                'team': {'abbreviation': 'BUF'},
              },
              'details': {'type': 'Ankle'},
            },
            {
              'status': 'Active',
              'athlete': {
                'displayName': 'Healthy Player',
                'position': {'abbreviation': 'QB'},
                'team': {'abbreviation': 'BUF'},
              },
            },
          ],
        },
      ],
    }, fetchedAt: now);

    expect(entries, hasLength(1));
    expect(entries.single.player, 'Star Receiver');
    expect(entries.single.team, 'BUF');
    expect(entries.single.position, 'WR');
    expect(entries.single.sourceLabel, 'ESPN, unofficial');
    expect(entries.single.official, isFalse);
    expect(entries.single.injury, 'Ankle');
  });

  test('NFL.com reads one report and skips a blank game status', () {
    const html = '''
      <h1>WEEK 10</h1>
      <div class="d3-o-section-sub-title"><span>Bills</span></div>
      <table>
        <tr><td>Player</td><td>Position</td><td>Injuries</td><td>Practice Status</td><td>Game Status</td></tr>
        <tr><td>Star Receiver</td><td>WR</td><td>Ankle</td><td>Did Not Participate</td><td>Out</td></tr>
        <tr><td>Practice Only</td><td>RB</td><td>Knee</td><td>Limited</td><td></td></tr>
      </table>
      <div class="d3-o-section-sub-title"><span>Commanders</span></div>
      <table>
        <tr><td>Another Player</td><td>QB</td><td>Shoulder</td><td>Did Not Participate</td><td>Doubtful</td></tr>
      </table>
    ''';
    final entries = parseNflInjuryPage(html, fetchedAt: now);
    expect(entries.map((entry) => entry.player), [
      'Star Receiver',
      'Another Player',
    ]);
    expect(entries.first.team, 'BUF');
    expect(entries.first.official, isTrue);
    expect(entries.first.week, 10);
    expect(entries.last.team, 'WAS');
  });

  test('nflverse keeps the latest regular-season week and maps LA', () {
    const csv = '''
season,season_type,week,team,position,full_name,report_status,report_primary_injury
2026,REG,9,BUF,RB,Old Runner,Out,Knee
2026,REG,10,LA,WR,"Star Receiver",Out,Ankle
2026,REG,10,BUF,QB,Healthy Player,,
2026,PRE,10,BUF,WR,Camp Player,Out,Hamstring
2025,REG,18,BUF,WR,Last Year,Out,Foot
''';
    final entries = parseNflverseInjuries(csv, fetchedAt: now);
    expect(entries, hasLength(1));
    expect(entries.single.player, 'Star Receiver');
    expect(entries.single.team, 'LAR');
    expect(entries.single.week, 10);
    expect(nflSeasonYear(DateTime.utc(2027, 1, 15)), 2026);
    expect(nflSeasonYear(DateTime.utc(2026, 11, 12)), 2026);
  });

  test('sources confirm, disagree, and a short list does not clear names', () {
    final espn = [
      player(name: 'Star Receiver', team: 'BUF', position: 'WR', status: 'Out'),
      player(
        name: 'Quiet Guard',
        team: 'BUF',
        position: 'G',
        status: 'Questionable',
      ),
    ];
    final nfl = [
      player(
        name: 'Star Receiver',
        team: 'Buffalo Bills',
        position: 'WR',
        status: 'Out',
        sourceId: 'nfl',
        sourceLabel: 'NFL.com',
      ),
      player(
        name: 'Quiet Guard',
        team: 'BUF',
        position: 'G',
        status: 'Doubtful',
        sourceId: 'nfl',
        sourceLabel: 'NFL.com',
      ),
    ];
    final agreed = assembleInjuryReport(
      now: now,
      live: true,
      espn: espn,
      nfl: nfl,
      nflverse: const [],
      previous: const [],
      sources: const [],
    );
    final star = agreed.entries.firstWhere(
      (entry) => entry.player == 'Star Receiver',
    );
    final guard = agreed.entries.firstWhere(
      (entry) => entry.player == 'Quiet Guard',
    );
    expect(star.agrees, ['NFL.com']);
    expect(star.differs, isNull);
    expect(guard.differs, 'NFL.com says Doubtful');
    expect(agreed.changes, isEmpty);

    final previous = [
      for (var i = 0; i < 21; i++)
        player(name: 'Player $i', team: 'BUF', position: 'WR', status: 'Out'),
      player(
        name: 'Star Receiver',
        team: 'BUF',
        position: 'WR',
        status: 'Questionable',
      ),
    ];
    final thin = assembleInjuryReport(
      now: now,
      live: true,
      espn: [
        player(
          name: 'Star Receiver',
          team: 'BUF',
          position: 'WR',
          status: 'Out',
        ),
        player(name: 'New Tackle', team: 'KC', position: 'T', status: 'Out'),
      ],
      nfl: const [],
      nflverse: const [],
      previous: previous,
      sources: const [],
    );
    expect(
      thin.changes.map((change) => change.summary),
      containsAll([
        'Star Receiver moved from Questionable to Out.',
        'New Tackle is now listed Out.',
      ]),
    );
    expect(
      thin.changes.any((change) => change.summary.contains('no longer listed')),
      isFalse,
    );
    expect(thin.notice, contains('not marked as back'));
  });

  test('a full list does mark a player who came off the report', () {
    final report = assembleInjuryReport(
      now: now,
      live: true,
      espn: [
        player(name: 'Still Out', team: 'BUF', position: 'WR', status: 'Out'),
      ],
      nfl: const [],
      nflverse: const [],
      previous: [
        player(name: 'Still Out', team: 'BUF', position: 'WR', status: 'Out'),
        player(name: 'Came Back', team: 'BUF', position: 'RB', status: 'Out'),
      ],
      sources: const [],
    );
    expect(
      report.changes.single.summary,
      'Came Back is no longer listed. The last status was Out.',
    );
  });

  test('badges and links follow the player and the position', () {
    final report = assembleInjuryReport(
      now: now,
      live: true,
      espn: [
        player(
          name: 'Star Receiver',
          team: 'BUF',
          position: 'WR',
          status: 'Out',
        ),
        player(
          name: 'Josh Allen',
          team: 'BUF',
          position: 'QB',
          status: 'Questionable',
        ),
      ],
      nfl: const [],
      nflverse: const [],
      previous: const [],
      sources: const [],
    );
    final passing = badgeForProp(
      report,
      market: 'player_pass_yds',
      playerName: 'Other Quarterback',
      playerTeam: 'BUF',
      opponent: 'KC',
    );
    expect(passing!.label, '1 out');
    expect(passing.severe, isTrue);
    final named = badgeForProp(
      report,
      market: 'player_rush_yds',
      playerName: 'Josh Allen',
      playerTeam: 'BUF',
    );
    expect(named!.label, '1 questionable');
    expect(badgeForClubs(report, ['Buffalo Bills'])!.outCount, 1);
    expect(
      injuryPollInterval(
        now: now,
        kickoffs: [now.add(const Duration(hours: 2))],
      ),
      const Duration(minutes: 2),
    );
    expect(
      injuryPollInterval(
        now: now,
        kickoffs: [now.add(const Duration(days: 3))],
      ),
      const Duration(minutes: 5),
    );
    expect(
      injuryPollInterval(
        now: DateTime.utc(2026, 4, 2),
        kickoffs: [DateTime.utc(2026, 9, 1)],
      ),
      const Duration(hours: 6),
    );
    expect(
      nflConfirmationInterval(const Duration(minutes: 2)),
      const Duration(minutes: 5),
    );
    expect(
      updatedAgo(now, now.add(const Duration(seconds: 20))),
      'Updated just now',
    );
    expect(
      updatedAgo(now, now.add(const Duration(minutes: 4))),
      'Updated 4 min ago',
    );
  });

  test('the stored file is a report, not a live check', () {
    final text = File('assets/nfl-matchup.json').readAsStringSync();
    final decoded = jsonDecode(text.replaceFirst('\uFEFF', ''));
    final report = InjuryReport.fromMatchup(
      MatchupContext.fromJson(Map<String, dynamic>.from(decoded as Map)),
      now: now,
    );
    expect(report.live, isFalse);
    expect(report.entries, isNotEmpty);
    expect(report.freshness(now), 'Stored report, not a live check');
    expect(report.notice, contains('not a live check'));
    expect(report.notice, contains('not marked as back'));
    expect(report.changes, isNotEmpty);
    expect(
      report.changes.any(
        (change) => change.summary.contains('no longer listed'),
      ),
      isFalse,
    );
    final again = InjuryReport.fromJson(report.toJson());
    expect(again.entries.length, report.entries.length);
    expect(again.changes.length, report.changes.length);
  });
}
