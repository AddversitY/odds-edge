import 'dart:convert';
import 'dart:io';

/// Credits The Odds API charges for one odds request.
///
/// Published rule: cost = markets × regions. A `bookmakers` list of at most
/// 10 books is billed as a single region, so three markets across `us` and
/// `us2` cost 6 credits, while the same markets with a bookmaker list cost 3.
/// The events endpoint is free and is not passed through this function.
int oddsRequestCost({
  required int markets,
  int regions = 1,
  bool bookmakers = false,
}) {
  if (markets < 0 || regions < 0) {
    throw ArgumentError('Market and region counts cannot be negative.');
  }
  if (markets == 0) return 0;
  final billedRegions = bookmakers ? 1 : regions;
  return markets * billedRegions;
}

/// Ten major US books on The Odds API. Offshore skins are intentionally absent.
///
/// Caesars (`williamhill_us`) and Fanatics are on this list, but a free-tier
/// NFL response may simply omit them. A missing book is not an error.
const defaultUsBookmakers = <String>[
  'draftkings',
  'fanduel',
  'betmgm',
  'williamhill_us',
  'espnbet',
  'fanatics',
  'betrivers',
  'hardrockbet',
  'ballybet',
  'fliff',
];

const supportedOddsMarkets = <String>['h2h', 'spreads', 'totals'];

List<String> resolveBookmakers(Iterable<String>? raw) {
  if (raw == null) return List<String>.from(defaultUsBookmakers);
  final values = [
    for (final item in raw)
      if (item.trim().isNotEmpty) item.trim().toLowerCase(),
  ];
  if (values.isEmpty) return List<String>.from(defaultUsBookmakers);
  final pattern = RegExp(r'^[a-z0-9_]+$');
  if (values.any((id) => !pattern.hasMatch(id))) {
    throw const FormatException(
      'Bookmaker ids must look like draftkings or williamhill_us.',
    );
  }
  if (values.toSet().length != values.length) {
    throw const FormatException('The bookmaker list contains duplicates.');
  }
  if (values.length > 10) {
    throw const FormatException(
      'The Odds API accepts at most 10 bookmakers per request.',
    );
  }
  return values;
}

List<String> resolveMarkets(Iterable<String>? raw) {
  if (raw == null) return List<String>.from(supportedOddsMarkets);
  final values = [
    for (final item in raw)
      if (item.trim().isNotEmpty) item.trim().toLowerCase(),
  ];
  if (values.isEmpty) return List<String>.from(supportedOddsMarkets);
  if (values.toSet().length != values.length ||
      values.any((market) => !supportedOddsMarkets.contains(market))) {
    throw const FormatException(
      'ODDS_API_MARKETS must be a comma-separated subset of h2h,spreads,totals.',
    );
  }
  return values;
}

/// When the shared backend should spend credits on The Odds API.
///
/// One daily snapshot, plus a refresh about an hour and about 10 minutes
/// before each distinct kickoff. Games that start together share a refresh
/// because one odds call returns the whole slate.
class OddsRefreshSchedule {
  const OddsRefreshSchedule({
    this.dailyUtc = const Duration(hours: 15),
    this.leadTimes = const [Duration(hours: 1), Duration(minutes: 10)],
    this.grace = const Duration(minutes: 20),
    this.coalesce = const Duration(minutes: 10),
  });

  /// Time of day, UTC, for the daily snapshot.
  final Duration dailyUtc;

  /// How long before kickoff to take a snapshot.
  final List<Duration> leadTimes;

  /// How long after a kickoff lead we still take a missed snapshot.
  final Duration grace;

  /// Planned times closer together than this become one request.
  final Duration coalesce;

  String describe() {
    String lead(Duration duration) => duration.inMinutes % 60 == 0
        ? '${duration.inHours}h'
        : '${duration.inMinutes}m';
    final hours = dailyUtc.inHours.toString().padLeft(2, '0');
    final minutes = (dailyUtc.inMinutes % 60).toString().padLeft(2, '0');
    final leads = leadTimes.map(lead).join(' and ');
    return 'Daily snapshot at $hours:$minutes UTC, plus refreshes $leads before kickoff.';
  }

