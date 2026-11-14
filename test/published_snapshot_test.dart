import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/data/published_snapshot.dart';
import 'package:odds_edge/domain/odds.dart';

Map<String, dynamic> snapshotJson(DateTime at) {
  final event = SportEvent(
    'nflverse:2026_11_BUF_KC',
    'Buffalo Bills',
    'Kansas City Chiefs',
    at.add(const Duration(days: 1)),
  );
  final board = OddsBoard(events: [event], quotes: const [], fetchedAt: at);
  return {
    'schemaVersion': 1,
    'generatedAt': at.toIso8601String(),
    'schedule': {'source': 'nflverse', 'fetchedAt': at.toIso8601String()},
    'odds': {'status': 'not_configured'},
    'board': board.toJson(),
    'props': board.toJson(),
  };
}

void main() {
  final now = DateTime.utc(2026, 11, 14);
  test('published games preserve source dates and become stale', () {
    final value = PublishedSnapshot.parse(snapshotJson(now), now);
    expect(value.board.demo, isFalse);
    expect(value.board.quotes, isEmpty);
    expect(value.stale(now), isFalse);
    expect(value.stale(now.add(const Duration(hours: 25))), isTrue);
    expect(value.scheduleAt, now);
  });
  test('examples, prices, unknown schema and mismatched games cannot enter a schedule snapshot', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (r) => r['schemaVersion'] = 2,
      (r) => r['board']['demo'] = true,
      (r) => r['board']['quotes'] = [demoBoard(now).quotes.first.toJson()],
      (r) => r['props']['events'] = [],
      (r) => r['board']['events'][0]['home'] = 'Unknown team',
      (r) => r['board']['events'].add(r['board']['events'][0]),
      (r) => r['schedule']['source'] = 'unknown',
      (r) =>
          r['generatedAt'] = now.add(const Duration(days: 1)).toIso8601String(),
    ]) {
      final raw = snapshotJson(now);
      change(raw);
      expect(() => PublishedSnapshot.parse(raw, now), throwsFormatException);
    }
  });
  test('published HTTP fetch is read-only, cache-busted, and carries no credentials', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(request.url.path, '/odds-edge/data/snapshot.json');
      expect(request.url.queryParameters.keys, ['v']);
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response(jsonEncode(snapshotJson(now)), 200);
    });
    await loadPublishedSnapshot(
      Uri.parse('https://example.com/odds-edge/data/snapshot.json'),
      client: client,
      now: now,
    );
    expect(requests, 1);
    for (final url in [
      'http://example.com/data.json',
      'https://secret@example.com/data.json',
    ]) {
      await expectLater(
        loadPublishedSnapshot(Uri.parse(url), client: client, now: now),
        throwsArgumentError,
      );
    }
    expect(requests, 1);
    client.close();
  });
  test(
    'redirects, server errors and oversized responses remain unavailable',
    () async {
      for (final status in [302, 500]) {
        final client = MockClient((_) async => http.Response('{}', status));
        await expectLater(
          loadPublishedSnapshot(
            Uri.parse('https://example.com/data.json'),
            client: client,
            now: now,
          ),
          throwsStateError,
        );
        client.close();
      }
      final large = MockClient((_) async => http.Response(' ' * 1000001, 200));
      await expectLater(
        loadPublishedSnapshot(
          Uri.parse('https://example.com/data.json'),
          client: large,
          now: now,
        ),
        throwsFormatException,
      );
      large.close();
    },
  );
}
