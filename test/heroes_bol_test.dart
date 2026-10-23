// Card-by-card tests: King Arthur, Alice, Medusa, Sinbad, Bigfoot, Robin Hood, Achilles,
// Yennenga, Sun Wukong. Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/heroes/bol1.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

void main() {
  group('King Arthur', () {
    test('Noble Sacrifice boosts in addition to his face-down boost', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Regroup'); // boost 1
      s.give(s.p1, 'Excalibur'); // boost 3
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Noble Sacrifice', null,
          then1: [card('Regroup'), card('Excalibur')]);
      expect(c.attackValue, 2 + 1 + 3);
    });

    test('The Holy Grail sets Arthur to 8 at 4 or less health', () async {
      final s = Scenario('medusa', 'king-arthur');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 6;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'The Holy Grail', then1: [skip]);
      expect(s.hero(s.p2).hp, 8, reason: '6 - (3-1) = 4, then set to 8');
      s.hero(s.p2).hp = 10;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'The Holy Grail', then1: [skip]);
      expect(s.hero(s.p2).hp, 8, reason: '10 - 2 = 8, Grail does nothing above 4');
    });

    test('The Lady of the Lake finds Excalibur in the deck (and shuffles) or the discard pile', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.deck(s.p1, ['Feint', 'Excalibur', 'Regroup']);
      await s.game.playScheme(s.p1, s.give(s.p1, 'The Lady of the Lake'));
      expect(s.p1.hand.map((c) => c.title), ['Excalibur']);
      expect(s.events.whereType<Shuffled>(), hasLength(1));
      s.p1.hand.clear();
      s.discardPile(s.p1, ['Excalibur']);
      await s.game.playScheme(s.p1, s.give(s.p1, 'The Lady of the Lake'));
      expect(s.p1.hand.map((c) => c.title), ['Excalibur']);
      expect(s.events.whereType<Shuffled>(), hasLength(1), reason: 'deck not searched, no shuffle');
    });

    test('Prophecy: 2 of the top 4 to hand, the other 2 back on top in chosen order', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.deck(s.p1, ['Feint', 'Regroup', 'Skirmish', 'Excalibur', 'Swift Strike']);
      s.a1
        ..then([1, 3]) // Regroup, Excalibur
        ..then(card('Skirmish'));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Prophecy'));
      expect(s.p1.hand.map((c) => c.title), ['Regroup', 'Excalibur']);
      expect(s.p1.deck.map((c) => c.title), ['Skirmish', 'Feint', 'Swift Strike']);
    });

    test('Bewilderment prevents the combat damage, so the defender wins; Merlin may be placed', () async {
      final s = Scenario('medusa', 'king-arthur');
      s.place(s.hero(s.p1), 3);
      s.place(s.sidekick(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.sidekick(s.p2), 'Second Shot', 'Bewilderment', then1: [skip], then2: [sp(10)]);
      expect(s.sidekick(s.p2).hp, 7);
      expect(c.attackerWon, isFalse);
      expect(s.sidekick(s.p2).space, 10);
    });

    test("Restless Spirits hits opposing fighters in a space of Merlin's zone and one adjacent space", () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.sidekick(s.p2), 6); // Harpy, 1 health
      s.place(s.hero(s.p2), 7);
      s.deck(s.p1, ['Feint']);
      s.a1
        ..then(sp(6))
        ..then(sp(7));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Restless Spirits'));
      expect(s.sidekick(s.p2).defeated, isTrue);
      expect(s.hero(s.p2).hp, 14);
      expect(s.p1.hand.map((c) => c.title), ['Feint'], reason: 'a fighter was defeated: draw 1');
    });

    test('Command the Storms moves opposing fighters too', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.hero(s.p2), 7);
      s.a1
        ..then(s.hero(s.p2))
        ..then(sp(10))
        ..then(sp(4)); // Merlin, the last fighter left, stays
      await s.game.playScheme(s.p1, s.give(s.p1, 'Command the Storms'));
      expect(s.hero(s.p2).space, 10);
    });

    test('Divine Intervention moves King Arthur up to 5 after combat', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Divine Intervention', null, then1: [sp(0)]); // empty hand: no boost prompt
      expect(s.hero(s.p1).space, 0);
    });
  });

  group('Alice', () {
    test('BIG adds 2 to her attacks only; SMALL adds 1 to her defenses only', () async {
      final s = Scenario('alice', 'medusa');
      final alice = s.p1.script as Alice;
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      alice.big = true;
      var c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snicker-Snack', null);
      expect(c.attackValue, 5);
      s.startTurn(s.p2);
      c = await s.fight(s.hero(s.p2), s.hero(s.p1), 'Second Shot', 'Skirmish', then1: [skip]);
      expect(c.defenseValue, 4, reason: 'BIG gives nothing on defense');
      alice.big = false;
      c = await s.fight(s.hero(s.p2), s.hero(s.p1), 'Second Shot', 'Skirmish', then1: [skip]);
      expect(c.defenseValue, 5);
    });

    test('O Frabjous Day! changes size; the Jabberwock does not get the bonus', () async {
      final s = Scenario('alice', 'medusa');
      final alice = s.p1.script as Alice;
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 6);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'O Frabjous Day!', null);
      expect(alice.big, isFalse);
      final c = await s.fight(s.sidekick(s.p1), s.hero(s.p2), 'Claws That Catch', null);
      expect(c.attackValue, 5, reason: 'Claws That Catch vs a hero');
    });



    test('Looking Glass exact: Snipe 3 vs Glass 2 → 1 damage, then draw 2 + recover 3', () async {
      final s = Scenario('medusa', 'alice');
      (s.p2.script as Alice).big = true;
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 8;
      s.deck(s.p2, ['Feint', 'Regroup']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', 'Looking Glass', then2: ['Draw 2', 'recovers 3']);
      expect(s.p2.hand, hasLength(2));
      expect(s.hero(s.p2).hp, 10);
    });

    test('Jaws That Bite deals 2 to a fighter adjacent to the Jabberwock', () async {
      final s = Scenario('alice', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.place(s.sidekick(s.p2), 3);
      await s.fight(s.sidekick(s.p1), s.hero(s.p2), 'Jaws That Bite', null, then1: [s.sidekick(s.p2)]);
      expect(s.sidekick(s.p2).defeated, isTrue);
      expect(s.hero(s.p2).hp, 12);
    });

    test('Manxome Foe adds the BOOST of the top card of the deck', () async {
      final s = Scenario('alice', 'medusa');
      (s.p1.script as Alice).big = false;
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, ['Looking Glass']); // boost 4
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Manxome Foe', null);
      expect(c.attackValue, 7);
      expect(s.p1.discard.map((c) => c.title), contains('Looking Glass'));
    });

    test('Snicker-Snack: if won, look at the hand and choose the discard', () async {
      final s = Scenario('alice', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p2, 'Feint');
      s.give(s.p2, 'Gaze of Stone');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snicker-Snack', null, then1: [card('Gaze of Stone')]);
      expect(s.p2.hand.map((c) => c.title), ['Feint']);
      expect(s.events.whereType<Revealed>(), hasLength(1));
    });

    test('Mad as a Hatter moves each of her fighters, then changes size', () async {
      final s = Scenario('alice', 'medusa');
      final alice = s.p1.script as Alice..big = true;
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 2);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Mad as a Hatter', null,
          then1: [s.hero(s.p1), sp(3), sp(0)]); // the Jabberwock is the only one left
      expect(s.hero(s.p1).space, 3);
      expect(s.sidekick(s.p1).space, 0);
      expect(alice.big, isFalse);
    });
  });

  group('Medusa', () {
    test('start of turn: may deal 1 damage to an opposing fighter in her zone', () async {
      final s = Scenario('medusa', 'king-arthur');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 7);
      s.a1.then(s.hero(s.p2));
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(s.hero(s.p2).hp, 17);
      s.place(s.hero(s.p2), 9);
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(s.hero(s.p2).hp, 17, reason: 'not in her zone');
    });

    test('Gaze of Stone deals 8 if Medusa won, nothing if she lost', () async {
      final s = Scenario('medusa', 'king-arthur');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Gaze of Stone', null);
      expect(s.hero(s.p2).hp, 18 - 2 - 8);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Gaze of Stone', 'Momentous Shift');
      expect(s.hero(s.p2).hp, 8, reason: '2 vs 3: lost');
    });

    test('Winged Frenzy moves through enemies and returns a defeated Harpy to her zone', () async {
      final s = Scenario('medusa', 'king-arthur');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final harpy = s.sidekick(s.p1)..defeated = true;
      s.a1
        ..then(sp(7)) // only Medusa on board: move through Arthur to 7
        ..then(sp(3));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Winged Frenzy'));
      expect(s.hero(s.p1).space, 7);
      expect(harpy.space, 3);
      expect(harpy.hp, 1);
    });

    test('A Momentary Glance deals 2 to a fighter in her zone; Hiss and Slither makes them discard', () async {
      final s = Scenario('medusa', 'king-arthur');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 7);
      s.a1.then(s.hero(s.p2));
      await s.game.playScheme(s.p1, s.give(s.p1, 'A Momentary Glance'));
      expect(s.hero(s.p2).hp, 16);
    });

    test('Second Shot may be boosted', () async {
      final s = Scenario('medusa', 'king-arthur');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Gaze of Stone'); // boost 4
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', null, then1: [card('Gaze of Stone')]);
      expect(c.attackValue, 7);
    });
  });

  group('Sinbad', () {
    test('VOYAGE cards are +1 per other VOYAGE in the discard pile; maneuvers get +1 per VOYAGE', () async {
      final s = Scenario('sinbad', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.discardPile(s.p1, ['Voyage Home', 'Voyage to the City of the King of Serendib']);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Voyage to the City of the Man-Eating Apes', null);
      expect(c.attackValue, 4);
      expect(s.hero(s.p2).hp, 16 - 4 - 2, reason: 'plus 2 after combat');
      expect(s.game.moveAllowance(s.hero(s.p1)), 2 + 3, reason: '3 VOYAGE cards now in the discard pile');
    });

    test('Voyage Home takes every other VOYAGE card back to hand', () async {
      final s = Scenario('sinbad', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.discardPile(s.p1, ['Voyage to the Island That Was a Whale', 'Exploit', 'Voyage to the City of the King of Serendib']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Voyage Home', null);
      expect(s.p1.hand.map((c) => c.title).toSet(),
          {'Voyage to the Island That Was a Whale', 'Voyage to the City of the King of Serendib'});
      expect(s.p1.discard.map((c) => c.title).toSet(), {'Exploit', 'Voyage Home'});
    });

    test('Whale heals 2, Coals of Fire discards at random, Giant Snakes reveals the hand', () async {
      final s = Scenario('sinbad', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p1).hp = 10;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Voyage to the Island That Was a Whale', null);
      expect(s.hero(s.p1).hp, 12);
      s.give(s.p2, 'Feint');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Voyage to the Creature With Eyes Like Coals of Fire', null);
      expect(s.p2.hand, isEmpty);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Voyage to the Valley of the Giant Snakes', null);
      expect(s.events.whereType<Revealed>(), hasLength(1));
    });
  });

  group('Bigfoot', () {
    test('end of turn: may draw if no opposing fighter is in his zone', () async {
      final s = Scenario('bigfoot', 'medusa');
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 9);
      s.deck(s.p1, ['Feint', 'Feint']);
      s.a1.then('Yes');
      await s.p1.script.endOfTurn(s.game, s.p1);
      expect(s.p1.hand, hasLength(1));
      s.place(s.hero(s.p2), 2);
      await s.p1.script.endOfTurn(s.game, s.p1);
      expect(s.p1.hand, hasLength(1));
    });

    test('Jackalope Horns: move through enemies, then 2 damage next to the Jackalope', () async {
      final s = Scenario('bigfoot', 'medusa');
      s.place(s.sidekick(s.p1), 3);
      s.place(s.hero(s.p2), 4);
      s.place(s.sidekick(s.p2), 7);
      s.a1
        ..then(sp(6))
        ..then(s.sidekick(s.p2));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Jackalope Horns'));
      expect(s.sidekick(s.p1).space, 6);
      expect(s.sidekick(s.p2).defeated, isTrue);
    });

    test('Disengage places the fighter in an empty space in its zone', () async {
      final s = Scenario('bigfoot', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Disengage', null, then1: [sp(12)]);
      expect(s.hero(s.p1).space, 12);
    });
  });

  group('Robin Hood', () {
    test('Hit and run: after attacking, the attacker may move up to 2', () async {
      final s = Scenario('robin-hood', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      s.give(s.p1, "A Hunter's Eye");
      s.a1
        ..then(card("A Hunter's Eye"))
        ..then(sp(2));
      s.a2.then(skip);
      await s.game.attack(s.hero(s.p1), s.hero(s.p2));
      expect(s.hero(s.p1).space, 2);
      expect(s.hero(s.p2).hp, 11);
    });

    test('Highway Robbery cancels the defense and ignores its value', () async {
      final s = Scenario('robin-hood', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p2, ['Snipe']);
      final c = await s.fight(s.sidekick(s.p1), s.hero(s.p2), 'Highway Robbery', 'Hiss and Slither');
      expect(c.defenseValue, 0);
      expect(s.hero(s.p2).hp, 14);
    });

    test('Disarming Shot draws one card per damage dealt', () async {
      final s = Scenario('robin-hood', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, ['Feint', 'Feint', 'Feint', 'Feint']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Disarming Shot', 'Snipe');
      expect(s.p1.hand, hasLength(1), reason: '4 - 3 = 1 damage');
    });

    test('Steal From the Rich: opponent may discard, otherwise Robin draws again', () async {
      final s = Scenario('robin-hood', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.deck(s.p1, ['Feint', 'Feint']);
      s.give(s.p2, 'Snipe');
      s.a2.then('No');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Steal From the Rich'));
      expect(s.p1.hand, hasLength(2));
      s.p1.hand.clear();
      s.deck(s.p1, ['Feint', 'Feint']);
      s.a2.then('Yes');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Steal From the Rich'));
      expect(s.p1.hand, hasLength(1));
      expect(s.p2.hand, isEmpty);
    });

    test("Defenders of Sherwood draws and returns an Outlaw to Robin's zone", () async {
      final s = Scenario('medusa', 'robin-hood');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.sidekick(s.p2).defeated = true;
      s.deck(s.p2, ['Feint']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', 'Defenders of Sherwood', then2: [sp(6)]);
      expect(s.sidekick(s.p2).space, 6);
      expect(s.p2.hand.map((c) => c.title), ['Feint']);
    });
  });

  group('Achilles', () {
    test('Patroclus falls: discard 2 random, +2 to Achilles attacks, draw on a win', () async {
      final s = Scenario('achilles', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 3);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Feint');
      s.give(s.p1, 'Feint');
      s.give(s.p1, 'Feint');
      await s.game.damage(s.sidekick(s.p1), 6);
      expect(s.p1.hand, hasLength(1));
      s.deck(s.p1, ['Skirmish']);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Brothers In Arms', null);
      expect(c.attackValue, 6);
      expect(s.p1.hand.map((c) => c.title), containsAll(['Feint', 'Skirmish']));
    });


    test("Under Achilles' Helm exact: Patroclus takes the 1 damage", () async {
      final s = Scenario('medusa', 'achilles');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.place(s.sidekick(s.p2), 6);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', "Under Achilles' Helm", then1: [skip], then2: ['Yes']);
      expect(c.defender.fighter, s.sidekick(s.p2));
      expect(s.sidekick(s.p2).space, 5);
      expect(s.hero(s.p2).space, 6);
      expect(s.sidekick(s.p2).hp, 5);
      expect(s.hero(s.p2).hp, 18);
    });

    test('Test for Weakness makes a bonus attack of 3; the defender may defend again', () async {
      final s = Scenario('achilles', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final test = s.give(s.p1, 'Test For Weakness');
      s.give(s.p2, 'Snipe');
      s.a1.then(card('Test For Weakness'));
      s.a2
        ..then(skip)
        ..then(card('Snipe'));
      await s.game.attack(s.hero(s.p1), s.hero(s.p2));
      expect(s.hero(s.p2).hp, 15, reason: '1 damage, then 3 vs 3');
      expect(s.events.whereType<CombatStarted>(), hasLength(2));
      expect(s.p1.discard, [test], reason: 'the bonus attack is not a card');
    });

    test('Feint on Test for Weakness stops the bonus attack', () async {
      final s = Scenario('achilles', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Test For Weakness');
      s.give(s.p2, 'Feint');
      s.a1.then(card('Test For Weakness'));
      s.a2.then(card('Feint'));
      await s.game.attack(s.hero(s.p1), s.hero(s.p2));
      expect(s.events.whereType<CombatStarted>(), hasLength(1));
    });

    test("Battle Frenzy hurts both fighters; Achilles' Heel gives the attacker an action on a loss", () async {
      final s = Scenario('achilles', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.sidekick(s.p1), s.hero(s.p2), 'Battle Frenzy', null);
      expect(s.sidekick(s.p1).hp, 4);
      expect(s.hero(s.p2).hp, 16 - 3 - 2);
      s.startTurn(s.p2);
      s.place(s.hero(s.p1), 6);
      s.game.actions = 0;
      await s.fight(s.hero(s.p2), s.hero(s.p1), 'Snipe', "Achilles' Heel");
      expect(s.game.actions, 0, reason: 'Achilles won: no action');
      s.give(s.p2, 'Gaze of Stone'); // boost 4
      await s.fight(s.hero(s.p2), s.hero(s.p1), 'Second Shot', "Achilles' Heel", then1: [card('Gaze of Stone')]);
      expect(s.game.actions, 1, reason: 'Achilles lost: the attacker gains 1 action');
    });

    test('The Day of Your Doom: 2 damage to Patroclus makes it 5', () async {
      final s = Scenario('achilles', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.sidekick(s.p1), s.hero(s.p2), 'The Day of Your Doom', null, then1: ['Yes']);
      expect(c.attackValue, 5);
      expect(s.sidekick(s.p1).hp, 4);
    });

    test('Battle Hardened returns a card from the discard pile', () async {
      final s = Scenario('achilles', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.discardPile(s.p1, ['Spear Throw']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Battle Hardened', null);
      expect(s.p1.hand.map((c) => c.title), ['Spear Throw']);
    });
  });

  group('Yennenga', () {
    test('damage to Yennenga may be shifted onto Archers in her zone', () async {
      final s = Scenario('yennenga', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 6);
      s.place(s.sidekick(s.p1, 2), 9);
      s.a1.then('2');
      await s.game.damage(s.hero(s.p1), 5);
      expect(s.sidekick(s.p1).defeated, isTrue);
      expect(s.hero(s.p1).hp, 12);
      expect(s.sidekick(s.p1, 2).hp, 2, reason: 'not in her zone');
    });

    test('Surprise Volley: a returned Archer becomes the attacker, otherwise gain an action', () async {
      final s = Scenario('yennenga', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      final archer = s.sidekick(s.p1)..defeated = true;
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Surprise Volley', null, then1: ['Yes', sp(7)]);
      expect(c.attacker.fighter, archer);
      expect(archer.space, 7);
      s.game.actions = 0;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Surprise Volley', null, then1: ['No']);
      expect(s.game.actions, 1);
    });

    test('Stallion Charge damages each opposing fighter she moved through', () async {
      final s = Scenario('yennenga', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.place(s.sidekick(s.p2), 6);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Stallion Charge', null, then1: [sp(8)]);
      expect(s.hero(s.p1).space, 8);
      expect(s.sidekick(s.p2).defeated, isTrue);
      expect(s.hero(s.p2).hp, 16 - 3 - 1);
    });

    test('Jaws of the Beast counts zones; Divide and Conquer is 4 outside her zone', () async {
      final s = Scenario('yennenga', 'medusa');
      s.place(s.hero(s.p1), 2);
      s.place(s.hero(s.p2), 3);
      var c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Jaws of the Beast', null);
      expect(c.attackValue, 5, reason: 'space 3 is in two zones');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.hero(s.p1), 9);
      c = await s.fight(s.sidekick(s.p1), s.hero(s.p2), 'Divide and Conquer', null);
      expect(c.attackValue, 4);
    });

    test('Shield Formation: the opponent discards or an Archer returns', () async {
      final s = Scenario('medusa', 'yennenga');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.sidekick(s.p2).defeated = true;
      s.give(s.p1, 'Feint');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', 'Shield Formation', then1: ['No'], then2: [sp(6)]);
      expect(s.sidekick(s.p2).space, 6);
    });
  });

  group('Sun Wukong', () {
    test('start of turn: take 1 damage to summon a Clone next to him', () async {
      final s = Scenario('sun-wukong', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.a1
        ..then('Yes')
        ..then(sp(5));
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(s.hero(s.p1).hp, 16);
      expect(s.p1.fighters.where((f) => f.isSidekick && f.onBoard).single.space, 5);
    });

    test('Golden Chain Mail sends the combat damage to the attacker, who does not win', () async {
      final s = Scenario('medusa', 'sun-wukong');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Gaze of Stone', 'Golden Chain Mail');
      expect(c.attackValue, 2);
      expect(s.hero(s.p2).hp, 17, reason: '2 vs 4: no damage anyway');
      final c2 = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Golden Chain Mail', then1: [skip]);
      expect(c2.attackerWon, isFalse);
      expect(s.hero(s.p2).hp, 17);
    });

    test('Ruyi Jingo Bang: TRICKED YOU bonus attack of 4 when the opponent played a card', () async {
      final s = Scenario('sun-wukong', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Ruyi Jingo Bang');
      s.give(s.p2, 'Snipe');
      s.a1.then(card('Ruyi Jingo Bang'));
      s.a2
        ..then(card('Snipe'))
        ..then(skip);
      await s.game.attack(s.hero(s.p1), s.hero(s.p2));
      expect(s.hero(s.p2).hp, 12);
    });

    test("Taunting Laughter: discard a card or the opponent's value is ignored", () async {
      final s = Scenario('sun-wukong', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Taunting Laughter', 'Snipe', then2: ['No']);
      expect(c.defenseValue, 0);
    });

    test('Sly Monkey: a Clone appears where Sun Wukong was, and he is placed in his zone', () async {
      final s = Scenario('sun-wukong', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Sly Monkey', null, then1: [sp(12)]);
      expect(s.hero(s.p1).space, 12);
      expect(s.p1.fighters.where((f) => f.isSidekick && f.onBoard).single.space, 4);
    });

    test('Infinite Strikes: +1 per other friend adjacent to the target, then gain 1 action', () async {
      final s = Scenario('sun-wukong', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 12);
      s.place(s.sidekick(s.p1, 2), 6);
      s.place(s.hero(s.p2), 5);
      s.game.actions = 0;
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Infinite Strikes', null);
      expect(c.attackValue, 4);
      expect(s.game.actions, 1);
    });

    test('Phoenix Form heals 1 per Clone on the board', () async {
      final s = Scenario('sun-wukong', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 12);
      s.place(s.sidekick(s.p1, 2), 6);
      s.hero(s.p1).hp = 10;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Phoenix Form'));
      expect(s.hero(s.p1).hp, 12);
    });
  });

  test('Card ids stay unique per game', () {
    final s = Scenario('king-arthur', 'medusa');
    final a = s.make(s.p1, 'Feint'), b = s.make(s.p1, 'Feint');
    expect(identical(a, b), isFalse);
    expect(a, isA<Card>());
  });
}
