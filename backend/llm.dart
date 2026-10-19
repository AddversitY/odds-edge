import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:odds_edge/domain/assistant.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/research.dart';

/// OpenAI-compatible xAI Responses API. The key is supplied by the server.
final xaiResponsesEndpoint = Uri.https('api.x.ai', '/v1/responses');

const defaultXaiModel = 'grok-4.7';

const assistantInstructions = '''
You are the Odds Edge transparent research assistant. You explain or challenge research using only the JSON inputs in the user message.

Grounding:
- Use only the provided inputs. Do not use outside knowledge, memory of teams, players, injuries, weather, news, or markets.
- Never invent statistics, odds, prices, records, probabilities, or dates. If a number is not in the provided inputs, say that it was not provided.
- If an input id is listed under notProvided, do not cite it and do not guess its contents.
- User assumptions are assumptions, not measurements. Hypothetical expected value is conditional on those assumptions. It is not a validated forecast and it is not evidence of an edge.
- A selection without a frozen quote is the on-screen research subject, not a live price.

Uncertainty and responsible gambling:
- Clearly flag uncertainty and missing inputs.
- Do not guarantee a win, a profit, or a favorable outcome. Do not tell the user to place, increase, or remove a bet.
- Sports results are uncertain. This is research commentary, not a recommendation.

Response format:
- Return one JSON object and nothing else: {"answer":"...","cited":["input_id"]}
- cited must list only provided input ids you actually used. Allowed ids are frozen_quote, team_evidence, player_evidence, assumptions, and question.
- The answer is plain language. Do not present it as a sourced fact or a model forecast.
- Mode explain: describe what the provided inputs say and what they do not say.
- Mode challenge: point out gaps, sensitivity, and ways the assumption-based conclusion can fail, without inventing counter-evidence.
''';

String xaiModel(String? raw) {
  final model = (raw ?? '').trim();
  if (RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(model)) return model;
  return defaultXaiModel;
}

