import 'odds.dart';

/// Shown when no public ticket or money percentages are allowed on screen.
const publicSplitsUnavailableNotice =
    'Public betting percentages are not available. '
    'The places that publish ticket and money percentages do not allow this app to copy them. '
    'Nothing was estimated.';

/// Home spread move, in points, that counts as a real change.
const sharpMovePoints = 0.5;

/// How close together book moves have to be before they can be a steam.
const steamWindow = Duration(minutes: 20);

/// Distinct books that must move the same way inside [steamWindow].
const steamBookCount = 3;

/// Decimal price nearest to a pick'em (-110). Used to ignore alternate lines.
const _evenDecimal = 1 + 100 / 110;

const sharpReferenceBook = 'pinnacle';

/// One number from a saved odds snapshot. Built from our line history or
/// from the board already on screen. It does not call The Odds API.
class LinePrice {
  const LinePrice({
    required this.bookId,
    required this.market,
    required this.outcome,
    required this.decimal,
    this.point,
    this.status = 'open',
  });

  final String bookId;
  final String market;
  final String outcome;
  final double decimal;
  final double? point;
  final String status;

  bool get usable =>
      status == 'open' ||
      status == 'unverified' ||
      status == 'demo' ||
      status.isEmpty;
}

/// Every usable spread and total at one moment.
class LineSnapshot {
  const LineSnapshot({
    required this.at,
    required this.prices,
    this.eventId = '',
    this.away = '',
    this.home = '',
  });

  final DateTime at;
  final String eventId;
  final String away;
  final String home;
  final List<LinePrice> prices;

  static LineSnapshot? fromJson(
    Object? raw, {
    String eventId = '',
    String away = '',
    String home = '',
  }) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}')?.toUtc();
    final rows = raw['prices'];
    if (at == null || rows is! List) return null;
    final prices = <LinePrice>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final decimal = row['decimal'];
      if (decimal is! num) continue;
      final point = row['point'];
      prices.add(
        LinePrice(
          bookId: '${row['bookId'] ?? ''}',
          market: '${row['market'] ?? ''}',
          outcome: '${row['outcome'] ?? ''}',
          decimal: decimal.toDouble(),
          point: point is num ? point.toDouble() : null,
          status: '${row['status'] ?? 'open'}',
        ),
      );
    }
    if (prices.isEmpty) return null;
    return LineSnapshot(
      at: at,
      eventId: eventId.isEmpty ? '${raw['id'] ?? ''}' : eventId,
      away: away.isEmpty ? '${raw['away'] ?? ''}' : away,
      home: home.isEmpty ? '${raw['home'] ?? ''}' : home,
      prices: prices,
    );
  }
}

/// Ticket percent and money percent for one market, when a source that
/// allows display has actually returned them.
class PublicSplit {
  const PublicSplit({
    required this.eventId,
    required this.market,
    required this.sourceName,
    required this.attribution,
    required this.fetchedAt,
    required this.homeLabel,
    required this.awayLabel,
    required this.homeTickets,
    required this.awayTickets,
    required this.homeMoney,
    required this.awayMoney,
  });

  final String eventId;
  final String market;
  final String sourceName;
  final String attribution;
  final DateTime fetchedAt;

  /// For a spread, the home team. For a total, Over.
  final String homeLabel;
  final String awayLabel;
  final double homeTickets;
  final double awayTickets;
  final double homeMoney;
  final double awayMoney;

  bool get complete =>
      _percent(homeTickets) &&
      _percent(awayTickets) &&
      _percent(homeMoney) &&
      _percent(awayMoney);

  static bool _percent(double value) =>
      value.isFinite && value >= 0 && value <= 100;
}

/// What the server knows about public percentages. Empty means we do not
/// have any, which is different from inventing a number.
class PublicFeed {
  const PublicFeed({
    required this.available,
    required this.notice,
    this.source,
    this.attribution,
    this.splits = const [],
  });

  final bool available;
  final String notice;
  final String? source;
  final String? attribution;
  final List<PublicSplit> splits;

  static const unavailable = PublicFeed(
    available: false,
    notice: publicSplitsUnavailableNotice,
  );