  /// Planned odds-request times in `[from, until)`.
  List<DateTime> slots({
    required DateTime from,
    required DateTime until,
    required List<DateTime> kickoffs,
  }) {
    final start = from.toUtc();
    final end = until.toUtc();
    final raw = <DateTime>[];
    var day = DateTime.utc(start.year, start.month, start.day);
    final lastDay = DateTime.utc(end.year, end.month, end.day);
    while (!day.isAfter(lastDay)) {
      final slot = day.add(dailyUtc);
      if (!slot.isBefore(start) && slot.isBefore(end)) raw.add(slot);
      day = day.add(const Duration(days: 1));
    }
    for (final kickoff in kickoffs) {
      final startAt = kickoff.toUtc();
      for (final lead in leadTimes) {
        final slot = startAt.subtract(lead);
        if (!slot.isBefore(start) && slot.isBefore(end)) raw.add(slot);
      }
    }
    raw.sort();
    return _coalesce(raw);
  }

  /// The earliest planned time that still needs a snapshot, if one is due.
  ///
  /// A daily snapshot can be caught up any later time that same UTC day.
  /// A kickoff snapshot is caught up only inside [grace]. One successful
  /// fetch satisfies every planned time at or before it.
  DateTime? dueSlot({
    required DateTime now,
    required DateTime? lastFetch,
    required List<DateTime> kickoffs,
  }) {
    final current = now.toUtc();
    final candidates = slots(
      from: current.subtract(const Duration(days: 1)),
      until: current.add(const Duration(seconds: 1)),
      kickoffs: kickoffs,
    );
    for (final slot in candidates) {
      if (slot.isAfter(current)) continue;
      if (lastFetch != null && !lastFetch.toUtc().isBefore(slot)) continue;
      final daily = _isDaily(slot);
      if (daily && !_sameUtcDay(slot, current)) continue;
      if (!daily && current.difference(slot) > grace) continue;
      return slot;
    }
    return null;
  }

  List<DateTime> _coalesce(List<DateTime> sorted) {
    final kept = <DateTime>[];
    for (final slot in sorted) {
      if (kept.isNotEmpty) {
        final gap = slot.difference(kept.last);
        if (gap == Duration.zero || gap < coalesce) continue;
      }
      kept.add(slot);
    }
    return kept;
  }

  bool _isDaily(DateTime slot) {
    final day = DateTime.utc(slot.year, slot.month, slot.day);
    return slot == day.add(dailyUtc);
  }

  bool _sameUtcDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Latest credit counters reported by The Odds API response headers.
class CreditObservation {
  const CreditObservation({this.remaining, this.used, this.lastCost});

  final int? remaining;
  final int? used;
  final int? lastCost;

  bool get hasAny => remaining != null || used != null || lastCost != null;

  factory CreditObservation.fromHeaders(Map<String, String> headers) {
    int? read(String name) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == name) {
          return int.tryParse(entry.value.trim());
        }
      }
      return null;
    }

    return CreditObservation(
      remaining: read('x-requests-remaining'),
      used: read('x-requests-used'),
      lastCost: read('x-requests-last'),
    );
  }
}

/// Credits that must stay untouched so the rest of this billing month's
/// scheduled snapshots can still run, plus a small buffer.
int scheduledCreditHold({
  required int scheduledRefreshes,
  required int cost,
  required int buffer,
}) {
  if (scheduledRefreshes < 0 || cost < 0 || buffer < 0) {
    throw ArgumentError('Credit hold inputs cannot be negative.');
  }
  return scheduledRefreshes * cost + buffer;
}

/// Start of the next billing period. [resetDay] is the UTC day the allowance
/// renews (1 means a calendar month). Days after 28 are not used, so every
/// month has the boundary.
DateTime billingPeriodEnd(DateTime now, {int resetDay = 1}) {
  final current = now.toUtc();
  final day = resetDay.clamp(1, 28);
  final thisMonth = DateTime.utc(current.year, current.month, day);
  if (current.isBefore(thisMonth)) return thisMonth;
  return DateTime.utc(current.year, current.month + 1, day);
}

