/// US Eastern wall time, without a timezone database.
///
/// Daylight time runs from 2:00 AM Eastern on the second Sunday of March
/// until 2:00 AM Eastern on the first Sunday of November.
Duration easternOffset(DateTime instant) {
  final utc = instant.toUtc();
  final start = _nthSunday(utc.year, 3, 2).add(const Duration(hours: 7));
  final end = _nthSunday(utc.year, 11, 1).add(const Duration(hours: 6));
  if (!utc.isBefore(start) && utc.isBefore(end)) {
    return const Duration(hours: -4);
  }
  return const Duration(hours: -5);
}

/// Clock fields are Eastern. The value stays marked UTC so [toLocal] cannot
/// shift it again.
DateTime easternWall(DateTime instant) {
  final utc = instant.toUtc();
  return utc.add(easternOffset(utc));
}

DateTime easternWallToUtc(int year, int month, int day, int hour, int minute) {
  for (final hours in const [4, 5]) {
    final utc = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
    ).add(Duration(hours: hours));
    final wall = utc.add(easternOffset(utc));
    if (wall.year == year &&
        wall.month == month &&
        wall.day == day &&
        wall.hour == hour &&
        wall.minute == minute) {
      return utc;
    }
  }
  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
  ).add(const Duration(hours: 5));
}

/// The next [weekday] at [hour]:[minute] Eastern that is still ahead of [now].
DateTime nextEasternKickoff(DateTime now, int weekday, int hour, int minute) {
  final wall = easternWall(now);
  var cursor = DateTime.utc(wall.year, wall.month, wall.day);
  for (var i = 0; i < 21; i++) {
    if (cursor.weekday == weekday) {
      final utc = easternWallToUtc(
        cursor.year,
        cursor.month,
        cursor.day,
        hour,
        minute,
      );
      if (utc.isAfter(now.toUtc())) return utc;
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  throw StateError('No Eastern kickoff falls after $now.');
}

String formatEastern(DateTime instant, {bool year = false}) {
  final wall = easternWall(instant);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
  final minute = wall.minute.toString().padLeft(2, '0');
  final suffix = wall.hour >= 12 ? 'PM' : 'AM';
  final date = year
      ? '${months[wall.month - 1]} ${wall.day}, ${wall.year}'
      : '${days[wall.weekday - 1]} ${months[wall.month - 1]} ${wall.day}';
  return '$date · $hour:$minute $suffix ET';
}

DateTime _nthSunday(int year, int month, int n) {
  var day = DateTime.utc(year, month, 1);
  while (day.weekday != DateTime.sunday) {
    day = day.add(const Duration(days: 1));
  }
  return day.add(Duration(days: 7 * (n - 1)));
}