  static PublicFeed parse(Object? raw) {
    if (raw is! Map) return unavailable;
    final available = raw['available'] == true;
    final notice = '${raw['notice'] ?? publicSplitsUnavailableNotice}';
    final games = raw['games'];
    final splits = <PublicSplit>[];
    if (games is List) {
      for (final game in games) {
        final split = _parseSplit(
          game,
          source: '${raw['source'] ?? ''}',
          attribution: '${raw['attribution'] ?? ''}',
        );
        if (split != null) splits.add(split);
      }
    }
    if (!available || splits.isEmpty) {
      return PublicFeed(
        available: false,
        notice: notice.isEmpty ? publicSplitsUnavailableNotice : notice,
      );
    }
    return PublicFeed(
      available: true,
      notice: notice,
      source: '${raw['source'] ?? ''}',
      attribution: '${raw['attribution'] ?? ''}',
      splits: splits,
    );
  }
}

PublicSplit? _parseSplit(
  Object? raw, {
  required String source,
  required String attribution,
}) {
  if (raw is! Map) return null;
  final spread = raw['spread'];
  if (spread is! Map) return null;
  double? numOf(Object? value) => value is num ? value.toDouble() : null;
  final homeTickets = numOf(spread['homeTickets']);
  final awayTickets = numOf(spread['awayTickets']);
  final homeMoney = numOf(spread['homeMoney']);
  final awayMoney = numOf(spread['awayMoney']);
  final at = DateTime.tryParse('${raw['fetchedAt'] ?? ''}')?.toUtc();
  if (homeTickets == null ||
      awayTickets == null ||
      homeMoney == null ||
      awayMoney == null ||
      at == null) {
    return null;
  }
  final split = PublicSplit(
    eventId: '${raw['eventId'] ?? ''}',
    market: 'spreads',
    sourceName: source.isEmpty ? '${raw['source'] ?? ''}' : source,
    attribution: attribution.isEmpty
        ? '${raw['attribution'] ?? ''}'
        : attribution,
    fetchedAt: at,
    homeLabel: '${raw['home'] ?? 'Home'}',
    awayLabel: '${raw['away'] ?? 'Away'}',
    homeTickets: homeTickets,
    awayTickets: awayTickets,
    homeMoney: homeMoney,
    awayMoney: awayMoney,
  );
  if (!split.complete || split.eventId.isEmpty || split.sourceName.isEmpty) {
    return null;
  }
  return split;
}

/// The sharp read for one game. Sentences are signals, not picks.
class SharpRead {
  const SharpRead({
    required this.eventId,
    required this.away,
    required this.home,
    required this.oneLine,
    required this.detail,
    required this.publicLine,
    required this.sparkline,
    required this.sparklineLabel,
    required this.clarity,
    required this.sample,
    this.startsAt,
    this.reverseLine,
    this.ticketMoney,
  });

  final String eventId;
  final String away;
  final String home;
  final DateTime? startsAt;
  final String oneLine;
  final List<String> detail;
  final String publicLine;
  final String? reverseLine;
  final String? ticketMoney;
  final List<double> sparkline;
  final String sparklineLabel;
  final int clarity;
  final bool sample;

  bool get hasSignal => clarity > 0;
}

Map<String, List<LineSnapshot>> parseLineSlate(Object? raw) {
  if (raw is! Map) return {};
  final events = raw['events'];
  if (events is! List) return {};
  final grouped = <String, List<LineSnapshot>>{};
  for (final event in events) {
    if (event is! Map) continue;
    final id = '${event['id'] ?? ''}';
    if (id.isEmpty) continue;
    final away = '${event['away'] ?? ''}';
    final home = '${event['home'] ?? ''}';
    final shots = event['snapshots'];
    if (shots is! List) continue;
    final parsed = <LineSnapshot>[];
    for (final shot in shots) {
      final snapshot = LineSnapshot.fromJson(
        shot,
        eventId: id,
        away: away,
        home: home,
      );
      if (snapshot != null) parsed.add(snapshot);
    }
    if (parsed.isNotEmpty) grouped[id] = parsed;
  }
  return grouped;
}

