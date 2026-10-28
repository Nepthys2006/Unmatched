// Special abilities of the heroes whose cards were only covered by simulated games until now.
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/combat.dart';
import 'package:unmatched_game/engine/hero_script.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

/// The value breakdown lines of [title] played by [a] against [d] (or defending, [defend]).
List<String> labels(Scenario s, Fighter a, Fighter d, String title, {bool defend = false}) {
  final c = Combat(a, d);
  final side = defend ? c.defender : c.attacker;
  side.card = s.make(side.player, title);
  return [for (final l in s.game.valueOf(side).lines) l.$1];
}

/// [hero] (player 1) at 4 and Medusa at 5, both with plenty of health.
Scenario duel(String hero) {
  final s = Scenario(hero, 'medusa');
  s.place(s.hero(s.p1), 4);
  s.place(s.hero(s.p2), 5);
  s.hero(s.p2).hp = 30;
  return s;
}

Fighter sk(Player p, String id) => p.fighters.firstWhere((f) => f.id == id);

void main() {
  test('The Genie · Infinite Power: discard a card at the start of the turn to gain 1 action', () async {
    final s = duel('the-genie');
    s.give(s.p1, 'Feint');
    s.give(s.p1, 'Three Wishes');
    s.a1.then(card('Feint'));
    await s.p1.script.startOfTurn(s.game, s.p1);
    expect(s.p1.hand.map((c) => c.title), ['Three Wishes']);
    expect(s.game.actions, 3);
  });

  test('Harry Houdini · Escape Artist: a boosted maneuver may place him anywhere; the Magician blocks a hand look', () async {
    final s = duel('harry-houdini');
    s.a1
      ..then('Yes')
      ..then(sp(10));
    await s.p1.script.maneuverMove(s.hero(s.p1), 2, boosted: true);
    expect(s.hero(s.p1).space, 10);
    s.give(s.p1, 'A Magician Never Reveals His Secrets');
    s.a1.then('Yes');
    expect(await s.game.lookAtHand(s.p2, s.p1), isFalse);
  });

  test('Annie Christmas · Necklace of Pearls: +2 to her attacks with less health than the defender', () {
    final s = duel('annie-christmas');
    s.hero(s.p1).hp = 5;
    expect(labels(s, s.hero(s.p1), s.hero(s.p2), 'Lagniappe'), contains('Necklace of Pearls'));
    s.hero(s.p1).hp = 14;
    s.hero(s.p2).hp = 5;
    expect(labels(s, s.hero(s.p1), s.hero(s.p2), 'Lagniappe'), isNot(contains('Necklace of Pearls')));
  });

  test('Nikola Tesla · Electrical Overflow: charges at end of turn; both coils hit and push adjacent foes', () async {
    final s = duel('nikola-tesla');
    final t = s.p1.script as dynamic;
    expect(t.coils, 1, reason: 'starts with 1 coil charged');
    await s.p1.script.endOfTurn(s.game, s.p1);
    expect(t.coils, 2);
    final hp = s.hero(s.p2).hp;
    s.a1.then(sp(6));
    await s.p1.script.startOfTurn(s.game, s.p1);
    expect(s.hero(s.p2).hp, hp - 1);
    expect(s.hero(s.p2).space, 6);
  });

  test('Golden Bat · The First Superhero: +2 to his attacks if you have not maneuvered this turn', () {
    final s = duel('golden-bat');
    expect(labels(s, s.hero(s.p1), s.hero(s.p2), 'Super Strength'), contains('The First Superhero'));
    s.game.turn.maneuvers = 1;
    expect(labels(s, s.hero(s.p1), s.hero(s.p2), 'Super Strength'), isNot(contains('The First Superhero')));
  });

  test('Blackbeard · Privateer Turned Pirate: pay a doubloon for an action; pay one when hit in combat', () async {
    final s = duel('blackbeard');
    final b = s.p1.script as dynamic;
    expect([b.doubloons, b.treasury], [2, 1]);
    s.a1.then('Yes');
    await s.p1.script.startOfTurn(s.game, s.p1);
    expect(s.game.actions, 3);
    expect([b.doubloons, b.treasury], [1, 2]);
    await s.game.damage(s.hero(s.p1), 2, info: DamageInfo(combat: true, source: s.hero(s.p2)));
    expect([b.doubloons, b.treasury], [0, 3]);
  });

  test("Loki · Mischief-Monger: +1 move per TRICK in opponents' hands; a played TRICK goes to their hand", () async {
    final s = duel('loki');
    final loki = s.hero(s.p1);
    expect(s.game.moveValueOf(loki), 2);
    s.p2.hand.add(s.make(s.p1, "Trick: Freyja's Rescue"));
    expect(s.game.moveValueOf(loki), 3);
    await s.fight(loki, s.hero(s.p2), "Trick: Baldr's Downfall", null);
    expect(s.p2.hand.where((c) => c.owner == s.p1).map((c) => c.def.upperTitle), contains("TRICK: BALDR'S DOWNFALL"));
    expect(s.game.moveValueOf(loki), 4);
  });

  test('Doctor Strange · Dark Pact: take 1 damage to put the played card under the deck and draw 1', () async {
    final s = duel('doctor-strange');
    final ds = s.hero(s.p1);
    final hp = ds.hp, hand = s.p1.hand.length;
    await s.fight(ds, s.hero(s.p2), 'Feint', null, then1: ['Yes']);
    expect(ds.hp, hp - 1);
    expect(s.p1.deck.last.title, 'Feint');
    expect(s.p1.hand.length, hand + 1);
  });

  test('Black Widow · Mission Ready: starts with The Moscow Protocol; missions need their requirement', () async {
    final s = duel('black-widow');
    s.deck(s.p1, ['Feint', 'Feint', 'The Moscow Protocol']);
    await s.p1.script.beforeStartingHand();
    expect(s.p1.hand.map((c) => c.title), contains('The Moscow Protocol'));
    for (var i = 0; i < 4; i++) {
      s.give(s.p1, 'Feint');
    }
    final budapest = s.give(s.p1, 'The Budapest Gambit');
    expect(s.game.schemeFighters(s.p1, budapest), isEmpty, reason: 'needs 2 or fewer other cards in hand');
    s.p1.hand.removeWhere((c) => c.title == 'Feint');
    expect(s.game.schemeFighters(s.p1, budapest), isNotEmpty);
  });

  test('Willow: damage turns her into Dark Willow; next to Tara at the end of the turn she turns back', () async {
    final s = duel('willow');
    final w = s.hero(s.p1), tara = sk(s.p1, 'tara');
    s.place(tara, 3);
    await s.game.damage(w, 1);
    expect(s.p1.script.status(), ['DARK']);
    expect(s.p1.name, 'Dark Willow');
    await s.p1.script.endOfTurn(s.game, s.p1);
    expect(s.p1.script.status(), isEmpty);
  });

  test('Titania · Fairy Magic: flips a glamour at the start of the turn; Glamour of Sleep stops effect damage', () async {
    final s = duel('titania');
    final t = s.p1.script as dynamic;
    (t.glamourDeck as List<String>)
      ..clear()
      ..add('SLEEP');
    await s.p1.script.startOfTurn(s.game, s.p1);
    expect(t.glamour, 'SLEEP');
    final hp = s.hero(s.p1).hp;
    await s.game.damage(s.hero(s.p1), 2);
    expect(s.hero(s.p1).hp, hp, reason: 'non-combat damage is prevented');
    await s.game.damage(s.hero(s.p1), 2, info: const DamageInfo(combat: true));
    expect(s.hero(s.p1).hp, hp - 2);
  });

  test('Hamlet · The Question: NOT TO BE hurts one of his fighters and adds +2; TO BE draws 1 more on a maneuver', () async {
    final s = duel('hamlet');
    final h = s.hero(s.p1);
    s.place(sk(s.p1, 'rosencrantz-guildenstern'), 3);
    final hp = h.hp;
    s.a1
      ..then('NOT TO BE')
      ..then(h);
    await s.p1.script.startOfTurn(s.game, s.p1);
    expect(h.hp, hp - 2);
    expect(labels(s, h, s.hero(s.p2), 'Uncertain Doom'), contains('NOT TO BE'));
    s.a1.then('TO BE');
    await s.p1.script.startOfTurn(s.game, s.p1);
    expect(s.p1.script.maneuverDraws(s.game, s.p1, 1), 2);
    expect(labels(s, h, s.hero(s.p2), 'Uncertain Doom'), isNot(contains('NOT TO BE')));
  });

  test('Leonardo · Team Tactics: at the start of the turn, move any fighter up to 1 space', () async {
    final s = duel('leonardo');
    s.a1
      ..then(s.hero(s.p2))
      ..then(sp(6));
    await s.p1.script.startOfTurn(s.game, s.p1);
    expect(s.hero(s.p2).space, 6);
  });

  test('Donatello · Inventive: draw 2 on a maneuver and put one on the bottom; inventions stay as bonuses', () async {
    final s = duel('donatello');
    s.deck(s.p1, ['Quick strike', 'Shift focus', 'Bo staff']);
    final hand = s.p1.hand.length;
    s.a1
      ..then('Yes')
      ..then(card('Quick strike'));
    await s.p1.script.maneuverDraw(1);
    expect(s.p1.hand.length, hand + 1);
    expect(s.p1.deck.last.title, 'Quick strike');
    await s.fight(s.hero(s.p1), s.hero(s.p2), 'Electro grenade', null);
    expect(labels(s, s.hero(s.p1), s.hero(s.p2), 'Quick strike'), contains('Invention: Electro Grenade'));
  });

  test('Michelangelo · Pizza Party: hand of 3 to start and at most; draws 1 after an attack or scheme', () async {
    final s = duel('michelangelo');
    expect(s.p1.script.startingHand, 3);
    expect(s.p1.script.handLimit(s.game, s.p1, 7), 3);
    final hand = s.p1.hand.length;
    await s.p1.script.afterAction(s.game, s.p1, ActionKind.attack);
    expect(s.p1.hand.length, hand + 1);
    await s.p1.script.afterAction(s.game, s.p1, ActionKind.maneuver);
    expect(s.p1.hand.length, hand + 1, reason: 'not after a maneuver');
  });

  test('Shredder · Master of the Clan: deploys a Foot soldier; his fighters reach foes next to Foot soldiers', () async {
    final s = Scenario('shredder', 'medusa');
    final sh = s.hero(s.p1), m = s.hero(s.p2);
    s.place(sh, 0);
    s.place(sk(s.p1, 'bebop-rocksteady'), 7);
    s.place(m, 9);
    expect(s.game.inReach(sh, m), isFalse);
    s.a1.then('Path 7–8');
    await s.p1.script.startOfTurn(s.game, s.p1);
    s.place(m, 8);
    expect(s.game.inReach(sh, m), isTrue, reason: 'Medusa is next to a Foot soldier');
  });

  test('Krang · DOOOOM!: move is 1 + active machines; deactivating a machine rerolls the die', () async {
    final s = duel('krang');
    final k = s.p1.script as dynamic;
    expect(s.game.moveValueOf(s.hero(s.p1)), 2);
    s.a1.then('Yes');
    await s.p1.script.rollDie('test');
    expect(k.machines, 0);
    expect(s.game.moveValueOf(s.hero(s.p1)), 1);
  });

  test('Moon Knight: moves 2 at the start of his turn, then Khonshu (+2 attack, no effect damage), then Mr. Knight (+1 defense)', () async {
    final s = duel('moon-knight');
    final mk = s.hero(s.p1);
    s.a1.then(sp(2));
    await s.p1.script.startOfTurn(s.game, s.p1);
    expect(mk.space, 2);
    await s.p1.script.endOfTurn(s.game, s.p1);
    expect(s.p1.name, 'Khonshu');
    expect(labels(s, mk, s.hero(s.p2), 'Fist of Khonshu'), contains('Khonshu'));
    final hp = mk.hp;
    await s.game.damage(mk, 2);
    expect(mk.hp, hp);
    await s.p1.script.endOfTurn(s.game, s.p1);
    expect(s.p1.name, 'Mr. Knight');
    expect(labels(s, s.hero(s.p2), mk, 'Fist of Khonshu', defend: true), contains('Mr. Knight'));
  });

  test('Eredin · King of the Wild Hunt: ENRAGED with every Red Rider defeated: +1 to his cards, move 3', () {
    final s = duel('eredin');
    final e = s.hero(s.p1);
    expect(labels(s, e, s.hero(s.p2), 'Backhand'), isNot(contains('Eredin is ENRAGED')));
    for (final r in s.p1.fighters.where((f) => f.isSidekick)) {
      r.defeated = true;
    }
    expect(labels(s, e, s.hero(s.p2), 'Backhand'), contains('Eredin is ENRAGED'));
    expect(s.game.moveValueOf(e), 3);
  });

  test('Philippa · Two Steps Ahead: at the end of the turn, draw up to 4 cards', () async {
    final s = duel('philippa');
    s.give(s.p1, 'Cunning');
    s.a1.then('Yes');
    await s.p1.script.endOfTurn(s.game, s.p1);
    expect(s.p1.hand, hasLength(4));
  });

  test('Yennefer & Triss: choose the hero; Triss deals 2 after her schemes; Yennefer may BOOST her attack', () async {
    final s = Scenario('yennefer-triss', 'medusa');
    s.a1.then('Triss');
    await s.p1.script.beforeDeck();
    expect(s.p1.name, 'Triss');
    expect(s.p1.fighters.where((f) => f.id == 'triss'), isEmpty, reason: 'the chosen sorceress is the hero, not a sidekick');
    final t = s.hero(s.p1), m = s.hero(s.p2);
    s.place(t, 4);
    s.place(m, 5);
    m.hp = 30;
    s.a1
      ..then(t)
      ..then(m);
    await s.game.playScheme(s.p1, s.give(s.p1, 'Lodge of sorceresses'));
    expect(m.hp, lessThanOrEqualTo(28));

    final y = Scenario('yennefer-triss', 'medusa');
    y.a1.then('Yennefer');
    await y.p1.script.beforeDeck();
    y.place(y.hero(y.p1), 4);
    y.place(y.hero(y.p2), 5);
    y.hero(y.p2).hp = 30;
    y.give(y.p1, 'Ball lightning');
    final c = await y.fight(y.hero(y.p1), y.hero(y.p2), 'Echoing blast', null, then1: [card('Ball lightning')]);
    expect(c.attackValue, 3 + 1, reason: 'Echoing blast 3, boosted by Ball lightning (BOOST 1)');
  });
}
