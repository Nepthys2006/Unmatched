// Card-by-card tests: Squirrel Girl (Marvel Teen Spirit) and the small-fighter rules.
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

void main() {
  List<Fighter> squirrels(Scenario s, [Player? p]) => (p ?? s.p1).fighters.where((f) => f.id == 'squirrel').toList();

  group('Small fighters', () {
    test('squirrels start off the board; 8 of them, 1 health, small', () {
      final s = Scenario('squirrel-girl', 'medusa');
      final q = squirrels(s);
      expect(q, hasLength(8));
      expect(q.every((f) => f.hp == 1 && f.isSmall), isTrue);
      expect(s.hero(s.p1).isSmall, isFalse);
      expect(q.first.name, 'Squirrel 1');
    });

    test('share a space with any fighter, up to 4; adjacent to who they share with', () {
      final s = Scenario('squirrel-girl', 'medusa');
      final q = squirrels(s), m = s.hero(s.p2);
      s.place(m, 5);
      for (var i = 0; i < 4; i++) {
        expect(s.game.canOccupy(q[i], 5), isTrue);
        s.place(q[i], 5);
      }
      expect(s.game.canOccupy(q[4], 5), isFalse, reason: 'at most 4 small fighters in a space');
      expect(s.game.canOccupy(s.hero(s.p1), 5), isFalse, reason: 'still one normal fighter per space');
      expect(s.game.adjacent(q[0], m), isTrue);
      expect(s.game.inReach(q[0], m), isTrue);
      expect(s.game.inReach(m, q[0]), isTrue);
      expect(s.game.fighterAt(5), m, reason: 'the normal fighter is the one shown first');
    });

    test('opposing fighters move through squirrels (and end on them); squirrels move through enemies', () {
      final s = Scenario('squirrel-girl', 'medusa');
      final q = squirrels(s), m = s.hero(s.p2);
      s.place(m, 6);
      s.place(q[0], 5);
      final reach = s.game.reachable(m, 2);
      expect(reach.keys, containsAll([4, 5]));
      expect(reach[4], [6, 5, 4]);
      s.place(m, 3);
      s.place(q[0], 2);
      expect(s.game.reachable(q[0], 2).keys, containsAll([3, 4]));
    });

    test('damage to one squirrel defeats every squirrel in its space, not the others', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final q = squirrels(s);
      s.place(q[0], 5);
      s.place(q[1], 5);
      s.place(q[2], 6);
      await s.game.damage(q[0], 1);
      expect([q[0].defeated, q[1].defeated, q[2].defeated], [true, true, false]);
      expect(s.p1.defeated, isFalse);
    });
  });

  group('Squirrel Girl', () {
    test('Go Nuts: may summon a squirrel next to her; when all 8 are out, one moves instead', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final sg = s.hero(s.p1), q = squirrels(s);
      s.place(sg, 5);
      s.place(s.hero(s.p2), 11);
      s.a1.then(sp(12));
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(q.first.space, 12);
      s.a1.then(skip);
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(q.where((f) => f.onBoard), hasLength(1), reason: 'summoning is optional');
      for (var i = 0; i < 8; i++) {
        s.place(q[i], 0);
      }
      s.a1
        ..then(q[3])
        ..then(sp(4));
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(q[3].space, 4);
    });

    test('Kick Butts +1 per adjacent squirrel; Bite of Steel 5 with 4+ squirrels in the zone', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final sg = s.hero(s.p1), q = squirrels(s), m = s.hero(s.p2);
      s.place(sg, 4);
      s.place(m, 5);
      m.hp = 30;
      s.place(q[0], 6);
      s.place(q[1], 5);
      s.place(q[2], 12);
      expect((await s.fight(sg, m, 'Kick Butts', null)).attackValue, 4);
      expect((await s.fight(q[0], m, 'Bite of Steel', null)).attackValue, 2, reason: 'only 3 squirrels in the zone');
      s.place(q[3], 7);
      expect((await s.fight(q[0], m, 'Bite of Steel', null)).attackValue, 5);
    });

    test('Unbeatable Squirrel Girl: 4+ adjacent squirrels cancel and ignore the opposing card', () async {
      final s = Scenario('medusa', 'squirrel-girl');
      final m = s.hero(s.p1), sg = s.hero(s.p2), q = squirrels(s, s.p2);
      s.place(m, 5);
      s.place(sg, 6);
      sg.hp = 13;
      final r1 = await s.fight(m, sg, 'Snipe', 'Unbeatable Squirrel Girl');
      expect(r1.attackValue, r1.attacker.card!.def.value, reason: 'no squirrels: normal combat');
      s.place(q[0], 5);
      s.place(q[1], 4);
      s.place(q[2], 4);
      s.place(q[3], 6);
      final r2 = await s.fight(m, sg, 'Snipe', 'Unbeatable Squirrel Girl');
      expect(r2.attackValue, 0);
      expect(r2.attacker.canceled, isTrue);
    });

    test('Horde of Squirrels: 2 damage to a fighter in a space with 4+ squirrels next to it', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final sg = s.hero(s.p1), q = squirrels(s), m = s.hero(s.p2);
      s.place(sg, 0);
      s.place(m, 5);
      expect(s.game.schemeFighters(s.p1, s.give(s.p1, 'Horde of Squirrels')), isNotEmpty);
      s.place(q[0], 4);
      s.place(q[1], 6);
      s.place(q[2], 12);
      s.place(q[3], 5);
      final hp = m.hp;
      s.a1.then(m);
      await s.game.playScheme(s.p1, s.p1.hand.last);
      expect(m.hp, hp - 2);
    });

    test('Nutwork of Spies: 1 card, or 2 when one of their fighters has 4+ squirrels adjacent', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final sg = s.hero(s.p1), q = squirrels(s), m = s.hero(s.p2);
      s.place(sg, 0);
      s.place(m, 5);
      for (final t in ['Snipe', 'Snipe', 'Snipe', 'Snipe']) {
        s.give(s.p2, t);
      }
      await s.game.playScheme(s.p1, s.give(s.p1, 'Nutwork of Spies'));
      expect(s.p2.hand, hasLength(3));
      for (var i = 0; i < 4; i++) {
        s.place(q[i], i < 2 ? 4 : 6);
      }
      await s.game.playScheme(s.p1, s.give(s.p1, 'Nutwork of Spies'));
      expect(s.p2.hand, hasLength(1));
    });

    test('Eat Nuts heals 2 and summons next to her; Get \'Em Tippy-Toe! summons two anywhere', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final sg = s.hero(s.p1), q = squirrels(s), m = s.hero(s.p2);
      s.place(sg, 5);
      s.place(m, 6);
      sg.hp = 8;
      s.a1.then(sp(4));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Eat Nuts'));
      expect(sg.hp, 10);
      expect(q.first.space, 4);
      m.hp = 30;
      await s.fight(sg, m, "Get 'Em Tippy-Toe!", null, then1: [sp(0), sp(11)]);
      expect(q.where((f) => f.onBoard).map((f) => f.space), containsAll([0, 11]));
    });

    test('Squirmish: summon a squirrel in her space, then place her in her zone', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final sg = s.hero(s.p1), q = squirrels(s), m = s.hero(s.p2);
      s.place(sg, 5);
      s.place(m, 6);
      m.hp = 30;
      await s.fight(sg, m, 'Squirmish', null, then1: [sp(3)]);
      expect(q.first.space, 5);
      expect(sg.space, 3);
    });

    test('Squirgility: moves through sidekicks, and their spaces cost nothing', () async {
      final s = Scenario('medusa', 'squirrel-girl');
      final m = s.hero(s.p1), sg = s.hero(s.p2), q = squirrels(s, s.p2);
      s.place(m, 4);
      s.place(sg, 5);
      s.place(q[0], 6);
      s.place(q[1], 7);
      s.place(s.sidekick(s.p1, 1), 8);
      final routes = (s.p2.script as dynamic).squirgilityRoutes(sg, 3) as Map<int, List<int>>;
      expect(routes.keys, contains(11), reason: '6, 7, 8 hold sidekicks: 9, 10, 11 are the 3 paid steps');
      expect(routes.keys, isNot(contains(8)), reason: "can't end on Medusa's Harpy");
      final r = await s.fight(m, sg, 'Snipe', 'Squirgility', then2: [sp(11)]);
      expect(r.defender.fighter.space, 11);
    });

    test('Call of the Mild: 4 with 4+ squirrels in the zone, draws 2 when it wins', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final sg = s.hero(s.p1), q = squirrels(s), m = s.hero(s.p2);
      s.place(sg, 4);
      s.place(m, 5);
      m.hp = 30;
      for (var i = 0; i < 4; i++) {
        s.place(q[i], [3, 6, 7, 12][i]);
      }
      final hand = s.p1.hand.length;
      final r = await s.fight(sg, m, 'Call of the Mild', null);
      expect(r.attackValue, 4);
      expect(s.p1.hand.length, hand + 2);
    });

    test('Fuzzball Special moves each squirrel up to 3', () async {
      final s = Scenario('squirrel-girl', 'medusa');
      final sg = s.hero(s.p1), q = squirrels(s), m = s.hero(s.p2);
      s.place(sg, 4);
      s.place(m, 5);
      m.hp = 30;
      s.place(q[0], 0);
      s.place(q[1], 11);
      await s.fight(sg, m, 'Fuzzball Special', null, then1: [q[0], sp(3), sp(8)]);
      expect([q[0].space, q[1].space], [3, 8]);
    });
  });
}
