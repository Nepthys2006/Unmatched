// Card-by-card tests: Bloody Mary, Chupacabra, Pandora (Battle of Legends).
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/heroes/bol_more.dart';

import 'support.dart';

void main() {
  group('Bloody Mary', () {
    test('ability: exactly 3 cards in hand at the start of the turn gains 1 action', () async {
      final s = Scenario('bloody-mary', 'medusa');
      s.place(s.hero(s.p1), 4);
      for (var i = 0; i < 3; i++) {
        s.give(s.p1, 'Evade');
      }
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(s.game.actions, 3);
      s.give(s.p1, 'Evade');
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(s.game.actions, 3, reason: '4 cards: no action');
    });

    test('Speak Three Times is 7 as the third action; Ghostly Touch heals 3 then', () async {
      final s = Scenario('bloody-mary', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), 'Speak Three Times', null)).attackValue, 3);
      s.game.turn.actionsTaken = 2;
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), 'Speak Three Times', null)).attackValue, 7);
      s.hero(s.p1).hp = 10;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Ghostly Touch', null, then1: [skip]);
      expect(s.hero(s.p1).hp, 13);
    });

    test('Stolen Memories: they discard the chosen card, or their hero takes its BOOST', () async {
      final s = Scenario('bloody-mary', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 9);
      s.give(s.p2, 'Second Shot'); // boost 3
      s.a1.then(card('Second Shot'));
      s.a2.then('No');
      final hp = s.hero(s.p2).hp;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Stolen Memories'));
      expect(s.hero(s.p2).hp, hp - 3);
      expect(s.p2.hand, hasLength(1));
      s.a1.then(card('Second Shot'));
      s.a2.then('Yes');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Stolen Memories'));
      expect(s.p2.hand, isEmpty);
    });

    test('Bloody Requiem is followed by Bloody Reprise, worth the printed value played against it', () async {
      final s = Scenario('bloody-mary', 'medusa');
      final mary = s.hero(s.p1);
      s.place(mary, 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Hiss and Slither'); // defense 4
      s.give(s.p1, 'Bloody Requiem');
      s.a1.then(card('Bloody Requiem'));
      s.a2.then(card('Hiss and Slither'));
      final hp = s.hero(s.p2).hp;
      await s.game.attack(mary, s.hero(s.p2));
      // Requiem 3 vs 4: no damage. Reprise: value = 4 (printed value of Hiss and Slither).
      expect(s.hero(s.p2).hp, hp - 4);
    });

    test('Broken Glass: matching values draws 1 and deals 2', () async {
      final s = Scenario('bloody-mary', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final hp = s.hero(s.p2).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Broken Glass', 'Hiss and Slither', then1: ['+1']); // 4 vs 4
      expect(s.p1.hand, hasLength(1));
      expect(s.hero(s.p2).hp, hp - 2);
    });

    test('Mirror Image copies the printed value; Jump Scare is 6 away from her start zone', () async {
      final s = Scenario('medusa', 'bloody-mary');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Mirror Image', then1: [skip]);
      expect(c.defenseValue, 3);
      final t = Scenario('bloody-mary', 'medusa');
      t.place(t.hero(t.p1), 9);
      t.place(t.hero(t.p2), 10);
      t.game.turn.startSpace[t.hero(t.p1)] = 1; // started in zone a, now in zone c
      expect((await t.fight(t.hero(t.p1), t.hero(t.p2), 'Jump Scare', null)).attackValue, 6);
    });

    test('Out of the Mirror, Infinity Mirror, Trick of the Light, Closer Than She Appears, Evade', () async {
      final s = Scenario('bloody-mary', 'medusa');
      final mary = s.hero(s.p1);
      s.place(mary, 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Second Shot'); // boost 3
      expect((await s.fight(mary, s.hero(s.p2), 'Out of the Mirror', null)).attackValue, 1 + 3);
      await s.fight(mary, s.hero(s.p2), 'Infinity Mirror', null, then1: [s.hero(s.p2), sp(8)]);
      expect(s.hero(s.p2).space, 8);
      s.place(s.hero(s.p2), 5);
      await s.fight(mary, s.hero(s.p2), 'Trick of the Light', null, then1: [sp(6)]);
      expect(mary.space, 6);
      s.a1.then(sp(7));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Closer Than She Appears'));
      expect(mary.space, 7);
    });
  });

  group('Chupacabra', () {
    test('The Hunger: may draw after attacking', () async {
      final s = Scenario('chupacabra', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Feeding');
      s.a1
        ..then(card('Feeding'))
        ..then('Yes');
      await s.game.attack(s.hero(s.p1), s.hero(s.p2));
      expect(s.p1.hand, hasLength(1));
    });

    test('Wounded Beast, Feeding and Ravenous Lunge at 7 health or less', () async {
      final s = Scenario('chupacabra', 'medusa');
      final c = s.hero(s.p1);
      s.place(c, 4);
      s.place(s.hero(s.p2), 5);
      expect((await s.fight(c, s.hero(s.p2), 'Wounded beast', null)).attackValue, 3);
      c.hp = 7;
      expect((await s.fight(c, s.hero(s.p2), 'Wounded beast', null)).attackValue, 5);
      await s.fight(c, s.hero(s.p2), 'Feeding', null);
      expect(c.hp, 8);
      expect(s.game.actions, 3);
      await s.fight(c, s.hero(s.p2), 'Ravenous lunge', null);
      expect(c.hp, 10);
    });

    test('Blood in the Air may BOOST after a won combat this turn', () async {
      final s = Scenario('chupacabra', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Feint'); // boost 2
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), 'Blood in the air', null)).attackValue, 4, reason: 'nothing won yet');
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Blood in the air', null, then1: [card('Feint')]);
      expect(c.attackValue, 4 + 2);
    });

    test('Natural Toughness returns to hand when Chupacabra loses', () async {
      final s = Scenario('medusa', 'chupacabra');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Natural toughness'); // 3 vs 3: Chupacabra won (no boost: empty hand)
      expect(s.p2.hand, isEmpty);
      s.p1.hand.clear();
      s.give(s.p1, 'Feint');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Natural toughness', then1: [card('Feint')]);
      expect(s.p2.hand.map((c) => c.title), ['Natural toughness']);
    });

    test('The More They Struggle is twice their printed value; Traveler moves through', () async {
      final s = Scenario('chupacabra', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'The more they struggle', 'Hiss and Slither');
      expect(c.attackValue, 8);
      s.a1.then(sp(7));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Traveler of the night'));
      expect(s.hero(s.p1).space, 7);
      expect(s.game.actions, 3);
    });

    test('Unsettle: 1 discard, or 2 if Chupacabra takes 2 damage', () async {
      final s = Scenario('chupacabra', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      for (var i = 0; i < 3; i++) {
        s.give(s.p2, 'Snipe');
      }
      s.a1.then('Yes');
      final hp = s.hero(s.p1).hp;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Unsettle'));
      expect(s.p2.hand, hasLength(1));
      expect(s.hero(s.p1).hp, hp - 2);
    });

    test('Tooth and Tail hits up to 2 adjacent fighters and heals per fighter hit', () async {
      final s = Scenario('chupacabra', 'medusa');
      final c = s.hero(s.p1);
      s.place(c, 5);
      s.place(s.hero(s.p2), 4);
      s.place(s.sidekick(s.p2), 6);
      c.hp = 8;
      await s.fight(c, s.hero(s.p2), 'Tooth and tail', null, then1: [s.hero(s.p2), s.sidekick(s.p2)]);
      expect(s.sidekick(s.p2).defeated, isTrue);
      expect(c.hp, 10);
    });
  });

  group('Pandora', () {
    Pandora pan(Scenario s) => s.p1.script as Pandora;
    void stack(Scenario s, List<String> names) {
      pan(s).box
        ..clear()
        ..addAll([for (final n in names) miseries.firstWhere((m) => m.name == n)]);
    }

    test("Pandora's Box: reveal until you stop; Greed draws, Toil adds +1 this turn", () async {
      final s = Scenario('pandora', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      stack(s, ['Greed', 'Toil', 'Misfortune']);
      s.a1
        ..then('Yes')
        ..then('No');
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(pan(s).revealed.map((m) => m.name), ['Greed', 'Toil']);
      expect(s.p1.hand, hasLength(1));
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Hindsight', null);
      expect(c.attackValue, 3 + 1);
      await s.p1.script.endOfTurn(s.game, s.p1);
      expect(pan(s).revealed, isEmpty);
      expect(pan(s).box, hasLength(3));
    });

    test('3 feathers: the box must close and Pandora takes 1 damage per revealed MISERY', () async {
      final s = Scenario('pandora', 'medusa');
      s.place(s.hero(s.p1), 4);
      stack(s, ['Woe', 'Greed', 'Misfortune', 'Pain']);
      s.a1
        ..then(sp(3)) // Woe: summon a Kakodaemon in her zone
        ..then('Yes')
        ..then('Yes');
      final hp = s.hero(s.p1).hp;
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(pan(s).revealed.map((m) => m.name), ['Woe', 'Greed', 'Misfortune']);
      expect(s.hero(s.p1).hp, hp - 3);
      expect(s.sidekick(s.p1).onBoard, isTrue);
      expect(s.sidekick(s.p1).space, 3);
    });

    test('Kakodaemons do not start on the board', () {
      final s = Scenario('pandora', 'medusa');
      expect(s.p1.script.startsInReserve(s.sidekick(s.p1)), isTrue);
    });

    test("Hera's Curiosity, Zeus's Mischief and Aphrodite's Beauty count revealed MISERIES", () async {
      final s = Scenario('pandora', 'medusa');
      final p = s.hero(s.p1);
      s.place(p, 4);
      s.place(s.hero(s.p2), 5);
      stack(s, ['Hope', 'Confusion', 'Misfortune']);
      s.a1
        ..then('Yes')
        ..then(sp(4)) // Confusion: stay
        ..then('No');
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(pan(s).revealed, hasLength(2));
      final c = await s.fight(p, s.hero(s.p2), "Hera's Curiosity", null);
      expect(c.attackValue, 3 + 2);
      expect(s.events.whereType<Revealed>().where((e) => e.viewer == s.p1), isNotEmpty);
      p.hp = 5;
      await s.fight(p, s.hero(s.p2), "Aphrodite's Beauty", null);
      expect(p.hp, 7);
      s.p1.hand.clear();
      s.a1.then(sp(6)); // Medusa is the only opposing fighter: chosen automatically
      await s.game.playScheme(s.p1, s.give(s.p1, "Zeus's Mischief"));
      expect(s.p1.hand, hasLength(2));
      expect(s.hero(s.p2).space, 6);
    });

    test('Spite, Malice, Offering to the Gods, Guided by the Fates, Celestial Raiments, Divine Intervention', () async {
      final s = Scenario('pandora', 'medusa');
      final p = s.hero(s.p1);
      final k = s.sidekick(s.p1);
      s.place(p, 4);
      s.place(k, 6);
      s.place(s.hero(s.p2), 5);
      final hp = s.hero(s.p2).hp;
      await s.fight(k, s.hero(s.p2), 'Spite', null);
      expect(s.hero(s.p2).hp, hp - 3 - 1);
      s.give(s.p2, 'Snipe');
      await s.fight(k, s.hero(s.p2), 'Malice', null);
      expect(s.p2.hand, isEmpty);
      final c = await s.fight(s.hero(s.p2), p, 'Second Shot', 'Celestial Raiments', then1: [skip]);
      expect(c.attackValue, 0);
      await s.fight(p, s.hero(s.p2), 'DIVINE INTERVENTION', null, then1: [sp(0)]);
      expect(p.space, 0);
    });
  });
}
