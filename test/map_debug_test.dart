// The map connection editor (MAPDEBUG): cycling paths, problem spaces, the patch it copies, and
// the inspector's editor mode.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/board/board_painter.dart';
import 'package:unmatched_game/ui/dialogs/map_debug.dart';
import 'package:unmatched_game/ui/dialogs/map_inspect_dialog.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';

import 'support.dart';

void main() {
  group('MapEdits', () {
    test('starts as the map data, with no changes or problems', () {
      final e = MapEdits(lineMap());
      expect(e.links, hasLength(12));
      expect(e.changeCount, 0);
      expect(e.problems(), isEmpty);
      expect(e.kindOf(0, 1), PathKind.path);
      expect(e.kindOf(0, 2), PathKind.none);
    });

    test('tapping a pair cycles none → path → arrow → arrow back → +1 → none', () {
      final e = MapEdits(lineMap());
      expect(e.cycle(0, 2), PathKind.path);
      expect(e.cycle(0, 2), PathKind.forward);
      expect(e.oneWay, contains((0, 2)));
      expect(e.kindOf(2, 0), PathKind.backward, reason: 'seen from the other end');
      expect(e.cycle(0, 2), PathKind.backward);
      expect(e.oneWay, contains((2, 0)));
      expect(e.cycle(0, 2), PathKind.stairs);
      expect(e.oneWay, isEmpty);
      expect(e.stairs, contains((0, 2)));
      expect(e.cycle(0, 2), PathKind.none);
      expect(e.changeCount, 0);
    });

    test('removing a path shows it as removed and flags the space it cut off', () {
      final e = MapEdits(lineMap());
      e.setKind(5, 12, PathKind.none);
      expect(e.removed, [(5, 12)]);
      expect(e.changeCount, 1);
      expect(e.problems(), {12: 'no path'});
    });

    test('an arrow away from a space makes it unreachable; one into a dead end traps', () {
      final e = MapEdits(lineMap());
      e.setKind(12, 5, PathKind.forward);
      expect(e.problems(), {12: 'unreachable'});
      e.setKind(5, 12, PathKind.forward);
      expect(e.problems(), {12: 'dead end'});
    });

    test('undo and reset', () {
      final e = MapEdits(lineMap());
      e.cycle(0, 2);
      e.cycle(3, 9);
      e.undo();
      expect(e.kindOf(3, 9), PathKind.none);
      expect(e.kindOf(0, 2), PathKind.path);
      e.reset();
      expect(e.changeCount, 0);
      e.undo();
      expect(e.kindOf(0, 2), PathKind.path, reason: 'reset can be undone');
    });

    test('the patch holds the whole edited path data', () {
      final e = MapEdits(lineMap())..setKind(11, 10, PathKind.forward);
      e.setKind(0, 1, PathKind.stairs);
      final p = jsonDecode(e.patch()) as Map<String, dynamic>;
      expect(p['map'], 'line');
      expect(p['links'], hasLength(12));
      expect(p['links'], contains(equals([10, 11])));
      expect(p['oneway'], [
        [11, 10]
      ]);
      expect(p['stairs'], [
        [0, 1]
      ]);
    });

    test('every real map loads into the editor without problems', () {
      for (final m in loadData().maps.values) {
        final e = MapEdits(m);
        expect(e.changeCount, 0, reason: m.id);
        expect(e.problems().values.where((v) => v != 'dead end'), isEmpty, reason: m.id);
      }
    });
  });

  testWidgets('the inspector in editor mode: tap two spaces to add a path, then copy the patch', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final map = lineMap();
    final services = Services(settings: Settings.memory(), audio: Audio(Settings.memory(), enabled: false), preloadImages: false);
    await tester.pumpWidget(ServicesScope(
      services: services,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showMapInspectDialog(context, map, debug: true), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap a space'), findsOneWidget);
    expect(find.text('0 changes · no problems'), findsOneWidget);

    // The board is drawn at BoardGeometry's size inside the viewer; find each space on screen.
    final painted = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is MapDebugPainter);
    final box = tester.getRect(painted);
    final geo = BoardGeometry(map);
    Offset at(int s) => box.topLeft + Offset(geo.of(s).dx * box.width / geo.size.width, geo.of(s).dy * box.height / geo.size.height);

    await tester.tapAt(at(0));
    await tester.pump();
    expect(find.textContaining('Space 0 selected'), findsOneWidget);
    await tester.tapAt(at(2));
    await tester.pump();
    expect(find.text('0 – 2: path'), findsOneWidget);
    expect(find.text('1 change · no problems'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy patch'));
    await tester.pump();
    expect(jsonDecode(copied!)['links'], contains(equals([0, 2])));
    expect(find.textContaining('Patch copied (1 change)'), findsOneWidget);
  });

  // A printed map larger than the viewer and of another shape: the art must keep its shape, and
  // the overlay and taps must cover all of it (they were squashed into the viewer's shape).
  testWidgets('a big printed map is scaled to fit: art, overlay and taps line up', (tester) async {
    tester.view.physicalSize = const Size(1300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final map = loadData().maps['mcminnville-or']!;
    final services = Services(settings: Settings.memory(), audio: Audio(Settings.memory(), enabled: false), preloadImages: false);
    await tester.pumpWidget(ServicesScope(
      services: services,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showMapInspectDialog(context, map, debug: true), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final geo = BoardGeometry(map);
    final overlay = tester.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is MapDebugPainter));
    final art = tester.getRect(find.byType(Image));
    expect(art, overlay, reason: 'the art and the overlay cover the same box');
    expect(overlay.width / overlay.height, closeTo(geo.size.width / geo.size.height, 0.01), reason: 'the art keeps its shape');

    // The space furthest from the top-left corner can be tapped.
    final far = map.spaces.reduce((a, b) => a.x + a.y > b.x + b.y ? a : b).id;
    final p = geo.of(far);
    await tester.tapAt(overlay.topLeft + Offset(p.dx * overlay.width / geo.size.width, p.dy * overlay.height / geo.size.height));
    await tester.pump();
    expect(find.textContaining('Space $far selected'), findsOneWidget);
  });
}
