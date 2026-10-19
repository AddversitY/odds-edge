import 'assistant.dart';
import 'odds.dart';

/// Fixed teaching fixture, not a live event or calibrated predictive model.
class ResearchAssumptions {
  const ResearchAssumptions({
    this.performance = 2,
    this.availability = -1.5,
    this.environment = 1,
    this.baseProbability = baseline,
    this.push = 0,
  });
  final double performance, availability, environment;
  final double baseProbability, push;
  static const baseline = .48;
  static const decimalOdds = 2.25;
  static const modelVersion = 'illustrative-additive-v2';
  double get probability =>
      (baseProbability + (performance + availability + environment) / 100)
          .clamp(.01, .99 * (1 - push));
  double get ev => evAt(decimalOdds);
  double evAt(double price) => expectedValue(price, probability, push: push);
  ResearchAssumptions copyWith({
    double? performance,
    double? availability,
    double? environment,
    double? baseProbability,
    double? push,
  }) => ResearchAssumptions(
    performance: performance ?? this.performance,
    availability: availability ?? this.availability,
    environment: environment ?? this.environment,
    baseProbability: baseProbability ?? this.baseProbability,
    push: push ?? this.push,
  );
  List<ResearchScenario> get scenarios => [
    ResearchScenario('Your assumptions', probability),
    ResearchScenario(
      'Lower efficiency (−4 pp)',
      (probability - .04).clamp(.01, .99),
    ),
    ResearchScenario(
      'Slower pace (−7 pp)',
      (probability - .07).clamp(.01, .99),
    ),
    ResearchScenario(
      'Higher injury impact (−9 pp)',
      (probability - .09).clamp(.01, .99),
    ),
  ];
  bool get sensitive =>
      scenarios.any(
        (s) => expectedValue(decimalOdds, s.probability, push: push) > 0,
      ) &&
      scenarios.any(
        (s) => expectedValue(decimalOdds, s.probability, push: push) <= 0,
      );
  Map<String, dynamic> toJson() => {
    'performance': performance,
    'availability': availability,
    'environment': environment,
    'baseProbability': baseProbability,
    'push': push,
  };
  factory ResearchAssumptions.fromJson(Map<String, dynamic> j) {
    double value(String key) {
      final v = (j[key] as num).toDouble();
      if (!v.isFinite || v < -10 || v > 10) {
        throw const FormatException('Invalid assumption');
      }
      return v;
    }

    final base = (j['baseProbability'] as num?)?.toDouble() ?? baseline;
    final push = (j['push'] as num?)?.toDouble() ?? 0;
    if (!base.isFinite ||
        base < .01 ||
        base > .99 ||
        !push.isFinite ||
        push < 0 ||
        push > .5) {
      throw const FormatException('Invalid probability');
    }
    return ResearchAssumptions(
      baseProbability: base,
      push: push,
      performance: value('performance'),
      availability: value('availability'),
      environment: value('environment'),
    );
  }
}

class ResearchScenario {
  const ResearchScenario(this.name, this.probability);
  final String name;
  final double probability;
  double get ev => expectedValue(ResearchAssumptions.decimalOdds, probability);
}

class SavedResearch {
  const SavedResearch({
    required this.savedAt,
    required this.thesis,
    required this.assumptions,
    this.name = '',
    this.context = const ResearchContext(),
    this.assistant,
  });
  final DateTime savedAt;
  final String thesis;
  final ResearchAssumptions assumptions;
  final String name;
  final ResearchContext context;

  /// Model commentary. Never mixed into [thesis] or [assumptions].
  final AssistantNote? assistant;
  double get ev => assumptions.evAt(context.price);
  String get title => name.isEmpty ? context.label : name;
  Map<String, dynamic> toJson() => {
    'schema': 2,
    'name': name,
    'context': context.toJson(),
    'modelVersion': ResearchAssumptions.modelVersion,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'thesis': thesis,
    'fixture': context.event?.id ?? 'synthetic-detroit-green-bay',
    'selection': context.label,
    'decimalOdds': context.price,
    'baseline': assumptions.baseProbability,
    'dataOrigin': context.demo
        ? 'demonstration'
        : 'captured_quote_user_assumptions',
    'winProbability': assumptions.probability,
    'expectedValue': ev,
    'assumptions': assumptions.toJson(),
    if (assistant != null) 'assistant': assistant!.toJson(),
  };
  factory SavedResearch.fromJson(Map<String, dynamic> j) {
    if (j['schema'] == 2) {
      if (![
        'illustrative-additive-v1',
        ResearchAssumptions.modelVersion,
      ].contains(j['modelVersion'])) {
        throw const FormatException('Unknown model');
      }
      final result = SavedResearch(
        savedAt: DateTime.parse(j['savedAt']),
        thesis: j['thesis'],
        name: j['name'] ?? '',
        assumptions: ResearchAssumptions.fromJson(j['assumptions']),
        context: ResearchContext.fromJson(j['context']),
        assistant: j['assistant'] == null
            ? null
            : AssistantNote.fromJson(
                Map<String, dynamic>.from(j['assistant'] as Map),
              ),
      );
      if (result.name.length > 100 || result.thesis.length > 1000) {
        throw const FormatException('Research text too long');
      }
      return result;
    }
    if (j['schema'] != 1 ||
        ![
          'illustrative-additive-v1',
          ResearchAssumptions.modelVersion,
        ].contains(j['modelVersion']) ||
        j['dataOrigin'] != 'demonstration' ||
        j['fixture'] != 'synthetic-detroit-green-bay' ||
        j['decimalOdds'] != ResearchAssumptions.decimalOdds ||
        j['baseline'] != ResearchAssumptions.baseline) {
      throw const FormatException('Unsupported research record');
    }
    return SavedResearch(
      savedAt: DateTime.parse(j['savedAt']),
      thesis: j['thesis'],
      assumptions: ResearchAssumptions.fromJson(j['assumptions']),
    );
  }
}

/// Frozen quote provenance. A saved price is never treated as a current offer.
class ResearchContext {
  const ResearchContext({this.quote, this.event});
  final OddsQuote? quote;
  final SportEvent? event;
  double get price => quote?.decimal ?? ResearchAssumptions.decimalOdds;
  String get label => quote?.selection.label ?? 'Detroit moneyline';
  String get matchup => event == null
      ? 'Detroit at Green Bay'
      : '${event!.away} at ${event!.home}';
  String get identity => quote?.selection.key ?? 'synthetic-detroit-green-bay';
  bool get demo => quote?.demo ?? true;
  Map<String, dynamic> toJson() => {
    'quote': quote?.toJson(),
    'event': event?.toJson(),
  };
  factory ResearchContext.fromJson(Map<String, dynamic> j) {
    final quote = j['quote'] == null ? null : OddsQuote.fromJson(j['quote']);
    final event = j['event'] == null ? null : SportEvent.fromJson(j['event']);
    if ((quote == null) != (event == null) ||
        (quote != null && quote.selection.eventId != event!.id)) {
      throw const FormatException('Mismatched research event');
    }
    return ResearchContext(quote: quote, event: event);
  }
}
