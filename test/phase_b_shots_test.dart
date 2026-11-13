import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/main.dart';

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
  testWidgets('390px shots of the prop breakdown, v1 vs v2, and new markets', (
    tester,
  ) async {
    if (Platform.environment['SCREENSHOT'] != '1') return;
    tester.view.physicalSize = const Size(390, 1600);
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

    await tester.tap(find.widgetWithText(NavigationDestination, 'Props'));
    await tester.pump();
    await _until(tester, find.textContaining('rush yards'));
    await _until(tester, find.textContaining('/'));
    expect(find.textContaining('rush yards'), findsWidgets);
    expect(find.textContaining('rec. yards'), findsWidgets);
    expect(find.textContaining('receptions'), findsWidgets);
    await _frameBoth(
      tester,
      find.textContaining('rush yards').first,
      find.textContaining('rec. yards').first,
    );
    final players = find.byType(Text).evaluate().map((item) {
      final text = item.widget;
      return text is Text ? text.data ?? '' : '';
    }).toSet();
    expect(
      players.where((name) => name.split(' ').length >= 2).length,
      greaterThan(3),
    );
    expect(find.textContaining('Over '), findsWidgets);
    expect(find.textContaining('Under '), findsWidgets);
    await _save(tester, '/opt/cursor/artifacts/props_list_markets_390.png');

    final henry = find.text('Derrick Henry');
    expect(henry, findsWidgets);
    final henryTop = tester.getTopLeft(henry.first).dy;
    await _nudge(tester, find.byKey(const Key('props-list')), henryTop, 180);
    expect(_nearbyLine(tester, henry.first), startsWith('Under '));
    await _save(tester, '/opt/cursor/artifacts/prop_under_card_390.png');

    final detailName = find.text('Jahmyr Gibbs').evaluate().isNotEmpty
        ? 'Jahmyr Gibbs'
        : find.text('James Cook').evaluate().isNotEmpty
        ? 'James Cook'
        : "Ja'Marr Chase";
    await _nudge(
      tester,
      find.byKey(const Key('props-list')),
      tester.getTopLeft(find.text(detailName).first).dy,
      220,
    );
    final opened = find.text(detailName).first;
    final cardLine = _nearbyLine(tester, opened);
    await tester.tap(opened);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('how-we-got-this')), findsOneWidget);
    expect(find.text('How we got this'), findsOneWidget);
    if (cardLine != null) {
      final number = RegExp(r'\d+\.\d+').firstMatch(cardLine)?.group(0);
      final side = cardLine.startsWith('Under ') ? 'Under' : 'Over';
      expect(find.text(side), findsWidgets);
      if (number != null) expect(find.textContaining(number), findsWidgets);
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await _save(tester, '/opt/cursor/artifacts/prop_detail_breakdown_390.png');
    _jump(tester, find.byType(Scrollable).last, 1);
    await tester.pump();
    expect(find.text('Comparison, not a pick.'), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('prop-detail')))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('open-report-card')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 20)),
    );
    await tester.pump();
    final reportScroll = find.descendant(
      of: find.byKey(const Key('report-card')),
      matching: find.byType(Scrollable),
    );
    for (var step = 0; step < 8; step++) {
      if (find.text('Usage Brier').evaluate().isNotEmpty) break;
      _jumpBy(tester, reportScroll, 400);
      await tester.pump();
    }
    expect(find.text('Usage Brier'), findsWidgets);
    expect(find.byKey(const Key('prop-v2')), findsOneWidget);
    expect(find.text('Usage Brier'), findsOneWidget);
    expect(find.text('Record Brier'), findsOneWidget);
    expect(find.byKey(const Key('prop-calibration-chart')), findsOneWidget);
    final chartTop = tester.getTopLeft(find.byKey(const Key('prop-v2'))).dy;
    _jumpBy(tester, reportScroll, chartTop - 90);
    await tester.pump();
    await _save(tester, '/opt/cursor/artifacts/report_card_v1_v2_390.png');
  }, timeout: const Timeout(Duration(minutes: 6)));
}

String? _nearbyLine(WidgetTester tester, Finder name) {
  final nameTop = tester.getTopLeft(name).dy;
  String? line;
  var best = 80.0;
  for (final item in find.byType(Text).evaluate()) {
    final text = item.widget;
    if (text is! Text) continue;
    final data = text.data ?? '';
    if (!data.startsWith('Over ') && !data.startsWith('Under ')) continue;
    final gap = (tester.getTopLeft(find.byWidget(text)).dy - nameTop).abs();
    if (gap < best) {
      best = gap;
      line = data;
    }
  }
  return line;
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var step = 0; step < 40; step++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

Future<void> _frameBoth(WidgetTester tester, Finder left, Finder right) async {
  for (var step = 0; step < 30; step++) {
    final a = tester.getRect(left);
    final b = tester.getRect(right);
    final view = tester.view.physicalSize.height;
    final onScreen = a.top >= 80 &&
        a.bottom <= view - 40 &&
        b.top >= 80 &&
        b.bottom <= view - 40;
    if (onScreen) return;
    final target = a.top < b.top ? a.top : b.top;
    await tester.drag(find.byKey(const Key('props-list')), Offset(0, 120 - target));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
  }
}

Future<void> _nudge(
  WidgetTester tester,
  Finder view,
  double top,
  double target,
) async {
  if ((top - target).abs() < 40) return;
  await tester.drag(view, Offset(0, target - top));
  await tester.pump(const Duration(milliseconds: 50));
}

void _jump(WidgetTester tester, Finder view, double fraction) {
  final scroll = tester.state<ScrollableState>(view);
  final span = scroll.position.maxScrollExtent;
  scroll.position.jumpTo((span * fraction).clamp(0, span));
}

void _jumpBy(WidgetTester tester, Finder view, double delta) {
  final scroll = tester.state<ScrollableState>(view);
  final next = scroll.position.pixels + delta;
  scroll.position.jumpTo(next.clamp(0, scroll.position.maxScrollExtent));
}

Future<void> _save(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  final file = File(path);
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
  image!.dispose();
}
