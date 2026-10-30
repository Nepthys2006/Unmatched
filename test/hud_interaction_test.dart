// Pressing things mid-game never breaks a match.
//
// 1. On your turn, every HUD control is used in turn: the skill (ability) chips, the companion
//    chips (sidekicks, pets, fellow heroes), every player plate (hero sheet open and closed), the
//    camera controls, the game log, the pause menu, a hand card, the mouse wheel over the board
//    and the attack toggle. Then you maneuver and the match plays on to its result.
// 2. A "monkey" plays whole matches in every mode and at every screen size while it taps random
//    points, HUD buttons, chips and cards, scrolls the wheel and opens and closes panels. Each
//    match must still reach its result, with no exception (any exception fails a widget test).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';
import 'package:unmatched_game/ui/match/plate_parts.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/widgets.dart';

import 'widget_test.dart' show loadFonts, makeServices, phone, desktop, smallPhone, pumpUntil;

/// The smallest landscape phone screen (an iPhone SE, first generation).
const tinyPhone = Size(568, 320);

Future<Services> _start(WidgetTester t, Size size, MatchConfig Function(Services) config, {required int seed}) async {
  final s = makeServices(speed: 0.05);
  await t.runAsync(() => s.loadData());
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UnmatchedApp(
      services: s,
      home: MatchScreen(config: config(s), seed: seed, autoplay: true),
    ),
  );
  return s;
}

