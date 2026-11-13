import 'bets.dart';
import 'odds.dart';
import 'public_sharp.dart';

/// How a saved bet lines up with prices already stored.
class CloseFill {
  const CloseFill({this.closingLine, this.closingDecimal, required this.note});

  final double? closingLine;
  final double? closingDecimal;

  /// Plain sentence for the bet log. It names the source.
  final String note;

  bool get hasNumber => closingLine != null || closingDecimal != null;
}

/// Fill only the closing fields that are still blank, and only after
/// kickoff, from the last snapshot at or before kickoff.
///
/// A number already on the bet is left alone. That includes a close
/// typed by hand and a close filled earlier. Reading the history does
/// not call The Odds API.
TrackedBet autoCloseBet(
  TrackedBet bet,
  Map<String, List<LineSnapshot>> history,
  List<SportEvent> events,
  DateTime now,
) {
  if (bet.closingLine != null && bet.closingDecimal != null) return bet;
  final fill = closeForBet(bet, history, events, now);
  if (fill == null || !fill.hasNumber) return bet;
  final line = bet.closingLine ?? fill.closingLine;
  final price = bet.closingDecimal ?? fill.closingDecimal;
  if (line == bet.closingLine && price == bet.closingDecimal) return bet;
  final note = bet.notes.trim().isEmpty
      ? fill.note
      : bet.notes.contains(fill.note)
      ? bet.notes
      : '${bet.notes.trim()} ${fill.note}';
  return bet.copyWith(
    closingLine: line,
    replaceClosingLine: true,
    closingDecimal: price,
    replaceClosing: true,
    notes: note,
    closeSource: bet.closeSource == 'typed' ? 'typed' : 'line-history',
  );
}

CloseFill? closeForBet(
  TrackedBet bet,
  Map<String, List<LineSnapshot>> history,
  List<SportEvent> events,
  DateTime now,
) {
  if (bet.closeSource == 'typed') return null;
  final eventId = bet.eventId.trim();
  if (eventId.isEmpty) return null;
  SportEvent? event;
  for (final candidate in events) {
    if (candidate.id == eventId) event = candidate;
  }
  if (event == null) return null;
  final kick = event.startsAt.toUtc();
  if (now.toUtc().isBefore(kick)) return null;
  final shots = [
    for (final shot in historyForEvent(event, history))
      if (!shot.at.toUtc().isAfter(kick)) shot,
  ]..sort((a, b) => a.at.compareTo(b.at));
  if (shots.isEmpty) return null;
  final close = shots.last;
  final side = _sidePrices(close, event, bet);
  if (side.isEmpty) return null;
  LinePrice? matched;
  for (final price in side) {
    if (_sameBook(bet.book, price.bookId)) {
      matched = price;
      break;
    }
  }
  final chosen = matched ?? _medianPrice(side);
  if (chosen == null) return null;
  final fromBook = matched != null;
  final line = bet.closingLine ?? chosen.point;
  final price = bet.closingDecimal ?? (fromBook ? chosen.decimal : null);
  if (line == null && price == null) return null;
  final note = fromBook
      ? 'Closing number filled from the last saved price at or before kickoff, from ${bet.book}. It was not typed.'
      : 'Closing number filled from the median of the books in the last snapshot before kickoff. ${bet.book} was not in that snapshot, so the closing price was left blank.';
  return CloseFill(closingLine: line, closingDecimal: price, note: note);
}

List<LinePrice> _sidePrices(
  LineSnapshot shot,
  SportEvent event,
  TrackedBet bet,
) {
  final market = bet.market;
  if (market.isEmpty) return const [];
  final outcome = _outcome(event, bet);
  if (outcome == null) return const [];
  return [
    for (final price in shot.prices)
      if (price.usable &&
          price.market == market &&
          price.outcome.toLowerCase() == outcome.toLowerCase())
        price,
  ];
}

String? _outcome(SportEvent event, TrackedBet bet) {
  switch (bet.market) {
    case 'spreads':
    case 'h2h':
      if (bet.side == 'home') return event.home;
      if (bet.side == 'away') return event.away;
      return null;
    case 'totals':
      if (bet.side == 'over') return 'Over';
      if (bet.side == 'under') return 'Under';
      return null;
    default:
      return null;
  }
}

bool _sameBook(String betBook, String bookId) {
  final left = betBook.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final right = bookId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (left.isEmpty || right.isEmpty) return false;
  return left == right || left.startsWith(right) || right.startsWith(left);
}

LinePrice? _medianPrice(List<LinePrice> prices) {
  final withPoint = [
    for (final price in prices)
      if (price.point != null) price,
  ];
  if (withPoint.isEmpty) return prices.isEmpty ? null : prices.first;
  final sorted = [...withPoint]..sort((a, b) => a.point!.compareTo(b.point!));
  return sorted[sorted.length ~/ 2];
}

