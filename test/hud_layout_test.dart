// The match HUD never covers itself: at every screen size, from a tiny phone to a full-HD
// desktop, and in every mode (1v1, 2v2, 3v3, free-for-all 5), the menu row, camera button, prompt
// bar, every player plate (with its companions and skill), the action buttons and each hand card
// sit side by side, whole and on screen. Set CAPTURE=true to also write screenshots to
// build/hud_shots/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';

import 'match_hud_test.dart' show shot;
import 'widget_test.dart' show loadFonts, makeServices;

const _sizes = {
  'tiny phone': Size(568, 320),
  'small phone': Size(740, 360),
  'iphone se': Size(667, 375),
  'phone': Size(915, 412),
  'tablet': Size(1024, 768),
  'laptop': Size(1280, 720),
  'desktop': Size(1440, 900),
  'full hd': Size(1920, 1080),
};

// You are the first hero. In the crowded modes it is one with no sidekick to place at the start
// (Bullseye), so the first prompt that waits for you is your turn; everyone else brings
// companions (Merlin, the Outlaws, the Raptors, Dagger...) to fill the plates.
const _modes = [
  ('1v1', GameMode.duel, 2, 'blossom', ['squirrel-girl', 'the-wayward-sisters']),
  ('2v2', GameMode.teams2, 4, 'harbor', ['bullseye', 'king-arthur', 'robin-hood', 'raptors']),
  ('3v3', GameMode.teams3, 6, 'keeps', ['bullseye', 'robin-hood', 'shredder', 'cloak-dagger', 'philippa', 'geralt-of-rivia']),
  ('ffa 5', GameMode.ffa, 5, 'star', ['bullseye', 'titania', 'krang', 'moon-knight', 'the-wayward-sisters']),
];

bool _overlaps(Rect a, Rect b) {
  final i = a.intersect(b);
  return i.width > 1 && i.height > 1;
}

void main() {
  setUpAll(loadFonts);

  for (final (mode, gameMode, players, map, heroes) in _modes) {
    for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
      // Every size for 1v1; the crowded modes on the smallest and the commonest screens.
      if (mode != '1v1' && !const ['tiny phone', 'small phone', 'phone', 'desktop'].contains(sizeName)) continue;
      testWidgets('HUD pieces never overlap: $mode, $sizeName', (t) async {
        final s = makeServices(speed: 0.05);
        await t.runAsync(() => s.loadData());
        final config = MatchConfig(mode: gameMode, players: players, map: s.data.maps[map]!, ai: AiLevel.easy, heroIds: heroes);
        t.view.physicalSize = size * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('shot'),
            child: UnmatchedApp(
              services: s,
              home: MatchScreen(config: config, seed: 5),
            ),
          ),
        );
        final yourTurn = find.textContaining('choose an action');
        for (var i = 0; i < 9000 && yourTurn.evaluate().isEmpty; i++) {
          await t.pump(const Duration(milliseconds: 20));
          // Optional start-of-turn choices and defending (an opponent may attack first): pass.
          for (final label in ['SKIP', 'NO DEFENSE']) {
            final skip = find.text(label);
            if (skip.evaluate().isNotEmpty) await t.tap(skip.first);
          }
        }
        final tag = '${mode.replaceAll(' ', '')}-${sizeName.replaceAll(' ', '-')}';
        if (yourTurn.evaluate().isEmpty) await shot(t, 'layout-$tag-stuck');
        expect(yourTurn, findsOneWidget);
        await t.pump(const Duration(milliseconds: 400));
        await shot(t, 'layout-$tag');

        Rect? rectOf(Finder f) => f.evaluate().isEmpty ? null : t.getRect(f.first);
        Rect union(Iterable<Rect> rs) => rs.reduce((a, b) => a.expandToInclude(b));
        final menu = union([
          for (final tip in ['Menu', 'Game log', 'Identity cards', 'Full screen']) ?rectOf(find.byTooltip(tip)),
        ]);
        final pieces = <String, Rect>{
          'menu': menu,
          'camera button': rectOf(find.byTooltip('Camera controls'))!,
          'prompt bar': rectOf(find.byType(PromptBar))!,
          'your plate': rectOf(find.byKey(const ValueKey('hud-me')))!,
          'actions': rectOf(find.byKey(const ValueKey('hud-actions')))!,
          'opponents': ?rectOf(find.byKey(const ValueKey('hud-opponents'))),
          'allies': ?rectOf(find.byKey(const ValueKey('hud-allies'))),
        };
        final cards = [
          for (final e in find.descendant(of: find.byType(HandFan), matching: find.byType(GestureDetector)).evaluate())
            t.getRect(find.byWidget(e.widget)),
        ];
        expect(cards, isNotEmpty);
        final screen = Offset.zero & size;

        for (final MapEntry(key: name, value: r) in pieces.entries) {
          expect(
            screen.inflate(1).contains(r.topLeft) && screen.inflate(1).contains(r.bottomRight),
            isTrue,
            reason: '$name $r is off screen $size',
          );
          for (final MapEntry(key: other, value: r2) in pieces.entries) {
            if (name.compareTo(other) >= 0) continue;
            expect(_overlaps(r, r2), isFalse, reason: '$name $r overlaps $other $r2 ($mode, $sizeName)');
          }
          for (final c in cards) {
            expect(_overlaps(r, c), isFalse, reason: '$name $r covers a hand card $c ($mode, $sizeName)');
          }
        }

        // The camera controls open beside their button, clear of everything else too.
        await t.tap(find.byTooltip('Camera controls'));
        await t.pump(const Duration(milliseconds: 300));
        final camera = union([
          for (final tip in ['Hide camera controls', 'Zoom in', 'Zoom out', 'Fit board']) ?rectOf(find.byTooltip(tip)),
        ]);
        for (final MapEntry(key: name, value: r) in pieces.entries) {
          if (name == 'camera button') continue;
          expect(_overlaps(camera, r), isFalse, reason: 'the open camera controls $camera cover $name $r ($mode, $sizeName)');
        }
        await shot(t, 'layout-$tag-camera');
        await t.pumpWidget(const SizedBox());
      }, timeout: const Timeout(Duration(minutes: 4)));
    }
  }
}
