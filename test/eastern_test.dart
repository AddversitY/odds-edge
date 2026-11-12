import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/eastern.dart';

void main() {
  test('Eastern offset follows the second Sunday in March and the first in November', () {
    expect(
      easternOffset(DateTime.utc(2026, 3, 8, 6, 59)),
      const Duration(hours: -5),
    );
    expect(
      easternOffset(DateTime.utc(2026, 3, 8, 7)),
      const Duration(hours: -4),
    );
    expect(
      easternOffset(DateTime.utc(2026, 11, 1, 5, 59)),
      const Duration(hours: -4),
    );
    expect(
      easternOffset(DateTime.utc(2026, 11, 1, 6)),
      const Duration(hours: -5),
    );
  });

  test('a Sunday 1:00 PM Eastern kickoff round-trips and labels in ET', () {
    final kick = easternWallToUtc(2026, 11, 15, 13, 0);
    expect(kick, DateTime.utc(2026, 11, 15, 18));
    expect(formatEastern(kick), 'Sun Nov 15 · 1:00 PM ET');
    expect(
      formatEastern(DateTime.utc(2026, 11, 12, 23, 36), year: true),
      'Nov 12, 2026 · 6:36 PM ET',
    );
  });

  test('the next Sunday 1:00 PM Eastern is after now', () {
    final now = DateTime.utc(2026, 11, 12, 23, 37);
    final kick = nextEasternKickoff(now, DateTime.sunday, 13, 0);
    expect(kick.isAfter(now), isTrue);
    expect(easternWall(kick).weekday, DateTime.sunday);
    expect(formatEastern(kick), contains('1:00 PM ET'));
  });
}