/// Closes whatever a tap may have opened: tooltips, the pause menu, a hero sheet, a confirmation.
Future<void> _tidy(WidgetTester t) async {
  Tooltip.dismissAllToolTips();
  if (find.text('PAUSED').evaluate().isNotEmpty) {
    await t.tap(find.text('RESUME'));
    await t.pump(const Duration(milliseconds: 400));
  }
  if (find.byTooltip('Close').evaluate().isNotEmpty) {
    await t.tap(find.byTooltip('Close').last);
    await t.pump(const Duration(milliseconds: 400));
  }
  if (find.text('CANCEL').evaluate().isNotEmpty) {
    await t.tap(find.text('CANCEL').last, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _wheel(WidgetTester t, Offset at, double dy) async {
  final pointer = TestPointer(77, PointerDeviceKind.mouse);
  await t.sendEventToBinding(pointer.hover(at));
  await t.sendEventToBinding(pointer.scroll(Offset(0, dy)));
}

void main() {
  setUpAll(loadFonts);

  final turnCases = <(String, GameMode, int, String, List<String>, Size)>[
    ('1v1', GameMode.duel, 2, 'blossom', ['king-arthur', 'robin-hood'], phone),
    ('1v1', GameMode.duel, 2, 'blossom', ['king-arthur', 'robin-hood'], smallPhone),
    ('1v1', GameMode.duel, 2, 'blossom', ['king-arthur', 'robin-hood'], desktop),
    ('2v2', GameMode.teams2, 4, 'harbor', ['king-arthur', 'raptors', 'robin-hood', 'cloak-dagger'], phone),
  ];
  for (final (mode, gameMode, players, map, heroes, size) in turnCases) {
    testWidgets('every HUD control on your turn, then the match plays on ($mode, ${size.width.round()}x${size.height.round()})', (t) async {
      final s = await _start(
        t,
        size,
        (s) => MatchConfig(mode: gameMode, players: players, map: s.data.maps[map]!, ai: AiLevel.easy, heroIds: heroes),
        seed: 9,
      );

      // Your turn: from the banner on, everything (and the autoplay answer) slows right down,
      // so there is time to press things before your action is chosen.
      final action = find.textContaining('choose an action');
      for (var i = 0; i < 20000; i++) {
        final slow = s.settings.speedOverride! > 1;
        if (slow && action.evaluate().isNotEmpty) break;
        if (!slow && find.textContaining('YOUR TURN').evaluate().isNotEmpty) s.settings.speedOverride = 120;
        await t.pump(Duration(milliseconds: slow ? 400 : 20));
      }
      expect(action, findsOneWidget, reason: 'your turn should come');
      expect(s.settings.speedOverride, 120);
      final me = find.byKey(const ValueKey('hud-me'));
      final rivals = [
        for (final k in ['hud-opponents', 'hud-allies'])
          if (find.byKey(ValueKey(k)).evaluate().isNotEmpty) find.byKey(ValueKey(k)),
      ];

      // The skill chip: a tap shows the ability (and doesn't open the hero sheet).
      final myAbility = find.descendant(of: me, matching: find.byType(AbilityChip));
      expect(myAbility, findsOneWidget);
      final hero = t.widget<AbilityChip>(myAbility).hero;
      await t.tap(myAbility);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining(abilityParts(hero).$2.substring(0, 20), findRichText: true), findsWidgets);
      expect(find.byTooltip('Close'), findsNothing, reason: 'the hero sheet stays shut');
      Tooltip.dismissAllToolTips();
      await t.pump(const Duration(milliseconds: 500));

      // Everyone's companions and skills.
      for (final area in [me, ...rivals]) {
        for (final chip in find.descendant(of: area, matching: find.byType(CompanionChip)).evaluate().toList()) {
          await t.longPress(find.byWidget(chip.widget).first);
          await t.pump(const Duration(milliseconds: 400));
          expect(find.textContaining(RegExp(r'health|left|defeated')), findsWidgets);
          Tooltip.dismissAllToolTips();
          await t.pump(const Duration(milliseconds: 300));
        }
        for (final chip in find.descendant(of: area, matching: find.byType(AbilityChip)).evaluate().toList()) {
          await t.tap(find.byWidget(chip.widget).first);
          await t.pump(const Duration(milliseconds: 400));
          Tooltip.dismissAllToolTips();
          await t.pump(const Duration(milliseconds: 300));
        }
      }

      // Every plate opens its hero sheet, which closes again.
      for (final area in [me, ...rivals]) {
        for (final emblem in find.descendant(of: area, matching: find.byType(HeroEmblem)).evaluate().toList()) {
          if ((emblem.widget as HeroEmblem).seat == null) continue; // a companion's
          await t.tap(find.byWidget(emblem.widget).first);
          await t.pump(const Duration(milliseconds: 500));
          expect(
            find.text('SPECIAL ABILITY', findRichText: true).evaluate().isNotEmpty ||
                find.textContaining('SPECIAL ABILITY').evaluate().isNotEmpty,
            isTrue,
            reason: 'the hero sheet opens',
          );
          await t.tap(find.byTooltip('Close').last);
          await t.pump(const Duration(milliseconds: 500));
          expect(find.byTooltip('Close'), findsNothing, reason: 'the hero sheet closes');
        }
      }

      // Camera controls.
      await t.tap(find.byTooltip('Camera controls'));
      await t.pump(const Duration(milliseconds: 300));
      for (final b in ['Zoom in', 'Zoom in', 'Zoom out', 'Fit board']) {
        await t.tap(find.byTooltip(b));
        await t.pump(const Duration(milliseconds: 150));
      }
      await t.tap(find.byTooltip('Hide camera controls'));
      await t.pump(const Duration(milliseconds: 300));

      // The wheel over the board: notches in quick succession, both ways.
      final centre = Offset(size.width / 2, size.height * 0.45);
      for (final dy in [-120.0, -120.0, -60.0, 200.0, 80.0]) {
        await _wheel(t, centre, dy);
        await t.pump(const Duration(milliseconds: 60));
      }
      await t.pump(const Duration(milliseconds: 500));

      // The game log, the pause menu and a hand card.
      await t.tap(find.byTooltip('Game log'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byTooltip('Game log'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byTooltip('Menu'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('PAUSED'), findsOneWidget);
      await t.tap(find.text('RESUME'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('PAUSED'), findsNothing);
      final cards = find.descendant(of: find.byType(HandFan), matching: find.byType(GestureDetector));
      await t.tap(cards.first);
      await t.pump(const Duration(milliseconds: 500));
      await t.tapAt(const Offset(4, 4)); // the zoom's backdrop
      await t.pump(const Duration(milliseconds: 500));
      await _tidy(t);

      // The attack toggle, on and off.
      final attack = find.text('ATTACK');
      final attackButton = find.ancestor(of: attack, matching: find.byType(PlateButton));
      if (attackButton.evaluate().isNotEmpty && t.widget<PlateButton>(attackButton.first).onPressed != null) {
        await t.tap(attack);
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.text('CANCEL ATTACK'));
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(action, findsOneWidget, reason: 'nothing above took your action');

      // Maneuver, then the match plays on at full speed to its end.
      await t.tap(find.text('MANEUVER'));
      s.settings.speedOverride = 0.05;
      await pumpUntil(t, () => find.byType(ResultView).evaluate().isNotEmpty, frames: 40000, step: const Duration(milliseconds: 20));
      expect(find.byType(ResultView), findsOneWidget, reason: 'the match should finish');
      expect(find.text('SOMETHING WENT WRONG'), findsNothing);
      // The slowed-down autoplay answer for the turn you took yourself is still timed; it finds
      // the prompt gone and does nothing. Let it run out before the test ends.
      await t.pump(const Duration(minutes: 3));
      await t.pumpWidget(const SizedBox());
    }, timeout: const Timeout(Duration(minutes: 6)));
  }

  final monkeyMatches = <(String, GameMode, int, String, List<String>)>[
    ('1v1', GameMode.duel, 2, 'blossom', ['king-arthur', 'robin-hood']),
    ('2v2', GameMode.teams2, 4, 'harbor', ['alice', 'dracula', 'sherlock-holmes', 'raptors']),
    ('3v3', GameMode.teams3, 6, 'keeps', ['robin-hood', 'shredder', 'invisible-man', 'squirrel-girl', 'philippa', 'cloak-dagger']),
    ('free-for-all 5', GameMode.ffa, 5, 'star', ['loki', 'titania', 'krang', 'the-wayward-sisters', 'yennenga']),
  ];
  for (final (mode, gameMode, players, map, heroes) in monkeyMatches) {
    for (final size in [tinyPhone, smallPhone, phone, desktop]) {
      testWidgets('random taps all match long never break it ($mode, ${size.width.round()}x${size.height.round()})', (t) async {
        await _start(
          t,
          size,
          (s) => MatchConfig(mode: gameMode, players: players, map: s.data.maps[map]!, ai: AiLevel.medium, heroIds: heroes),
          seed: heroes.length * 13 + size.width.round(),
        );
        final rnd = math.Random(size.width.round() + players);
        var actions = 0;
        for (var frame = 0; frame < 60000 && find.byType(ResultView).evaluate().isEmpty; frame++) {
          await t.pump(const Duration(milliseconds: 20));
          if (frame % 9 != 0) continue;
          actions++;
          final roll = rnd.nextInt(10);
          Finder? target;
          switch (roll) {
            case 0 || 1:
              await t.tapAt(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height));
            case 2:
              target = find.byType(AbilityChip);
            case 3:
              target = find.byType(CompanionChip);
            case 4:
              target = find.byType(HeroEmblem);
            case 5:
              target = find.byTooltip(['Camera controls', 'Game log', 'Identity cards', 'Menu'][rnd.nextInt(4)]);
            case 6:
              target = find.byTooltip(['Zoom in', 'Zoom out', 'Fit board'][rnd.nextInt(3)]);
            case 7:
              target = find.descendant(of: find.byType(HandFan), matching: find.byType(GestureDetector));
            case 8:
              await _wheel(t, Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height), rnd.nextBool() ? -120 : 120);
            default:
              target = find.byType(PlateButton);
          }
          if (target != null) {
            final hits = target.hitTestable().evaluate().toList();
            if (hits.isNotEmpty) {
              final pick = find.byWidget(hits[rnd.nextInt(hits.length)].widget).hitTestable();
              if (pick.evaluate().isNotEmpty) {
                // Leaving the match is the one button the monkey keeps its hands off.
                final label = pick.evaluate().first.widget is PlateButton ? (pick.evaluate().first.widget as PlateButton).label : '';
                if (label != 'Leave match') {
                  roll == 3 ? await t.longPress(pick.first, warnIfMissed: false) : await t.tap(pick.first, warnIfMissed: false);
                }
              }
            }
          }
          await t.pump(const Duration(milliseconds: 60));
          await _tidy(t);
        }
        expect(find.byType(ResultView), findsOneWidget, reason: 'the match should finish despite $actions random presses');
        expect(find.text('SOMETHING WENT WRONG'), findsNothing);
        await t.pumpWidget(const SizedBox());
        // _submit's 450 ms "back to the duel" camera timer may still be in flight; it checks
        // _disposed, so just let it fire.
        await t.pump(const Duration(seconds: 1));
      }, timeout: const Timeout(Duration(minutes: 8)));
    }
  }
}
