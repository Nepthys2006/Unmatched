// Card-by-card tests: She-Hulk, Spider-Man, Black Panther, Winter Soldier (Marvel).
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/events.dart';

import 'support.dart';

void main() {
  group('She-Hulk', () {
    test('Just Throw Something: discard a card to hit a fighter in her zone for its BOOST', () async {
      final s = Scenario('she-hulk', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 7);
      s.give(s.p1, 'Omega-Level Threat'); // boost 2
      s.a1.then(card('Omega-Level Threat'));
      final hp = s.hero(s.p2).hp;
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(s.hero(s.p2).hp, hp - 2);
      expect(s.p1.hand, isEmpty);
    });

    test('Jennifer Walters places her in a starting space; Leap Toward gains an action next to an enemy', () async {
      final s = Scenario('she-hulk', 'medusa');
      final h = s.hero(s.p1);
      s.place(h, 4);
      s.place(s.hero(s.p2), 9);
      s.a1.then(sp(0));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Jennifer Walters, Esq.'));
      expect(h.space, 0);
      expect(s.p1.hand, hasLength(1));
      s.place(h, 5);
      s.a1.then(sp(8));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Leap Toward'));
      expect(h.space, 8);
      expect(s.game.actions, 4);
    });

    test('Lady Justice adds twice the BOOST of their top card; Cease and Desist is 4 attacking', () async {
      final s = Scenario('medusa', 'she-hulk');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, ['A Momentary Glance']); // boost 4
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', 'Lady Justice');
      expect(c.defenseValue, 8);
      final t = Scenario('she-hulk', 'medusa');
      t.place(t.hero(t.p1), 4);
      t.place(t.hero(t.p2), 5);
      expect((await t.fight(t.hero(t.p1), t.hero(t.p2), 'Cease and Desist', null)).attackValue, 4);
    });

    test('Omega-Level Threat: 2+ combat damage makes them discard 2 at random', () async {
      final s = Scenario('she-hulk', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      for (var i = 0; i < 3; i++) {
        s.give(s.p2, 'Snipe');
      }
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Omega-Level Threat', null);
      expect(s.p2.hand, hasLength(1));
    });

    test('The Savage She-Hulk spends an action for 9; The Defense Rests draws per damage taken', () async {
      final s = Scenario('she-hulk', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Savage She-Hulk', null, then1: ['Yes']);
      expect(c.attackValue, 9);
      expect(s.game.actions, 1);
      final t = Scenario('medusa', 'she-hulk');
      t.place(t.hero(t.p1), 4);
      t.place(t.hero(t.p2), 5);
      await t.fight(t.hero(t.p1), t.hero(t.p2), 'Dash', 'The Defense Rests'); // 3 vs 2: 1 damage
      expect(t.p2.hand, hasLength(1));
    });

    test('Legalese: the loser of the combat chooses; Green Energy; Double Jeopardy; Nerve Cluster Strike', () async {
      final s = Scenario('she-hulk', 'medusa');
      final h = s.hero(s.p1);
      s.place(h, 4);
      s.place(s.hero(s.p2), 5);
      s.place(s.sidekick(s.p2), 3);
      await s.fight(h, s.hero(s.p2), 'Legalese', null, then2: ['Both draw a card']); // won: Medusa chooses
      expect([s.p1.hand.length, s.p2.hand.length], [1, 1]);
      s.p1.hand.clear();
      await s.fight(h, s.hero(s.p2), 'Green Energy', null);
      expect(s.sidekick(s.p2).defeated, isTrue);
      h.hp = 10;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Double Jeopardy'));
      expect(h.hp, 12);
      await s.fight(h, s.hero(s.p2), 'Nerve Cluster Strike', null);
      expect(s.game.cannotLeave(s.hero(s.p2)), isTrue);
    });
  });

  group('Spider-Man', () {
    test('Spidey-Sense: the attacker tells him the printed value before he defends', () async {
      final s = Scenario('medusa', 'spiderman');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', null);
      final told = s.events.whereType<StatusChanged>().where((e) => e.text.contains('printed value is 3'));
      expect(told, isNotEmpty);
      final i = s.events.indexOf(told.first), r = s.events.indexWhere((e) => e is CardsRevealed);
      expect(i, lessThan(r));
    });

    test('Web Shooters caps his combat damage at 2; Counter-Attack and Spider-Sense Tingling react to 4+', () async {
      final s = Scenario('she-hulk', 'spiderman');
      final spidey = s.hero(s.p2);
      s.place(s.hero(s.p1), 4);
      s.place(spidey, 5);
      await s.fight(s.hero(s.p1), spidey, 'Omega-Level Threat', 'Web Shooters'); // 5 vs 3: capped at 2
      expect(spidey.hp, 15 - 2);
      final c = await s.fight(s.hero(s.p1), spidey, 'Sensational', 'Counter-Attack'); // 4 vs 3
      expect(c.attackValue, 4);
      expect(s.hero(s.p1).hp, 20 - 2);
      await s.fight(s.hero(s.p1), spidey, 'Sensational', 'Spider-Sense Tingling!', then1: [skip]);
      expect(s.p2.hand, hasLength(2));
    });

    test('Swinging Kick moves them up to the damage; Disarming Shot draws per damage', () async {
      final s = Scenario('spiderman', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 30;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Swinging Kick', null, then1: [sp(11)]);
      expect(s.hero(s.p2).space, 11);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Disarming Shot', null);
      expect(s.p1.hand, hasLength(4));
    });

    test('Right in the Face! stops the opponent drawing this turn', () async {
      final s = Scenario('spiderman', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Right in the Face!', 'Regroup');
      expect(s.p2.hand, isEmpty);
      await s.game.draw(s.p1, 1);
      expect(s.p1.hand, hasLength(1), reason: 'only the opponent is blocked');
    });

    test('With Great Power, Snark, Thwip!, Wall Crawler, Friendly Neighborhood', () async {
      final s = Scenario('spiderman', 'medusa');
      final sp_ = s.hero(s.p1);
      s.place(sp_, 4);
      s.place(s.hero(s.p2), 5);
      await s.game.playScheme(s.p1, s.give(s.p1, 'With Great Power'));
      expect(s.p1.hand, hasLength(1));
      expect((await s.fight(sp_, s.hero(s.p2), 'Snark', null)).attackValue, 4);
      expect(s.p1.hand, hasLength(2));
      await s.fight(sp_, s.hero(s.p2), 'Thwip!', null, then1: [sp(7)]);
      expect(sp_.space, 7);
      sp_.hp = 5;
      s.a1.then(sp(3));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Friendly Neighborhood Spider-Man'));
      expect(sp_.hp, 8);
      expect(sp_.space, 3);
    });
  });

  group('Black Panther', () {
    test('Analyze and Adjust stores their top card; it can only BOOST, and boosting draws a card', () async {
      final s = Scenario('black-panther', 'medusa');
      final bp = s.hero(s.p1);
      s.place(bp, 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p2, ['A Momentary Glance', 'Snipe']);
      s.deck(s.p1, ['Evade', 'Evade', 'Evade']);
      await s.fight(bp, s.hero(s.p2), 'Analyze and Adjust', null);
      expect(s.p1.script.stored.map((c) => c.title), ['A Momentary Glance']);
      expect(s.p1.hand, isEmpty, reason: 'stored cards are not in the hand');
      final c = await s.fight(bp, s.hero(s.p2), 'Vibranium Shockwave', null, then1: [card('A Momentary Glance')]);
      expect(c.attackValue, 2 + 4);
      expect(s.p1.script.stored, isEmpty);
      expect(s.p2.discard.map((c) => c.title), contains('A Momentary Glance'), reason: "back to its owner's discard pile");
      expect(s.p1.hand, hasLength(1), reason: 'Vibranium Suit: draw 1 per BOOST');
    });

    test('Wakanda Forever! boosts twice (drawing each time); Anti-Metal Claws adds their BOOST', () async {
      final s = Scenario('black-panther', 'medusa');
      final bp = s.hero(s.p1);
      s.place(bp, 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, ['Evade', 'Evade', 'Evade']);
      s.give(s.p1, 'Feint'); // 1
      s.give(s.p1, 'Regroup'); // 2
      final c = await s.fight(bp, s.hero(s.p2), 'Wakanda Forever!', null, then1: [card('Feint'), card('Regroup')]);
      expect(c.attackValue, 3 + 1 + 2);
      expect(s.p1.hand, hasLength(2));
      s.p1.hand.clear();
      final d = await s.fight(bp, s.hero(s.p2), 'Anti-Metal Claws', 'Hiss and Slither'); // boost 3
      expect(d.attackValue, 1 + 3);
    });

    test('Tactical Remote Scanning stores 2; a stored card can boost a maneuver', () async {
      final s = Scenario('black-panther', 'medusa');
      final shuri = s.sidekick(s.p1);
      s.place(s.hero(s.p1), 4);
      s.place(shuri, 3);
      s.deck(s.p2, ['Snipe', 'Dash', 'Feint']);
      await s.game.playScheme(s.p1, s.give(s.p1, 'Tactical Remote Scanning'));
      expect(s.p1.script.stored.map((c) => c.title), ['Snipe', 'Dash']);
      expect(s.events.whereType<Revealed>().where((e) => e.viewer == null), isNotEmpty, reason: 'revealed to everyone');
      expect(s.game.boostOptions(s.p1).map((c) => c.title), ['Snipe', 'Dash']);
    });

    test('Nanotriage heals Shuri, and Black Panther in her zone; Cat-Like Reflexes; Stalking Panther', () async {
      final s = Scenario('black-panther', 'medusa');
      final bp = s.hero(s.p1), shuri = s.sidekick(s.p1);
      s.place(bp, 3);
      s.place(shuri, 4);
      s.place(s.hero(s.p2), 5);
      bp.hp = 10;
      shuri.hp = 3;
      await s.fight(shuri, s.hero(s.p2), 'Nanotriage Processor', null);
      expect([shuri.hp, bp.hp], [4, 11]);
      await s.fight(shuri, s.hero(s.p2), 'Cat-Like Reflexes', null, then1: [shuri, sp(1)]);
      expect(shuri.space, 1);
      s.a1
        ..then(bp) // plays the scheme
        ..then(bp)
        ..then(sp(6));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Stalking Panther'));
      expect(bp.space, 6, reason: 'through Medusa');
    });
  });

  group('Winter Soldier', () {
    test('Brainwashed: his card effects cannot be canceled', () async {
      final s = Scenario('medusa', 'winter-soldier');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Feint', 'Born in the Barracks');
      expect(c.defender.canceled, isFalse);
    });

    test('RED ROOM: Programmed to Kill hurts him when he wins, unless A Boy Named Bucky', () async {
      final s = Scenario('winter-soldier', 'medusa');
      final w = s.hero(s.p1);
      s.place(w, 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(w, s.hero(s.p2), 'Programmed to Kill', null);
      expect(w.hp, 15 - 2);
      await s.game.playScheme(s.p1, s.give(s.p1, 'A Boy Named Bucky'));
      await s.fight(w, s.hero(s.p2), 'Programmed to Kill', null);
      expect(w.hp, 15 - 2);
    });

    test('Marksman adds the spaces between; Bionic Arm is 6 adjacent and makes them move', () async {
      final s = Scenario('winter-soldier', 'medusa');
      final w = s.hero(s.p1);
      s.place(w, 4);
      s.place(s.hero(s.p2), 7); // same zone: ranged
      expect((await s.fight(w, s.hero(s.p2), 'Marksman', null)).attackValue, 1 + 2);
      s.place(s.hero(s.p2), 5);
      s.a2.then(sp(9));
      final c = await s.fight(w, s.hero(s.p2), 'Bionic Arm', null);
      expect(c.attackValue, 6);
      expect(s.hero(s.p2).space, 9, reason: 'the opponent moves their fighter');
    });

    test('Complete the Mission returns the damage taken; Reprogram; Manipulation; Without Remorse', () async {
      final s = Scenario('she-hulk', 'winter-soldier');
      final w = s.hero(s.p2);
      s.place(s.hero(s.p1), 4);
      s.place(w, 5);
      final hp = s.hero(s.p1).hp;
      await s.fight(s.hero(s.p1), w, 'Sensational', 'Complete the Mission', then1: [skip]); // 4 vs 3: 1
      expect(s.hero(s.p1).hp, hp - 1);
      final t = Scenario('winter-soldier', 'medusa');
      t.place(t.hero(t.p1), 4);
      t.place(t.hero(t.p2), 5);
      t.discardPile(t.p1, ['Feint', 'Feint', 'Marksman', 'Wily Fighting']);
      final deck = t.p1.deck.length;
      await t.fight(t.hero(t.p1), t.hero(t.p2), 'Reprogram', null, then1: [[0, 1, 2]]);
      expect(t.p1.deck.length, deck + 3);
      t.a2.then('Yes');
      await t.game.playScheme(t.p1, t.give(t.p1, 'Manipulation'));
      expect(t.p1.hand, hasLength(5));
      expect(t.p2.hand, hasLength(5));
    });
  });
}
