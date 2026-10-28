// The AI's judgement: when a BOOST is worth a card, where to end the turn, and that the
// difficulty levels really differ (tool/ai_arena.dart measures the same thing at length).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

Prompt boostPrompt(Player p) => Prompt(
      player: p,
      ask: Ask.card,
      text: 'Discard a card to BOOST your movement?',
      choices: [for (final c in p.hand) Choice(c.title, c)],
      optional: true,
      intent: Intent.boost,
    );

void main() {
  group('maneuver BOOST', () {
    late Scenario s;
    setUp(() {
      s = Scenario('bigfoot', 'medusa');
      for (final t in ['Hoax', 'Savagery', 'Larger Than Life']) {
        s.give(s.p1, t);
      }
      s.game.actions = 1; // the first of two actions
    });

    test('not when the normal move already reaches the enemy', () async {
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 3);
      expect(await AiAgent(level: AiLevel.insane).decide(s.game, boostPrompt(s.p1)), isEmpty);
    });

    test('when only the boosted move reaches the enemy', () async {
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 6);
      expect(await AiAgent(level: AiLevel.insane).decide(s.game, boostPrompt(s.p1)), hasLength(1));
    });

    test('not just because the hand is big', () async {
      for (final t in ['Hoax', 'Savagery']) {
        s.give(s.p1, t);
      }
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 11);
      expect(await AiAgent(level: AiLevel.insane).decide(s.game, boostPrompt(s.p1)), isEmpty);
    });
  });

  test('a hurt hero ends the turn where no enemy can strike next turn', () async {
    final s = Scenario('bigfoot', 'medusa');
    final bigfoot = s.hero(s.p1);
    s.place(bigfoot, 6);
    s.place(s.hero(s.p2), 0);
    bigfoot.hp = 4;
    s.give(s.p2, 'Gaze of Stone');
    s.game.actions = 0; // the last action
    // Medusa (ranged, move 3) can reach space 4 and shoot anyone in its zone (3-7, 12).
    final options = s.game.reachable(bigfoot, 3).keys.toList()..sort();
    final p = Prompt(
      player: s.p1,
      ask: Ask.space,
      text: 'Move Bigfoot',
      choices: [for (final o in options) Choice('Space $o', o)],
      intent: Intent.moveOwn,
      subject: bigfoot,
    );
    final [i] = await AiAgent(level: AiLevel.insane).decide(s.game, p);
    expect(options[i], greaterThanOrEqualTo(8));
  });

  test('the levels differ: Insane beats Easy', () async {
    final data = loadData();
    final heroes = data.heroes.keys.where(isImplemented).toList()..sort();
    final maps = data.mapsFor('1v1');
    final rng = Random(4);
    var insane = 0, games = 0;
    for (var k = 0; k < 20; k++) {
      final ids = (List.of(heroes)..shuffle(rng)).take(2).toList();
      final map = maps[rng.nextInt(maps.length)];
      for (final seat in [0, 1]) {
        final g = Game(
          data: data,
          map: map,
          heroIds: ids,
          agents: [
            for (var i = 0; i < 2; i++) AiAgent(level: i == seat ? AiLevel.insane : AiLevel.easy, seed: k * 2 + i),
          ],
          seed: k,
          firstSeat: k & 1,
        );
        final w = await g.run();
        games++;
        if (w?.seat == seat) insane++;
      }
    }
    expect(insane / games, greaterThan(0.65), reason: 'Insane won $insane of $games');
  });
}
