import '../domain/odds.dart';
import '../domain/public_sharp.dart';

/// Sample open-to-now prices for the demonstration games.
///
/// The numbers are invented so the sharp screen can be tried with no feed
/// connected. They are labeled as a sample wherever they are shown.
Map<String, List<LineSnapshot>> demoLineHistory(OddsBoard board) {
  final at = board.fetchedAt.toUtc();
  final history = <String, List<LineSnapshot>>{};
  for (final event in board.events) {
    final shots = switch (event.id) {
      'demo-buf-kc' => _chiefs(event, at),
      'demo-min-gb' => _quiet(event, at),
      'demo-bal-cin' => _slow(event, at),
      _ => const <LineSnapshot>[],
    };
    if (shots.isNotEmpty) history[event.id] = shots;
  }
  return history;
}

const _books = ['fanduel', 'draftkings', 'betmgm', 'caesars', 'bet365'];

List<LineSnapshot> _chiefs(SportEvent event, DateTime at) {
  final open = at.subtract(const Duration(hours: 6));
  final hold = at.subtract(const Duration(minutes: 30));
  final first = at.subtract(const Duration(minutes: 18));
  final steam = at.subtract(const Duration(minutes: 8));
  return [
    _shot(event, open, us: -2.5, pinnacle: -3),
    _shot(event, hold, us: -2.5, pinnacle: -3),
    _shot(
      event,
      first,
      us: -2.5,
      pinnacle: -3.5,
      moved: const {'draftkings': -3.5},
    ),
    _shot(event, steam, us: -3.5, pinnacle: -3.5),
  ];
}

List<LineSnapshot> _quiet(SportEvent event, DateTime at) {
  final open = at.subtract(const Duration(hours: 8));
  final later = at.subtract(const Duration(hours: 3));
  return [
    _shot(event, open, us: -2.5, pinnacle: -2.5),
    _shot(event, later, us: -2.5, pinnacle: -2.5),
  ];
}

List<LineSnapshot> _slow(SportEvent event, DateTime at) {
  final open = at.subtract(const Duration(hours: 8));
  final later = at.subtract(const Duration(hours: 4));
  return [
    _shot(event, open, us: -1, pinnacle: -1),
    _shot(event, later, us: -3.5, pinnacle: -3.5),
  ];
}

LineSnapshot _shot(
  SportEvent event,
  DateTime at, {
  required double us,
  required double pinnacle,
  Map<String, double> moved = const {},
}) {
  final prices = <LinePrice>[];
  for (final book in _books) {
    final point = moved[book] ?? us;
    prices.add(_spread(book, event.home, point));
    prices.add(_spread(book, event.away, -point));
  }
  prices.add(_spread(sharpReferenceBook, event.home, pinnacle));
  prices.add(_spread(sharpReferenceBook, event.away, -pinnacle));
  prices.add(_total('fanduel', 'Over', 47.5));
  prices.add(_total('fanduel', 'Under', 47.5));
  return LineSnapshot(
    at: at,
    eventId: event.id,
    away: event.away,
    home: event.home,
    prices: prices,
  );
}

LinePrice _spread(String book, String outcome, double point) => LinePrice(
  bookId: book,
  market: 'spreads',
  outcome: outcome,
  decimal: 1.91,
  point: point,
);

LinePrice _total(String book, String outcome, double point) => LinePrice(
  bookId: book,
  market: 'totals',
  outcome: outcome,
  decimal: 1.91,
  point: point,
);
