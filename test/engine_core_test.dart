// Core rules, checked against the rulebook and official rulings.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/prompt.dart';

import 'support.dart';

void main() {
  group('setup', () {
    test('heroes on start spaces, sidekicks in the hero zone, 5-card hands, 25-card decks', () async {
      final data = loadData();
      final g = Game(
          data: data,
          map: data.maps['blossom']!,
          heroIds: ['king-arthur', 'medusa'],
          agents: [AiAgent(seed: 1), AiAgent(seed: 2)],
          seed: 3,
          firstSeat: 0);
      await g.setup();
      final arthur = g.players[0], medusa = g.players[1];
      expect(arthur.heroFighter.space, g.board.startSpace(1));
      expect(medusa.heroFighter.space, g.board.startSpace(2));
      for (final p in g.players) {
        expect(p.hand, hasLength(5));
        expect(p.deck, hasLength(25));
        for (final s in p.fighters.where((f) => f.isSidekick)) {
          expect(g.board.sharesZone(s.space!, p.heroFighter.space!), isTrue, reason: '${s.name} in hero zone');
        }
      }
      expect(medusa.fighters.where((f) => f.onBoard), hasLength(4), reason: 'Medusa + 3 Harpies');
      final spaces = g.onBoard.map((f) => f.space).toList();
      expect(spaces.toSet(), hasLength(spaces.length), reason: 'one fighter per space');
    });
  });

  group('maneuver', () {
    test('draws 1, then BOOST adds the discarded card value to movement', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 11);
      s.deck(s.p1, ['Feint', 'Regroup']);
      s.give(s.p1, 'Noble Sacrifice'); // boost 3
      s.a1
        ..then(card('Noble Sacrifice'))
        ..then(s.hero(s.p1))
        ..then(sp(5));
      await s.game.maneuver(s.p1);
      expect(s.hero(s.p1).space, 5, reason: 'move 2 + boost 3');
      expect(s.p1.hand.map((c) => c.title), ['Feint']);
      expect(s.p1.discard.map((c) => c.title), ['Noble Sacrifice']);
    });

    test('may pass through friends but not enemies, and never end on an occupied space', () {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 0);
      s.place(s.sidekick(s.p1), 1);
      s.place(s.hero(s.p2), 3);
      expect(s.game.reachable(s.hero(s.p1), 5).keys.toSet(), {0, 2});
      expect(s.game.reachable(s.hero(s.p1), 5, throughOpp: true).keys.toSet(), {0, 2, 4, 5});
      expect(s.game.reachable(s.hero(s.p1), 6, throughOpp: true).keys.toSet(), {0, 2, 4, 5, 6, 12});
    });

    test('an empty deck deals 2 damage to each of your fighters instead of drawing', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 0);
      s.place(s.sidekick(s.p1), 1);
      s.place(s.hero(s.p2), 11);
      s.deck(s.p1, []);
      await s.game.maneuver(s.p1);
      expect(s.hero(s.p1).hp, 16);
      expect(s.sidekick(s.p1).hp, 5);
      expect(s.events.whereType<Exhausted>(), hasLength(1));
    });
  });

  group('attack reach', () {
    test('melee reaches adjacent spaces only', () {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isFalse, reason: 'same zone, not adjacent');
      s.place(s.hero(s.p2), 5);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isTrue);
    });

    test('ranged also reaches any fighter sharing a zone', () {
      final s = Scenario('medusa', 'king-arthur');
      s.place(s.hero(s.p1), 7);
      s.place(s.hero(s.p2), 4);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isTrue, reason: 'both in zone b');
      s.place(s.hero(s.p1), 9);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isFalse, reason: 'zone c vs zone b');
      s.place(s.hero(s.p1), 1);
      s.place(s.hero(s.p2), 3);
      expect(s.game.inReach(s.hero(s.p1), s.hero(s.p2)), isTrue, reason: 'space 3 is in zones a and b');
    });

    test('legal actions list attacks only when a usable attack card is in hand', () {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Prophecy'); // Merlin scheme, Merlin not on board
      expect(s.game.legalActions(s.p1).map((a) => a.kind), [ActionKind.maneuver]);
      s.give(s.p1, 'The Holy Grail'); // defense only
      expect(s.game.legalActions(s.p1).map((a) => a.kind), [ActionKind.maneuver]);
      s.give(s.p1, 'Excalibur');
      expect(s.game.legalActions(s.p1).map((a) => a.kind), [ActionKind.maneuver, ActionKind.attack]);
    });
  });

  group('combat', () {
    test('damage is attack minus defense; the attacker wins only if the attack dealt damage', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Feint');
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Excalibur', 'Hiss and Slither', then1: [skip]);
      expect(c.attackValue, 6);
      expect(c.defenseValue, 4);
      expect(s.hero(s.p2).hp, 14);
      expect(c.attackerWon, isTrue);
      expect(s.p1.hand, isEmpty, reason: 'Hiss and Slither: opponent discards 1');
    });

    test('a tie deals no damage and the defender wins', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'The Aid of Morgana', 'Hiss and Slither', then1: [skip]);
      expect(s.hero(s.p2).hp, 16);
      expect(c.attackerWon, isFalse);
    });

    test('with no defense card the full attack value is dealt', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Excalibur', null, then1: [skip]);
      expect(s.hero(s.p2).hp, 10);
    });

    test("the defender's effects resolve first", () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, ['Feint', 'Feint', 'Feint']);
      s.deck(s.p2, ['Snipe', 'Snipe', 'Snipe']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Regroup', 'Regroup', then1: [skip]);
      final draws = s.events.whereType<CardsDrawn>().map((e) => e.player).toList();
      expect(draws, [s.p2, s.p1]);
    });

    test("Feint cancels all effects on the opponent's card", () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p1, ['Feint', 'Feint']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Regroup', 'Feint', then1: [skip]);
      expect(s.p1.hand, isEmpty, reason: 'Regroup was canceled');
      expect(s.events.whereType<Canceled>().single.side.isAttacker, isTrue);
    });

    test("Feint vs Feint: the defender's Feint resolves first and cancels the attacker's", () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Feint', 'Feint', then1: [skip]);
      final canceled = s.events.whereType<Canceled>().toList();
      expect(canceled, hasLength(1));
      expect(canceled.single.side.isAttacker, isTrue);
    });

    test("King Arthur's face-down BOOST is lost if his attack card is canceled", () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Regroup'); // boost 1
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Noble Sacrifice', 'Feint', then1: [card('Regroup')]);
      expect(c.attackValue, 2, reason: 'boost discarded without effect');
      expect(s.hero(s.p2).hp, 16);
      expect(s.p1.discard.map((x) => x.title), containsAll(['Noble Sacrifice', 'Regroup']));
    });

    test('Excalibur has no effects, so it cannot be canceled and keeps the BOOST (ruling)', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Noble Sacrifice'); // boost 3
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Excalibur', 'Feint', then1: [card('Noble Sacrifice')]);
      expect(c.attackValue, 9);
      expect(s.hero(s.p2).hp, 16 - 7);
      expect(s.events.whereType<Canceled>(), isEmpty);
    });

    test('Momentous Shift is 5 only if the fighter started the turn in another space', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      var c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Momentous Shift', null, then1: [skip]);
      expect(c.attackValue, 3);
      s.game.turn.startSpace[s.hero(s.p1)] = 2;
      c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Momentous Shift', null, then1: [skip]);
      expect(c.attackValue, 5);
    });

    test('the defender may also use Momentous Shift; it checks where they started this turn', () async {
      final s = Scenario('king-arthur', 'sinbad');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Excalibur', 'Momentous Shift', then1: [skip]);
      expect(c.defenseValue, 3, reason: 'Medusa did not move this turn');
    });
  });

  group('turn', () {
    test('two actions, then discard down to the hand limit of 7', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 0);
      s.place(s.hero(s.p2), 11);
      for (var i = 0; i < 8; i++) {
        s.give(s.p1, 'Feint');
      }
      s.deck(s.p1, ['Regroup', 'Regroup', 'Regroup']);
      s.a1.queue.addAll(['Maneuver', skip, skip, 'Maneuver', skip, skip]);
      await s.game.playTurn(s.p1);
      expect(s.p1.hand, hasLength(7));
      expect(s.p1.discard, hasLength(3));
      expect(s.game.turn.maneuvers, 2);
    });

    test('gaining an action gives the active player one more action', () {
      final s = Scenario('king-arthur', 'medusa');
      s.game.actions = 1;
      s.game.gainActions(s.p1, 1);
      expect(s.game.actions, 2);
      s.game.gainActions(s.p2, 1);
      expect(s.game.actions, 2, reason: "only the active player's actions matter");
    });
  });

  group('winning', () {
    test('defeating the opposing hero wins at the end of combat', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 3;
      await expectLater(s.fight(s.hero(s.p1), s.hero(s.p2), 'Excalibur', null, then1: [skip]), throwsA(isA<GameOverSignal>()));
      expect(s.game.winner, s.p1);
    });

    test('defeating a sidekick does not end the game', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p2), 5);
      await s.fight(s.hero(s.p1), s.sidekick(s.p2), 'Excalibur', null, then1: [skip]);
      expect(s.sidekick(s.p2).defeated, isTrue);
      expect(s.game.over, isFalse);
    });

    test('if both heroes fall, the active player wins', () async {
      final s = Scenario('king-arthur', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.game.damage(s.hero(s.p1), 99);
      await s.game.damage(s.hero(s.p2), 99);
      await expectLater(s.game.checkWinner(), throwsA(isA<GameOverSignal>()));
      expect(s.game.winner, s.p1);
    });
  });
}
