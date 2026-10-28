// Invisible Man's fog through the real match screen. Every fog prompt (placing his 3 tokens,
// picking a token to move, where it goes) is answered by tapping the board, on purpose a little
// off the space (where the cloud is drawn, or where a finger lands): for his own player, and for
// the opponent whose turn it is when his cards say "your opponent moves a fog token". Everything
// else is answered by the AI. The fog must always be 3 tokens on 3 different spaces.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';

import 'widget_test.dart' show loadFonts, makeServices, phone, desktop;

void main() {
  setUpAll(loadFonts);

  final cases = [
    ('as Invisible Man', ['invisible-man', 'medusa'], phone, 1),
    ('as Invisible Man', ['invisible-man', 'sherlock-holmes'], desktop, 2),
    ('against Invisible Man', ['medusa', 'invisible-man'], phone, 3),
    ('against Invisible Man', ['king-arthur', 'invisible-man'], desktop, 4),
  ];
  for (final (name, heroes, size, seed) in cases) {
    testWidgets('fog is moved by tapping the board, $name (${heroes.join(' v ')}, ${size.width.round()} wide)', (t) async {
      // Speed 1.5: camera moves take ~1 s, the AI would answer a prompt after 1.35 s.
      final s = makeServices(speed: 1.5);
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = size * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final config = MatchConfig(mode: GameMode.duel, players: 2, map: s.data.maps['blossom']!, ai: AiLevel.hard, heroIds: heroes);
      await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: config, seed: seed, autoplay: true)));
      final rnd = math.Random(seed);
      var tapped = 0, covered = 0;
      Prompt? done;
      for (var frame = 0; frame < 15000 && find.byType(ResultView).evaluate().isEmpty; frame++) {
        await t.pump(const Duration(milliseconds: 20));
        final state = t.state(find.byType(MatchScreen)) as dynamic;
        final game = state.game as Game;
        final fog = [for (final tk in game.board.tokens) if (tk.kind == 'fog') tk.space];
        expect(fog.length, lessThanOrEqualTo(3));
        expect(fog.toSet().length, fog.length, reason: 'two fog tokens never share a space: $fog');
        final p = state.debugPrompt as Prompt?;
        if (p == null || p == done || p.ask != Ask.space || !p.text.toLowerCase().contains('fog')) continue;
        final marked = state.debugMarkedSpaces as List<int>;
        if (marked.isEmpty) continue;
        // Look before tapping, as a player does: a pick during a combat swings the camera back from
        // the duel to the whole board first.
        done = p;
        await t.pump(const Duration(milliseconds: 1100));
        if ((t.state(find.byType(MatchScreen)) as dynamic).debugPrompt != p) continue;
        // A space to pick, and a tap a little off its centre (up to most of a space's width).
        final target = marked[rnd.nextInt(marked.length)];
        final (centre, radius) = state.debugSpaceOnScreen(target) as (Offset, double);
        final a = rnd.nextDouble() * math.pi * 2, d = rnd.nextDouble() * 0.85 * radius;
        final at = centre + Offset(math.cos(a) * d, math.sin(a) * d - radius * 0.3);
        if (!(Offset.zero & size).deflate(2).contains(at)) {
          covered++;
          continue;
        }
        await t.tapAt(at);
        await t.pump(const Duration(milliseconds: 60)); // before the AI would answer
        if ((t.state(find.byType(MatchScreen)) as dynamic).debugPrompt == p) {
          covered++; // under the hand or a plate: the AI answers this one
        } else {
          tapped++;
        }
      }
      // ignore: avoid_print
      print('$name ${heroes.join(' v ')}: $tapped fog prompts answered by a tap, $covered under the HUD');
      expect(tapped, greaterThanOrEqualTo(name.startsWith('as') ? 3 : 1), reason: 'the fog prompts are answered by tapping');
      expect(tapped, greaterThan(covered), reason: 'most fog spaces can be tapped');
      // The match is still running: close it, then let its pacing timers run out.
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    }, timeout: const Timeout(Duration(minutes: 8)));
  }
}