/// Remembers credits from response headers and the buffer that sits on top
/// of the credits reserved for scheduled snapshots.
class CreditLedger {
  CreditLedger({this.reserve = 50, this.file});

  final int reserve;
  final File? file;
  int? remaining;
  int? used;
  int? lastCost;
  DateTime? updatedAt;

  /// [essential] snapshots may spend the last credits. Manual refreshes must
  /// leave at least [protect] credits, or [reserve] when [protect] is omitted.
  bool allowSpend({required int cost, required bool essential, int? protect}) {
    if (cost <= 0) return true;
    final left = remaining;
    if (left == null) return true;
    if (left < cost) return false;
    final floor = protect ?? reserve;
    if (!essential && left - cost < floor) return false;
    return true;
  }

  void apply(
    CreditObservation observation, {
    required DateTime at,
    bool updateLastCost = true,
  }) {
    if (!observation.hasAny) return;
    var changed = false;
    if (observation.remaining != null) {
      remaining = observation.remaining;
      changed = true;
    }
    if (observation.used != null) {
      used = observation.used;
      changed = true;
    }
    // The free events call also reports x-requests-last, usually 0. Only an
    // odds call should replace the last charged amount.
    if (updateLastCost && observation.lastCost != null) {
      lastCost = observation.lastCost;
      changed = true;
    }
    if (changed) updatedAt = at.toUtc();
  }

  Future<void> load() async {
    final source = file;
    if (source == null || !await source.exists()) return;
    try {
      final json = jsonDecode(await source.readAsString());
      if (json is! Map) return;
      remaining = (json['remaining'] as num?)?.toInt();
      used = (json['used'] as num?)?.toInt();
      lastCost = (json['lastCost'] as num?)?.toInt();
      final stamp = json['updatedAt'];
      updatedAt = stamp is String ? DateTime.parse(stamp).toUtc() : null;
    } catch (_) {
      // A damaged counter file should not block startup. The next response
      // header replaces it.
    }
  }

  Future<void> save() async {
    final target = file;
    if (target == null) return;
    await target.parent.create(recursive: true);
    await target.writeAsString(
      jsonEncode({
        'remaining': remaining,
        'used': used,
        'lastCost': lastCost,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'reserve': reserve,
      }),
      flush: true,
    );
  }

  Map<String, Object?> toJson() => {
    'remaining': remaining,
    'used': used,
    'lastCost': lastCost,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'reserve': reserve,
  };
}

class OddsBackendConfig {
  const OddsBackendConfig({
    required this.mode,
    required this.apiKey,
    required this.bookmakers,
    required this.markets,
    required this.verifiedRuleBooks,
    required this.creditReserve,
    required this.onDemandCooldown,
    required this.eventsMaxAge,
    required this.scheduleGrace,
    required this.coalesce,
    required this.dailyUtc,
    required this.leadTimes,
    required this.demoRefreshInterval,
    required this.onDemandDailyCap,
    required this.billingResetDay,
  });

  final String mode;
  final String apiKey;
  final List<String> bookmakers;
  final List<String> markets;
  final Set<String> verifiedRuleBooks;
  final int creditReserve;
  final Duration onDemandCooldown;
  final Duration eventsMaxAge;
  final Duration scheduleGrace;
  final Duration coalesce;
  final Duration dailyUtc;
  final List<Duration> leadTimes;
  final Duration demoRefreshInterval;

  /// Manual refreshes allowed per UTC day. Zero means no daily cap.
  final int onDemandDailyCap;

  /// UTC day of the month when the credit allowance renews.
  final int billingResetDay;

  bool get live => mode == 'the-odds-api';

