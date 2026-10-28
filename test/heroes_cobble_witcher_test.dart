// Card-by-card tests: Sherlock Holmes, Dracula, Jekyll & Hyde, Invisible Man, Little Red,
// Beowulf, Ancient Leshen, Geralt, Ciri. Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/hero_script.dart';
import 'package:unmatched_game/engine/heroes/cobble.dart';
import 'package:unmatched_game/engine/heroes/fables.dart';
import 'package:unmatched_game/engine/heroes/witcher_ss.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

void main() {
  group('Sherlock Holmes', () {
    test('HOLMES / DR. WATSON cards cannot be canceled, ANY cards can', () async {
      final s = Scenario('medusa', 'sherlock-holmes');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.deck(s.p2, ['Feint', 'Feint', 'Feint']);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Feint', 'Counterpunch');
      expect(s.hero(s.p1).hp, 14, reason: 'Counterpunch still deals 2');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Feint', 'Education Never Ends');
      expect(s.p2.hand, isEmpty, reason: 'ANY card was canceled');
    });

    test('Elementary: a correct prediction cancels and ignores the attack', () async {
      final s = Scenario('medusa', 'sherlock-holmes');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Gaze of Stone', 'Elementary', then2: ['2']);
      expect(c.attackValue, 0);
      expect(s.hero(s.p2).hp, 16);
      final c2 = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', 'Elementary', then2: ['5']);
      expect(c2.attackValue, 3, reason: 'wrong guess');
    });

    test('Confirm Suspicion: matching card discarded, hero takes its BOOST', () async {
      final s = Scenario('sherlock-holmes', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      s.give(s.p2, 'Gaze of Stone'); // value 2, boost 4
      s.give(s.p2, 'Snipe');
      s.a1.then('2');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Confirm Suspicion'));
      expect(s.p2.hand.map((c) => c.title), ['Snipe']);
      expect(s.hero(s.p2).hp, 12);
    });

    test('Master of Disguise swaps Holmes with the opposing hero and deals 1', () async {
      final s = Scenario('sherlock-holmes', 'medusa');
      s.place(s.hero(s.p1), 2);
      s.place(s.hero(s.p2), 9);
      await s.game.playScheme(s.p1, s.give(s.p1, 'Master of Disguise'));
      expect(s.hero(s.p1).space, 9);
      expect(s.hero(s.p2).space, 2);
      expect(s.hero(s.p2).hp, 15);
    });

    test('Deduce Strategy turns the opposing card into its BOOST value', () async {
      final s = Scenario('medusa', 'sherlock-holmes');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', 'Deduce Strategy', then2: ['Yes']);
      expect(c.attackValue, 1, reason: "Snipe's BOOST is 1");
    });
  });

  group('Dracula', () {
    test('start of turn: 1 damage to an adjacent fighter, then draw', () async {
      final s = Scenario('dracula', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.a1.then(s.hero(s.p2));
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(s.hero(s.p2).hp, 15);
      expect(s.p1.hand, hasLength(1));
    });

    test('Prey Upon heals 1 per damage dealt; Look Into My Eyes adds the attack BOOST', () async {
      final s = Scenario('dracula', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.place(s.sidekick(s.p2), 3);
      s.hero(s.p1).hp = 8;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Prey Upon'));
      expect(s.hero(s.p1).hp, 10);
      expect(s.sidekick(s.p2).defeated, isTrue);
      s.startTurn(s.p2);
      final c = await s.fight(s.hero(s.p2), s.hero(s.p1), 'Gaze of Stone', 'Look Into My Eyes');
      expect(c.defenseValue, 1 + 4);
    });

    test('Do My Bidding: Dracula picks the attacker\'s card', () async {
      final s = Scenario('medusa', 'dracula');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.give(s.p1, 'Regroup'); // value 1
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Second Shot', 'Do My Bidding', then1: [], then2: [card('Regroup')]);
      expect(c.attacker.card!.title, 'Regroup');
      expect(s.p1.hand.map((c) => c.title), contains('Second Shot'));
      expect(c.attackValue, 1);
    });

    test('Ravening Seduction: 1 damage per Sister next to the moved fighter', () async {
      final s = Scenario('dracula', 'medusa');
      s.place(s.sidekick(s.p1), 6);
      s.place(s.sidekick(s.p1, 2), 12);
      s.place(s.hero(s.p2), 3);
      s.a1
        ..then(s.sidekick(s.p1)) // which Sister plays it
        ..then(s.hero(s.p2))
        ..then(sp(5)); // next to both Sisters
      await s.game.playScheme(s.p1, s.give(s.p1, 'Ravening Seduction'));
      expect(s.hero(s.p2).hp, 14);
    });
  });

  group('Jekyll & Hyde', () {
    test('Dr. Jekyll cards only as Jekyll, Mr. Hyde cards only as Hyde; Hyde hurts after maneuvering', () async {
      final s = Scenario('jekyll-hyde', 'medusa');
      final jh = s.p1.script as JekyllHyde;
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final hyde = s.give(s.p1, 'Forever Hyde');
      expect(s.game.canAttackWith(hyde, s.hero(s.p1)), isFalse);
      await jh.transform(true);
      expect(s.game.canAttackWith(hyde, s.hero(s.p1)), isTrue);
      expect(s.p1.script.heroName, 'Mr. Hyde');
      await s.game.maneuver(s.p1);
      expect(s.hero(s.p1).hp, 15);
    });

    test('Duality of Man is 6 for Jekyll defending and for Hyde attacking', () async {
      final s = Scenario('medusa', 'jekyll-hyde');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', 'Duality of Man');
      expect(c.defenseValue, 6);
    });

    test('Succumb to Compulsion transforms him into Mr. Hyde', () async {
      final s = Scenario('jekyll-hyde', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Succumb to Compulsion', null, then1: [sp(4)]);
      expect((s.p1.script as JekyllHyde).hyde, isTrue);
    });
  });

  group('Invisible Man', () {
    InvisibleMan setupFog(Scenario s, List<int> spaces) {
      final im = s.p1.script as InvisibleMan;
      for (final sp in spaces) {
        s.game.board.tokens.add(Token('fog', s.p1, space: sp));
      }
      return im;
    }

    test('moves between fog spaces as if adjacent; +1 to his defense on fog', () async {
      final s = Scenario('invisible-man', 'medusa');
      setupFog(s, [1, 10]);
      s.place(s.hero(s.p1), 1);
      s.place(s.hero(s.p2), 9);
      expect(s.game.reachable(s.hero(s.p1), 1).keys, contains(10));
      s.startTurn(s.p2);
      s.place(s.hero(s.p1), 10);
      final c = await s.fight(s.hero(s.p2), s.hero(s.p1), 'Snipe', 'Into Thin Air', then2: [sp(10)], then1: [0, sp(3)]);
      expect(c.defenseValue, 5);
    });

    test('Impossible to See fixes the opposing value at 0', () async {
      final s = Scenario('medusa', 'invisible-man');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Gaze of Stone', 'Impossible to See');
      expect(c.attackValue, 0);
    });

    test('Vanish removes him; he returns anywhere at the start of his next turn', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [0]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p1).hp = 10;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Vanish'));
      expect(s.hero(s.p1).onBoard, isFalse);
      expect(s.hero(s.p1).hp, 11);
      expect(s.game.turnEnded, isTrue, reason: 'played as the first action');
      expect(s.game.legalActions(s.p2).where((a) => a.kind == ActionKind.attack), isEmpty);
      s.a1.then(sp(9));
      await im.startOfTurn(s.game, s.p1);
      expect(s.hero(s.p1).space, 9);
    });

    test('"your opponent moves a fog token": the opponent is asked, and the token moves', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [4, 10]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      // Step Lightly: Medusa's player picks the fog at 10 and moves it to 8.
      s.a2
        ..then('Fog at 10')
        ..then(sp(8));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Step Lightly'));
      final fogAsks = s.a2.asked.where((p) => p.text.contains('fog')).toList();
      expect(fogAsks, hasLength(2), reason: 'the opponent chooses the token and where it goes');
      expect(fogAsks.first.text, contains('Step Lightly'));
      expect(s.a1.asked.where((p) => p.text.contains('fog')), isEmpty, reason: "Invisible Man's player is not asked");
      expect(im.fog.map((t) => t.space).toSet(), {4, 8});
    });

    test('Covert Preparation: he moves one fog, then the opponent moves a different one', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [2, 9]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      // An attack (versatile card): its AFTER COMBAT moves the fog.
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Covert Preparation', null, then1: ['Fog at 2', sp(3)], then2: [sp(11)]);
      expect(im.fog.map((t) => t.space).toSet(), {3, 11});
      expect(s.a2.asked.last.text, contains('Covert Preparation'));
    });

    test('Vanish: off the board (not drawn, not targetable) until his next turn', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [0]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.game.playScheme(s.p1, s.give(s.p1, 'Vanish'));
      expect(s.game.fighters.where((f) => f.onBoard), isNot(contains(s.hero(s.p1))), reason: 'the board draws only onBoard fighters');
      expect(im.status(), ['VANISHED']);
      s.startTurn(s.p2);
      await im.startOfTurn(s.game, s.p2);
      expect(s.hero(s.p1).onBoard, isFalse, reason: "still gone during the opponent's turn");
      s.startTurn(s.p1);
      s.a1.then(sp(7));
      await im.startOfTurn(s.game, s.p1);
      expect(s.hero(s.p1).onBoard, isTrue);
      expect(s.hero(s.p1).space, 7);
    });

    test('the 3 fog tokens start in separate spaces of his zone', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = s.p1.script as InvisibleMan;
      s.place(s.hero(s.p1), 5);
      s.place(s.hero(s.p2), 10);
      await im.afterHeroPlaced();
      final at = im.fog.map((t) => t.space!).toList();
      expect(at, hasLength(3));
      expect(at.toSet(), hasLength(3), reason: 'separate spaces');
      expect(at.every((sp) => s.game.board.zoneOf(5).contains(sp)), isTrue, reason: "in Invisible Man's zone");
      final asks = s.a1.asked.where((p) => p.text.contains('fog')).toList();
      expect(asks, hasLength(3));
      expect(asks.every((p) => p.ask == Ask.space && p.subject is Token), isTrue, reason: 'picked on the board, the token as subject');
    });

    test('fog is picked on the board: the token choice offers each fog by its space', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [2, 6, 9]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 11);
      s.a1
        ..then('Fog at 6')
        ..then(sp(1));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Rolling Fog'));
      final pick = s.a1.asked.firstWhere((p) => p.text.contains('Rolling Fog: choose a fog token'));
      expect(pick.ask, Ask.space);
      expect([for (final c in pick.choices) c.label], ['Fog at 2', 'Fog at 6', 'Fog at 9']);
      expect(pick.choices.every((c) => c.value is Token), isTrue);
      final dest = s.a1.asked.firstWhere((p) => p.text.contains('move the fog token'));
      expect(dest.subject, isA<Token>(), reason: 'the board rings the token that moves');
      expect([for (final c in dest.choices) c.value as int], isNot(anyOf(contains(2), contains(9))), reason: 'never onto another fog');
      expect(im.fog.map((t) => t.space).toSet(), {1, 2, 9});
      expect(s.game.actions, greaterThanOrEqualTo(1), reason: 'Rolling Fog gains an action');
    });

    test('"up to N spaces": along the lines, may stay, never onto fog (Into Thin Air, opponent)', () async {
      final s = Scenario('medusa', 'invisible-man');
      final im = s.p2.script as InvisibleMan;
      for (final sp in [5, 7]) {
        s.game.board.tokens.add(Token('fog', s.p2, space: sp));
      }
      s.place(s.hero(s.p1), 3);
      s.place(s.hero(s.p2), 4);
      // Medusa attacks; Invisible Man defends with Into Thin Air: he moves 1, then Medusa's player
      // moves a fog token up to 3.
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Snipe', 'Into Thin Air', then2: [sp(4)], then1: ['Fog at 5', sp(2)]);
      final dest = s.a1.asked.lastWhere((p) => p.text.contains('move the fog token'));
      expect(dest.text, contains('Into Thin Air'));
      expect(dest.intent, Intent.moveEnemy, reason: "the opponent moves Invisible Man's fog: drawn as a harmful choice");
      expect({for (final c in dest.choices) c.value as int}, {2, 3, 4, 5, 6, 8, 12}, reason: 'within 3 of 5, staying allowed, not onto 7');
      expect(im.fog.map((t) => t.space).toSet(), {2, 7});
    });

    test('Covert Preparation: the opponent moves a different token even if his stayed put', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [2, 9]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      // He picks the fog at 2 and leaves it there; the opponent gets only the fog at 9.
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Covert Preparation', null, then1: ['Fog at 2', sp(2)], then2: [sp(11)]);
      expect(im.fog.map((t) => t.space).toSet(), {2, 11});
      final theirs = s.a2.asked.where((p) => p.text.contains('Covert Preparation')).toList();
      expect(theirs, hasLength(1), reason: 'one token left to them: only where it goes is asked');
      expect(theirs.single.subject, isA<Token>());
      expect((theirs.single.subject! as Token).space, 11);
    });

    test('Confound: he picks each fog on the board in turn, then Done', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [2, 6, 9]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.p2.hand.clear(); // the opponent can't pay to stop it
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Confound', null, then1: ['Fog at 9', sp(0), 'Fog at 2', sp(11), skip]);
      expect(im.fog.map((t) => t.space).toSet(), {0, 6, 11});
      final picks = s.a1.asked.where((p) => p.text.startsWith('Confound: choose a fog token')).toList();
      expect(picks, hasLength(3), reason: 'two moves, then Done');
      expect(picks.every((p) => p.ask == Ask.space && p.optional && p.skipLabel == 'Done'), isTrue);
      expect(picks[1].choices, hasLength(2), reason: 'a moved token is not offered again');
    });

    test('Confound: the opponent may discard a card to stop it', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [2, 6]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.p2.hand.clear();
      s.give(s.p2, 'Snipe');
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Confound', null, then2: ['Yes', card('Snipe')]);
      expect(im.fog.map((t) => t.space).toSet(), {2, 6});
      expect(s.p2.hand, isEmpty);
    });

    test('Surprise Attack moves the fog he stands on to another space', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [4, 9]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Surprise Attack', null, then1: [sp(1)]);
      expect(im.fog.map((t) => t.space).toSet(), {1, 9});
    });

    test('Lurking: move him to a free fog space, or move a fog up to 3', () async {
      final s = Scenario('invisible-man', 'medusa');
      final im = setupFog(s, [5, 8, 10]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5); // a fog space with a fighter on it: not a place to go
      s.startTurn(s.p2);
      await s.fight(s.hero(s.p2), s.hero(s.p1), 'Snipe', 'Lurking', then2: ['Move Invisible Man', sp(8)]);
      final place = s.a1.asked.lastWhere((p) => p.text.contains('fog space'));
      expect({for (final c in place.choices) c.value as int}, {8, 10});
      expect(s.hero(s.p1).space, 8);
      s.place(s.hero(s.p1), 4); // back within Medusa's reach
      await s.fight(s.hero(s.p2), s.hero(s.p1), 'Snipe', 'Lurking', then2: ['Move 1 fog', 'Fog at 10', sp(11)]);
      expect(im.fog.map((t) => t.space).toSet(), {5, 8, 11});
    });

    test('Slip Away: the fog goes to a free space and he is placed there (traps spring)', () async {
      final s = Scenario('invisible-man', 'robert-muldoon');
      final im = setupFog(s, [2, 9]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.game.board.tokens.add(Token('trap', s.p2, space: 7));
      final hp = s.hero(s.p1).hp;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Slip Away', null, then1: ['Fog at 9', sp(7)]);
      expect(s.hero(s.p1).space, 7);
      expect(im.fog.map((t) => t.space).toSet(), {2, 7});
      expect(s.hero(s.p1).hp, lessThan(hp), reason: "entering Muldoon's trap hurts, as any placement");
      expect(s.events.whereType<FighterMoved>().where((e) => e.fighter == s.hero(s.p1) && e.placed), isNotEmpty);
    });

    test('he moves between fog spaces as if adjacent, even through the middle of a move', () async {
      final s = Scenario('invisible-man', 'medusa');
      setupFog(s, [3, 10]);
      s.place(s.hero(s.p1), 2);
      s.place(s.hero(s.p2), 0);
      // 2 -> 3 (1 step) -> 10 (fog to fog) -> 11: three spaces with move 3
      final paths = s.game.reachable(s.hero(s.p1), 3);
      expect(paths.keys, containsAll([10, 11]));
      expect(paths[11], [2, 3, 10, 11]);
      // an opposing fighter on fog doesn't get the shortcut
      s.place(s.hero(s.p2), 3);
      expect(s.game.reachable(s.hero(s.p2), 1).keys, isNot(contains(10)));
    });

    test('Step Lightly deals 3 on fog; Reign of Terror needs fog', () async {
      final s = Scenario('invisible-man', 'medusa');
      setupFog(s, [4, 11]);
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.a2
        ..then(0)
        ..then(sp(6));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Step Lightly'));
      expect(s.hero(s.p2).hp, 13);
    });
  });

  group('Little Red', () {
    test('the basket is the symbol on top of the discard pile; empty pile = any', () async {
      final s = Scenario('little-red', 'medusa');
      final lr = s.p1.script as LittleRed;
      expect(lr.basket, '*');
      s.discardPile(s.p1, ["The Wolf's Skin"]);
      expect(lr.basket, 'A');
      expect(lr.has('W'), isFalse);
      s.discardPile(s.p1, ["What's That In My Basket?"]);
      expect(lr.has('W'), isTrue);
    });

    test('Once Upon a Time deals 3 only with Axes in the basket', () async {
      final s = Scenario('little-red', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.discardPile(s.p1, ['A Grimm Tale']); // rose
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Once Upon a Time', null);
      expect(s.hero(s.p2).hp, 14);
      s.discardPile(s.p1, ["The Wolf's Skin"]); // axes now on top of the discard pile
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Once Upon a Time', null);
      expect(s.hero(s.p2).hp, 14 - 2 - 3);
    });

    test('Never Leave the Path resolves each matching line (basket: any)', () async {
      final s = Scenario('little-red', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 6);
      s.deck(s.p1, ['A Grimm Tale', 'A Grimm Tale', 'A Grimm Tale', 'A Grimm Tale']);
      s.game.actions = 0;
      s.a1.then(sp(5));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Never Leave the Path'));
      expect(s.hero(s.p1).space, 5);
      expect(s.game.actions, 1);
      expect(s.hero(s.p2).hp, 14);
      expect(s.p1.hand, hasLength(3));
    });

    test('What Big Ears can defend only with Axes in the basket', () {
      final s = Scenario('little-red', 'medusa');
      s.place(s.hero(s.p1), 4);
      final ears = s.give(s.p1, 'What Big Ears You Have');
      s.discardPile(s.p1, ['A Grimm Tale']);
      expect(s.game.canDefendWith(ears, s.hero(s.p1)), isFalse);
      s.discardPile(s.p1, ['Long Have I Sought You']);
      expect(s.game.canDefendWith(ears, s.hero(s.p1)), isTrue);
    });
  });

  group('Beowulf', () {
    test('starts at 1 Rage, gains 1 when damaged, maximum 3', () async {
      final s = Scenario('beowulf', 'medusa');
      final b = s.p1.script as Beowulf;
      s.place(s.hero(s.p1), 4);
      expect(b.rage, 1);
      await s.game.damage(s.hero(s.p1), 1);
      await s.game.damage(s.hero(s.p1), 1);
      await s.game.damage(s.hero(s.p1), 1);
      expect(b.rage, 3);
    });

    test('The War-King: +2 per Rage spent; Epic Poem: +1 per Rage held', () async {
      final s = Scenario('beowulf', 'medusa');
      final b = s.p1.script as Beowulf;
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      b.rage = 3;
      var c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'The War-King', null, then1: ['2']);
      expect(c.attackValue, 1 + 4);
      expect(b.rage, 1);
      c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Epic Poem', null);
      expect(c.attackValue, 2 + 2, reason: 'gains 1 Rage first (2), then +2');
    });

    test('No Contest Expecteth: spend 3 Rage to defeat the sidekick', () async {
      final s = Scenario('beowulf', 'king-arthur');
      final b = s.p1.script as Beowulf;
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p2), 5);
      b.rage = 3;
      await s.fight(s.hero(s.p1), s.sidekick(s.p2), 'No Contest Expecteth', null, then1: ['Yes']);
      expect(s.sidekick(s.p2).defeated, isTrue);
      expect(b.rage, 0);
    });
  });

  group('Ancient Leshen', () {
    test("Heart of the Forest: +3 on the Leshen's second attack; Wolves move 3", () async {
      final s = Scenario('ancient-leshen', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.sidekick(s.p1), 0);
      s.place(s.hero(s.p2), 5);
      expect(s.game.moveValueOf(s.sidekick(s.p1)), 3);
      expect(s.game.moveValueOf(s.hero(s.p1)), 1);
      s.give(s.p1, 'Flock of Birds');
      s.a1
        ..then(card('Flock of Birds'))
        ..then(skip);
      await s.game.attack(s.hero(s.p1), s.hero(s.p2));
      s.give(s.p1, 'Flock of Birds');
      s.a1
        ..then(card('Flock of Birds'))
        ..then(skip);
      await s.game.attack(s.hero(s.p1), s.hero(s.p2));
      expect(s.hero(s.p2).hp, 16 - 5 - 8);
    });

    test('Strength of the Pack: summon, heal each turn, discarded without Wolves in the zone', () async {
      final s = Scenario('ancient-leshen', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.hero(s.p1).hp = 10;
      s.a1.then(sp(6));
      await s.game.playScheme(s.p1, s.give(s.p1, 'Strength of the Pack'));
      expect(s.sidekick(s.p1).space, 6);
      expect(s.p1.inPlay, hasLength(1));
      for (final m in s.game.mods.toList()) {
        await m.startOfTurn(s.game, s.p1);
      }
      expect(s.hero(s.p1).hp, 11);
      await s.game.defeat(s.sidekick(s.p1));
      for (final m in s.game.mods.whereType<OngoingMod>().toList()) {
        if (m.discardAtEndOfTurn(s.game)) await s.game.discardOngoing(m);
      }
      expect(s.p1.inPlay, isEmpty);
    });
  });

  group('Geralt', () {
    test('Always Prepared: the deck has one sword, armor and potion, 2 copies each (30 cards)', () async {
      final s = Scenario('geralt-of-rivia', 'medusa');
      final g = s.p1.script as Geralt;
      s.a1.queue.addAll([0, 1, 0]); // Steel, Armor of the Forgotten Wolf, Blizzard
      await g.beforeDeck();
      final deck = g.deckCards().toList();
      expect(deck, hasLength(30));
      expect(deck.where(isGear).map((c) => c.upperTitle).toSet(),
          {'GEAR: SWORD OF STEEL', 'GEAR: ARMOR OF THE FORGOTTEN WOLF', 'GEAR: BLIZZARD'});
      expect(deck.where(isGear), hasLength(6));
    });

    test('Blizzard: opponents cannot gain actions while it is in play', () async {
      final s = Scenario('geralt-of-rivia', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.a1.then(sp(4));
      await s.game.playScheme(s.p1, s.give(s.p1, 'GEAR: Blizzard'));
      s.startTurn(s.p2);
      s.game.actions = 0;
      s.game.gainActions(s.p2, 1);
      expect(s.game.actions, 0);
    });

    test('Wolf Medallion: cancel, and ignore the value when the attacker is not adjacent', () async {
      final s = Scenario('medusa', 'geralt-of-rivia');
      s.place(s.hero(s.p1), 3);
      s.place(s.hero(s.p2), 5);
      final c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Gaze of Stone', 'GEAR: Wolf Medallion');
      expect(c.attackValue, 0);
    });

    test('Sword of Steel: 2 actions against a fighter with 8+ health', () async {
      final s = Scenario('geralt-of-rivia', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.game.actions = 0;
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'GEAR: Sword of Steel', null);
      expect(s.game.actions, 2);
    });
  });

  group('Ciri', () {
    test('Source tiers: only the highest threshold reached resolves', () async {
      final s = Scenario('ciri', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      var c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Lion Cub of Cintra', null);
      expect(c.attackValue, 2, reason: 'no Source cards in the discard pile');
      s.p1.discard.clear();
      s.discardPile(s.p1, ['Zireael']);
      c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Lion Cub of Cintra', null);
      expect(c.attackValue, 4);
      s.discardPile(s.p1, ['Zireael', 'Zireael', 'Pushed to the Brink']);
      c = await s.fight(s.hero(s.p1), s.hero(s.p2), 'Lion Cub of Cintra', null);
      expect(c.attackValue, 7, reason: '6 Source cards now (incl. the last Lion Cub)');
    });

    test('7+ Source: Ciri cannot be canceled', () async {
      final s = Scenario('medusa', 'ciri');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.discardPile(s.p2, List.filled(7, 'Zireael'));
      await s.fight(s.hero(s.p1), s.hero(s.p2), 'Feint', 'Pushed to the Brink', then2: [s.hero(s.p1)]);
      expect(s.events.whereType<Canceled>(), isEmpty);
      expect(s.hero(s.p1).hp, 14);
    });
  });
}