/// Movement across saved snapshots. A close is only claimed after kickoff.
class ClosingSummary {
  const ClosingSummary({
    required this.games,
    required this.compared,
    required this.closed,
    required this.averageSpreadPoints,
    required this.beatTheLaterNumber,
    required this.plainEnglish,
    required this.example,
  });

  final int games;
  final int compared;

  /// Games whose kickoff is already in the past, so the later number
  /// can be called a close.
  final bool closed;

  /// Average points by which the first home number beat the later home
  /// number. Positive means the earlier number was the better one.
  final double? averageSpreadPoints;
  final int beatTheLaterNumber;
  final String plainEnglish;
  final bool example;

  static const empty = ClosingSummary(
    games: 0,
    compared: 0,
    closed: false,
    averageSpreadPoints: null,
    beatTheLaterNumber: 0,
    plainEnglish: 'No line history is saved yet. Closing-line value stays blank until this app has an earlier price and a later one for the same game. Reading history does not call the odds API.',
    example: false,
  );
}

ClosingSummary summarizeLineHistory({
  required Map<String, List<LineSnapshot>> history,
  required List<SportEvent> events,
  required DateTime now,
  bool example = false,
}) {
  if (history.isEmpty) {
    return ClosingSummary.empty;
  }
  final byId = {for (final event in events) event.id: event};
  final moves = <double>[];
  var games = 0;
  var closedGames = 0;
  for (final entry in history.entries) {
    final shots = [...entry.value]..sort((a, b) => a.at.compareTo(b.at));
    if (shots.isEmpty) continue;
    games++;
    final event = byId[entry.key] ?? _eventFromShots(entry.key, shots);
    final kick = event?.startsAt.toUtc();
    final started = kick != null && !now.toUtc().isBefore(kick);
    if (started) closedGames++;
    final usable = [
      for (final shot in shots)
        if (kick == null || !shot.at.toUtc().isAfter(kick)) shot,
    ];
    if (usable.length < 2 || event == null) continue;
    final early = _homeSpread(usable.first, event.home);
    final late = _homeSpread(usable.last, event.home);
    if (early == null || late == null) continue;
    moves.add(early - late);
  }
  final compared = moves.length;
  final beat = moves.where((value) => value > 0.05).length;
  final average = compared == 0
      ? null
      : moves.reduce((a, b) => a + b) / compared;
  final closed = games > 0 && closedGames == games && closedGames > 0;
  final anyClosed = closedGames > 0;
  return ClosingSummary(
    games: games,
    compared: compared,
    closed: anyClosed && closedGames == games,
    averageSpreadPoints: average,
    beatTheLaterNumber: beat,
    example: example,
    plainEnglish: _summaryText(
      games: games,
      compared: compared,
      closed: anyClosed,
      fullyClosed: closed,
      average: average,
      beat: beat,
      example: example,
    ),
  );
}

SportEvent? _eventFromShots(String id, List<LineSnapshot> shots) {
  for (final shot in shots.reversed) {
    if (shot.away.isEmpty || shot.home.isEmpty) continue;
    return SportEvent(id, shot.away, shot.home, shot.at);
  }
  return null;
}

double? _homeSpread(LineSnapshot shot, String home) {
  final points = [
    for (final price in shot.prices)
      if (price.usable &&
          price.market == 'spreads' &&
          price.outcome.toLowerCase() == home.toLowerCase() &&
          price.point != null)
        price.point!,
  ];
  if (points.isEmpty) return null;
  points.sort();
  return points[points.length ~/ 2];
}

String _summaryText({
  required int games,
  required int compared,
  required bool closed,
  required bool fullyClosed,
  required double? average,
  required int beat,
  required bool example,
}) {
  final sample = example ? 'Example prices. ' : '';
  if (compared == 0) {
    return '${sample}Line history has $games ${games == 1 ? 'game' : 'games'}, but none has both an earlier number and a later number before kickoff. Closing-line value stays blank. This does not call the odds API.';
  }
  final points = average!.abs() < 0.05
      ? 'about even'
      : '${average > 0 ? 'ahead of' : 'behind'} the later number by ${average.abs().toStringAsFixed(1)} points';
  final kind = fullyClosed
      ? 'The later number is the last saved price at or before kickoff, which is the close in this file.'
      : closed
      ? 'Some of these games have started. Where a game has not started, the later number is movement, not a close.'
      : 'None of these games have started, so this is how the saved number moved. It is not closing-line value.';
  return '$sample$kind On $compared ${compared == 1 ? 'game' : 'games'} with two saved home numbers, taking the home side at the first number was $points. That earlier number was better on $beat of $compared. The price on the ticket is a separate comparison, on My Bets. This is not a pick.';
}
