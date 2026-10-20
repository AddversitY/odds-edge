/// AI commentary contract. This is not a fact, a quote, or a user assumption.
const assistantModes = {'explain', 'challenge'};

const assistantInputLabels = {
  'frozen_quote': 'Frozen quote and selection',
  'team_evidence': 'Team evidence',
  'player_evidence': 'Player evidence',
  'assumptions': 'Your assumptions',
  'question': 'Your question',
};

class AssistantRequest {
  const AssistantRequest({
    required this.mode,
    required this.selection,
    required this.assumptions,
    this.question = '',
    this.quote,
    this.event,
    this.teamEvidence = const [],
    this.playerEvidence = const [],
  });

  final String mode, question;
  final Map<String, dynamic> selection, assumptions;
  final Map<String, dynamic>? quote, event;
  final List<Map<String, dynamic>> teamEvidence, playerEvidence;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'question': question,
    'selection': selection,
    'quote': quote,
    'event': event,
    'assumptions': assumptions,
    'teamEvidence': teamEvidence,
    'playerEvidence': playerEvidence,
  };
}

class AssistantReply {
  const AssistantReply({
    required this.available,
    required this.answer,
    required this.cited,
  });

  static const unavailable = AssistantReply(
    available: false,
    answer: 'assistant unavailable',
    cited: [],
  );

  final bool available;
  final String answer;
  final List<String> cited;

  Map<String, dynamic> toJson() => {
    'available': available,
    'answer': answer,
    'cited': cited,
  };

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    final available = json['available'];
    final answer = json['answer'];
    final citedRaw = json['cited'];
    if (available is! bool ||
        answer is! String ||
        answer.length > 4000 ||
        citedRaw is! List) {
      throw const FormatException('Invalid assistant reply');
    }
    if (available && answer.trim().isEmpty) {
      throw const FormatException('Invalid assistant reply');
    }
    final cited = <String>[];
    if (available) {
      for (final id in citedRaw) {
        if (id is String &&
            assistantInputLabels.containsKey(id) &&
            !cited.contains(id)) {
          cited.add(id);
        }
      }
    }
    return AssistantReply(available: available, answer: answer, cited: cited);
  }
}

/// Saved with a research snapshot, in its own field.
class AssistantNote {
  const AssistantNote({
    required this.generatedAt,
    required this.mode,
    required this.question,
    required this.answer,
    required this.cited,
  });

  final DateTime generatedAt;
  final String mode, question, answer;
  final List<String> cited;

  Map<String, dynamic> toJson() => {
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'mode': mode,
    'question': question,
    'answer': answer,
    'cited': cited,
  };

  factory AssistantNote.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'];
    final question = json['question'];
    final answer = json['answer'];
    final citedRaw = json['cited'];
    if (mode is! String ||
        !assistantModes.contains(mode) ||
        question is! String ||
        question.length > 500 ||
        answer is! String ||
        answer.trim().isEmpty ||
        answer.length > 4000 ||
        citedRaw is! List) {
      throw const FormatException('Invalid assistant note');
    }
    final cited = <String>[];
    for (final id in citedRaw) {
      if (id is! String ||
          !assistantInputLabels.containsKey(id) ||
          cited.contains(id)) {
        throw const FormatException('Invalid assistant note');
      }
      cited.add(id);
    }
    return AssistantNote(
      generatedAt: DateTime.parse(json['generatedAt'] as String).toUtc(),
      mode: mode,
      question: question,
      answer: answer,
      cited: cited,
    );
  }
}
