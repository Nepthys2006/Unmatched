// Card-by-card tests: Angel, Buffy, Spike (Buffy the Vampire Slayer).
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/heroes/buffy.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

void main() {
  group('Angel', () {
    test('ability: draws 1 after an attack by Angel or Faith that he loses', () async {
      final s = Scenario('angel', 'bruce-lee');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Wisdom of Ages', 'Skirmish'); // 3 vs 4: lost
      // Wisdom of Ages draws 1 + the ability draws 1.
      expect(s.p1.hand, hasLength(2));
    });

    test('Brooding: the opposing fighter takes 1 if Angel lost', () async {
      final s = Scenario('muhammad-ali', 'angel');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final hp = s.hero(s.p1).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Greatest', 'Brooding'); // 4 vs 3: Angel lost
      expect(s.hero(s.p1).hp, hp - 1);
    });

    test('Haunted by the Faces may place Angel in his zone after losing', () async {
      final s = Scenario('muhammad-ali', 'angel');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Greatest', 'Haunted by the Faces', then2: [sp(7)]);
      expect(s.hero(s.p2).space, 7);
    });

    test('Disengage moves the fighter to another space in their zone', () async {
      final s = Scenario('angel', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Disengage', null, then1: [sp(12)]);
      expect(s.hero(s.p1).space, 12);
    });

    test('The Rogue Slayer, Five by Five and Killer of the Dead (Faith)', () async {
      final s = Scenario('angel', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.place(s.sidekick(s.p2, 1), 3);
      await s.fight(s.sidekick(s.p1), s.hero(s.p2), 'The Rogue Slayer', null);
      expect(s.sidekick(s.p2, 1).defeated, isTrue, reason: 'the Harpy next to Faith took 1');
      final hp = s.hero(s.p2).hp;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Killer of the Dead'));
      expect(s.hero(s.p2).hp, hp - 2);
      await s.fight(s.sidekick(s.p1), s.hero(s.p2), 'Five by Five', null, then1: [sp(9)]);
      expect(s.sidekick(s.p1).space, 9, reason: 'Faith moved through Medusa');
    });

    test('Cursed with a Soul heals 1 only after losing', () async {
      final s = Scenario('angel', 'bruce-lee');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p1).hp = 10;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Cursed with a Soul', 'Be Like Water'); // 4 vs 3: won
      expect(s.hero(s.p1).hp, 10);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Cursed with a Soul', 'Skirmish'); // 4 vs 4: lost
      expect(s.hero(s.p1).hp, 11);
    });
  });

  group('Buffy', () {
    test('Buffy moves through opposing fighters, also when moved by effects', () async {
      final s = Scenario('buffy', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.a1.then(sp(7));
      await s.game.moveFighter(s.hero(s.p1), 3, chooser: s.p1);
      expect(s.hero(s.p1).space, 7, reason: 'through Medusa at 5');
      final xander = s.p1.fighters.firstWhere((f) => f.id == 'xander');
      s.place(xander, 4);
      s.place(s.hero(s.p1), 0);
      s.a1.then(sp(7));
      await expectLater(s.game.moveFighter(xander, 3, chooser: s.p1), throwsStateError, reason: 'sidekicks cannot pass Medusa');
    });

    test('setup: the chosen sidekick stays, the other one and their 5 cards leave', () async {
      final s = Scenario('buffy', 'medusa');
      final b = s.p1.script as Buffy;
      s.a1.then('Xander');
      await b.beforeDeck();
      expect(s.p1.fighters.map((f) => f.id), ['buffy', 'xander']);
      final deck = b.deckCards().map((c) => c.title).toList();
      expect(deck, hasLength(30), reason: '35 cards in the box, 5 belong to the sidekick left out');
      expect(deck, isNot(contains('Training')));
      expect(deck.where((t) => t == 'Military Knowledge'), hasLength(3));
    });

    test('Cartwheel Kick moves Buffy up to 3 (through enemies), then hits each adjacent opposing fighter', () async {
      final s = Scenario('muhammad-ali', 'buffy');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final hp = s.hero(s.p1).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Greatest', 'Cartwheel Kick', then2: [sp(3)]);
      expect(s.hero(s.p2).space, 3, reason: 'Buffy passed through Ali');
      expect(s.hero(s.p1).hp, hp - 1);
    });

    test('Insight looks at the hand and discards the chosen card', () async {
      final s = Scenario('buffy', 'medusa');
      final giles = s.p1.fighters.firstWhere((f) => f.id == 'giles');
      s.place(giles, 4);
      s.give(s.p2, 'Second Shot');
      s.give(s.p2, 'Snipe');
      s.a1.then(card('Snipe'));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Insight'));
      expect(s.p2.hand.map((c) => c.title), ['Second Shot']);
      expect(s.events.whereType<Revealed>().where((e) => e.viewer == s.p1), isNotEmpty);
    });

    test('Training draws 3; Daring Strike draws 2 or hurts', () async {
      final s = Scenario('buffy', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final giles = s.p1.fighters.firstWhere((f) => f.id == 'giles');
      s.place(giles, 3);
      await s.game.playScheme(s.p1, s.give(s.p1, 'Training'));
      expect(s.p1.hand, hasLength(3));
      s.p1.hand.clear();
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Daring Strike', null);
      expect(s.p1.hand, hasLength(2));
    });

    test('Daring Strike: if Buffy did not win, she takes 1 damage', () async {
      final s = Scenario('buffy', 'bruce-lee');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final hp = s.hero(s.p1).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Daring Strike', 'Skirmish'); // 4 vs 4
      expect(s.hero(s.p1).hp, hp - 1);
      expect(s.p1.hand, isEmpty);
    });

    test("Slayer's Strength moves every adjacent fighter within their zone and hits them", () async {
      final s = Scenario('buffy', 'medusa');
      s.place(s.hero(s.p1), 5);
      s.place(s.hero(s.p2), 6);
      final hp = s.hero(s.p2).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), "Slayer's Strength", null, then1: ['Yes', sp(7)]);
      expect(s.hero(s.p2).space, 7);
      expect(s.hero(s.p2).hp, hp - 4 - 1);
    });

    test('Rapid Recovery heals Buffy; Right-hand Man is 6 next to Buffy', () async {
      final s = Scenario('buffy', 'medusa');
      final xander = s.p1.fighters.firstWhere((f) => f.id == 'xander');
      s.place(s.hero(s.p1), 6);
      s.place(xander, 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p1).hp = 10;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Rapid Recovery', null);
      expect(s.hero(s.p1).hp, 11);
      expect((await s.fight(xander, s.hero(s.p2), 'Right-hand Man', null)).attackValue, 2, reason: 'not next to Buffy');
      s.place(s.hero(s.p1), 3);
      final c = await s.fight(xander, s.hero(s.p2), 'Right-hand Man', null);
      expect(c.attackValue, 6);
    });
  });

  group('Spike', () {
    Spike spikeOf(Scenario s) => s.p1.script as Spike;

    test('ability: places a shadow token next to Spike; with 3 out, moves one instead', () async {
      final s = Scenario('spike', 'medusa');
      s.place(s.hero(s.p1), 4);
      for (final sp_ in [3, 5, 3]) {
        s.a1.then(sp(sp_)); // a space may hold more than one
        await s.p1.script.startOfTurn(s.game, s.p1);
      }
      expect(spikeOf(s).shadows.map((t) => t.space), [3, 5, 3]);
      s.a1
        ..then(sp(5)) // where it goes
        ..then(sp(3)); // which token moves there
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(spikeOf(s).shadows.map((t) => t.space).toList()..sort(), [3, 5, 5]);
    });

    test('Seek the Shadows draws 2 and covers Spike and the spaces around him while tokens last', () async {
      final s = Scenario('spike', 'medusa');
      s.place(s.hero(s.p1), 5);
      s.a1
        ..then(sp(4))
        ..then(sp(6));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Seek the Shadows'));
      expect(s.p1.hand, hasLength(2));
      expect(spikeOf(s).shadows.map((t) => t.space).toSet(), {5, 4, 6}, reason: 'only 3 tokens');
    });

    test('Bloody Hell! deals 1 + 1 per adjacent space with a shadow token', () async {
      final s = Scenario('spike', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.game.board.tokens
        ..add(Token('shadow', s.p1, space: 6))
        ..add(Token('shadow', s.p1, space: 12));
      final hp = s.hero(s.p2).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Bloody Hell!', null);
      expect(s.hero(s.p2).hp, hp - 3 - 3);
    });

    test('The Rush and Let\'s Dance work when a fighter in the combat stands on a shadow', () async {
      final s = Scenario('spike', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Rush', null)).attackValue, 3);
      s.game.board.tokens.add(Token('shadow', s.p1, space: 5));
      expect((await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Rush', null)).attackValue, 5);
      s.give(s.p1, 'Feint'); // boost 2
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), "Let's Dance", null, then1: [card('Feint')]);
      expect(c.attackValue, 4 + 2);
    });

    test('Always Surprising blind boosts, doubled when Drusilla stands on a shadow', () async {
      final s = Scenario('spike', 'medusa');
      final dru = s.sidekick(s.p1);
      s.place(dru, 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, ['Regroup', 'Regroup']); // boost 1 each
      s.game.board.tokens.add(Token('shadow', s.p1, space: 4));
      final c = await s.fight(dru, s.hero(s.p2), 'Always Surprising', null, then1: ['Yes']);
      expect(c.attackValue, 1 + 1 + 1);
    });

    test('The Sight discards 1, or 2 when one of their fighters is on a shadow', () async {
      final s = Scenario('spike', 'medusa');
      s.place(s.sidekick(s.p1), 4);
      s.place(s.hero(s.p2), 7);
      for (var i = 0; i < 3; i++) {
        s.give(s.p2, 'Second Shot');
      }
      await s.game.playScheme(s.p1, s.give(s.p1, 'The Sight'));
      expect(s.p2.hand, hasLength(2));
      s.game.board.tokens.add(Token('shadow', s.p1, space: 7));
      await s.game.playScheme(s.p1, s.give(s.p1, 'The Sight'));
      expect(s.p2.hand, isEmpty);
    });

    test('Arrogance: discard the hand (even empty) for 6; Empathy draws 3 on a shadow', () async {
      final s = Scenario('spike', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Regroup');
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Arrogance', null, then1: ['Yes']);
      expect(c.attackValue, 6);
      expect(s.p1.hand, isEmpty);
      s.game.board.tokens.add(Token('shadow', s.p1, space: 5));
      final dru = s.sidekick(s.p1);
      s.place(dru, 6);
      await s.fight(dru, s.hero(s.p2), 'Empathy', null);
      expect(s.p1.hand, hasLength(3));
    });
  });
}
