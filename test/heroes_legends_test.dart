// Card-by-card tests: Bruce Lee, Muhammad Ali.
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/heroes/legends.dart';

import 'support.dart';

void main() {
  group('Bruce Lee', () {
    test('ability: at the end of his turn he may move 1 space', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.a1.then(sp(5));
      await s.p1.script.endOfTurn(s.game, s.p1);
      expect(s.hero(s.p1).space, 5);
      s.a1.then(sp(5)); // staying is allowed
      await s.p1.script.endOfTurn(s.game, s.p1);
      expect(s.hero(s.p1).space, 5);
    });

    test('Be Like Water returns a JEET KUNE DO card from the discard pile', () async {
      final s = Scenario('medusa', 'bruce-lee');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.discardPile(s.p2, ['Regroup', 'Jeet Kune Do: Wrist Lock']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Be Like Water', then1: [skip]);
      expect(s.p2.hand.map((c) => c.title), contains('Jeet Kune Do: Wrist Lock'));
      expect(s.p2.discard.map((c) => c.title), contains('Regroup'));
    });

    test('Corkscrew Finger Jab deals 1 more damage and gains an action', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final hp = s.hero(s.p2).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jeet Kune Do: Corkscrew Finger Jab', null);
      expect(s.hero(s.p2).hp, hp - 3 - 1);
      expect(s.game.actions, 3);
    });

    test('Taste of Blood draws 3 only at 5 health or less', () async {
      final s = Scenario('medusa', 'bruce-lee');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 7; // 7 - (3 - 3) = 7: no damage, above 5
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Taste of Blood', then1: [skip]);
      expect(s.p2.hand, isEmpty);
      s.hero(s.p2).hp = 5;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Taste of Blood', then1: [skip]);
      expect(s.p2.hand, hasLength(3));
    });

    test('Downward Side Kick: opponent discards 1 at random; gain 1 action', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Second Shot');
      s.give(s.p2, 'Second Shot');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jeet Kune Do: Downward Side Kick', null);
      expect(s.p2.hand, hasLength(1));
      expect(s.game.actions, 3);
    });

    test('Intercepting Fist cancels the opponent\'s card; gain 1 action', () async {
      final s = Scenario('bruce-lee', 'bruce-lee');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 5;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jeet Kune Do: Intercepting Fist', 'Taste of Blood');
      expect(s.p2.hand, isEmpty, reason: 'Taste of Blood was canceled');
      expect(s.game.actions, 3);
    });

    test('One-Inch Punch returns to hand only if it defeats the fighter', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p2), 5); // a Harpy: 1 health
      await s.game.playScheme(s.p1, s.give(s.p1, 'One-Inch Punch'));
      expect(s.sidekick(s.p2).defeated, isTrue);
      expect(s.p1.hand.map((c) => c.title), ['One-Inch Punch']);
      s.place(s.hero(s.p2), 3);
      s.p1.hand.clear();
      await s.game.playScheme(s.p1, s.give(s.p1, 'One-Inch Punch'));
      expect(s.p1.hand, isEmpty);
      expect(s.p1.discard.map((c) => c.title), contains('One-Inch Punch'));
    });

    test('Wrist Lock draws 1 and gains 1 action', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jeet Kune Do: Wrist Lock', null);
      expect(s.p1.hand, hasLength(1));
      expect(s.game.actions, 3);
    });

    test('Little Dragon is 6 with an empty hand, then draws 2', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Little Dragon', null);
      expect(c.attackValue, 6);
      expect(s.p1.hand, hasLength(2));
      final c2 = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Little Dragon', null);
      expect(c2.attackValue, 2, reason: 'hand not empty');
    });

    test('"HOO! WHAAAAAA!" returns a JEET KUNE DO card and gains 1 action', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.discardPile(s.p1, ['Jeet Kune Do: Wrist Lock']);
      await s.game.playScheme(s.p1, s.give(s.p1, '"HOO! WHAAAAAA!"'));
      expect(s.p1.hand.map((c) => c.title), ['Jeet Kune Do: Wrist Lock']);
      expect(s.game.actions, 3);
    });

    test('Bring It On pulls a fighter in his zone next to him', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 7);
      s.a1.then(sp(5));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Bring It On'));
      expect(s.hero(s.p2).space, 5);
      expect(s.game.actions, 3);
    });

    test('High Straight Lead is 5 if either fighter started the turn elsewhere', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jeet Kune Do: High Straight Lead', null);
      expect(c.attackValue, 3);
      s.game.turn.startSpace[s.hero(s.p2)] = 9;
      final c2 = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jeet Kune Do: High Straight Lead', null);
      expect(c2.attackValue, 5);
    });

    test('Short Lead Hook may swap with the opposing fighter', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jeet Kune Do: Short Lead Hook', null, then1: ['Yes']);
      expect(s.hero(s.p1).space, 5);
      expect(s.hero(s.p2).space, 4);
      expect(s.game.actions, 3);
    });

    test('Nunchaku: +1 to his attacks this turn', () async {
      final s = Scenario('bruce-lee', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.game.playScheme(s.p1, s.give(s.p1, 'Nunchaku'));
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jeet Kune Do: Wrist Lock', null);
      expect(c.attackValue, 4);
    });
  });

  group('Muhammad Ali', () {
    MuhammadAli ali(Scenario s, [int seat = 0]) => (seat == 0 ? s.p1 : s.p2).script as MuhammadAli;

    test('Butterfly reaches 2 spaces; winning an attack switches to Bee (+2), and back', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isTrue);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Greatest', null);
      expect(c.attackerWon, isTrue);
      expect(ali(s).butterfly, isFalse);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isFalse, reason: 'Bee is plain melee');
      s.place(s.hero(s.p2), 5);
      final c2 = await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Greatest', null);
      expect(c2.attackValue, 4 + 2);
      expect(ali(s).butterfly, isTrue);
    });

    test('Jab draws 1, gains 1 action and (Butterfly) moves up to 2', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jab', null, then1: [sp(2)]);
      expect(s.p1.hand, hasLength(1));
      expect(s.game.actions, 3);
      expect(s.hero(s.p1).space, 2);
    });

    test('Answer the Bell moves 3, heals 2, gains 1 action', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.hero(s.p1).hp = 10;
      s.a1.then(sp(1));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Answer the bell'));
      expect(s.hero(s.p1).space, 1);
      expect(s.hero(s.p1).hp, 12);
      expect(s.game.actions, 3);
    });

    test('Stick and Move locks the opposing card (Butterfly) and deals 1 to an adjacent fighter', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final hp = s.hero(s.p2).hp;
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Stick and Move', null, then1: [s.hero(s.p2)]);
      expect(c.defender.lockPrinted, isTrue);
      expect(s.hero(s.p2).hp, hp - 2 - 1);
    });

    test('Ali Shuffle (won) shuffles a non-scheme card from the discard pile into the deck', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.discardPile(s.p1, ['Answer the bell', 'Jab']);
      final before = s.p1.deck.length;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Ali Shuffle', null, then1: [skip]);
      expect(s.p1.deck.length, before + 1);
      expect(s.p1.discard.map((c) => c.title), containsAll(['Answer the bell', 'Ali Shuffle']));
      expect(s.p1.discard.map((c) => c.title), isNot(contains('Jab')));
    });

    test('Close and Clinch places Ali next to the opposing fighter; neither can leave', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Close and Clinch', null, then1: [sp(7)]);
      expect(s.hero(s.p1).space, 7);
      expect(s.game.cannotLeave(s.hero(s.p1)), isTrue);
      expect(s.game.cannotLeave(s.hero(s.p2)), isTrue);
    });

    test('Fancy Footwork ignores the opposing card if they share no zone', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 2); // zone a
      s.place(s.hero(s.p2), 4); // zone b; Butterfly reaches 2 spaces
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Fancy Footwork', 'Second Shot', then1: [sp(2)]);
      expect(c.defenseValue, 0);
    });

    test('Hard to be Humble (Butterfly) looks at the opponent\'s hand, then moves Ali up to 2', () async {
      final s = Scenario('medusa', 'muhammad-ali');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Second Shot');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Hard to be humble', then1: [skip], then2: [sp(7)]);
      final looks = s.events.whereType<Revealed>().where((e) => e.viewer == s.p2);
      expect(looks, isNotEmpty);
      expect(s.hero(s.p2).space, 7);
    });

    test('Louisville Lip heals 1, draws 2 and, after a won combat, makes each opponent discard', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p1).hp = 10;
      s.give(s.p2, 'Second Shot');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Louisville lip'));
      expect(s.hero(s.p1).hp, 11);
      expect(s.p1.hand, hasLength(2));
      expect(s.p2.hand, hasLength(1), reason: 'no combat won yet');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Greatest', null);
      await s.game.playScheme(s.p1, s.give(s.p1, 'Louisville lip'));
      expect(s.p2.hand, isEmpty);
    });

    test('Rope-a-Dope heals 3 when Ali loses (Butterfly)', () async {
      final s = Scenario('medusa', 'muhammad-ali');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 10;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Rope-a-dope', then1: [skip]);
      // Second Shot 3 vs 2: 1 damage, Ali lost, then +3.
      expect(s.hero(s.p2).hp, 10 - 1 + 3);
    });

    test('Champion of the World moves a fighter in the combat and (Butterfly) draws 1', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Champion of the world', null, then1: [s.hero(s.p2), sp(7)]);
      expect(s.hero(s.p2).space, 7);
      expect(s.p1.hand, hasLength(1));
    });

    test('Stronger than the Skill (won) shuffles one of their cards into their deck', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Second Shot');
      final deck = s.p2.deck.length;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Stronger than the skill', null, then2: [skip]);
      expect(s.p2.hand, isEmpty);
      expect(s.p2.deck.length, deck + 1);
    });

    test('The Greatest gains 2 actions after 6+ combat damage this turn', () async {
      final s = Scenario('muhammad-ali', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Greatest', null); // 4 damage, now Bee
      expect(s.game.actions, 2);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Greatest', null); // 6 more: 10 this turn
      expect(s.game.actions, 4);
    });
  });
}