class AssistantHttpCall {
  const AssistantHttpCall({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class AssistantHttpResult {
  const AssistantHttpResult({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

/// Same dart:io client style as the odds provider adapter.
Future<AssistantHttpResult> postWithHttpClient(AssistantHttpCall call) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client
        .postUrl(call.uri)
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    call.headers.forEach(request.headers.set);
    request.headers.contentType = ContentType.json;
    request.write(call.body);
    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.add(chunk);
      if (bytes.length > 1000000) {
        throw StateError('Assistant request failed or timed out.');
      }
    }
    return AssistantHttpResult(
      statusCode: response.statusCode,
      body: utf8.decode(bytes.takeBytes()),
    );
  } on StateError {
    rethrow;
  } catch (_) {
    // Never include the URL, query string, or underlying HTTP error.
    throw StateError('Assistant request failed or timed out.');
  } finally {
    client.close(force: true);
  }
}

class XaiAssistant {
  XaiAssistant({
    required String apiKey,
    String? model,
    Uri? endpoint,
    this.post = postWithHttpClient,
  }) : apiKey = apiKey.trim(),
       model = xaiModel(model),
       endpoint = endpoint ?? xaiResponsesEndpoint;

  final String apiKey, model;
  final Uri endpoint;
  final Future<AssistantHttpResult> Function(AssistantHttpCall call) post;
  bool get configured => apiKey.isNotEmpty;

  Future<AssistantReply> answer(Map<String, dynamic> payload) async {
    final prepared = _prepare(payload);
    if (!configured) return AssistantReply.unavailable;
    try {
      final user = _scrub(_encode(prepared.prompt));
      final call = AssistantHttpCall(
        uri: endpoint,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $apiKey',
          HttpHeaders.acceptHeader: 'application/json',
        },
        body: _scrub(
          jsonEncode({
            'model': model,
            'instructions': assistantInstructions,
            'input': [
              {'role': 'user', 'content': user},
            ],
            'search_parameters': {'mode': 'off'},
            'store': false,
            'temperature': 0.2,
          }),
        ),
      );
      if (call.uri.query.isNotEmpty) {
        throw StateError('Assistant request failed or timed out.');
      }
      final result = await post(call).timeout(const Duration(seconds: 25));
      if (result.statusCode != 200) return AssistantReply.unavailable;
      final text = extractAssistantOutputText(jsonDecode(result.body));
      final parsed = _parseModelJson(text, prepared.providedIds);
      final answer = _publicAnswer(parsed.answer);
      if (answer.isEmpty) return AssistantReply.unavailable;
      return AssistantReply(
        available: true,
        answer: answer,
        cited: parsed.cited,
      );
    } catch (_) {
      return AssistantReply.unavailable;
    }
  }

  String _scrub(String value) =>
      apiKey.isEmpty ? value : value.replaceAll(apiKey, '[redacted]');

  String _publicAnswer(String answer) {
    var text = _scrub(answer).trim();
    text = text.replaceAll(
      RegExp(r'https?:\/\/\S*x\.ai\S*', caseSensitive: false),
      '[redacted]',
    );
    text = text.replaceAll('XAI_API_KEY', '[redacted]');
    return text.trim();
  }
}

class _Prepared {
  const _Prepared(this.prompt, this.providedIds);
  final Map<String, Object?> prompt;
  final Set<String> providedIds;
}

_Prepared _prepare(Map<String, dynamic> payload) {
  try {
    final mode = payload['mode'];
    if (mode is! String || !assistantModes.contains(mode)) {
      throw const FormatException('Invalid request');
    }
    final questionRaw = payload['question'] ?? '';
    if (questionRaw is! String || questionRaw.trim().length > 500) {
      throw const FormatException('Invalid request');
    }
    final question = questionRaw.trim();
    final selection = _selection(payload['selection']);
    final quotePayload = payload['quote'];
    final eventPayload = payload['event'];
    OddsQuote? quote;
    SportEvent? event;
    if (quotePayload != null || eventPayload != null) {
      if (quotePayload is! Map || eventPayload is! Map) {
        throw const FormatException('Invalid request');
      }
      quote = OddsQuote.fromJson(Map<String, dynamic>.from(quotePayload));
      event = SportEvent.fromJson(Map<String, dynamic>.from(eventPayload));
      if (quote.selection.eventId != event.id ||
          selection['identity'] != quote.selection.key ||
          selection['label'] != quote.selection.label ||
          selection['matchup'] != '${event.away} at ${event.home}' ||
          selection['demo'] != quote.demo ||
          ((selection['price'] as num) - quote.decimal).abs() > 1e-9) {
        throw const FormatException('Invalid request');
      }
    }
    final assumptions = ResearchAssumptions.fromJson(
      Map<String, dynamic>.from(payload['assumptions'] as Map),
    );
    final teamEvidence = _evidence(payload['teamEvidence']);
    final playerEvidence = _evidence(payload['playerEvidence']);
    final frozen = <String, Object?>{
      'selection': selection,
      'note': quote == null
          ? 'No frozen market quote was provided. This is the on-screen research subject, not a live price.'
          : 'Frozen captured quote. It is not a promise that this price is still offered.',
      if (quote != null) 'quote': quote.toJson(),
      if (event != null) 'event': event.toJson(),
    };
    final provided = <String, Object?>{
      'frozen_quote': frozen,
      'assumptions': assumptions.toJson(),
      if (teamEvidence.isNotEmpty) 'team_evidence': teamEvidence,
      if (playerEvidence.isNotEmpty) 'player_evidence': playerEvidence,
      if (question.isNotEmpty) 'question': question,
    };
    return _Prepared({
      'mode': mode,
      'providedInputs': provided,
      'notProvided': [
        if (teamEvidence.isEmpty) 'team_evidence',
        if (playerEvidence.isEmpty) 'player_evidence',
        if (question.isEmpty) 'question',
      ],
    }, provided.keys.toSet());
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Invalid request');
  }
}

Map<String, Object?> _selection(Object? raw) {
  if (raw is! Map) throw const FormatException('Invalid request');
  final json = Map<String, dynamic>.from(raw);
  final label = json['label'];
  final matchup = json['matchup'];
  final identity = json['identity'];
  final price = json['price'];
  final demo = json['demo'];
  if (label is! String ||
      label.isEmpty ||
      label.length > 200 ||
      matchup is! String ||
      matchup.isEmpty ||
      matchup.length > 200 ||
      identity is! String ||
      identity.isEmpty ||
      identity.length > 2000 ||
      price is! num ||
      !price.isFinite ||
      price <= 1 ||
      demo is! bool) {
    throw const FormatException('Invalid request');
  }
  return {
    'label': label,
    'matchup': matchup,
    'price': price,
    'demo': demo,
    'identity': identity,
  };
}

List<Map<String, Object?>> _evidence(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List || raw.length > 12) {
    throw const FormatException('Invalid request');
  }
  final result = <Map<String, Object?>>[];
  for (final item in raw) {
    if (item is! Map) throw const FormatException('Invalid request');
    result.add(_map(_asMap(item), 0));
  }
  return result;
}

Map<String, Object?> _map(Map<String, dynamic> raw, int depth) {
  if (raw.length > 40 || depth > 4) {
    throw const FormatException('Invalid request');
  }
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key.isEmpty || entry.key.length > 80) {
      throw const FormatException('Invalid request');
    }
    result[entry.key] = _value(entry.value, depth + 1);
  }
  return result;
}

