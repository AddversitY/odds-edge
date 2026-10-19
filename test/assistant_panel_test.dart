import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/assistant.dart';
import 'package:odds_edge/research_workspace.dart';

import 'memory_research_store.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    MemoryResearchStore store, {
    Future<AssistantReply> Function(AssistantRequest request)? assistant,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchWorkspace(store: store, assistant: assistant),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Explain / challenge panel is unavailable in demo mode', (
    tester,
  ) async {
    final store = MemoryResearchStore();
    await pump(tester, store);
    await tester.ensureVisible(find.text('Explain / challenge this research'));
    expect(find.text('AI-generated'), findsOneWidget);
    expect(find.textContaining('No team evidence is attached'), findsOneWidget);
    expect(
      find.textContaining('No player evidence is attached'),
      findsOneWidget,
    );
    expect(find.textContaining('api.x.ai'), findsNothing);
    expect(find.textContaining('XAI_API_KEY'), findsNothing);
    await tester.tap(find.text('Explain this research'));
    await tester.pumpAndSettle();
    expect(find.textContaining('assistant unavailable'), findsOneWidget);
    expect(
      find.text('What supports your theory? What would change your mind?'),
      findsOneWidget,
    );
    expect(store.records, isEmpty);
    expect(store.latest, isNull);
    expect(find.textContaining('api.x.ai'), findsNothing);
  });

  testWidgets('a server unavailable reply stays out of notes and assumptions', (
    tester,
  ) async {
    final store = MemoryResearchStore();
    await pump(
      tester,
      store,
      assistant: (_) async => AssistantReply.unavailable,
    );
    await tester.ensureVisible(find.text('Challenge this research'));
    await tester.tap(find.text('Challenge this research'));
    await tester.pumpAndSettle();
    expect(find.textContaining('assistant unavailable'), findsOneWidget);
    expect(find.text('AI-generated'), findsOneWidget);
    expect(
      find.text('What supports your theory? What would change your mind?'),
      findsOneWidget,
    );
    expect(store.records, isEmpty);
  });

  testWidgets('an answer is labeled AI-generated and saved apart from facts', (
    tester,
  ) async {
    const answer = 'The assumption-based EV is unvalidated.';
    final store = MemoryResearchStore();
    await pump(
      tester,
      store,
      assistant: (request) async {
        expect(request.mode, 'challenge');
        expect(request.assumptions.containsKey('performance'), isTrue);
        expect(request.selection['label'], 'Detroit moneyline');
        expect(request.teamEvidence, isEmpty);
        expect(request.playerEvidence, isEmpty);
        return const AssistantReply(
          available: true,
          answer: answer,
          cited: ['assumptions', 'frozen_quote'],
        );
      },
    );
    await tester.ensureVisible(find.text('Challenge this research'));
    await tester.tap(find.text('Challenge this research'));
    await tester.pumpAndSettle();
    expect(find.text('AI-generated'), findsWidgets);
    expect(find.text(answer), findsOneWidget);
    expect(
      find.text('Cited inputs: Your assumptions, Demonstration selection'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Not a recommendation. No outcome is guaranteed.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Save research snapshot'));
    await tester.tap(find.text('Save research snapshot'));
    await tester.pumpAndSettle();
    final saved = store.records.single;
    expect(saved.thesis, isEmpty);
    expect(saved.assistant!.answer, answer);
    expect(saved.assistant!.cited, ['assumptions', 'frozen_quote']);
    expect(saved.assumptions.toJson().toString().contains(answer), isFalse);
    expect(saved.toJson()['assistant']['answer'], answer);
  });

  testWidgets('panel shows thinking while a reply is still running', (
    tester,
  ) async {
    final store = MemoryResearchStore();
    final gate = Completer<AssistantReply>();
    await pump(tester, store, assistant: (_) => gate.future);
    await tester.ensureVisible(find.text('Explain this research'));
    await tester.tap(find.text('Explain this research'));
    await tester.pump();
    expect(find.text('thinking…'), findsOneWidget);
    expect(find.textContaining('assistant unavailable'), findsNothing);
    gate.complete(AssistantReply.unavailable);
    await tester.pumpAndSettle();
    expect(find.text('thinking…'), findsNothing);
    expect(find.textContaining('assistant unavailable'), findsOneWidget);
    expect(store.records, isEmpty);
  });
}
