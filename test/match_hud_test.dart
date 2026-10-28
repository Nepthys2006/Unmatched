// The match HUD: whole hand cards on screen, the camera dropdown, and the identity cards sheet
// for every player. Set CAPTURE=true to also write screenshots to build/hud_shots/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';

import 'widget_test.dart' show loadFonts, makeServices, phone, desktop, sizeName;

const _capture = bool.fromEnvironment('CAPTURE');

Future<void> shot(WidgetTester t, String name) async {
  if (!_capture) return;
  await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/hud_shots/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(loadFonts);

  for (final size in [phone, desktop]) {
    testWidgets('hand, camera dropdown and identity cards (${sizeName(size)})', (t) async {
      final s = makeServices(speed: 0.05);
      await t.runAsync(() => s.loadData());
      final config = MatchConfig(
        mode: GameMode.duel,
        players: 2,
        map: s.data.maps[const String.fromEnvironment('MAP', defaultValue: 'blossom')]!,
        ai: AiLevel.medium,
        heroIds: ['squirrel-girl', 'the-wayward-sisters'],
      );
      t.view.physicalSize = size * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('shot'),
          child: UnmatchedApp(services: s, home: MatchScreen(config: config, seed: 3)),
        ),
      );
      // Wait for your first choice of action.
      final yourTurn = find.textContaining('choose an action');
      for (var i = 0; i < 6000 && yourTurn.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 20));
        // Start-of-turn choices (Go Nuts!) are optional: skip them.
        final skip = find.text('SKIP');
        if (skip.evaluate().isNotEmpty) await t.tap(skip.first);
      }
      if (yourTurn.evaluate().isEmpty) await shot(t, '${sizeName(size)}-0-stuck');
      expect(yourTurn, findsOneWidget);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 300));
      final tag = sizeName(size);
      await shot(t, '$tag-1-board');

      // Every hand card is whole and above the bottom edge.
      final screenH = size.height;
      final hand = find.descendant(of: find.byType(HandFan), matching: find.byType(GestureDetector));
      expect(hand, findsWidgets);
      for (final e in hand.evaluate()) {
        final r = t.getRect(find.byWidget(e.widget));
        expect(r.bottom, lessThanOrEqualTo(screenH + 0.5), reason: 'a hand card is cut off at the bottom');
        expect(r.top, greaterThan(0));
      }

      // Camera controls: one button; the rest open from it.
      expect(find.byTooltip('Zoom in'), findsNothing);
      await t.tap(find.byTooltip('Camera controls'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      expect(find.byTooltip('Fit board'), findsOneWidget);
      await shot(t, '$tag-2-camera-open');
      await t.tap(find.byTooltip('Hide camera controls'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Zoom in'), findsNothing);

      // Identity cards: yours, then the enemy's, with ability and rules.
      final idButton = find.byTooltip('Identity cards');
      await t.tap(idButton);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('SQUIRREL GIRL'), findsWidgets);
      expect(find.textContaining('summon a squirrel'), findsWidgets);
      expect(find.text('RULES TO KNOW'), findsOneWidget);
      await shot(t, '$tag-3-identity-mine');
      // The tab in the sheet (the opponent's plate behind it has the same name).
      await t.tap(find.text('THE WAYWARD SISTERS').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('cauldron'), findsWidgets);
      expect(find.textContaining('Spell'), findsWidgets);
      expect(find.text('Their hand and deck order stay hidden.'), findsOneWidget);
      await shot(t, '$tag-4-identity-enemy');
      final nav = Navigator.of(t.element(find.text('RULES TO KNOW')));
      expect(nav.canPop(), isTrue, reason: 'the sheet is open');
      await t.tap(find.byTooltip('Close').last);
      expect(nav.canPop(), isFalse, reason: 'Close shuts the sheet');
      await t.pump(const Duration(milliseconds: 400));

      await t.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}
