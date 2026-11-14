import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/my_bets_screen.dart';
import 'package:odds_edge/coach/stale_board_screen.dart';
import 'package:odds_edge/domain/bets.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/public_sharp.dart';
import 'package:odds_edge/main.dart';
import 'package:odds_edge/theme/edge_theme.dart';
import 'package:odds_edge/ui/wordmark.dart';

import 'memory_research_store.dart';

Future<void> _loadType() async {
  final outfit = FontLoader('Outfit')
    ..addFont(rootBundle.load('assets/fonts/Outfit-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Outfit-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Outfit-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Outfit-Bold.ttf'));
  final fraunces = FontLoader('Fraunces')
    ..addFont(rootBundle.load('assets/fonts/Fraunces-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Fraunces-SemiBoldItalic.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([outfit.load(), fraunces.load(), icons.load()]);
}

void main() {
  testWidgets('390px shots of the report card, skip list, and stale board', (
    tester,
  ) async {
    if (Platform.environment['SCREENSHOT'] != '1') return;
    tester.view.physicalSize = const Size(390, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadType);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: OddsEdgeApp(researchStore: MemoryResearchStore()),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1500)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('open-report-card')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 20)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.textContaining('no edge'), findsWidgets);
    await _save(tester, '/opt/cursor/artifacts/report_card_390.png');
    await tester.scrollUntilVisible(find.text('We said vs it happened'), 500);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await _save(
      tester,
      '/opt/cursor/artifacts/report_card_calibration_390.png',
    );
    await tester.scrollUntilVisible(find.text('Record vs usage'), 500);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await _save(tester, '/opt/cursor/artifacts/report_card_props_390.png');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Today'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Pass'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('not a pick'), findsWidgets);
    await _save(tester, '/opt/cursor/artifacts/dont_390.png');

    await tester.tap(find.byKey(const Key('open-stale-board')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('Not a live board'), findsWidgets);
    await _save(tester, '/opt/cursor/artifacts/stale_board_390.png');
  });

  testWidgets('390px shot of a close filled on My Bets', (tester) async {
    if (Platform.environment['SCREENSHOT'] != '1') return;
    tester.view.physicalSize = const Size(390, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadType);
    final event = SportEvent(
      'game-1',
      'Buffalo Bills',
      'Kansas City Chiefs',
      DateTime.utc(2026, 11, 8, 18),
    );
    final store = MemoryResearchStore();
    await store.saveBet(
      TrackedBet(
        id: 'bet-1',
        placedAt: DateTime.utc(2026, 11, 7, 15),
        description: 'Chiefs -2.5',
        book: 'FanDuel',
        decimal: americanToDecimal(-110),
        stake: 10,
        result: BetResult.pending,
        market: 'spreads',
        side: 'home',
        line: -2.5,
        eventId: event.id,
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: edgeTheme(),
          home: Scaffold(
            body: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OddsWordmark(height: 22),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: MyBetsScreen(
                    store: store,
                    now: DateTime.utc(2026, 11, 9),
                    board: OddsBoard(
                      events: [event],
                      quotes: const [],
                      fetchedAt: DateTime.utc(2026, 11, 8, 17),
                    ),
                    lineHistory: {
                      event.id: [
                        LineSnapshot(
                          at: DateTime.utc(2026, 11, 8, 17),
                          eventId: event.id,
                          away: event.away,
                          home: event.home,
                          prices: [
                            LinePrice(
                              bookId: 'fanduel',
                              market: 'spreads',
                              outcome: event.home,
                              decimal: 1.87,
                              point: -3.5,
                            ),
                          ],
                        ),
                      ],
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bet log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.0 pts'), findsWidgets);
    await _save(tester, '/opt/cursor/artifacts/my_bets_close_390.png');
  });

  testWidgets('390px shot of a book that lags the fee-free consensus', (
    tester,
  ) async {
    if (Platform.environment['SCREENSHOT'] != '1') return;
    tester.view.physicalSize = const Size(390, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadType);
    final now = DateTime.utc(2026, 11, 12, 18);
    final event = SportEvent(
      'lag',
      'Buffalo Bills',
      'Miami Dolphins',
      now.add(const Duration(days: 2)),
    );
    OddsQuote quote(String book, String outcome, double decimal) => OddsQuote(
      selection: Selection(
        eventId: event.id,
        market: 'spreads',
        outcome: outcome,
        point: outcome == event.home ? -3.5 : 3.5,
      ),
      bookId: book,
      book: book == 'draftkings' ? 'DraftKings' : 'FanDuel',
      provider: 'test',
      decimal: decimal,
      sourceAt: now,
      collectedAt: now,
      demo: true,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: edgeTheme(),
          home: Scaffold(
            body: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OddsWordmark(height: 22),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StaleBoardScreen(
                    board: OddsBoard(
                      events: [event],
                      quotes: [
                        quote('fanduel', event.home, 1.91),
                        quote('fanduel', event.away, 1.91),
                        quote('draftkings', event.home, 1.50),
                        quote('draftkings', event.away, 2.40),
                      ],
                      fetchedAt: now,
                      demo: true,
                    ),
                    now: now,
                    stamp: (_) => 'saved',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('DraftKings'), findsWidgets);
    expect(find.text('EXAMPLE'), findsOneWidget);
    await _save(tester, '/opt/cursor/artifacts/stale_lag_390.png');
  });
}

Future<void> _save(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('shot')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