List<LineSnapshot> historyForEvent(
  SportEvent event,
  Map<String, List<LineSnapshot>> history,
) {
  final direct = history[event.id];
  if (direct != null && direct.isNotEmpty) return direct;
  final away = event.away.toLowerCase();
  final home = event.home.toLowerCase();
  for (final shots in history.values) {
    if (shots.isEmpty) continue;
    final sample = shots.last;
    if (sample.away.toLowerCase() == away &&
        sample.home.toLowerCase() == home) {
      return shots;
    }
  }
  return const [];
}

PublicSplit? publicSplitFor(SportEvent event, List<PublicSplit> splits) {
  for (final split in splits) {
    if (split.eventId == event.id && split.market == 'spreads') return split;
  }
  final away = event.away.toLowerCase();
  final home = event.home.toLowerCase();
  for (final split in splits) {
    if (split.market != 'spreads') continue;
    if (split.awayLabel.toLowerCase() == away &&
        split.homeLabel.toLowerCase() == home) {
      return split;
    }
  }
  return null;
}

LineSnapshot snapshotFromQuotes({
  required DateTime at,
  required SportEvent event,
  required Iterable<OddsQuote> quotes,
}) {
  final prices = <LinePrice>[];
  for (final quote in quotes) {
    if (quote.selection.eventId != event.id) continue;
    final market = quote.selection.market;
    if (market != 'spreads' && market != 'totals') continue;
    prices.add(
      LinePrice(
        bookId: quote.bookId,
        market: market,
        outcome: quote.selection.outcome,
        decimal: quote.decimal,
        point: quote.selection.point,
        status: quote.status,
      ),
    );
  }
  return LineSnapshot(
    at: at.toUtc(),
    eventId: event.id,
    away: event.away,
    home: event.home,
    prices: prices,
  );
}

List<LineSnapshot> combineHistory(
  List<LineSnapshot> history,
  LineSnapshot? current,
) {
  final shots = [...history]..sort((a, b) => a.at.compareTo(b.at));
  if (current == null || current.prices.isEmpty) return shots;
  final merged = <LineSnapshot>[];
  var usedCurrent = false;
  for (final shot in shots) {
    if (shot.at.isAtSameMomentAs(current.at)) {
      merged.add(_mergeSnapshots(shot, current));
      usedCurrent = true;
    } else {
      merged.add(shot);
    }
  }
  if (!usedCurrent) merged.add(current);
  merged.sort((a, b) => a.at.compareTo(b.at));
  return merged;
}

LineSnapshot _mergeSnapshots(LineSnapshot saved, LineSnapshot current) {
  final seen = <String>{};
  final prices = <LinePrice>[];
  for (final price in current.prices) {
    seen.add(_priceKey(price));
    prices.add(price);
  }
  for (final price in saved.prices) {
    if (seen.add(_priceKey(price))) prices.add(price);
  }
  return LineSnapshot(
    at: current.at,
    eventId: current.eventId.isEmpty ? saved.eventId : current.eventId,
    away: current.away.isEmpty ? saved.away : current.away,
    home: current.home.isEmpty ? saved.home : current.home,
    prices: prices,
  );
}

String _priceKey(LinePrice price) =>
    '${price.bookId}|${price.market}|${price.outcome}|${price.point}|${price.decimal}|${price.status}';

