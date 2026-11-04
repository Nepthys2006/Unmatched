// The AI's judgement: when a BOOST is worth a card, where to end the turn, and that the
// difficulty levels really differ (tool/ai_arena.dart measures the same thing at length).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/ai_playbook.dart';
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

    test('with the cheapest card big enough to get there, never a scheme', () async {
      s.p1.hand.clear();
      for (final t in ['Crash Through the Trees', 'Hoax', 'Larger Than Life', 'Savagery']) {
        s.give(s.p1, t);
      }
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 7); // Bigfoot (move 3) needs a BOOST of 3 to reach space 6
      final p = boostPrompt(s.p1);
      final [i] = await AiAgent(level: AiLevel.insane).decide(s.game, p);
      expect((p.choices[i].value as Card).title, 'Savagery');
    });

    test('at the hand limit only when a card would be discarded anyway', () async {
      s.game.actions = 0;
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 11);
      for (final t in ['Hoax', 'Skirmish', 'Feint', 'Regroup']) {
        s.give(s.p1, t);
      }
      expect(s.p1.hand, hasLength(7));
      expect(await AiAgent(level: AiLevel.insane).decide(s.game, boostPrompt(s.p1)), isEmpty);
      s.give(s.p1, 'Crash Through the Trees');
      final p = boostPrompt(s.p1);
      final [i] = await AiAgent(level: AiLevel.insane).decide(s.game, p);
      expect((p.choices[i].value as Card).def.isScheme, isFalse);
    });

    test('Easy never throws a card away on a pointless BOOST', () async {
      s.give(s.p1, 'Crash Through the Trees');
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 11);
      for (var seed = 0; seed < 200; seed++) {
        expect(await AiAgent(level: AiLevel.easy, seed: seed).decide(s.game, boostPrompt(s.p1)), isEmpty);
      }
    });
  });

  group('ground rules', () {
    test('a BOOST with a scheme card breaks them; with a dead one it does not', () {
      final s = Scenario('bigfoot', 'medusa');
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 11);
      s.give(s.p1, 'Crash Through the Trees');
      s.give(s.p1, 'Jackalope Horns'); // the Jackalope isn't on the board: no one can play it
      final p = boostPrompt(s.p1);
      final ai = AiAgent(level: AiLevel.insane);
      expect(ai.obeysRules(s.game, p, [0]), isFalse);
      expect(ai.obeysRules(s.game, p, [1]), isTrue);
      expect(ai.obeysRules(s.game, p, const []), isTrue);
    });

    test('every rule and hero in the playbooks exists', () {
      final heroes = loadData().heroes;
      expect(groundRules, isNotEmpty);
      for (final id in [...playbooks.keys, ...counterplays.keys]) {
        expect(heroes, contains(id));
      }
    });
  });

  test('a counterplay: Bullseye shoots from 5 spaces away', () async {
    final s = Scenario('bigfoot', 'bullseye');
    final bigfoot = s.hero(s.p1);
    s.place(bigfoot, 6);
    s.place(s.hero(s.p2), 0);
    bigfoot.hp = 4;
    s.give(s.p2, 'Feint');
    s.game.actions = 0;
    // Bullseye (move 2) can get to space 3 and shoot anything up to space 8.
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
    expect(options[i], 9);
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
