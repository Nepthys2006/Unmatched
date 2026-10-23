// Card-by-card tests: Raptors, Robert Muldoon, Dr. Sattler (Jurassic Park).
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/heroes/jurassic.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

void main() {
  group('Raptors', () {
    List<Fighter> pack(Scenario s, [int seat = 0]) => (seat == 0 ? s.p1 : s.p2).fighters.where((f) => f.isHero).toList();

    test('three Raptors, each a hero with 7 health; you lose only when the last falls', () async {
      final s = Scenario('raptors', 'medusa');
      final r = pack(s);
      expect(r, hasLength(3));
      expect(r.map((f) => f.hp), [7, 7, 7]);
      expect(r.map((f) => f.name), ['Raptor 1', 'Raptor 2', 'Raptor 3']);
      for (final f in r.take(2)) {
        f.defeated = true;
      }
      expect(s.p1.defeated, isFalse);
      expect(s.p1.heroFighter, r[2]);
      r[2].defeated = true;
      expect(s.p1.defeated, isTrue);
    });

    test('ability: +1 to an attack for each other Raptor next to the defender', () async {
      final s = Scenario('raptors', 'medusa');
      final r = pack(s);
      s.place(r[0], 4);
      s.place(r[1], 6);
      s.place(r[2], 12);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(r[0], s.hero(s.p2), 'Eviscerate', null);
      expect(c.attackValue, 5 + 2);
    });

    test('Pack Hunters, Eaten Alive and Clever Girl', () async {
      final s = Scenario('raptors', 'medusa');
      final r = pack(s);
      s.place(r[0], 4);
      s.place(r[1], 6);
      s.place(s.hero(s.p2), 5);
      s.place(s.sidekick(s.p2), 3);
      s.hero(s.p2).hp = 40; // survives the whole test
      final hp = s.hero(s.p2).hp;
      await s.fight(r[0], s.hero(s.p2), 'Pack Hunters', null);
      expect(s.hero(s.p2).hp, hp - (4 + 1) - 2, reason: '2 Raptors adjacent after winning');
      await s.fight(r[0], s.hero(s.p2), 'Eaten Alive', null, then1: [s.sidekick(s.p2)]);
      expect(s.sidekick(s.p2).defeated, isTrue);
      final actions = s.game.actions;
      await s.fight(r[0], s.hero(s.p2), 'Clever Girl', null);
      expect(s.game.actions, actions + 1);
    });

    test('Working Things Out moves every Raptor 3 (through enemies) and gains 1 action', () async {
      final s = Scenario('raptors', 'medusa');
      final r = pack(s);
      s.place(r[0], 4);
      s.place(r[1], 3);
      s.place(r[2], 2);
      s.place(s.hero(s.p2), 5);
      s.a1
        ..then(r[0]) // plays the scheme
        ..then(r[0])
        ..then(sp(7))
        ..then(r[1])
        ..then(sp(6))
        ..then(sp(1));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Working Things Out'));
      expect([r[0].space, r[1].space, r[2].space], [7, 6, 1]);
      expect(s.game.actions, 3);
    });

    test('Coordinated Attack Pattern gathers the pack; Decoy places a Raptor next to the attacker', () async {
      final s = Scenario('raptors', 'medusa');
      final r = pack(s);
      s.place(r[0], 9);
      s.place(r[1], 1);
      s.place(r[2], 2);
      s.a1
        ..then(r[0]) // plays the scheme
        ..then(r[0])
        ..then(sp(10))
        ..then(sp(11));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Coordinated Attack Pattern'));
      expect([r[1].space, r[2].space], [10, 11]);

      final t = Scenario('medusa', 'raptors');
      final q = pack(t, 1);
      t.place(t.hero(t.p1), 4);
      t.place(q[0], 5);
      t.place(q[1], 9);
      await t.fight(t.hero(t.p1), q[0], 'Snipe', 'Decoy', then2: [sp(3)]); // the only other Raptor is chosen
      expect(q[1].space, 3);
    });

    test('They Remember gains 1 action; Disengage moves within the zone', () async {
      final s = Scenario('raptors', 'medusa');
      final r = pack(s);
      s.place(r[0], 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(r[0], s.hero(s.p2), 'They Remember', null);
      expect(s.game.actions, 3);
      await s.fight(r[0], s.hero(s.p2), 'Disengage', null, then1: [sp(12)]);
      expect(r[0].space, 12);
    });
  });

  group('Robert Muldoon', () {
    Muldoon m(Scenario s) => s.p1.script as Muldoon;

    test('ability: a trap in his zone at the start of the turn; 8 for the whole game', () async {
      final s = Scenario('robert-muldoon', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.a1.then(sp(6));
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(m(s).traps.map((t) => t.space), [6]);
      expect(m(s).supply, 7);
    });

    test('an opposing fighter entering a trap stops, takes 1 damage, and Muldoon draws', () async {
      final s = Scenario('robert-muldoon', 'medusa');
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 9);
      s.game.board.tokens.add(Token('trap', s.p1, space: 7));
      m(s).placed = 1;
      final hp = s.hero(s.p2).hp;
      s.a2.then(sp(5)); // tries to run past the trap at 7
      await s.game.moveFighter(s.hero(s.p2), 4, chooser: s.p2);
      expect(s.hero(s.p2).space, 7, reason: 'stopped on the trap');
      expect(s.hero(s.p2).hp, hp - 1);
      expect(m(s).traps, isEmpty);
      expect(s.p1.hand, hasLength(1), reason: 'the trap went back to the box: draw');
    });

    test('his own fighters walk over traps; placing an enemy on one sets it off', () async {
      final s = Scenario('robert-muldoon', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 9);
      s.game.board.tokens.add(Token('trap', s.p1, space: 6));
      s.a1.then(sp(7));
      await s.game.moveFighter(s.hero(s.p1), 3, chooser: s.p1);
      expect(s.hero(s.p1).space, 7);
      expect(m(s).traps, hasLength(1));
      s.a1.then(sp(6));
      await s.game.placeFighter(s.hero(s.p2), [6], chooser: s.p1);
      expect(m(s).traps, isEmpty);
    });

    test('Call for Backup: traps + revived InGen Workers, or draw 2', () async {
      final s = Scenario('robert-muldoon', 'medusa');
      s.place(s.hero(s.p1), 4);
      final w = s.sidekick(s.p1);
      w.defeated = true;
      s.a1
        ..then('Place all defeated InGen Workers')
        ..then('Draw 2 cards')
        ..then(sp(5));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Call for Backup'));
      expect(w.onBoard, isTrue);
      expect(w.space, 5);
      expect(s.p1.hand, hasLength(2));
    });

    test('Shoot Her! is 5 as the first action of the turn', () async {
      final s = Scenario('robert-muldoon', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), 'Shoot Her!', null)).attackValue, 5);
      s.game.turn.actionsTaken = 1;
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), 'Shoot Her!', null)).attackValue, 3);
    });

    test('Remote Detonation and They Should All Be Destroyed use traps', () async {
      final s = Scenario('robert-muldoon', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 3);
      s.place(s.hero(s.p2), 5);
      s.game.board.tokens
        ..add(Token('trap', s.p1, space: 6))
        ..add(Token('trap', s.p1, space: 12));
      m(s).placed = 2;
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'They Should All Be Destroyed', null);
      expect(c.attackValue, 4 + 2);
      final hp = s.hero(s.p2).hp;
      s.a1
        ..then(s.hero(s.p1)) // plays the scheme
        ..then(sp(6));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Remote Detonation'));
      expect(s.hero(s.p2).hp, hp - 1);
      expect(m(s).traps.map((t) => t.space), [12]);
    });

    test("Rending Shot, Tactical Advance, I've Hunted Most Things", () async {
      final s = Scenario('robert-muldoon', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 9);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Rending Shot', null, then1: [sp(8)]);
      expect(s.hero(s.p2).space, 8);
      final w = s.sidekick(s.p1);
      await s.fight(w, s.hero(s.p2), 'Tactical Advance', null, then1: [sp(11)]);
      expect(w.space, 11);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p2), s.hero(s.p1), 'Snipe', "I've Hunted Most Things That Can Hunt You",
          then2: [s.hero(s.p1), sp(9), sp(10)]);
      expect(s.hero(s.p1).space, 9, reason: 'Muldoon ran past Medusa at 8');
    });
  });

  group('Dr. Sattler', () {
    Sattler d(Scenario s) => s.p1.script as Sattler;

    test('ability: moving (not being placed) leaves an insight token; 5 in supply', () async {
      final s = Scenario('dr-sattler', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.a1.then(sp(6));
      await s.game.moveFighter(s.hero(s.p1), 2, chooser: s.p1);
      expect(d(s).insight.map((t) => t.space), [6]);
      s.a1.then(sp(9));
      await s.game.placeFighter(s.hero(s.p1), [9], chooser: s.p1);
      expect(d(s).onBoard, 1, reason: 'placing does not leave a token');
    });

    test('You Never Had Control adds the tokens on the board, then clears them', () async {
      final s = Scenario('dr-sattler', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      for (final sp_ in [1, 1, 9]) {
        await d(s).putInsight(sp_);
      }
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), "You Never Had Control, That's the Illusion", null);
      expect(c.attackValue, 2 + 3);
      expect(d(s).onBoard, 0);
    });

    test('Woman Inherits the Earth draws 1 and heals per token; Violently hits fighters near tokens', () async {
      final s = Scenario('dr-sattler', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await d(s).putInsight(6);
      final hp = s.hero(s.p2).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Violently, If Necessary', null);
      expect(s.hero(s.p2).hp, hp - 3 - 2);
      s.hero(s.p1).hp = 5;
      await d(s).putInsight(0);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Woman Inherits the Earth', null);
      expect(s.p1.hand, hasLength(1));
      expect(d(s).onBoard, 0);
      expect(s.hero(s.p1).hp, 5 + 2);
    });

    test("I Think We're Back in Business is the hand size; Sexism is 4 against a hero", () async {
      final s = Scenario('dr-sattler', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      for (var i = 0; i < 3; i++) {
        s.give(s.p1, 'Feint');
      }
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), "I Think We're Back In Business", null)).attackValue, 3);
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), 'Sexism in Survival Situations', null, then1: [sp(3)])).attackValue, 4);
      expect(s.hero(s.p1).space, 3);
    });

    test('Life Finds a Way heals both by the BOOST of their top card', () async {
      final s = Scenario('dr-sattler', 'medusa');
      final malcolm = s.sidekick(s.p1);
      s.place(s.hero(s.p1), 3);
      s.place(malcolm, 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p1).hp = 5;
      malcolm.hp = 3;
      s.deck(s.p2, ['A Momentary Glance']); // boost 4
      await s.fight(malcolm, s.hero(s.p2), 'Life Finds a Way', null);
      expect(s.hero(s.p1).hp, 9);
      expect(malcolm.hp, 7);
    });

    test('The Future Ex-Mrs. Malcolm; Chaotician; Concept of Attraction; Hey! Hey! Hey!', () async {
      final s = Scenario('dr-sattler', 'medusa');
      final malcolm = s.sidekick(s.p1);
      s.place(s.hero(s.p1), 6);
      s.place(malcolm, 4);
      s.place(s.hero(s.p2), 5);
      await s.game.playScheme(s.p1, s.give(s.p1, 'The Future Ex-Mrs. Malcolm'));
      expect(s.p1.hand, hasLength(2));
      expect(d(s).insight.map((t) => t.space), [4]);
      expect(s.game.actions, 3);
      await s.fight(malcolm, s.hero(s.p2), 'Chaotician', null, then1: [sp(10)]);
      expect(d(s).insight.map((t) => t.space), [4, 10]);
      await s.fight(s.hero(s.p2), malcolm, 'Snipe', 'The Concept of Attraction', then2: [sp(10)]);
      expect(malcolm.space, 10);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Hey! Hey! Hey!', null, then1: [sp(8)]);
      expect(malcolm.space, 8);
    });
  });

  group('T. Rex', () {
    test('a large fighter: her tail follows into the space she left; adjacency and zones count both', () async {
      final s = Scenario('t-rex', 'medusa');
      final rex = s.hero(s.p1);
      s.place(rex, 4);
      s.place(s.hero(s.p2), 2);
      s.a1.then(sp(5));
      await s.game.moveFighter(rex, 1, chooser: s.p1);
      expect([rex.space, rex.tail], [5, 4]);
      expect(s.game.isEmpty(4), isFalse, reason: 'her back still covers 4');
      s.place(s.hero(s.p2), 3);
      expect(s.game.adjacent(rex, s.hero(s.p2)), isTrue, reason: '3 is next to her tail at 4');
      expect(s.game.inReach(rex, s.hero(s.p2)), isTrue);
      s.place(s.hero(s.p2), 7);
      expect(s.game.inReach(rex, s.hero(s.p2)), isTrue, reason: 'she attacks up to 2 spaces away');
      s.place(s.hero(s.p2), 8);
      expect(s.game.inReach(rex, s.hero(s.p2)), isFalse);
      // She may start moving from her tail.
      s.a1.then(sp(3));
      await s.game.moveFighter(rex, 1, chooser: s.p1);
      expect([rex.space, rex.tail], [3, 4]);
    });

    test('placing her: the placer picks the space under the back of her base', () async {
      final s = Scenario('t-rex', 'medusa');
      final rex = s.hero(s.p1);
      s.place(rex, 4);
      s.a1.then(sp(10)); // 9 is the only option, so only the back is asked
      await s.game.placeFighter(rex, [9], chooser: s.p1);
      expect([rex.space, rex.tail], [9, 10]);
    });

    test('ability: draws a card at the end of her turn', () async {
      final s = Scenario('t-rex', 'medusa');
      s.place(s.hero(s.p1), 4);
      await s.p1.script.endOfTurn(s.game, s.p1);
      expect(s.p1.hand, hasLength(1));
    });

    test('Reckless Lunge, 15,000 Pounds of Muscle, When Dinosaurs Ruled the Earth', () async {
      final s = Scenario('t-rex', 'medusa');
      final rex = s.hero(s.p1);
      s.place(rex, 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 30;
      final hp = s.hero(s.p2).hp;
      await s.fight(rex, s.hero(s.p2), 'Reckless Lunge', null);
      expect(s.hero(s.p2).hp, hp - 3 - 3);
      expect(rex.hp, 27 - 3);
      final c = await s.fight(rex, s.hero(s.p2), '15,000 Pounds of Muscle', 'Hiss and Slither');
      expect(c.defenseValue, 0);
      expect(rex.hp, 27 - 3 - 2);
      final before = s.game.actions;
      await s.fight(rex, s.hero(s.p2), 'When Dinosaurs Ruled the Earth', null, then1: [skip]);
      expect(s.game.actions, before + 1);
      expect(rex.hp, 27 - 3 - 2 - 2);
    });

    test("You're Just Making Her Angry returns to hand when she wins; Terrifying Roar pins everyone", () async {
      final s = Scenario('medusa', 't-rex');
      final rex = s.hero(s.p2);
      s.place(rex, 5);
      s.place(s.hero(s.p1), 4);
      await s.fight(s.hero(s.p1), rex, 'Regroup', "You're Just Making Her Angry", then2: [skip]);
      expect(s.p2.hand.map((c) => c.title), contains("You're Just Making Her Angry"));
      final t = Scenario('t-rex', 'medusa');
      t.place(t.hero(t.p1), 4);
      t.place(t.hero(t.p2), 5);
      await t.fight(t.hero(t.p1), t.hero(t.p2), 'Terrifying Roar', null);
      expect(t.game.cannotLeave(t.hero(t.p2)), isTrue);
      expect(t.game.cannotLeave(t.hero(t.p1)), isTrue);
    });

    test('Ripples in the Water, 65 Million Years, Closer Than She Appears, Thrash', () async {
      final s = Scenario('t-rex', 'medusa');
      final rex = s.hero(s.p1);
      s.place(rex, 4);
      s.place(s.hero(s.p2), 7);
      s.give(s.p2, 'Snipe');
      s.a1.then(sp(6)); // her back can only go to 5 (Medusa is on 7)
      await s.game.playScheme(s.p1, s.give(s.p1, 'Ripples in the Water'));
      expect(rex.tail, 5);
      expect(rex.space, 6);
      expect(s.p2.hand, isEmpty, reason: 'Medusa is next to T. Rex: discards at random');
      s.discardPile(s.p1, ['Thrash']);
      s.a1.then(card('Thrash'));
      await s.game.playScheme(s.p1, s.give(s.p1, '65 Million Years of Gut Instinct'));
      expect(s.p1.hand.map((c) => c.title), contains('Thrash'));
      s.p1.hand.clear();
      s.a1.then(sp(5));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Closer Than She Appears'));
      expect(s.p1.hand, hasLength(1));
      s.place(s.sidekick(s.p2), 3);
      final hp = s.hero(s.p2).hp;
      await s.fight(rex, s.hero(s.p2), 'Thrash', null, then1: [skip]);
      expect(s.sidekick(s.p2).defeated, isTrue, reason: 'the Harpy in her zone took 1');
      expect(s.hero(s.p2).hp, hp - 2 - 1);
    });
  });
}
