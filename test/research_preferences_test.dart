import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/research_store.dart';
import 'package:odds_edge/data/text_journal.dart';
import 'package:odds_edge/domain/coach_board.dart';
import 'package:odds_edge/main.dart';
import 'package:odds_edge/ui/feed_card.dart';

import 'memory_research_store.dart';

class PreferenceJournal implements TextJournal {
  final files = <String, String>{};
  @override
  Future<Uint8List?> readBytes(String name) async => files[name] == null
      ? null
      : Uint8List.fromList(utf8.encode(files[name]!));
  @override
  Future<void> append(String name, String text) async {
    files[name] = '${files[name] ?? ''}$text';
  }

  @override
  Future<String> makeBackup({
    required String researchName,
    required List<String> copies,
  }) async => '';
}

void main() {
  test(
    'prop preferences survive restart without replacing sportsbook preferences',
    () async {
      final disk = PreferenceJournal();
      final first = ResearchStore(journal: disk);
      await first.saveBooks({'fanduel'});
      const filter = PropFilter(
        market: 'player_rush_yds',
        bookId: 'draftkings',
        minAmerican: -150,
        maxAmerican: 200,
        onlyLongerThanTheBooks: true,
        sort: PropSort.line,
      );
      await first.savePropFilter(filter);
      final restored = ResearchStore(journal: disk);
      expect(
        propFilterJson((await restored.loadPropFilter())!),
        propFilterJson(filter),
      );
      expect(await restored.loadBooks(), {'fanduel'});
      await restored.saveBooks(null);
      expect(
        propFilterJson((await restored.loadPropFilter())!),
        propFilterJson(filter),
      );
    },
  );

  test('invalid saved filters never silently become plausible defaults', () {
    final json = propFilterJson(const PropFilter());
    expect(
      () => propFilterFromJson({...json, 'minAmerican': 0}),
      throwsFormatException,
    );
    expect(
      () => propFilterFromJson({
        ...json,
        'minAmerican': 200,
        'maxAmerican': -100,
      }),
      throwsFormatException,
    );
    expect(
      () => propFilterFromJson({...json, 'minFair': 1.1}),
      throwsFormatException,
    );
    expect(
      () => propFilterFromJson({...json, 'market': 'imaginary'}),
      throwsFormatException,
    );
    expect(
      () => propFilterFromJson({...json, 'sort': 'imaginary'}),
      throwsArgumentError,
    );
  });

  testWidgets(
    'three destinations preserve research search and the selected market across Today',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        OddsEdgeApp(researchStore: MemoryResearchStore()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.widgetWithText(NavigationDestination, 'Bets'), findsNothing);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Research'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('prop-search')),
        'Josh Allen',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<FeedPropCard>(find.byType(FeedPropCard))
            .every((card) => card.shown.card.player == 'Josh Allen'),
        isTrue,
      );
      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Research'));
      await tester.pumpAndSettle();
      expect(find.text('GAMES'), findsOneWidget);
      await tester.tap(find.text('Props'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('prop-search')),
      );
      // TextField owns its controller; verify the retained editable state.
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('prop-search')),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.decoration?.hintText, 'Search player, team, or stat');
      expect(editable.controller.text, 'Josh Allen');
      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-parlay-builder')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a leg').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prop-search')), findsOneWidget);
      expect(find.text('GAMES'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
