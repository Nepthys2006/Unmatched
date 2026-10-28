// Looking at an opponent's hand and choosing the card they discard, on the real match screen:
// as Sherlock Holmes, play Eliminate the Impossible from the hand (tap the card, PLAY THIS
// SCHEME); Medusa's hand is shown face up to you (and only to you, it stays out of the log); tap
// to close it; then her cards are offered in the card picker and the one you tap is the one she
// discards.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';

import 'widget_test.dart' show loadFonts, makeServices, phone, desktop;

/// Taps the part of [f] that is on top (hand cards overlap).
Future<bool> tapVisible(WidgetTester t, Finder f, Size size) async {
  if (f.evaluate().isEmpty) return false;
  final target = f.evaluate().first.renderObject;
  final r = t.getRect(f.first);
  for (final fy in const [0.5, 0.3, 0.7, 0.15]) {
    for (final fx in const [0.5, 0.3, 0.15, 0.7, 0.85, 0.05]) {
      final at = Offset(r.left + r.width * fx, r.top + r.height * fy);
      if (!(Offset.zero & size).deflate(2).contains(at)) continue;
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, at, t.view.viewId);
      var inside = false;
      for (Object? o = hit.path.first.target; o is RenderObject; o = o.parent) {
        if (o == target) inside = true;
      }
      if (!inside) continue;
      await t.tapAt(at);
      return true;
    }
  }
  return false;
}

void main() {
  setUpAll(loadFonts);

  for (final size in [phone, desktop]) {
    testWidgets('look at the opponent\'s hand and choose their discard (${size.width.round()} wide)', (t) async {
      final s = makeServices(speed: 0.2);
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = size * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final config = MatchConfig(mode: GameMode.duel, players: 2, map: s.data.maps['blossom']!, ai: AiLevel.medium, heroIds: ['sherlock-holmes', 'medusa']);
      await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: config, seed: 7)));
      final state = t.state(find.byType(MatchScreen)) as dynamic;
      final game = state.game as Game;
      final me = game.players[0], medusa = game.players[1];
      final ai = AiAgent(level: AiLevel.medium, seed: 2);
      Card? scheme;
      var stage = 'waiting for the scheme';
      List<Card>? shown;
      Card? picked;
      for (var i = 0; i < 6000 && stage != 'done'; i++) {
        await t.pump(const Duration(milliseconds: 20));
        expect(state.debugError, isNull);
        // Once the opening hand is drawn, slip the scheme into it.
        if (scheme == null && me.hand.isNotEmpty) {
          scheme = me.deck.where((c) => c.def.title == 'Eliminate the Impossible').firstOrNull ??
              me.hand.where((c) => c.def.title == 'Eliminate the Impossible').firstOrNull;
          if (me.deck.remove(scheme)) me.hand.add(scheme!);
        }
        // Medusa's hand, face up, for you.
        if (stage == 'played' && find.byType(RevealView).evaluate().isNotEmpty) {
          final view = t.widget<RevealView>(find.byType(RevealView));
          expect(view.title, contains("Medusa"));
          shown = List.of(medusa.hand);
          expect(view.images, [for (final c in shown) c.def.image]);
          await t.pump(const Duration(milliseconds: 300));
          await t.tap(find.descendant(of: find.byType(RevealView), matching: find.text('OK')));
          await t.pump(const Duration(milliseconds: 60));
          expect(find.byType(RevealView), findsNothing, reason: 'OK closes it');
          stage = 'looked';
          continue;
        }
        final p = state.debugPrompt as Prompt?;
        if (p == null) continue;
        await t.pump(const Duration(milliseconds: 200));
        if (state.debugPrompt != p) continue;
        final values = [for (final c in p.choices) c.value];
        if (stage == 'waiting for the scheme' && p.ask == Ask.action && values.any((v) => v is ActionChoice && v.card == scheme)) {
          expect(await tapVisible(t, find.byKey(ValueKey(scheme!.uid)), size), isTrue, reason: 'the scheme can be tapped in the hand');
          await t.pump(const Duration(milliseconds: 300));
          await t.tap(find.text('PLAY THIS SCHEME'));
          await t.pump(const Duration(milliseconds: 60));
          stage = 'played';
          continue;
        }
        if ((stage == 'looked' || stage == 'played') && (p.ask == Ask.card || p.ask == Ask.cards) && values.every((v) => v is Card && medusa.hand.contains(v))) {
          expect(stage, 'looked', reason: 'her hand was shown before choosing');
          expect(find.byType(CardPicker), findsOneWidget);
          final n = values.length;
          expect(n, shown!.length);
          picked = values[1] as Card;
          await t.tap(find.byKey(const ValueKey('pick-1')));
          await t.pump(const Duration(milliseconds: 100));
          expect(state.debugPrompt, isNot(p), reason: 'one tap on her card answers it');
          await t.pump(const Duration(seconds: 2));
          stage = 'done';
          continue;
        }
        state.debugAnswer(await ai.decide(game, p));
      }
      expect(stage, 'done');
      expect(medusa.discard.last, picked, reason: 'the card you tapped is the one she discards');
      expect(medusa.hand, isNot(contains(picked)));
      expect(medusa.hand.length, shown!.length - 1);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}