Object? _value(Object? value, int depth) {
  if (value == null || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) throw const FormatException('Invalid request');
    return value;
  }
  if (value is String) {
    if (value.length > 500) throw const FormatException('Invalid request');
    return value;
  }
  if (depth > 4) throw const FormatException('Invalid request');
  if (value is List) {
    if (value.length > 40) throw const FormatException('Invalid request');
    return [for (final item in value) _value(item, depth + 1)];
  }
  if (value is Map) return _map(_asMap(value), depth);
  throw const FormatException('Invalid request');
}

Map<String, dynamic> _asMap(Map raw) => Map<String, dynamic>.from(raw);

String _encode(Object? value) => jsonEncode(value);

/// Reads `output[].content[]` items whose type is `output_text`.
String extractAssistantOutputText(Object? decoded) {
  if (decoded is! Map) {
    throw StateError('Assistant request failed or timed out.');
  }
  final output = decoded['output'];
  if (output is! List) {
    throw StateError('Assistant request failed or timed out.');
  }
  final buffer = StringBuffer();
  for (final item in output) {
    if (item is! Map) continue;
    final content = item['content'];
    if (content is! List) continue;
    for (final part in content) {
      if (part is Map &&
          part['type'] == 'output_text' &&
          part['text'] is String) {
        buffer.write(part['text']);
      }
    }
  }
  final text = buffer.toString().trim();
  if (text.isEmpty) throw StateError('Assistant request failed or timed out.');
  return text;
}

({String answer, List<String> cited}) _parseModelJson(
  String text,
  Set<String> provided,
) {
  final fenced = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$')
      .firstMatch(text.trim());
  final decoded = jsonDecode(fenced?.group(1) ?? text);
  if (decoded is! Map) {
    throw StateError('Assistant request failed or timed out.');
  }
  final answer = decoded['answer'];
  final citedRaw = decoded['cited'];
  if (answer is! String || answer.trim().isEmpty || answer.length > 4000) {
    throw StateError('Assistant request failed or timed out.');
  }
  if (citedRaw is! List) {
    throw StateError('Assistant request failed or timed out.');
  }
  final cited = <String>[];
  for (final id in citedRaw) {
    if (id is String && provided.contains(id) && !cited.contains(id)) {
      cited.add(id);
    }
  }
  return (answer: answer.trim(), cited: cited);
}
