import 'package:flutter/foundation.dart';

import 'odds.dart';

/// The parlays the person is building. Keys are selection ids already
/// in the snapshot. The slip does not invent a price for a missing leg.
class ParlaySlip {
  const ParlaySlip({this.selectionKeys = const [], this.stake = 10});

  final List<String> selectionKeys;

  /// Dollars the person typed. The payout is this times the ticket price.
  final double stake;

  bool contains(String key) => selectionKeys.contains(key);

  int get length => selectionKeys.length;

  ParlaySlip add(String key) {
    final id = key.trim();
    if (id.isEmpty || selectionKeys.contains(id)) return this;
    return ParlaySlip(selectionKeys: [...selectionKeys, id], stake: stake);
  }

  ParlaySlip remove(String key) => ParlaySlip(
    selectionKeys: [
      for (final item in selectionKeys)
        if (item != key) item,
    ],
    stake: stake,
  );

  ParlaySlip clear() => ParlaySlip(stake: stake);

  ParlaySlip withStake(double next) {
    if (!next.isFinite || next <= 0) {
      throw ArgumentError('A stake has to be greater than zero.');
    }
    return ParlaySlip(selectionKeys: selectionKeys, stake: next);
  }
}

/// Shared slip for Home, a prop, and the Parlays tab.
class ParlaySlipController extends ChangeNotifier {
  ParlaySlip slip = const ParlaySlip();

  void setSlip(ParlaySlip next) {
    slip = next;
    notifyListeners();
  }

  void add(String key) => setSlip(slip.add(key));

  void remove(String key) => setSlip(slip.remove(key));

  void clear() => setSlip(slip.clear());
}

/// Over and Under of one player, one stat, one number. Those two cannot
/// both win, so they are not a parlay.
bool oppositeSides(Selection left, Selection right) {
  if (left.eventId != right.eventId || left.market != right.market) {
    return false;
  }
  if (left.participant != right.participant || left.point != right.point) {
    return false;
  }
  if (left.period != right.period) return false;
  return left.outcome != right.outcome;
}