/// Sharp signals for one game, from snapshots we already stored plus the
/// board on screen. [publicSplit] is omitted when public percentages are
/// not available. This function does not fetch anything.
SharpRead readSharp({
  required SportEvent event,
  required List<LineSnapshot> history,
  required Iterable<OddsQuote> currentQuotes,
  PublicSplit? publicSplit,
  bool sample = false,
  DateTime? now,
  DateTime? pricesAt,
}) {
  final clock = (now ?? DateTime.now()).toUtc();
  final pricedAt = (pricesAt ?? clock).toUtc();
  final homeNick = clubNickname(event.home);
  final awayNick = clubNickname(event.away);
  if (!event.startsAt.isAfter(clock)) {
    return SharpRead(
      eventId: event.id,
      away: event.away,
      home: event.home,
      startsAt: event.startsAt,
      oneLine: 'Kickoff has passed',
      detail: const [
        'This game has started. The saved line is not treated as a live signal.',
        'This is a signal, not a pick.',
      ],
      publicLine: publicSplitsUnavailableNotice,
      sparkline: const [],
      sparklineLabel: 'No line sparkline after kickoff.',
      clarity: 0,
      sample: sample,
    );
  }

  final current = snapshotFromQuotes(
    at: pricedAt,
    event: event,
    quotes: currentQuotes,
  );
  final shots = combineHistory(
    history,
    current.prices.isEmpty ? null : current,
  );
  final market = _series(shots, event, sharp: false);
  final pinnacle = _series(shots, event, sharp: true);
  final total = _totalSeries(shots, event);

  final detail = <String>[];
  if (sample) {
    detail.add(
      'Sample line history, so this screen can be tried before a feed is connected. Not a live market.',
    );
  }

  String? movedToward;
  double? openLine;
  double? nowLine;
  final sparkline = <double>[];
  if (market.length >= 2) {
    openLine = market.first.point;
    nowLine = market.last.point;
    sparkline.addAll(market.map((point) => point.point));
    final delta = nowLine - openLine;
    if (delta.abs() + 1e-9 >= sharpMovePoints) {
      movedToward = delta < 0 ? homeNick : awayNick;
      final favored = delta < 0
          ? 'the $homeNick are more favored'
          : 'the $awayNick are more favored';
      detail.add(
        'The US books moved from ${pointsLabel(openLine)} to ${pointsLabel(nowLine)}. '
        'That is the home spread. A lower number means $favored.',
      );
    } else {
      detail.add(
        'The US books stayed at ${pointsLabel(nowLine)}. A half point is the smallest move counted here.',
      );
    }
  } else if (market.length == 1) {
    nowLine = market.single.point;
    sparkline.add(nowLine);
    detail.add(
      'One snapshot of the US books is on this screen, at ${pointsLabel(nowLine)}. Open-to-now movement needs an earlier number.',
    );
  } else {
    detail.add('No US spread is in the saved snapshots for this game.');
  }

  double? pinOpen;
  double? pinNow;
  if (pinnacle.isNotEmpty) {
    pinNow = pinnacle.last.point;
    pinOpen = pinnacle.first.point;
    if (pinnacle.length >= 2 &&
        (pinNow - pinOpen).abs() + 1e-9 >= sharpMovePoints) {
      final toward = pinNow < pinOpen ? homeNick : awayNick;
      detail.add(
        'Pinnacle moved from ${pointsLabel(pinOpen)} to ${pointsLabel(pinNow)}, toward the $toward.',
      );
    } else if (pinnacle.length >= 2) {
      detail.add('Pinnacle stayed at ${pointsLabel(pinNow)}.');
    } else {
      detail.add(
        'Pinnacle is ${pointsLabel(pinNow)} now. The saved history does not show an earlier Pinnacle number.',
      );
    }
  } else {
    detail.add('Pinnacle is not in the saved snapshots for this spread.');
  }

  final moves = _bookMoves(shots, event);
  final steam = _steamFor(moves, homeNick, awayNick);
  if (steam == null) {
    detail.add(
      'No fast move across several books in these snapshots. A steam is three or more books moving the same way inside 20 minutes.',
    );
  } else {
    final names = steam.books.map(bookLabel).toList()..sort(_nameSort);
    detail.add(
      '${_join(names)} moved toward the ${steam.toward} inside 20 minutes, by ${magnitude(steam.points)}. '
      'A fast move across several books is a steam. It is a signal, not a pick.',
    );
  }
  detail.add(_firstMoverSentence(moves));

  String? gapToward;
  double gapPoints = 0;
  if (pinNow != null && nowLine != null) {
    final gap = nowLine - pinNow;
    gapPoints = gap.abs();
    if (gapPoints + 1e-9 < sharpMovePoints) {
      detail.add('Pinnacle and the US books are on the same number now.');
    } else {
      gapToward = gap > 0 ? homeNick : awayNick;
      detail.add(
        'Pinnacle has the $gapToward ${magnitude(gapPoints)} more favored than the US books.',
      );
    }
    final earlier = _earlierGap(shots, event, homeNick, awayNick, gapPoints);
    if (earlier != null) detail.add(earlier);
  }

  if (total.length >= 2) {
    final from = total.first.point;
    final to = total.last.point;
    if ((to - from).abs() + 1e-9 >= 1) {
      final way = to < from ? 'the under' : 'the over';
      detail.add(
        'The total moved from ${pointsLabel(from)} to ${pointsLabel(to)}, toward $way.',
      );
    }
  }

  String? reverseLine;
  String? reverseShort;
  String? ticketMoney;
  var publicLine = publicSplitsUnavailableNotice;
  var ticketsDisagree = false;
  if (publicSplit != null && publicSplit.complete) {
    final publicHome =
        publicSplit.homeLabel.toLowerCase() == event.home.toLowerCase()
        ? homeNick
        : clubNickname(publicSplit.homeLabel);
    final publicAway =
        publicSplit.awayLabel.toLowerCase() == event.away.toLowerCase()
        ? awayNick
        : clubNickname(publicSplit.awayLabel);
    final ticketLeader = publicSplit.homeTickets == publicSplit.awayTickets
        ? null
        : publicSplit.homeTickets > publicSplit.awayTickets
        ? publicHome
        : publicAway;
    final moneyLeader = publicSplit.homeMoney == publicSplit.awayMoney
        ? null
        : publicSplit.homeMoney > publicSplit.awayMoney
        ? publicHome
        : publicAway;
    final credit = publicSplit.attribution.isEmpty
        ? publicSplit.sourceName
        : '${publicSplit.sourceName}. ${publicSplit.attribution}';
    publicLine =
        '$credit. ${_percent(publicSplit.homeTickets)} of bets and ${_percent(publicSplit.homeMoney)} of the money are on the $publicHome. '
        '${_percent(publicSplit.awayTickets)} of bets and ${_percent(publicSplit.awayMoney)} of the money are on the $publicAway.';
    if (ticketLeader != null &&
        movedToward != null &&
        ticketLeader != movedToward) {
      reverseLine =
          'Most bets are on the $ticketLeader, but the line moved toward the $movedToward. '
          'That usually means bigger bettors like the $movedToward.';
      reverseShort = 'Bets on the $ticketLeader, line to the $movedToward';
    }
    if (ticketLeader != null &&
        moneyLeader != null &&
        ticketLeader != moneyLeader) {
      final ticketPct = ticketLeader == publicHome
          ? publicSplit.homeTickets
          : publicSplit.awayTickets;
      final moneyPct = moneyLeader == publicHome
          ? publicSplit.homeMoney
          : publicSplit.awayMoney;
      ticketMoney =
          'Most bets are on the $ticketLeader (${_percent(ticketPct)} of tickets), '
          'but most of the money is on the $moneyLeader (${_percent(moneyPct)} of the money).';
      ticketsDisagree = true;
    } else if (ticketLeader != null && ticketLeader == moneyLeader) {
      final tickets = ticketLeader == publicHome
          ? publicSplit.homeTickets
          : publicSplit.awayTickets;
      final money = ticketLeader == publicHome
          ? publicSplit.homeMoney
          : publicSplit.awayMoney;
      if ((tickets - money).abs() >= 10) {
        ticketMoney =
            'The $ticketLeader have ${_percent(tickets)} of the bets and ${_percent(money)} of the money. '
            'The dollars are more lopsided than the number of bets.';
        ticketsDisagree = true;
      } else {
        ticketMoney = 'Bets and money both lean toward the $ticketLeader.';
      }
    }
  }

  if (reverseLine != null) detail.add(reverseLine);
  if (ticketMoney != null) detail.add(ticketMoney);
  detail.add('This is a signal, not a pick.');

  final moveAbs = openLine == null || nowLine == null
      ? 0.0
      : (nowLine - openLine).abs();
  var clarity = 0;
  if (reverseLine != null) clarity += 100;
  if (steam != null) clarity += 60;
  if (gapPoints + 1e-9 >= 1) {
    clarity += 40;
  } else if (gapPoints + 1e-9 >= sharpMovePoints) {
    clarity += 15;
  }
  if (moveAbs + 1e-9 >= 1) {
    clarity += 20;
  } else if (moveAbs + 1e-9 >= sharpMovePoints) {
    clarity += 10;
  }
  if (ticketsDisagree) clarity += 25;
  clarity += (moveAbs * 2).round();

  final oneLine = _oneLine(
    reverseShort: reverseShort,
    steam: steam,
    gapToward: gapToward,
    gapPoints: gapPoints,
    movedToward: movedToward,
    openLine: openLine,
    nowLine: nowLine,
    hasMarket: market.isNotEmpty,
  );

  final sparkLabel = sparkline.length < 2
      ? 'Not enough saved numbers for a line sparkline.'
      : 'Home spread from ${pointsLabel(sparkline.first)} to ${pointsLabel(sparkline.last)}.';

  return SharpRead(
    eventId: event.id,
    away: event.away,
    home: event.home,
    startsAt: event.startsAt,
    oneLine: oneLine,
    detail: detail,
    publicLine: publicLine,
    reverseLine: reverseLine,
    ticketMoney: ticketMoney,
    sparkline: sparkline,
    sparklineLabel: sparkLabel,
    clarity: clarity,
    sample: sample,
  );
}

