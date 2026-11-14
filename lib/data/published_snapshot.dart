import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/odds.dart';
import '../domain/nfl_teams.dart';

/// Public, read-only app snapshot. Never an authenticated backend or raw feed.
class PublishedSnapshot {
  const PublishedSnapshot({
    required this.board,
    required this.props,
    required this.generatedAt,
    required this.scheduleAt,
    required this.oddsMessage,
  });
  final OddsBoard board, props;
  final DateTime generatedAt, scheduleAt;
  final String oddsMessage;
  bool stale(DateTime now) =>
      scheduleAt.isAfter(now.add(const Duration(minutes: 5))) ||
      now.difference(scheduleAt) > const Duration(hours: 24);
  factory PublishedSnapshot.parse(Object? raw, DateTime now) {
    if (raw is! Map<String, dynamic> || raw['schemaVersion'] != 1) {
      throw const FormatException('Unsupported public snapshot.');
    }
    final generated = DateTime.parse(raw['generatedAt'] as String).toUtc();
    final schedule = raw['schedule'] as Map<String, dynamic>;
    final scheduleAt = DateTime.parse(schedule['fetchedAt'] as String).toUtc();
    if (generated.isAfter(now.add(const Duration(minutes: 5))) ||
        scheduleAt.isAfter(generated) ||
        schedule['source'] != 'nflverse') {
      throw const FormatException('Invalid schedule provenance.');
    }
    final board = OddsBoard.fromJson(raw['board'] as Map<String, dynamic>);
    final props = OddsBoard.fromJson(raw['props'] as Map<String, dynamic>);
    final odds = raw['odds'] as Map<String, dynamic>;
    // Current release publishes free schedule data only. Odds require a
    // separately configured, approved data pipeline; never disguise examples.
    if (board.demo ||
        props.demo ||
        board.quotes.isNotEmpty ||
        props.quotes.isNotEmpty ||
        odds['status'] != 'not_configured' ||
        board.fetchedAt != scheduleAt ||
        props.fetchedAt != scheduleAt) {
      throw const FormatException(
        'This schedule snapshot cannot contain sportsbook prices.',
      );
    }
    final ids = <String>{};
    for (final event in board.events) {
      if (!event.id.startsWith('nflverse:') ||
          !ids.add(event.id) ||
          event.home == event.away ||
          !nflTeams.containsKey(event.home) ||
          !nflTeams.containsKey(event.away) ||
          event.league != 'NFL') {
        throw const FormatException('Invalid schedule identity.');
      }
    }
    if (jsonEncode(props.events.map((e) => e.toJson()).toList()) !=
        jsonEncode(board.events.map((e) => e.toJson()).toList())) {
      throw const FormatException(
        'Snapshot boards disagree about the schedule.',
      );
    }
    return PublishedSnapshot(
      board: board,
      props: props,
      generatedAt: generated,
      scheduleAt: scheduleAt,
      oddsMessage: 'Sportsbook prices are not connected.',
    );
  }
}

Future<PublishedSnapshot> loadPublishedSnapshot(
  Uri url, {
  http.Client? client,
  DateTime? now,
}) async {
  final local =
      url.scheme == 'http' && ['localhost', '127.0.0.1'].contains(url.host);
  if (!(url.scheme == 'https' || local) || url.userInfo.isNotEmpty) {
    throw ArgumentError('Use an HTTPS public snapshot.');
  }
  final connection = client ?? http.Client();
  final at = now ?? DateTime.now().toUtc();
  try {
    final request = http.Request(
      'GET',
      url.replace(
        queryParameters: {
          ...url.queryParameters,
          'v': '${at.millisecondsSinceEpoch ~/ 300000}',
        },
      ),
    )..followRedirects = false;
    final response = await connection
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Schedule snapshot unavailable.');
    }
    final bytes = <int>[];
    await for (final part in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      bytes.addAll(part);
      if (bytes.length > 1000000) {
        throw const FormatException('Unexpected snapshot size.');
      }
    }
    return PublishedSnapshot.parse(jsonDecode(utf8.decode(bytes)), at);
  } finally {
    if (client == null) connection.close();
  }
}
