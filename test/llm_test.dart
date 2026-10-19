import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/repository.dart';
import 'package:odds_edge/domain/assistant.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/research.dart';

import '../backend/llm.dart';
import '../backend/providers.dart';
import '../backend/server.dart';
import '../backend/service.dart';

void main() {
  final secret = 'supersecret-key-value';
  Map<String, dynamic> payload({
    String mode = 'explain',
    String question = 'What is missing?',
    bool withEvidence = true,
    bool withQuote = false,
  }) {
    final selection = <String, dynamic>{
      'label': 'Detroit moneyline',
      'matchup': 'Detroit at Green Bay',
      'price': 2.25,
      'demo': true,
      'identity': 'synthetic-detroit-green-bay',
    };
    Map<String, dynamic>? quote;
    Map<String, dynamic>? event;
    if (withQuote) {
      final time = DateTime.utc(2026, 10, 18, 17);
      final frozen = OddsQuote(
        selection: const Selection(
          eventId: 'event-1',
          market: 'h2h',
          outcome: 'Detroit Lions',
        ),
        bookId: 'demo',
        book: 'Demo Book',
        provider: 'demonstration',
        decimal: 2.25,
        sourceAt: time,
        collectedAt: time,
        demo: true,
      );
      final sportEvent = SportEvent(
        'event-1',
        'Green Bay Packers',
        'Detroit Lions',
        time,
      );
      quote = frozen.toJson();
      event = sportEvent.toJson();
      selection['label'] = frozen.selection.label;
      selection['matchup'] = '${sportEvent.away} at ${sportEvent.home}';
      selection['identity'] = frozen.selection.key;
      selection['price'] = frozen.decimal;
      selection['demo'] = frozen.demo;
    }
    return {
      'mode': mode,
      'question': question,
      'selection': selection,
      'quote': quote,
      'event': event,
      'assumptions': const ResearchAssumptions().toJson(),
      'teamEvidence': withEvidence
          ? [
              {
                'team': 'DET',
                'games': 3,
                'pointsFor': 21.5,
                'window': 'last 3 played',
              },
            ]
          : [],
      'playerEvidence': withEvidence
          ? [
              {
                'name': 'Example Player',
                'team': 'DET',
                'stats': {'targets': 8},
              },
            ]
          : [],
    };
  }

  Map<String, Object?> grok(String text) => {
    'output': [
      {
        'type': 'reasoning',
        'content': [
          {'type': 'reasoning_text', 'text': 'hidden chain of thought'},
        ],
      },
      {
        'content': [
          {'type': 'output_text', 'text': text},
          {'type': 'other', 'text': 'ignore this item'},
        ],
      },
    ],
  };

  test('output_text parts are joined and other content is ignored', () {
    expect(
      extractAssistantOutputText({
        'output': [
          {
            'content': [
              {'type': 'reasoning_text', 'text': 'hidden'},
            ],
          },
          {
            'content': [
              {'type': 'output_text', 'text': 'Hello '},
              {'type': 'output_text', 'text': 'there'},
            ],
          },
        ],
      }),
      'Hello there',
    );
    expect(xaiModel(null), defaultXaiModel);
    expect(xaiModel(''), defaultXaiModel);
    expect(xaiModel('grok-4'), 'grok-4');
    expect(xaiModel('not a model'), defaultXaiModel);
    expect(
      XaiAssistant(apiKey: 'k').endpoint,
      Uri.https('api.x.ai', '/v1/responses'),
    );
    expect(XaiAssistant(apiKey: 'k').endpoint.query, isEmpty);
    expect(XaiAssistant(apiKey: 'k').model, defaultXaiModel);
    expect(assistantInstructions, contains('Never invent statistics, odds'));
    expect(assistantInstructions, contains('Clearly flag uncertainty'));
    expect(assistantInstructions, contains('Do not guarantee'));
    expect(assistantInstructions, contains('only the JSON inputs'));
  });

  test(
    'missing key does not call xAI and says assistant unavailable',
    () async {
      var calls = 0;
      final assistant = XaiAssistant(
        apiKey: '   ',
        post: (_) async {
          calls++;
          return const AssistantHttpResult(statusCode: 200, body: '{}');
        },
      );
      final reply = await assistant.answer(payload());
      expect(calls, 0);
      expect(reply.available, isFalse);
      expect(reply.answer, 'assistant unavailable');
      expect(reply.cited, isEmpty);
    },
  );

  test('mock response cites only provided inputs and hides the key', () async {
    AssistantHttpCall? seen;
    final assistant = XaiAssistant(
      apiKey: secret,
      post: (call) async {
        seen = call;
        return AssistantHttpResult(
          statusCode: 200,
          body: jsonEncode(
            grok(
              '{"answer":"The frozen quote and assumptions are the only prices on file. Team pointsFor is 21.5.","cited":["frozen_quote","assumptions","team_evidence","player_evidence","web","https://api.x.ai/v1/responses?api_key=$secret"]}',
            ),
          ),
        );
      },
    );
    final reply = await assistant.answer(payload(question: 'Look at $secret'));
    expect(seen, isNotNull);
    expect(seen!.uri, xaiResponsesEndpoint);
    expect(seen!.uri.query, isEmpty);
    expect(seen!.headers[HttpHeaders.authorizationHeader], 'Bearer $secret');
    expect(seen!.body.contains(secret), isFalse);
    expect(seen!.body, contains('[redacted]'));
    final sent = jsonDecode(seen!.body) as Map;
    expect(sent['model'], defaultXaiModel);
    expect(sent['instructions'], contains('Never invent statistics, odds'));
    expect(sent['search_parameters'], {'mode': 'off'});
    expect(sent['store'], isFalse);
    expect(sent['input'], isA<List>());
    final user = (sent['input'] as List).single as Map;
    expect(user['content'], contains('pointsFor'));
    expect(user['content'], contains('targets'));
    expect(reply.available, isTrue);
    expect(reply.answer, contains('21.5'));
    expect(reply.answer.contains(secret), isFalse);
    expect(reply.answer.contains('api.x.ai'), isFalse);
    expect(reply.cited, [
      'frozen_quote',
      'assumptions',
      'team_evidence',
      'player_evidence',
    ]);
    expect(reply.toJson().toString().contains(secret), isFalse);
  });

  test('failures and uncited evidence do not leak the key or the query', () async {
    final assistant = XaiAssistant(
      apiKey: secret,
      post: (_) async => throw Exception(
        'GET https://api.x.ai/v1/responses?api_key=$secret failed',
      ),
    );
    final failed = await assistant.answer(payload());
    expect(failed.toJson(), AssistantReply.unavailable.toJson());
    expect(failed.toJson().toString().contains(secret), isFalse);
    expect(failed.toJson().toString().contains('api.x.ai'), isFalse);
    expect(failed.toJson().toString().contains('api_key'), isFalse);

    final dropped = XaiAssistant(
      apiKey: secret,
      post: (_) async => AssistantHttpResult(
        statusCode: 500,
        body:
            '{"error":"$secret","url":"https://api.x.ai/v1/responses?api_key=$secret"}',
      ),
    );
    final hidden = await dropped.answer(payload(withEvidence: false));
    expect(hidden.answer, 'assistant unavailable');
    expect(hidden.toJson().toString().contains(secret), isFalse);

    final fenced = XaiAssistant(
      apiKey: secret,
      post: (_) async => AssistantHttpResult(
        statusCode: 200,
        body: jsonEncode(
          grok(
            '```json\n{"answer":"Question only.","cited":["question","team_evidence"]}\n```',
          ),
        ),
      ),
    );
    final reply = await fenced.answer(
      payload(withEvidence: false, question: 'What is missing?'),
    );
    expect(reply.answer, 'Question only.');
    expect(reply.cited, ['question']);
    await expectLater(
      XaiAssistant(
        apiKey: secret,
        post: (_) async => hiddenHttp(),
      ).answer({'mode': 'bet'}),
      throwsFormatException,
    );
  });

  test(
    'HttpClient posts the bearer token without a query and reads output_text',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var hits = 0;
      server.listen((request) async {
        hits++;
        final body = await utf8.decoder.bind(request).join();
        expect(request.uri.query, isEmpty);
        expect(request.uri.path, '/v1/responses');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer $secret',
        );
        expect(body.contains(secret), isFalse);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            grok(
              '{"answer":"Grounded in the provided assumptions only.","cited":["assumptions"]}',
            ),
          ),
        );
        await request.response.close();
      });
      final assistant = XaiAssistant(
        apiKey: secret,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/responses'),
        post: postWithHttpClient,
      );
      final reply = await assistant.answer(payload(question: ''));
      expect(hits, 1);
      expect(reply.available, isTrue);
      expect(reply.answer, 'Grounded in the provided assumptions only.');
      expect(reply.cited, ['assumptions']);
    },
  );

  test(
    'HttpClient does not follow a redirect that would leak the key',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var hits = 0;
      server.listen((request) async {
        hits++;
        await request.drain<void>();
        request.response.statusCode = 302;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'https://api.x.ai/v1/responses?api_key=$secret',
        );
        request.response.write('leak $secret');
        await request.response.close();
      });
      final assistant = XaiAssistant(
        apiKey: secret,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/responses'),
        post: postWithHttpClient,
      );
      final reply = await assistant.answer(payload());
      expect(hits, 1);
      expect(reply, AssistantReply.unavailable);
      expect(reply.toJson().toString().contains(secret), isFalse);
      expect(reply.toJson().toString().contains('api.x.ai'), isFalse);
    },
  );

  test(
    'POST /v1/assistant returns the answer or assistant unavailable',
    () async {
      final dir = await Directory.systemTemp.createTemp('assistant-route');
      addTearDown(() => dir.delete(recursive: true));
      final service = OddsService([
        DemoProvider(),
      ], SnapshotStore(File('${dir.path}/snapshots.jsonl')));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var modelCalls = 0;
      final assistant = XaiAssistant(
        apiKey: secret,
        post: (call) async {
          modelCalls++;
          expect(call.uri.query, isEmpty);
          expect(call.body.contains(secret), isFalse);
          return AssistantHttpResult(
            statusCode: 200,
            body: jsonEncode(
              grok(
                '{"answer":"Challenge: the EV follows your assumptions only.","cited":["assumptions","frozen_quote"]}',
              ),
            ),
          );
        },
      );
      server.listen((request) {
        handleRequest(
          request,
          providerMode: 'demo',
          service: service,
          assistant: assistant,
        ).whenComplete(() => request.response.close());
      });
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final ok = await _post(
        base.replace(path: '/v1/assistant'),
        payload(mode: 'challenge'),
      );
      expect(ok.status, 200);
      expect(jsonDecode(ok.body), {
        'available': true,
        'answer': 'Challenge: the EV follows your assumptions only.',
        'cited': ['assumptions', 'frozen_quote'],
      });
      expect(modelCalls, 1);
      final missing = XaiAssistant(
        apiKey: '',
        post: (_) async => throw StateError('network'),
      );
      final off = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(off.close);
      off.listen((request) {
        handleRequest(
          request,
          providerMode: 'demo',
          service: service,
          assistant: missing,
        ).whenComplete(() => request.response.close());
      });
      final unavailable = await _post(
        Uri.parse('http://127.0.0.1:${off.port}/v1/assistant'),
        payload(),
      );
      expect(unavailable.status, 200);
      expect(jsonDecode(unavailable.body), AssistantReply.unavailable.toJson());
      final invalid = await _post(
        Uri.parse('http://127.0.0.1:${off.port}/v1/assistant'),
        {'mode': 'bet'},
      );
      expect(invalid.status, 400);
      expect(invalid.body.contains(secret), isFalse);
      final health = await _get(base.replace(path: '/health'));
      expect(jsonDecode(health.body)['status'], 'ok');
    },
  );

  test('the Flutter repository posts only to its own backend', () async {
    await expectLater(
      BackendRepository('https://api.x.ai').assistant(
        const AssistantRequest(mode: 'explain', selection: {}, assumptions: {}),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          isNot(contains('api.x.ai')),
        ),
      ),
    );
    await expectLater(
      BackendRepository('https://files.x.ai').board(),
      throwsA(isA<StateError>()),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String? method, path, hostHeader, auth;
    Object? body;
    server.listen((request) async {
      try {
        method = request.method;
        path = request.uri.path;
        hostHeader = request.headers.value(HttpHeaders.hostHeader);
        auth = request.headers.value(HttpHeaders.authorizationHeader);
        body = jsonDecode(await utf8.decoder.bind(request).join());
        request.response.statusCode = 302;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'https://api.x.ai/v1/responses?api_key=$secret',
        );
        request.response.write('no');
      } finally {
        await request.response.close();
      }
    });
    final repository = BackendRepository('http://127.0.0.1:${server.port}');
    await expectLater(
      repository.assistant(
        AssistantRequest(
          mode: 'explain',
          question: 'Why?',
          selection: const {
            'label': 'Detroit moneyline',
            'matchup': 'Detroit at Green Bay',
            'price': 2.25,
            'demo': true,
            'identity': 'synthetic-detroit-green-bay',
          },
          assumptions: const ResearchAssumptions().toJson(),
          teamEvidence: const [
            {'team': 'DET'},
          ],
          playerEvidence: const [
            {'name': 'Example'},
          ],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          allOf(isNot(contains(secret)), isNot(contains('api.x.ai'))),
        ),
      ),
    );
    expect(method, 'POST');
    expect(path, '/v1/assistant');
    expect(hostHeader, startsWith('127.0.0.1'));
    expect(auth, isNull);
    expect((body as Map)['mode'], 'explain');
    expect((body as Map)['teamEvidence'], isA<List>());
    expect((body as Map)['playerEvidence'], isA<List>());
    final lib = Directory('lib');
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      expect(text.contains('api.x.ai'), isFalse, reason: entity.path);
      expect(text.contains('XAI_API_KEY'), isFalse, reason: entity.path);
    }
  });
}

AssistantHttpResult hiddenHttp() =>
    const AssistantHttpResult(statusCode: 200, body: '{}');

Future<({int status, String body})> _post(Uri uri, Object body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

Future<({int status, String body})> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}