List<SharpRead> readSlate({
  required List<SportEvent> events,
  required Map<String, List<LineSnapshot>> history,
  required Iterable<OddsQuote> currentQuotes,
  List<PublicSplit> publicSplits = const [],
  bool sample = false,
  DateTime? now,
  DateTime? pricesAt,
}) {
  final reads =
      [
        for (final event in events)
          readSharp(
            event: event,
            history: historyForEvent(event, history),
            currentQuotes: currentQuotes,
            publicSplit: publicSplitFor(event, publicSplits),
            sample: sample,
            now: now,
            pricesAt: pricesAt,
          ),
      ]..sort((a, b) {
        final clarity = b.clarity.compareTo(a.clarity);
        if (clarity != 0) return clarity;
        return a.home.compareTo(b.home);
      });
  return reads;
}

String _oneLine({
  required String? reverseShort,
  required _Steam? steam,
  required String? gapToward,
  required double gapPoints,
  required String? movedToward,
  required double? openLine,
  required double? nowLine,
  required bool hasMarket,
}) {
  if (reverseShort != null) return reverseShort;
  if (steam != null) return 'Fast move to the ${steam.toward}';
  if (gapToward != null && gapPoints + 1e-9 >= sharpMovePoints) {
    return 'Pinnacle ${magnitude(gapPoints)} to the $gapToward';
  }
  if (movedToward != null && openLine != null && nowLine != null) {
    return '$movedToward ${pointsLabel(openLine)} to ${pointsLabel(nowLine)}';
  }
  if (!hasMarket) return 'No saved spread';
  return 'No clear move';
}

