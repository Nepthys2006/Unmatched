// Card-by-card tests: Cloak & Dagger, Ms. Marvel (Marvel Teen Spirit).
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

void main() {
  group('Cloak & Dagger', () {
    Fighter cloak(Scenario s) => s.p1.fighters.firstWhere((f) => f.id == 'cloak');
    Fighter dagger(Scenario s) => s.p1.fighters.firstWhere((f) => f.id == 'dagger');

    test('two heroes of 8 health; you lose only when both are defeated', () {
      final s = Scenario('cloak-dagger', 'medusa');
      expect([cloak(s).hp, dagger(s).hp], [8, 8]);
      expect([cloak(s).name, dagger(s).name], ['Cloak', 'Dagger']);
      cloak(s).defeated = true;
      expect(s.p1.defeated, isFalse);
      dagger(s).defeated = true;
      expect(s.p1.defeated, isTrue);
    });

    test('Umbra: Cloak dealing 2+ makes them discard; Refraction: Dagger dealing 2+ gains an action', () async {
      final s = Scenario('cloak-dagger', 'medusa');
      s.place(cloak(s), 4);
      s.place(dagger(s), 6);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Snipe');
      s.give(s.p2, 'Snipe');
      s.give(s.p1, 'Commanding Impact');
      s.a1.then(card('Commanding Impact'));
      s.a2.then(skip);
      await s.game.attack(cloak(s), s.hero(s.p2));
      expect(s.p2.hand, hasLength(1), reason: 'Umbra');
      s.give(s.p1, 'Commanding Impact');
      s.a1.then(card('Commanding Impact'));
      s.a2.then(skip);
      final actions = s.game.actions;
      await s.game.attack(dagger(s), s.hero(s.p2));
      expect(s.game.actions, actions + 1, reason: 'Refraction');
    });

    test('Living Shadow: Dagger swaps with Cloak, Cloak defends at 4', () async {
      final s = Scenario('medusa', 'cloak-dagger');
      final c = s.p2.fighters.firstWhere((f) => f.id == 'cloak'), d = s.p2.fighters.firstWhere((f) => f.id == 'dagger');
      s.place(s.hero(s.p1), 4);
      s.place(d, 5);
      s.place(c, 6);
      final r = await s.fight(s.hero(s.p1), d, 'Snipe', 'Living Shadow');
      expect(r.defender.fighter, c);
      expect(r.defenseValue, 4);
      expect([d.space, c.space], [6, 5]);
    });

    test('Channel the Dark (Cloak) pulls the target next to Dagger and gains an action; Perfect Balance', () async {
      final s = Scenario('cloak-dagger', 'medusa');
      s.place(cloak(s), 4);
      s.place(dagger(s), 9);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 30;
      await s.fight(cloak(s), s.hero(s.p2), 'Channel the Dark', null, then1: [sp(10)]);
      expect(s.hero(s.p2).space, 10);
      expect(s.game.actions, 3);
      s.place(s.hero(s.p2), 5);
      s.place(dagger(s), 6);
      expect((await s.fight(cloak(s), s.hero(s.p2), 'Perfect Balance', null)).attackValue, 6);
    });

    test('Chosen Fate moves health between them; Living Light; Lightforce Barrage hurts Dagger', () async {
      final s = Scenario('cloak-dagger', 'medusa');
      s.place(cloak(s), 4);
      s.place(dagger(s), 3);
      s.place(s.hero(s.p2), 5);
      dagger(s).hp = 4;
      s.a1
        ..then(cloak(s)) // plays the scheme
        ..then(cloak(s))
        ..then(3);
      await s.game.playScheme(s.p1, s.give(s.p1, 'Chosen Fate'));
      expect([cloak(s).hp, dagger(s).hp], [5, 7]);
      expect(s.p1.hand, hasLength(2));
      s.place(dagger(s), 6);
      s.hero(s.p2).hp = 30;
      await s.fight(dagger(s), s.hero(s.p2), 'Lightforce Barrage', 'Feint');
      expect(dagger(s).hp, 7 - 5, reason: "can't be canceled: 7 vs 2, Dagger takes the 5 she dealt");
    });

    test('Darkforce Dimension places the target anywhere and they discard', () async {
      final s = Scenario('cloak-dagger', 'medusa');
      s.place(cloak(s), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Snipe');
      await s.fight(cloak(s), s.hero(s.p2), 'Darkforce Dimension', null, then1: [sp(11)]);
      expect(s.hero(s.p2).space, 11);
      expect(s.p2.hand, isEmpty);
    });
  });

  group('Ms. Marvel', () {
    test('Stretchy: moves 1 at the start of her turn; attacks up to 2 spaces away', () async {
      final s = Scenario('ms-marvel', 'medusa');
      final k = s.hero(s.p1);
      s.place(k, 4);
      s.place(s.hero(s.p2), 6);
      expect(s.game.inReach(k, s.hero(s.p2)), isTrue);
      s.place(s.hero(s.p2), 7);
      expect(s.game.inReach(k, s.hero(s.p2)), isFalse);
      s.a1.then(sp(5));
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(k.space, 5);
    });

    test("Fangirl is the hand size; Embiggen is 6 in more zones; I'm Not Touching You draws 2 apart", () async {
      final s = Scenario('ms-marvel', 'medusa');
      final k = s.hero(s.p1);
      s.place(k, 3); // zones a and b
      s.place(s.hero(s.p2), 4); // zone b
      for (var i = 0; i < 3; i++) {
        s.give(s.p1, 'Feint');
      }
      expect((await s.fight(k, s.hero(s.p2), 'Fangirl', null)).attackValue, 3);
      expect((await s.fight(k, s.hero(s.p2), 'Embiggen', null)).attackValue, 6);
      s.place(k, 2); // zone a, two spaces from Medusa in zone b
      s.place(s.hero(s.p2), 4);
      final before = s.p1.hand.length;
      await s.fight(k, s.hero(s.p2), "I'm Not Touching You", null);
      expect(s.p1.hand.length, before + 2);
    });

    test('Shrink! Shrink! Shrink! does both when apart; Easy Peasy; Gyro and Fries; Friends and Family', () async {
      final s = Scenario('ms-marvel', 'medusa');
      final k = s.hero(s.p1);
      s.place(k, 2);
      s.place(s.hero(s.p2), 4);
      s.give(s.p2, 'Snipe');
      await s.fight(k, s.hero(s.p2), 'Shrink! Shrink! Shrink!', null, then1: [sp(7)]);
      expect(s.p2.hand, isEmpty);
      expect(s.hero(s.p2).space, 7);
      k.hp = 10;
      for (var i = 0; i < 4; i++) {
        s.give(s.p1, 'Feint');
      }
      await s.game.playScheme(s.p1, s.give(s.p1, 'Gyro and Fries'));
      expect(k.hp, 12);
      expect(s.game.actions, 3);
      s.p1.hand.clear();
      s.a1.then('Yes');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Friends and Family'));
      expect(s.p1.hand, hasLength(7), reason: 'drew 2, then spent an action to draw to 7');
      expect(s.game.actions, 2);
    });
  });
}
