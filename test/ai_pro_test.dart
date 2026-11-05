// The Pro AI's game plan (lib/engine/ai_pro.dart): hand first, press only with more cards,
// punish an opponent who stopped defending. Board: line 0-11 (+12 off 5); zones a=0..3,
// b=3..7+12, c=8..11. Achilles moves 2.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/combat.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';
import 'package:unmatched_game/ui/match/match_config.dart';

import 'support.dart';

/// The action [p] picks now, as the Pro AI.
Future<ActionChoice> proAction(Scenario s, Player p) async {
  final choices = s.game.legalActions(p);
  final prompt = Prompt(
    player: p,
    ask: Ask.action,
    text: 'Choose an action',
    choices: [for (final a in choices) Choice(a.kind.name, a)],
  );
  final [i] = await AiAgent(level: AiLevel.pro).decide(s.game, prompt);
  return choices[i];
}

void main() {
  late Scenario s;
  late Fighter achilles, medusa;
  setUp(() {
    s = Scenario('achilles', 'medusa');
    achilles = s.hero(s.p1);
    medusa = s.hero(s.p2);
    s.game.actions = 1; // the first of two actions
  });

  void hands(List<String> mine, List<String> theirs) {
    s.p1.hand.clear();
    s.p2.hand.clear();
    for (final t in mine) {
      s.give(s.p1, t);
    }
    for (final t in theirs) {
      s.give(s.p2, t);
    }
  }

  test('1. apart with a hand to fill, it maneuvers, even with a Harpy to hit', () async {
    s.place(achilles, 2);
    s.place(s.sidekick(s.p2), 3);
    s.place(medusa, 11);
    hands(['Brothers In Arms', 'Skirmish', "Achilles' Heel"], ['Snipe', 'Dash']);
    expect((await proAction(s, s.p1)).kind, ActionKind.maneuver);
  });

  test('2. head to head with more cards and a defense to spare, it presses the attack', () async {
    s.place(achilles, 4);
    s.place(medusa, 5);
    hands(['Brothers In Arms', 'Skirmish', "Achilles' Heel"], ['Snipe', 'Dash']);
    final a = await proAction(s, s.p1);
    expect(a.kind, ActionKind.attack);
    expect(a.target, medusa);
  });

  test('2. head to head with fewer cards than them, it makes distance', () async {
    s.place(achilles, 4);
    s.place(medusa, 5);
    hands(['Brothers In Arms', "Achilles' Heel"], ['Snipe', 'Dash', 'Feint', 'Regroup']);
    expect((await proAction(s, s.p1)).kind, ActionKind.maneuver);
  });

  test('3. they let an attack through: they are out of defenses, so it attacks with fewer cards', () async {
    s.place(achilles, 4);
    s.place(medusa, 5);
    hands(['Brothers In Arms', "Achilles' Heel"], ['A Momentary Glance', 'Winged Frenzy', 'Second Shot']);
    await s.fight(achilles, medusa, 'Skirmish', null); // Medusa has nothing to defend with
    expect(s.p2.hand.length, greaterThan(s.p1.hand.length));
    final a = await proAction(s, s.p1);
    expect(a.kind, ActionKind.attack);
  });

  group('Achilles', () {
    late Fighter patroclus;
    setUp(() => patroclus = s.sidekick(s.p1));

    Future<String> proDefense(Fighter attacker, List<String> cards) async {
      s.p1.hand.clear();
      for (final t in cards) {
        s.give(s.p1, t);
      }
      final p = Prompt(
        player: s.p1,
        ask: Ask.card,
        text: 'Play a defense card or skip',
        choices: [for (final c in s.p1.hand) Choice(c.title, c)],
        optional: true,
        intent: Intent.defenseCard,
        subject: Combat(attacker, achilles),
      );
      final [i] = await AiAgent(level: AiLevel.pro).decide(s.game, p);
      return s.p1.hand[i].title;
    }

    test('1. no level plays Spear Throw with nobody in his zone', () async {
      s.place(achilles, 0);
      s.place(medusa, 11);
      hands(['Spear Throw', 'Skirmish'], ['Snipe']);
      final choices = s.game.legalActions(s.p1);
      final p = Prompt(player: s.p1, ask: Ask.action, text: 'Choose', choices: [for (final a in choices) Choice(a.kind.name, a)]);
      final scheme = choices.indexWhere((a) => a.kind == ActionKind.scheme);
      for (final level in AiLevel.values) {
        expect(AiAgent(level: level).obeysRules(s.game, p, [scheme]), isFalse, reason: level.name);
      }
    });

    test('2. Patroclus leads the attack', () async {
      s.place(achilles, 4);
      s.place(medusa, 5);
      s.place(patroclus, 6);
      hands(['Battle Frenzy', 'Skirmish', 'Brothers In Arms', "Achilles' Heel"], ['Snipe', 'Dash']);
      final a = await proAction(s, s.p1);
      expect(a.kind, ActionKind.attack);
      expect(a.fighter, patroclus);
    });

    test("3. while Patroclus lives, Achilles defends with Under Achilles' Helm", () async {
      s.place(achilles, 4);
      s.place(medusa, 5);
      s.place(patroclus, 8);
      expect(await proDefense(medusa, ['Skirmish', "Under Achilles' Helm", 'Feint']), "Under Achilles' Helm");
    });

    test('4. once Patroclus falls, all out: it attacks even with fewer cards than them', () async {
      patroclus.defeated = true;
      s.place(achilles, 4);
      s.place(medusa, 5);
      hands(['Skirmish', 'Brothers In Arms'], ['Snipe', 'Dash', 'Feint', 'Regroup']);
      final a = await proAction(s, s.p1);
      expect(a.kind, ActionKind.attack);
      expect(a.target, medusa);
    });

    test('5. Spear Throw finishes their hero; not otherwise with cards to fill the hand', () async {
      s.place(achilles, 3);
      s.place(medusa, 6); // in Achilles' zone, out of his reach
      hands(['Spear Throw', 'Skirmish', 'Feint'], ['Snipe']);
      expect((await proAction(s, s.p1)).kind, isNot(ActionKind.scheme));
      medusa.hp = 2;
      final a = await proAction(s, s.p1);
      expect(a.kind, ActionKind.scheme);
      expect(a.card!.title, 'Spear Throw');
    });

    Future<String> proAttackCard(Fighter attacker, Fighter target, List<String> cards) async {
      s.p1.hand.clear();
      for (final t in cards) {
        s.give(s.p1, t);
      }
      final p = Prompt(
        player: s.p1,
        ask: Ask.card,
        text: 'Choose an attack card',
        choices: [for (final c in s.p1.hand) Choice(c.title, c)],
        intent: Intent.attackCard,
        subject: Combat(attacker, target),
      );
      final [i] = await AiAgent(level: AiLevel.pro).decide(s.game, p);
      return s.p1.hand[i].title;
    }

    Future<String> proTakeBack(List<String> discard) async {
      s.p1.discard.clear();
      s.discardPile(s.p1, discard);
      final p = Prompt(
        player: s.p1,
        ask: Ask.card,
        text: 'Return a card from your discard pile to your hand',
        choices: [for (final c in s.p1.discard) Choice(c.title, c)],
        intent: Intent.gainOwn,
      );
      final [i] = await AiAgent(level: AiLevel.pro).decide(s.game, p);
      return s.p1.discard[i].title;
    }

    test('7. Battle Hardened takes back Brothers In Arms while Patroclus lives; Spear Throw to finish them', () async {
      s.place(achilles, 3);
      s.place(medusa, 6);
      s.place(patroclus, 2);
      expect(await proTakeBack(['Skirmish', 'Brothers In Arms', 'Feint', 'Spear Throw']), 'Brothers In Arms');
      medusa.hp = 2;
      expect(await proTakeBack(['Skirmish', 'Brothers In Arms', 'Feint', 'Spear Throw']), 'Spear Throw');
    });

    test('7. the second Battle Hardened takes back the first, unless Spear Throw would finish them', () async {
      s.place(achilles, 3);
      s.place(medusa, 6);
      s.place(patroclus, 2);
      final pile = ['Skirmish', 'Brothers In Arms', 'Battle Hardened', 'Feint', 'Spear Throw'];
      expect(await proTakeBack(pile), 'Battle Hardened');
      medusa.hp = 2;
      expect(await proTakeBack(pile), 'Spear Throw');
    });

    test('7. ... and Feint against a hero whose card effects are best canceled', () async {
      final w = Scenario('achilles', 'sun-wukong');
      s = w;
      w.place(w.hero(w.p1), 3);
      w.place(w.hero(w.p2), 6);
      w.sidekick(w.p1).defeated = true;
      expect(await proTakeBack(['Skirmish', 'Feint', 'Brothers In Arms']), 'Feint');
    });

    test('7. late, with Patroclus fallen, Battle Hardened defends (a win would draw)', () async {
      patroclus.defeated = true;
      s.place(achilles, 4);
      s.place(medusa, 5);
      s.deck(s.p1, ['Skirmish', 'Skirmish']);
      expect(await proDefense(medusa, ['Skirmish', 'Battle Hardened']), 'Battle Hardened');
    });

    test('8. Test For Weakness once Patroclus has fallen', () async {
      patroclus.defeated = true;
      s.place(achilles, 4);
      s.place(medusa, 5);
      expect(await proAttackCard(achilles, medusa, ['Skirmish', 'Test For Weakness', 'Brothers In Arms']), 'Test For Weakness');
    });

    test("9. Brothers In Arms first against a sidekick, Patroclus' own cards later", () async {
      final harpy = s.sidekick(s.p2);
      s.place(patroclus, 4);
      s.place(harpy, 5);
      s.place(achilles, 0);
      s.place(medusa, 11);
      expect(await proAttackCard(patroclus, harpy, ['Battle Frenzy', 'Brothers In Arms', 'Skirmish']), 'Brothers In Arms');
    });

    test("6. Achilles' Heel not against an attack that may beat 4, unless it is the only defense", () async {
      final b = Scenario('achilles', 'bigfoot'); // Bigfoot holds 6s
      s = b;
      achilles = b.hero(b.p1);
      final bigfoot = b.hero(b.p2);
      b.place(achilles, 4);
      b.place(bigfoot, 5);
      b.give(b.p2, 'Larger Than Life');
      expect(await proDefense(bigfoot, ["Achilles' Heel", 'Feint']), 'Feint');
      expect(await proDefense(bigfoot, ["Achilles' Heel"]), "Achilles' Heel");
    });
  });

  group('general rules', () {
    late Scenario b;
    late Fighter achilles, bigfoot, patroclus;
    setUp(() {
      b = Scenario('achilles', 'bigfoot');
      achilles = b.hero(b.p1);
      bigfoot = b.hero(b.p2);
      patroclus = b.sidekick(b.p1);
      b.a1.fallback = AiAgent(level: AiLevel.pro);
    });

    /// Bigfoot attacks Achilles, who wins with Skirmish (4 against 1) and moves someone 2.
    Future<void> skirmish({required int theirActionsLeft}) async {
      b.startTurn(b.p2);
      b.game.actions = theirActionsLeft;
      b.give(b.p1, 'Feint');
      await b.fight(bigfoot, achilles, 'Regroup', 'Skirmish');
    }

    test("5. Skirmish on their first action: out of their reach (they'd attack again)", () async {
      b.place(achilles, 4);
      b.place(bigfoot, 5);
      await skirmish(theirActionsLeft: 1);
      expect(b.game.board.adjacent(achilles.space!, bigfoot.space!), isFalse);
    });

    test('5. Skirmish on their last action: my turn next, so stay in reach', () async {
      b.place(achilles, 4);
      b.place(bigfoot, 5);
      await skirmish(theirActionsLeft: 0);
      expect(b.game.board.adjacent(achilles.space!, bigfoot.space!), isTrue);
    });

    test('5. ... and next to two of mine, it moves them away from both', () async {
      b.place(achilles, 4);
      b.place(bigfoot, 5);
      b.place(patroclus, 6);
      await skirmish(theirActionsLeft: 1);
      expect(bigfoot.space, isNot(5));
      expect(b.game.board.adjacent(achilles.space!, bigfoot.space!), isFalse);
      expect(b.game.board.adjacent(patroclus.space!, bigfoot.space!), isFalse);
    });

    test('6. a sidekick with cards of its own and no defense ends the turn out of reach', () {
      final h = Scenario('alice', 'bigfoot');
      final watson = h.sidekick(h.p1); // the Jabberwock
      h.place(h.hero(h.p1), 0);
      h.place(watson, 3);
      h.place(h.hero(h.p2), 5);
      h.game.actions = 0;
      h.p1.hand.clear();
      final pro = AiAgent(level: AiLevel.pro), insane = AiAgent(level: AiLevel.insane);
      // How much more it likes space 11 (out of Bigfoot's reach) than 6 (next to him) than Insane does.
      double extra() =>
          (pro.ownSpaceScore(h.game, watson, 11) - pro.ownSpaceScore(h.game, watson, 6)) -
          (insane.ownSpaceScore(h.game, watson, 11) - insane.ownSpaceScore(h.game, watson, 6));
      expect(extra(), greaterThan(5));
      final guard = h.p1.hero.cards.firstWhere((c) => c.canDefend && c.fighters.isEmpty);
      h.give(h.p1, guard.title);
      expect(extra(), lessThan(1));
    });

    /// Plays p1's whole turn as [level]; whether one of its fighters attacked.
    Future<bool> turnAttacks(AiLevel level) async {
      b.a1.fallback = AiAgent(level: level);
      b.startTurn(b.p1);
      final before = b.events.length;
      await b.game.finishTurn(b.p1);
      return b.events.skip(before).any((e) => e is CombatEnded && e.combat.attacker.player == b.p1);
    }

    // Pro only: Insane still maneuvers twice (the other levels play as before).
    for (final level in [AiLevel.pro, AiLevel.insane]) {
      test('8. ${level.name}: 6 cards, they are a BOOST away: Pro boosts the first maneuver and attacks', () async {
        b.place(achilles, 0);
        b.place(bigfoot, 5); // Achilles moves 2: from 0 he needs 4 to get next to him
        b.give(b.p2, 'Regroup');
        b.p1.hand.clear();
        for (final t in ['Brothers In Arms', 'Skirmish', 'Feint', 'Battle Hardened', 'Wily Fighting', 'Spear Throw']) {
          b.give(b.p1, t);
        }
        expect(await turnAttacks(level), level == AiLevel.pro);
      });
    }

    test('8. ... but not a hurt hero with no defense', () async {
      b.place(achilles, 0);
      b.place(bigfoot, 5);
      achilles.hp = 4;
      b.p1.hand.clear();
      for (final t in ['Brothers In Arms', 'Test For Weakness', 'Spear Throw', 'Brothers In Arms', 'Spear Throw', 'Test For Weakness']) {
        b.give(b.p1, t);
      }
      b.deck(b.p1, List.filled(10, 'Spear Throw')); // draws nothing to defend with
      expect(await turnAttacks(AiLevel.pro), isFalse);
    });

    test('7. with fewer cards than them, the fewer it holds the further it keeps away', () async {
      b.place(achilles, 2);
      b.place(bigfoot, 11);
      for (var i = 0; i < 7; i++) {
        b.give(b.p2, 'Regroup');
      }
      final pro = AiAgent(level: AiLevel.pro);
      void hand(int n) {
        b.p1.hand.clear();
        for (var i = 0; i < n; i++) {
          b.give(b.p1, 'Skirmish');
        }
      }

      hand(5);
      final choices = b.game.legalActions(b.p1);
      await pro.decide(b.game, Prompt(player: b.p1, ask: Ask.action, text: 'Choose', choices: [for (final a in choices) Choice(a.kind.name, a)]));
      // Space 0 is 7 moves beyond Bigfoot's reach, space 4 is 3.
      double gap() => pro.ownSpaceScore(b.game, achilles, 0) - pro.ownSpaceScore(b.game, achilles, 4);
      final five = gap();
      hand(2);
      expect(gap(), greaterThan(five + 1));
    });
  });

  group('Sherlock Holmes', () {
    late Scenario h;
    late Fighter holmes, foe;
    late AiAgent pro;

    /// Sherlock against [hero]: Holmes in 2, their hero far away in 9.
    void vs(String hero) {
      h = Scenario('sherlock-holmes', hero);
      holmes = h.hero(h.p1);
      foe = h.hero(h.p2);
      h.place(holmes, 2);
      h.place(foe, 9);
      h.game.actions = 1;
      pro = AiAgent(level: AiLevel.pro);
    }

    void mine(List<String> cards) {
      h.p1.hand.clear();
      for (final t in cards) {
        h.give(h.p1, t);
      }
    }

    /// Their hand; [seen]: Holmes has looked at it.
    void theirs(List<String> cards, {bool seen = true}) {
      h.p2.hand.clear();
      for (final t in cards) {
        h.give(h.p2, t);
      }
      if (seen) h.p1.script.seen(h.p2.hand);
    }

    Future<ActionChoice> act() async {
      final choices = h.game.legalActions(h.p1);
      final p = Prompt(player: h.p1, ask: Ask.action, text: 'Choose an action', choices: [for (final a in choices) Choice(a.kind.name, a)]);
      final [i] = await pro.decide(h.game, p);
      return choices[i];
    }

    Future<int> suspicion() async {
      final p = Prompt(player: h.p1, ask: Ask.number, text: 'Confirm Suspicion: name a value', choices: [for (var v = 0; v <= 8; v++) Choice('$v', v)]);
      final [i] = await pro.decide(h.game, p);
      return i;
    }

    Future<String> eliminate() async {
      final p = Prompt(
        player: h.p1,
        ask: Ask.cards,
        text: 'Choose 1 card for them to discard',
        choices: [for (final c in h.p2.hand) Choice(c.title, c)],
        min: 1,
        max: 1,
        intent: Intent.loseEnemy,
      );
      final [i] = await pro.decide(h.game, p);
      return h.p2.hand[i].title;
    }

    test('1. Confirm Suspicion names the value of the high-BOOST card it has seen', () async {
      vs('achilles');
      theirs(['Skirmish', "Under Achilles' Helm"]); // 4 (BOOST 1), 2 (BOOST 4)
      expect(await suspicion(), 2);
    });

    test('1. ... and the card that takes cards back over a plain one', () async {
      vs('achilles');
      theirs(['Skirmish', 'Battle Hardened']); // 4 (BOOST 1), 2 (takes a card back)
      expect(await suspicion(), 2);
    });

    test('2. with both, Eliminate the Impossible first (5+ cards, hand unseen)', () async {
      vs('bigfoot');
      mine(['Confirm Suspicion', 'Eliminate the Impossible', 'Feint']);
      theirs(['Regroup', 'Feint', 'Hoax', 'Skirmish', 'Savagery'], seen: false);
      final a = await act();
      expect(a.kind, ActionKind.scheme);
      expect(a.card!.title, 'Eliminate the Impossible');
    });

    test('2. no Eliminate the Impossible against 4 cards, unless it sets up the finishing blow', () async {
      vs('bigfoot');
      mine(['Eliminate the Impossible', 'The Game is Afoot', 'Feint']);
      theirs(['Regroup', 'Feint', 'Hoax', 'Skirmish'], seen: false);
      final ei = h.game.legalActions(h.p1).firstWhere((a) => a.card?.title == 'Eliminate the Impossible');
      bool allowed() {
        final choices = h.game.legalActions(h.p1);
        final p = Prompt(player: h.p1, ask: Ask.action, text: 'Choose', choices: [for (final a in choices) Choice(a.kind.name, a)]);
        return pro.obeysRules(h.game, p, [choices.indexWhere((a) => a.card?.title == ei.card!.title)]);
      }

      expect(allowed(), isFalse);
      // Their hero low, next to Holmes, 2 cards: see them, discard the defense, attack with a 5.
      h.place(foe, 3);
      foe.hp = 4;
      theirs(['Regroup', "It's Just Your Imagination"], seen: false);
      expect(allowed(), isTrue);
      h.p1.script.seen(h.p2.hand);
      expect(await eliminate(), "It's Just Your Imagination");
    });

    test('2. Eliminate the Impossible takes a scheme that heals over a card that heals', () async {
      vs('sherlock-holmes');
      theirs(['Fixed Point in a Changing Age', 'Administer Aid', 'Service Revolver']);
      expect(await eliminate(), 'Administer Aid');
    });

    test('3. Administer Aid as soon as Holmes is hurt and safe, not at full health', () async {
      vs('bigfoot');
      h.place(h.sidekick(h.p1), 6);
      mine(['Administer Aid', 'Feint', 'Elementary']);
      theirs(['Regroup', 'Feint', 'Hoax'], seen: false);
      expect((await act()).card?.title, isNot('Administer Aid'));
      holmes.hp = 13;
      final a = await act();
      expect(a.card?.title, 'Administer Aid');
    });

    Future<String> defend(Fighter attacker, Fighter defender, List<String> cards) async {
      mine(cards);
      final p = Prompt(
        player: h.p1,
        ask: Ask.card,
        text: 'Play a defense card or skip',
        choices: [for (final c in h.p1.hand) if (h.game.canDefendWith(c, defender)) Choice(c.title, c)],
        optional: true,
        intent: Intent.defenseCard,
        subject: Combat(attacker, defender),
      );
      final [i] = await pro.decide(h.game, p);
      return (p.choices[i].value as Card).title;
    }

    Future<String> attackWith(Fighter attacker, Fighter target, List<String> cards) async {
      mine(cards);
      final p = Prompt(
        player: h.p1,
        ask: Ask.card,
        text: 'Choose an attack card',
        choices: [for (final c in h.p1.hand) if (h.game.canAttackWith(c, attacker)) Choice(c.title, c)],
        intent: Intent.attackCard,
        subject: Combat(attacker, target),
      );
      final [i] = await pro.decide(h.game, p);
      return (p.choices[i].value as Card).title;
    }

    const seven = ['Confirm Suspicion', 'Feint', 'Elementary', 'Counterpunch', 'Study Methods', 'Deduce Strategy', 'Feint'];

    test('5. below 7 cards, holding: no attack', () async {
      vs('bigfoot');
      h.place(foe, 3);
      mine(seven.take(5).toList());
      theirs(['Regroup', 'Feint', 'Hoax', 'Skirmish', 'Savagery', 'Disengage', 'Momentous Shift'], seen: false);
      expect((await act()).kind, isNot(ActionKind.attack));
    });

    test('11. at 7 cards with a scheme, he attacks: with The Game is Afoot', () async {
      vs('bigfoot');
      h.place(foe, 3);
      mine(['The Game is Afoot', ...seven.take(6)]);
      theirs(['Regroup', 'Feint', 'Hoax', 'Skirmish', 'Savagery', 'Disengage', 'Momentous Shift'], seen: false);
      final a = await act();
      expect(a.kind, ActionKind.attack);
      expect(a.fighter, holmes);
      expect(await attackWith(holmes, foe, ['The Game is Afoot', ...seven.take(6)]), 'The Game is Afoot');
    });

    test('11. ... and out of reach, he maneuvers in to attack', () async {
      vs('bigfoot');
      h.place(foe, 5); // Holmes moves 2: from 2 to 4, next to him
      mine(['The Game is Afoot', ...seven.take(6)]);
      theirs(['Regroup', 'Feint', 'Hoax', 'Skirmish', 'Savagery', 'Disengage', 'Momentous Shift'], seen: false);
      expect((await act()).kind, ActionKind.maneuver);
    });

    test('12. three schemes: play one down (Eliminate the Impossible even against 3 cards)', () async {
      vs('bigfoot');
      mine(['Eliminate the Impossible', 'Master of Disguise', 'Confirm Suspicion', 'Feint']);
      theirs(['Regroup', 'Feint', 'Hoax'], seen: false);
      expect((await act()).kind, ActionKind.scheme);
    });

    test('13. Watson stands by Holmes, and in front of him when Holmes has no defense', () {
      vs('bigfoot');
      final watson = h.sidekick(h.p1);
      h.place(watson, 6);
      h.game.actions = 0;
      mine(['Elementary', 'Service Revolver']);
      expect(pro.ownSpaceScore(h.game, watson, 3), greaterThan(pro.ownSpaceScore(h.game, watson, 6)));
      // Holmes (in 2) with nothing to defend: Watson between him and Bigfoot (in 9).
      mine(['Service Revolver', 'Confirm Suspicion']);
      expect(pro.ownSpaceScore(h.game, watson, 3), greaterThan(pro.ownSpaceScore(h.game, watson, 1)));
    });

    test('5. next to them, he attacks only holding 3 cards more than them', () async {
      vs('bigfoot');
      h.place(foe, 3);
      mine(['The Game is Afoot', 'Elementary', 'Counterpunch', 'Feint', 'Study Methods']);
      theirs(['Regroup', 'Feint', 'Hoax'], seen: false); // 5 against 3
      expect((await act()).kind, isNot(ActionKind.attack));
      h.p2.hand.removeLast(); // 5 against 2
      expect((await act()).kind, ActionKind.attack);
    });

    test('6. Counterpunch defends Holmes against a melee attacker next to him, not to attack with', () async {
      vs('bigfoot');
      h.place(foe, 3);
      expect(await defend(foe, holmes, ['Counterpunch', 'Deduce Strategy', 'Feint']), 'Counterpunch');
      expect(await attackWith(holmes, foe, ['Counterpunch', 'Deduce Strategy']), 'Deduce Strategy');
    });

    test('7. Elementary predicts the strongest attack it has seen, and defends with it', () async {
      vs('bigfoot');
      h.place(foe, 3);
      theirs(['Larger Than Life', 'Regroup']);
      expect(await defend(foe, holmes, ['Elementary', 'Counterpunch', 'Study Methods']), 'Elementary');
      final c = Combat(foe, holmes);
      h.game.combat = c;
      final p = Prompt(player: h.p1, ask: Ask.number, text: "Elementary: predict the printed value of the opponent's attack", choices: [for (var v = 0; v <= 8; v++) Choice('$v', v)]);
      final [i] = await pro.decide(h.game, p);
      expect(i, 6);
      h.game.combat = null;
    });

    test('8. Fixed Point heals Holmes at 10 or less (Watson next to him), on defense', () async {
      vs('bigfoot');
      final watson = h.sidekick(h.p1);
      h.place(watson, 3);
      h.place(foe, 4);
      holmes.hp = 9;
      expect(await defend(foe, watson, ['Fixed Point in a Changing Age', 'Feint', 'Study Methods']), 'Fixed Point in a Changing Age');
    });

    test('9. Watson shoots with Service Revolver', () async {
      vs('bigfoot');
      final watson = h.sidekick(h.p1);
      h.place(watson, 6);
      expect(await attackWith(watson, foe, ['Service Revolver', 'Study Methods', 'Education Never Ends', 'Feint']), 'Service Revolver');
    });

    test('7. no Study Methods against Achilles at +2 (Patroclus fallen), unless it is the only defense', () async {
      vs('achilles');
      h.place(foe, 3);
      h.sidekick(h.p2).defeated = true;
      expect(await defend(foe, holmes, ['Study Methods', 'Deduce Strategy']), 'Deduce Strategy');
      expect(await defend(foe, holmes, ['Study Methods']), 'Study Methods');
    });

    test('14. holding, even the first of two maneuvers ends out of reach, as far as it goes', () async {
      vs('bigfoot');
      mine(['Elementary', 'Feint', 'Counterpunch', 'Study Methods', 'Deduce Strategy']);
      theirs(['Regroup', 'Feint', 'Hoax', 'Skirmish', 'Savagery', 'Disengage', 'Momentous Shift'], seen: false);
      expect((await act()).kind, ActionKind.maneuver); // holding: sets the turn's plan
      // The first action's maneuver (one left): not next to Bigfoot (in 9) for an attack it won't make.
      expect(pro.ownSpaceScore(h.game, holmes, 1), greaterThan(pro.ownSpaceScore(h.game, holmes, 8)));
      // Out of his plain reach, further still is better (he BOOSTs too).
      expect(pro.ownSpaceScore(h.game, holmes, 1), greaterThan(pro.ownSpaceScore(h.game, holmes, 3) + 1));
    });

    test('4. Master of Disguise finishes a 1-health hero; otherwise it is the card to let go', () async {
      vs('bigfoot');
      mine(['Master of Disguise', 'Feint', 'Elementary']);
      theirs(['Regroup', 'Feint'], seen: false);
      expect((await act()).card?.title, isNot('Master of Disguise'));
      final p = Prompt(
        player: h.p1,
        ask: Ask.cards,
        text: 'Discard 1 card',
        choices: [for (final c in h.p1.hand) Choice(c.title, c)],
        min: 1,
        max: 1,
        intent: Intent.loseOwn,
      );
      final [i] = await pro.decide(h.game, p);
      expect(h.p1.hand[i].title, 'Master of Disguise');
      foe.hp = 1;
      expect((await act()).card?.title, 'Master of Disguise');
    });
  });

  test('a random AI hero for Pro is one it has been taught', () {
    final data = loadData();
    for (var seed = 0; seed < 20; seed++) {
      final ids = MatchConfig.lineup(data, 'medusa', 2, preferred: proHeroes, rng: Random(seed));
      expect(ids.first, 'medusa');
      expect(proHeroes, contains(ids[1]));
    }
    // Not the hero you play, though.
    expect(MatchConfig.lineup(data, 'achilles', 2, preferred: proHeroes, rng: Random(1))[1], isNot('achilles'));
  });
}