class _PointAt {
  const _PointAt(this.at, this.point);
  final DateTime at;
  final double point;
}

class _BookMove {
  const _BookMove({
    required this.bookId,
    required this.at,
    required this.previousAt,
    required this.from,
    required this.to,
  });

  final String bookId;
  final DateTime at;
  final DateTime previousAt;
  final double from;
  final double to;

  double get delta => to - from;
  bool get fast =>
      !at.difference(previousAt).isNegative &&
      at.difference(previousAt) <= steamWindow;
}

class _Steam {
  const _Steam({
    required this.books,
    required this.toward,
    required this.points,
  });

  final List<String> books;
  final String toward;
  final double points;
}

List<_PointAt> _series(
  List<LineSnapshot> shots,
  SportEvent event, {
  required bool sharp,
}) {
  final points = <_PointAt>[];
  for (final shot in shots) {
    final values = <double>[];
    final books = shot.prices.map((price) => price.bookId).toSet();
    for (final book in books) {
      if (sharp && book != sharpReferenceBook) continue;
      if (!sharp && book == sharpReferenceBook) continue;
      final point = _homeSpread(shot.prices, book, event.home, event.away);
      if (point != null) values.add(point);
    }
    if (values.isEmpty) continue;
    points.add(_PointAt(shot.at, _median(values)));
  }
  return points;
}

List<_PointAt> _totalSeries(List<LineSnapshot> shots, SportEvent event) {
  final points = <_PointAt>[];
  for (final shot in shots) {
    final values = <double>[];
    final books = shot.prices
        .map((price) => price.bookId)
        .where((book) => book != sharpReferenceBook)
        .toSet();
    for (final book in books) {
      final point = _total(shot.prices, book);
      if (point != null) values.add(point);
    }
    if (values.isEmpty) continue;
    points.add(_PointAt(shot.at, _median(values)));
  }
  return points;
}

