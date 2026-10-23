// Card-by-card tests: Ghost Rider, Luke Cage, Deadpool (Marvel).
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/heroes/redemption_row.dart';

import 'support.dart';

void main() {
  group('Ghost Rider', () {
    GhostRider gr(Scenario s) => s.p1.script as GhostRider;

    test('starts with 5 Hellfire; a maneuver may spend 1 to move 4 through enemies, burning them', () async {
      final s = Scenario('ghost-rider', 'medusa');
      final r = s.hero(s.p1);
      s.place(r, 2);
      s.place(s.hero(s.p2), 4);
      expect(gr(s).hellfire, 5);
      s.a1
        ..then('Yes')
        ..then(sp(6));
      final hp = s.hero(s.p2).hp;
      await s.p1.script.maneuverMove(r, 2, boosted: false);
      expect(r.space, 6);
      expect(s.hero(s.p2).hp, hp - 1);
      expect(gr(s).hellfire, 4);
    });

    test('Control the Demon adds Hellfire; Deal With the Devil spends it; Penance Stare doubles for 2', () async {
      final s = Scenario('ghost-rider', 'medusa');
      final r = s.hero(s.p1);
      s.place(r, 4);
      s.place(s.hero(s.p2), 5);
      expect((await s.fight(r, s.hero(s.p2), 'Control The Demon', null)).attackValue, 5);
      final t = Scenario('medusa', 'ghost-rider');
      t.place(t.hero(t.p1), 4);
      t.place(t.hero(t.p2), 5);
      final c = await t.fight(t.hero(t.p1), t.hero(t.p2), 'Snipe', 'Deal With The Devil', then2: [3]);
      expect(c.defenseValue, 2 + 3);
      expect((t.p2.script as GhostRider).hellfire, 2);
      final d = await s.fight(r, s.hero(s.p2), 'Penance Stare', 'Hiss and Slither', then1: ['Yes']); // boost 3, twice
      expect(d.attackValue, 3 + 3 + 3);
      expect(gr(s).hellfire, 3);
    });

    test('Chains of Hellfire sets 5; Stoke the Flames gains the damage taken; Blaze of Glory hits the zone', () async {
      final s = Scenario('medusa', 'ghost-rider');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final g = s.p2.script as GhostRider;
      g.hellfire = 1;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Stoke The Flames', then1: [skip]); // 3 vs 2: 1
      expect(g.hellfire, 2);
      final t = Scenario('ghost-rider', 'medusa');
      final r = t.hero(t.p1);
      t.place(r, 4);
      t.place(t.hero(t.p2), 5);
      t.place(t.sidekick(t.p2), 7);
      final hp = t.hero(t.p2).hp;
      await t.fight(r, t.hero(t.p2), 'Blaze of Glory', null, then1: [2]);
      expect(t.hero(t.p2).hp, hp - 2 - 2);
      expect(t.sidekick(t.p2).defeated, isTrue);
      expect(r.hp, 17 - 2, reason: 'him too');
      await t.game.playScheme(t.p1, t.give(t.p1, 'Chains of Hellfire'));
      expect((t.p1.script as GhostRider).hellfire, 5);
    });
  });

  group('Luke Cage', () {
    test('takes 2 less combat damage', () async {
      final s = Scenario('medusa', 'luke-cage');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', null); // 3 damage - 2
      expect(s.hero(s.p2).hp, 13 - 1);
    });

    test("Got My Back? makes Luke the defender; Skin Like Titanium hits back; Where's My Money?", () async {
      final s = Scenario('she-hulk', 'luke-cage');
      final luke = s.hero(s.p2), misty = s.sidekick(s.p2);
      s.place(s.hero(s.p1), 4);
      s.place(misty, 5);
      s.place(luke, 6);
      final c = await s.fight(s.hero(s.p1), misty, 'Omega-Level Threat', 'Got My Back?', then2: ['Yes']);
      expect(c.defender.fighter, luke);
      expect(luke.hp, 13 - (5 - 1 - 2), reason: 'Luke takes 2 less');
      final hp = s.hero(s.p1).hp;
      s.place(luke, 5);
      s.place(misty, 9);
      await s.fight(s.hero(s.p1), luke, 'Omega-Level Threat', 'Skin Like Titanium');
      expect(s.hero(s.p1).hp, hp - 3);
      final t = Scenario('luke-cage', 'medusa');
      t.place(t.hero(t.p1), 0);
      t.place(t.hero(t.p2), 8);
      t.a1.then(sp(7));
      await t.game.playScheme(t.p1, t.give(t.p1, "Where's My Money?"));
      expect(t.hero(t.p1).space, 7);
      expect(t.game.actions, 3);
    });

    test('Trash Talk ends the turn after a win; Daughter of the Dragon; Power Man burns', () async {
      final s = Scenario('luke-cage', 'medusa');
      final luke = s.hero(s.p1), misty = s.sidekick(s.p1);
      s.place(luke, 4);
      s.place(misty, 6);
      s.place(s.hero(s.p2), 5);
      expect((await s.fight(misty, s.hero(s.p2), 'Daughter of the Dragon', null)).attackValue, 6);
      s.place(misty, 0);
      final hp = s.hero(s.p2).hp;
      await s.fight(s.hero(s.p2), luke, 'Snipe', 'Power Man', then2: [sp(8)]);
      expect(s.hero(s.p2).space, 8);
      expect(s.hero(s.p2).hp, hp - 1);
      final t = Scenario('medusa', 'luke-cage');
      t.place(t.hero(t.p1), 4);
      t.place(t.hero(t.p2), 5);
      await t.fight(t.hero(t.p1), t.hero(t.p2), 'Second Shot', 'Trash Talk');
      expect(t.game.turnEnded, isTrue);
    });
  });

  group('Deadpool', () {
    test('recovers 1 after attacking; +5 against a Logan', () async {
      final s = Scenario('deadpool', 'medusa');
      final w = s.hero(s.p1);
      s.place(w, 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 40;
      w.hp = 5;
      s.give(s.p1, 'Underrated Super Heroes');
      s.a1.then(card('Underrated Super Heroes'));
      s.a2.then(skip);
      await s.game.attack(w, s.hero(s.p2));
      expect(w.hp, 6);
      s.p2.label = 'Logan';
      expect((await s.fight(w, s.hero(s.p2), 'Underrated Super Heroes', null)).attackValue, 6 + 5);
    });

    test("Chimichanga Break! and Exploding Card! ask the player; I'm Not Wearing Pants is 5", () async {
      final s = Scenario('deadpool', 'medusa');
      final w = s.hero(s.p1);
      s.place(w, 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 40;
      expect((await s.fight(w, s.hero(s.p2), 'Chimichanga Break!', null, then1: ['Yes'])).attackValue, 5);
      expect((await s.fight(w, s.hero(s.p2), 'Chimichanga Break!', null, then1: ['No'])).attackValue, 2);
      expect((await s.fight(w, s.hero(s.p2), 'Exploding Card!', null, then1: ['Yes'])).attackValue, 4);
      expect((await s.fight(w, s.hero(s.p2), "I'm Not Wearing Pants", null)).attackValue, 5);
    });

    test('Call Me is 4 once their name is written on it', () async {
      final s = Scenario('deadpool', 'medusa');
      final w = s.hero(s.p1);
      s.place(w, 4);
      s.place(s.hero(s.p2), 5);
      s.p2.label = 'Sam';
      final callMe = s.give(s.p1, 'Call Me');
      s.a1.then(card('Call Me'));
      s.a2.then(skip);
      await s.game.resolveCombat(w, s.hero(s.p2));
      s.p1.discard.remove(callMe);
      s.p1.hand.add(callMe);
      s.a1.then(card('Call Me'));
      s.a2.then(skip);
      final c = await s.game.resolveCombat(w, s.hero(s.p2));
      expect(c.attackValue, 4);
    });

    test('Holy Mackerel! discards every copy, or go fish; Time Out swaps in a card from the deck', () async {
      final s = Scenario('deadpool', 'medusa');
      final w = s.hero(s.p1);
      s.place(w, 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Snipe');
      s.give(s.p2, 'Snipe');
      s.give(s.p2, 'Dash');
      s.a1.then('Snipe');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Holy Mackerel!'));
      expect(s.p2.hand.map((c) => c.title), ['Dash']);
      s.a1.then('Feint');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Holy Mackerel!'));
      expect(s.p1.hand, hasLength(1), reason: 'go fish');
      s.p1.hand.clear();
      s.deck(s.p1, ['Gaze of Stone', 'Feint']);
      s.hero(s.p2).hp = 30;
      final c = await s.fight(w, s.hero(s.p2), 'Time out time out time out!', null, then1: [card('Gaze of Stone')]);
      expect(c.attacker.card!.title, 'Gaze of Stone');
      expect(s.hero(s.p2).hp, 30 - 2 - 8);
    });

    test("I've Been Hacked!: the opponent picks your discard; Klunkin' Heads; Buffet at full health", () async {
      final s = Scenario('medusa', 'deadpool');
      final w = s.hero(s.p2);
      s.place(s.hero(s.p1), 4);
      s.place(w, 5);
      s.give(s.p2, 'Feint');
      s.give(s.p2, 'Gaze of Stone');
      s.a1.then(card('Gaze of Stone'));
      await s.fight(s.hero(s.p1), w, 'Second Shot', "I've Been Hacked!");
      expect(s.p2.hand.map((c) => c.title), ['Feint']);
      await s.fight(s.hero(s.p1), w, 'Snipe', 'They Have An Amazing Buffet');
      expect(w.hp, 10 - 2, reason: 'healed to full, then took 2');
    });
  });
}
