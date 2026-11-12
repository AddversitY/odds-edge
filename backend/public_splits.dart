import 'package:odds_edge/domain/public_sharp.dart';

/// Public ticket and money percentages.
///
/// No source we checked allows this app to copy those percentages.
/// This payload stays empty on purpose. It does not call the network,
/// and it does not invent a number. See docs/PUBLIC_SHARP.md.
Map<String, Object?> publicSplitsPayload() => {
  'available': false,
  'source': null,
  'attribution': null,
  'games': <Object>[],
  'notice': publicSplitsUnavailableNotice,
};