List<_BookMove> _bookMoves(List<LineSnapshot> shots, SportEvent event) {
  final previous = <String, _PointAt>{};
  final moves = <_BookMove>[];
  for (final shot in shots) {
    final books = shot.prices
        .map((price) => price.bookId)
        .where((book) => book != sharpReferenceBook && book.isNotEmpty)
        .toSet();
    for (final book in books) {
      final point = _homeSpread(shot.prices, book, event.home, event.away);
      if (point == null) continue;
      final prior = previous[book];
      if (prior != null &&
          (point - prior.point).abs() + 1e-9 >= sharpMovePoints) {
        moves.add(
          _BookMove(
            bookId: book,
            at: shot.at,
            previousAt: prior.at,
            from: prior.point,
            to: point,
          ),
        );
      }
      previous[book] = _PointAt(shot.at, point);
    }
  }
  moves.sort((a, b) {
    final time = a.at.compareTo(b.at);
    if (time != 0) return time;
    return bookLabel(a.bookId)
        .toLowerCase()
        .compareTo(bookLabel(b.bookId).toLowerCase());
  });
  return moves;
}

_Steam? _steam(List<_BookMove> moves) {
  final fast = moves.where((move) => move.fast).toList();
  if (fast.length < steamBookCount) return null;
  _Steam? best;
  var bestScore = 0;
  for (var start = 0; start < fast.length; start++) {
    final window = <_BookMove>[];
    for (var index = start; index < fast.length; index++) {
      final gap = fast[index].at.difference(fast[start].at);
      if (gap.isNegative || gap > steamWindow) break;
      window.add(fast[index]);
    }
    for (final sign in const [-1, 1]) {
      final same = window.where((move) => move.delta.sign == sign).toList();
      final books = same.map((move) => move.bookId).toSet();
      if (books.length < steamBookCount) continue;
      final points = same
          .map((move) => move.delta.abs())
          .reduce((a, b) => a > b ? a : b);
      final score = books.length * 10 + (points * 2).round();
      if (score >= bestScore) {
        bestScore = score;
        best = _Steam(
          books: books.toList(),
          toward: sign < 0 ? 'home-side' : 'away-side',
          points: points,
        );
      }
    }
  }
  if (best == null) return null;
  // The toward label needs the team nickname, which _steam does not know.
  // Callers replace home-side / away-side. Kept here only as a placeholder
  // until _steam is wrapped below.
  return best;
}

/// Steam with team names. Recomputed here so the placeholder does not leak.
_Steam? _steamFor(List<_BookMove> moves, String home, String away) {
  final raw = _steam(moves);
  if (raw == null) return null;
  return _Steam(
    books: raw.books,
    toward: raw.toward == 'home-side' ? home : away,
    points: raw.points,
  );
}

String _firstMoverSentence(List<_BookMove> moves) {
  if (moves.isEmpty) {
    return 'No book moved half a point or more, so there is no first mover.';
  }
  final firstAt = moves.first.at;
  final first = moves.where((move) => move.at == firstAt).toList();
  final names = first.map((move) => bookLabel(move.bookId)).toList()
    ..sort(_nameSort);
  if (names.length > 1) {
    return '${_join(names)} all changed in the same snapshot, so this history cannot say which book moved first.';
  }
  final lead = first.single;
  final rest = moves.where((move) => move.at.isAfter(firstAt)).toList();
  final leadSentence =
      '${bookLabel(lead.bookId)} moved first in these snapshots, from ${pointsLabel(lead.from)} to ${pointsLabel(lead.to)}.';
  if (rest.isEmpty) return leadSentence;
  final nextAt = rest.first.at;
  final next = rest.where((move) => move.at == nextAt).toList();
  final nextNames = next.map((move) => bookLabel(move.bookId)).toList()
    ..sort(_nameSort);
  if (nextNames.length == 1) {
    return '$leadSentence ${nextNames.single} moved in a later snapshot.';
  }
  return '$leadSentence ${_join(nextNames)} moved together in a later snapshot, so this history cannot say which of those was first.';
}

