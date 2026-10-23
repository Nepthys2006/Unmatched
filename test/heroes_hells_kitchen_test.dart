// Card-by-card tests: Bullseye, Daredevil, Elektra (Marvel Hell's Kitchen).
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/hells_kitchen.dart';

import 'support.dart';

void main() {
  group('Bullseye', () {
    test('he attacks from up to 5 spaces away, ignoring zones', () {
      final s = Scenario('bullseye', 'medusa');
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 5);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isTrue);
      s.place(s.hero(s.p2), 6);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isFalse);
    });

    test("after a won combat: I'm Better is 6, World's Greatest ignores, Study the Target draws 3 + action", () async {
      final s = Scenario('bullseye', 'medusa');
      final b = s.hero(s.p1);
      s.place(b, 4);
      s.place(s.hero(s.p2), 5);
      expect((await s.fight(b, s.hero(s.p2), "I'm Better And I'll Prove It", null)).attackValue, 2);
      expect((await s.fight(b, s.hero(s.p2), "I'm Better And I'll Prove It", null)).attackValue, 6);
      final c = await s.fight(b, s.hero(s.p2), "World's Greatest Assassin", 'Hiss and Slither');
      expect(c.defenseValue, 0);
      s.p1.hand.clear();
      await s.game.playScheme(s.p1, s.give(s.p1, 'Study The Target'));
      expect(s.p1.hand, hasLength(3));
      expect(s.game.actions, 3);
    });

    test('Arrogant But Effective counts as a win even when he lost', () async {
      final s = Scenario('bullseye', 'medusa');
      final b = s.hero(s.p1);
      s.place(b, 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(b, s.hero(s.p2), 'Arrogant But Effective', 'Hiss and Slither', then1: [sp(2)]);
      expect(c.won(s.p1), isTrue);
      expect(b.space, 2);
      expect((await s.fight(b, s.hero(s.p2), "I'm Better And I'll Prove It", null)).attackValue, 6);
    });

    test('I Never Miss draws when not boosted; Ricochet; Tactical Retreat; Master Strategist exactly 4', () async {
      final s = Scenario('bullseye', 'medusa');
      final b = s.hero(s.p1);
      s.place(b, 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(b, s.hero(s.p2), 'I Never Miss', null);
      expect(s.p1.hand, hasLength(1), reason: 'no boost: draw 1');
      s.place(s.sidekick(s.p2), 7);
      await s.fight(b, s.hero(s.p2), 'Ricochet', null, then1: [s.sidekick(s.p2)]);
      expect(s.sidekick(s.p2).defeated, isTrue);
      await s.fight(s.hero(s.p2), b, 'Snipe', 'Tactical Retreat', then2: [sp(10)]);
      expect(b.space, 10);
      s.place(b, 4);
      await s.fight(b, s.hero(s.p2), 'Master Strategist', null, then1: [sp(8)]);
      expect(b.space, 8, reason: '4 to 8 is exactly 4 spaces, through Medusa');
    });
  });

  group('Daredevil', () {
    test('ability: with 2 or fewer cards he may BLIND BOOST', () async {
      final s = Scenario('daredevil', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, ['Feint', 'Feint']); // boost 1
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Grappling Hook', null, then1: ['Yes', sp(4)]);
      expect(c.attackValue, 3 + 1);
      for (var i = 0; i < 3; i++) {
        s.give(s.p1, 'Breather');
      }
      final d = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Grappling Hook', null, then1: [sp(4)]);
      expect(d.attackValue, 3, reason: '3 cards in hand: no blind boost');
    });

    test("Take a Knee heals by the top card's BOOST; Son of a Boxer; Breather", () async {
      final s = Scenario('daredevil', 'medusa');
      final dd = s.hero(s.p1);
      s.place(dd, 4);
      s.place(s.hero(s.p2), 5);
      dd.hp = 10;
      s.deck(s.p1, ['Man Without Fear', 'Man Without Fear', 'Man Without Fear']); // boost 3
      s.give(s.p1, 'Breather');
      s.give(s.p1, 'Breather');
      s.give(s.p1, 'Breather');
      await s.fight(dd, s.hero(s.p2), 'Take A Knee', null);
      expect(dd.hp, 13);
      final t = Scenario('medusa', 'daredevil');
      t.place(t.hero(t.p1), 4);
      t.place(t.hero(t.p2), 5);
      final hp = t.hero(t.p1).hp;
      await t.fight(t.hero(t.p1), t.hero(t.p2), 'Snipe', 'Son Of A Boxer', then2: ['No']); // no blind boost
      expect(t.hero(t.p1).hp, hp, reason: '3 vs 3: Daredevil won, no damage');
      t.discardPile(t.p2, ['Grappling Hook', 'Breather']);
      t.a2.then(card('Grappling Hook'));
      await t.game.playScheme(t.p2, t.give(t.p2, 'Breather'));
      expect(t.p2.hand.map((c) => c.title), ['Grappling Hook']);
    });

    test("Devil of Hell's Kitchen is 8 with an empty deck and reshuffles itself with the top 4 discards", () async {
      final s = Scenario('daredevil', 'medusa');
      final dd = s.hero(s.p1);
      s.place(dd, 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, []);
      s.discardPile(s.p1, ['Feint', 'Feint', 'Breather', 'Breather', 'Grappling Hook']);
      for (var i = 0; i < 3; i++) {
        s.give(s.p1, 'Breather');
      }
      final c = await s.fight(dd, s.hero(s.p2), "Devil of Hell's Kitchen", null);
      expect(c.attackValue, 8);
      expect(s.p1.deck, hasLength(5), reason: 'itself + the top 4 discards');
      expect(s.p1.discard.map((c) => c.title), ['Feint']);
    });

    test('Through Adversity hurts each opposing fighter he moves through', () async {
      final s = Scenario('daredevil', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.place(s.sidekick(s.p2), 6);
      final hp = s.hero(s.p2).hp;
      s.a1.then(sp(7));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Through Adversity'));
      expect(s.hero(s.p1).space, 7);
      expect(s.hero(s.p2).hp, hp - 1);
      expect(s.sidekick(s.p2).defeated, isTrue);
    });
  });

  group('Elektra', () {
    Elektra el(Scenario s, [int seat = 0]) => (seat == 0 ? s.p1 : s.p2).script as Elektra;

    test('first defeat: she and the Hand leave the board, then resurrect at 9 in different zones', () async {
      final s = Scenario('elektra', 'medusa');
      final e = s.hero(s.p1);
      final h1 = s.sidekick(s.p1);
      s.place(e, 4);
      s.place(h1, 9);
      s.place(s.hero(s.p2), 5);
      s.discardPile(s.p1, ['Sai', 'Sai']);
      e.hp = 2;
      await s.fight(s.hero(s.p2), e, 'Snipe', null);
      expect(e.defeated, isFalse);
      expect(e.onBoard, isFalse);
      expect(h1.onBoard, isFalse);
      expect(s.p1.defeated, isFalse, reason: 'she is not defeated');
      s.a1
        ..then(sp(1)) // zone a
        ..then(sp(10)); // zone c
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(el(s).resurrected, isTrue);
      expect([e.hp, e.space, h1.space], [9, 1, 10]);
      expect(s.p1.discard, isEmpty, reason: 'discard shuffled into the deck');
      e.hp = 1;
      s.place(s.hero(s.p2), 2);
      s.place(h1, 9);
      // Only the first defeat is prevented: the second time she falls, the game is over.
      await expectLater(s.fight(s.hero(s.p2), e, 'Snipe', null), throwsA(isA<GameOverSignal>()));
      expect(e.defeated, isTrue);
      expect(s.game.winner, s.p2);
    });

    test('Mystic Assassin hurts her before resurrecting, not after', () async {
      final s = Scenario('elektra', 'medusa');
      final e = s.hero(s.p1);
      s.place(e, 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(e, s.hero(s.p2), 'Mystic Assassin', null);
      expect(e.hp, 7 - 3);
      el(s).resurrected = true;
      await s.fight(e, s.hero(s.p2), 'Mystic Assassin', null);
      expect(e.hp, 7 - 3);
    });

    test('Snakeroot Clan makes a Hand the defender; Hands of Red returns a defeated Hand', () async {
      final s = Scenario('medusa', 'elektra');
      final e = s.hero(s.p2), h = s.sidekick(s.p2);
      s.place(s.hero(s.p1), 4);
      s.place(e, 5);
      s.place(h, 6);
      final c = await s.fight(s.hero(s.p1), e, 'Snipe', 'Snakeroot Clan', then2: [h]);
      expect(c.defender.fighter, h);
      expect(e.space, 6);
      expect(h.defeated, isTrue, reason: 'the Hand took the hit (1 health)');
      final t = Scenario('elektra', 'medusa');
      t.place(t.hero(t.p1), 4);
      t.place(t.hero(t.p2), 5);
      t.sidekick(t.p1).defeated = true;
      await t.fight(t.hero(t.p1), t.hero(t.p2), 'Hands of Red', null, then1: [sp(3)]);
      expect(t.sidekick(t.p1).space, 3);
    });

    test('RESURRECTED effects: Mesmerize discard, Whirlwind, Intercept with a SAI', () async {
      final s = Scenario('elektra', 'medusa');
      final e = s.hero(s.p1);
      s.place(e, 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Snipe');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Mesmerize'));
      expect(s.p2.hand, hasLength(1), reason: 'not resurrected: only a look');
      el(s).resurrected = true;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Mesmerize'));
      expect(s.p2.hand, isEmpty);
      s.give(s.p1, 'Sai');
      final c = await s.fight(s.hero(s.p2), e, 'Second Shot', 'Intercept', then1: [skip], then2: ['Yes']);
      expect(c.defenseValue, 5);
    });

    test('The Fist may hurt the attacking Hand to return to hand and gain an action', () async {
      final s = Scenario('elektra', 'medusa');
      final h = s.sidekick(s.p1, 2);
      s.place(s.hero(s.p1), 0);
      s.place(h, 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 30;
      await s.fight(h, s.hero(s.p2), 'The Fist', null, then1: ['Yes']);
      expect(h.defeated, isTrue);
      expect(s.p1.hand.map((c) => c.title), ['The Fist']);
      expect(s.game.actions, 3);
    });
  });
}