  factory OddsBackendConfig.fromEnvironment(Map<String, String> env) {
    final mode = env['ODDS_PROVIDER'] ?? 'demo';
    final apiKey = env['THE_ODDS_API_KEY'] ?? '';
    if (mode != 'demo' && mode != 'the-odds-api') {
      throw const FormatException(
        'Set ODDS_PROVIDER to demo or the-odds-api. Real mode needs THE_ODDS_API_KEY on the server.',
      );
    }
    if (mode == 'the-odds-api' && apiKey.isEmpty) {
      throw const FormatException(
        'Set ODDS_PROVIDER to demo or the-odds-api. Real mode needs THE_ODDS_API_KEY on the server.',
      );
    }
    final seconds = int.tryParse(env['ODDS_REFRESH_SECONDS'] ?? '') ?? 60;
    return OddsBackendConfig(
      mode: mode,
      apiKey: apiKey,
      bookmakers: resolveBookmakers(_csv(env['ODDS_API_BOOKMAKERS'])),
      markets: resolveMarkets(_csv(env['ODDS_API_MARKETS'])),
      verifiedRuleBooks: (env['VERIFIED_NFL_RULE_BOOKS'] ?? '')
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet(),
      creditReserve: _intEnv(env, 'ODDS_CREDIT_RESERVE', 50, min: 0),
      onDemandCooldown: Duration(
        seconds: _intEnv(
          env,
          'ODDS_ON_DEMAND_COOLDOWN_SECONDS',
          600,
          min: 0,
          max: 86400,
        ),
      ),
      eventsMaxAge: Duration(
        hours: _intEnv(env, 'ODDS_EVENTS_REFRESH_HOURS', 6, min: 1, max: 48),
      ),
      scheduleGrace: Duration(
        minutes: _intEnv(
          env,
          'ODDS_SCHEDULE_GRACE_MINUTES',
          20,
          min: 1,
          max: 180,
        ),
      ),
      coalesce: Duration(
        minutes: _intEnv(
          env,
          'ODDS_SLOT_COALESCE_MINUTES',
          10,
          min: 0,
          max: 120,
        ),
      ),
      dailyUtc: _dailyUtc(env['ODDS_DAILY_SNAPSHOT_UTC']),
      leadTimes: _leadTimes(env['ODDS_KICKOFF_LEADS']),
      demoRefreshInterval: Duration(seconds: seconds.clamp(30, 3600)),
      onDemandDailyCap: _intEnv(
        env,
        'ODDS_ON_DEMAND_DAILY_CAP',
        6,
        min: 0,
        max: 500,
      ),
      billingResetDay: _intEnv(
        env,
        'ODDS_BILLING_RESET_DAY',
        1,
        min: 1,
        max: 28,
      ),
    );
  }
}

List<String>? _csv(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return raw.split(',');
}

int _intEnv(
  Map<String, String> env,
  String name,
  int fallback, {
  required int min,
  int? max,
}) {
  final raw = env[name];
  if (raw == null || raw.trim().isEmpty) return fallback;
  final value = int.tryParse(raw.trim());
  if (value == null) {
    throw FormatException('$name must be a whole number.');
  }
  if (value < min || (max != null && value > max)) {
    throw FormatException('$name is outside the allowed range.');
  }
  return value;
}

Duration _dailyUtc(String? raw) {
  final text = (raw == null || raw.trim().isEmpty) ? '15:00' : raw.trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (match == null) {
    throw const FormatException(
      'ODDS_DAILY_SNAPSHOT_UTC must look like 15:00.',
    );
  }
  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  if (hours > 23 || minutes > 59) {
    throw const FormatException(
      'ODDS_DAILY_SNAPSHOT_UTC is not a valid UTC time.',
    );
  }
  return Duration(hours: hours, minutes: minutes);
}

List<Duration> _leadTimes(String? raw) {
  final text = (raw == null || raw.trim().isEmpty) ? '60m,10m' : raw.trim();
  final leads = <Duration>[];
  for (final part in text.split(',')) {
    final match = RegExp(r'^(\d+)(m|h)$').firstMatch(part.trim().toLowerCase());
    if (match == null) {
      throw const FormatException('ODDS_KICKOFF_LEADS must look like 60m,10m.');
    }
    final amount = int.parse(match.group(1)!);
    if (amount <= 0) {
      throw const FormatException('ODDS_KICKOFF_LEADS must be greater than 0.');
    }
    leads.add(
      match.group(2) == 'h'
          ? Duration(hours: amount)
          : Duration(minutes: amount),
    );
  }
  return leads;
}