double? _homeSpread(
  List<LinePrice> prices,
  String bookId,
  String home,
  String away,
) {
  final homePoint = _featuredPoint(
    prices.where(
      (price) =>
          price.bookId == bookId &&
          price.market == 'spreads' &&
          price.outcome == home &&
          price.usable &&
          price.point != null,
    ),
  );
  if (homePoint != null) return homePoint;
  final awayPoint = _featuredPoint(
    prices.where(
      (price) =>
          price.bookId == bookId &&
          price.market == 'spreads' &&
          price.outcome == away &&
          price.usable &&
          price.point != null,
    ),
  );
  if (awayPoint == null) return null;
  return -awayPoint;
}

String? _earlierGap(
  List<LineSnapshot> shots,
  SportEvent event,
  String homeNick,
  String awayNick,
  double currentGap,
) {
  String? toward;
  var biggest = currentGap;
  var earlier = false;
  for (var index = 0; index < shots.length; index++) {
    final shot = shots[index];
    final us = <double>[];
    double? pin;
    final books = shot.prices.map((price) => price.bookId).toSet();
    for (final book in books) {
      final point = _homeSpread(shot.prices, book, event.home, event.away);
      if (point == null) continue;
      if (book == sharpReferenceBook) {
        pin = point;
      } else {
        us.add(point);
      }
    }
    if (us.isEmpty || pin == null) continue;
    final gap = _median(us) - pin;
    if (gap.abs() > biggest + 0.05) {
      biggest = gap.abs();
      toward = gap > 0 ? homeNick : awayNick;
      earlier = index < shots.length - 1;
    }
  }
  if (!earlier || toward == null || biggest + 1e-9 < sharpMovePoints) {
    return null;
  }
  return 'Earlier, Pinnacle had the $toward ${magnitude(biggest)} more favored than the US books.';
}

double? _total(List<LinePrice> prices, String bookId) {
  final over = _featuredPoint(
    prices.where(
      (price) =>
          price.bookId == bookId &&
          price.market == 'totals' &&
          price.outcome == 'Over' &&
          price.usable &&
          price.point != null,
    ),
  );
  if (over != null) return over;
  return _featuredPoint(
    prices.where(
      (price) =>
          price.bookId == bookId &&
          price.market == 'totals' &&
          price.outcome == 'Under' &&
          price.usable &&
          price.point != null,
    ),
  );
}

double? _featuredPoint(Iterable<LinePrice> prices) {
  LinePrice? best;
  for (final price in prices) {
    if (best == null ||
        (price.decimal - _evenDecimal).abs() <
            (best.decimal - _evenDecimal).abs() - 1e-9) {
      best = price;
    }
  }
  return best?.point;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

String clubNickname(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return name;
  return parts.last;
}

String bookLabel(String bookId) => switch (bookId) {
  'pinnacle' => 'Pinnacle',
  'fanduel' => 'FanDuel',
  'draftkings' => 'DraftKings',
  'betmgm' => 'BetMGM',
  'caesars' || 'williamhill_us' => 'Caesars',
  'bet365' => 'bet365',
  'fanatics' => 'Fanatics',
  'betrivers' => 'BetRivers',
  'hardrock' || 'hardrockbet' => 'Hard Rock Bet',
  'espnbet' || 'thescore' => 'theScore Bet',
  'ballybet' => 'Bally Bet',
  'fliff' => 'Fliff',
  _ => bookId,
};

String pointsLabel(double value) {
  final rounded = (value * 100).round() / 100;
  if (rounded.abs() < 0.001) return '0';
  final abs = rounded.abs();
  final digits = abs == abs.roundToDouble()
      ? 0
      : ((abs * 10).roundToDouble() - abs * 10).abs() < 0.001
      ? 1
      : 2;
  final text = abs.toStringAsFixed(digits);
  return rounded > 0 ? '+$text' : '-$text';
}

String magnitude(double points) {
  final abs = ((points.abs()) * 100).round() / 100;
  if ((abs - 0.5).abs() < 0.001) return 'a half point';
  if ((abs - 1).abs() < 0.001) return '1 point';
  final text = abs == abs.roundToDouble()
      ? abs.toStringAsFixed(0)
      : abs.toStringAsFixed(1);
  return '$text points';
}

String _percent(double value) => '${value.round()}%';

int _nameSort(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

String _join(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.single;
  if (names.length == 2) return '${names[0]} and ${names[1]}';
  return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
}
