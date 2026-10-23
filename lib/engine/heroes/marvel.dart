/// Marvel: She-Hulk, Spider-Man (Brains and Brawn), Black Panther, Winter Soldier (For King and
/// Country).
library;

import 'dart:math' as math;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

/// Moves each of [p]'s fighters up to [n], with [p] choosing (effects that make the opponent move).
Future<void> _opponentMovesEach(Game g, Player p, int n) async {
  final left = p.onBoard.toList();
  while (left.isNotEmpty) {
    final f = left.length == 1
        ? left.first
        : await g.chooseFighter(p, left, 'Move each of your fighters up to $n (choose one, or finish)', optional: true);
    if (f == null) break;
    left.remove(f);
    if (f.onBoard) await g.moveFighter(f, n, chooser: p);
  }
}

// ================================================================================= She-Hulk

/// JUST THROW SOMETHING: at the start of your turn, you may discard a card to deal damage equal
/// to its BOOST value to a fighter in your zone.
class SheHulk extends HeroScript {
  Fighter get hulk => me.heroFighter;

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || !hulk.onBoard || me.hand.isEmpty) return;
    final targets = g.fightersInZoneOf(hulk).where((f) => f != hulk).toList();
    if (targets.isEmpty) return;
    final c = await g.chooseCard(me, me.hand.where((c) => (c.def.boost ?? 0) > 0), 'Just Throw Something: discard a card to throw it?',
        optional: true, skipLabel: "Don't throw", intent: Intent.loseOwn);
    if (c == null) return;
    final f = await g.chooseFighter(me, targets, 'Throw ${c.title}: deal ${g.boostValueOf(c)} damage to a fighter in your zone', intent: Intent.harm);
    final dmg = g.boostValueOf(c);
    await g.discardCard(c, reason: ' (Just Throw Something)');
    if (f != null) await g.damage(f, dmg, info: DamageInfo(by: me, source: hulk));
  }

  @override
  Map<String, CardScript> get cards => {
    'JENNIFER WALTERS, ESQ.': CardScript(effect: (x) async {
      await x.place(hulk, x.board.startSpaces, text: 'Place She-Hulk in a starting space');
      await x.draw(1);
      x.gainActions(1);
    }),
    'LEAP TOWARD': CardScript(effect: (x) async {
      await x.move(hulk, 4, throughOpp: true);
      if (x.enemiesAdjacentTo(hulk).isNotEmpty) x.gainActions(1);
    }),
    'NERVE CLUSTER STRIKE': CardScript(immediately: (x) async {
      final o = x.oppFighter;
      if (x.adjacent(hulk, o)) x.game.addTurnMod(TurnMod(name: 'Nerve Cluster Strike', cannotLeaveFn: (g, f) => f == o));
    }),
    'LADY JUSTICE': CardScript(during: (x) async {
      final c = await x.game.discardTopOfDeck(x.opp);
      if (c != null) x.addValue(2 * x.game.boostValueOf(c), '2 x BOOST of ${c.title}');
    }),
    'OMEGA-LEVEL THREAT': CardScript(after: (x) async {
      if (x.attacking && x.damageDealt >= 2) await x.discard(x.opp, 2, random: true);
    }),
    'SENSATIONAL': CardScript(after: (x) async {
      if (!x.won || x.me.discard.isEmpty) return;
      final c = await x.game.chooseCard(x.me, x.me.discard, 'Sensational: shuffle a card from your discard pile into your deck?',
          optional: true, intent: Intent.help, source: x.card);
      if (c != null) await x.game.toDeck(c, shuffle: true);
    }),
    'CEASE AND DESIST': CardScript(
      immediately: (x) async => x.cancelOpponent(),
      during: (x) async {
        if (x.attacking) x.setValue(4);
      },
    ),
    'DOUBLE JEOPARDY': CardScript(effect: (x) async {
      await x.draw(2);
      await x.heal(hulk, 2);
    }),
    'GREEN ENERGY': CardScript(after: (x) async {
      if (!x.won || !hulk.onBoard) return;
      for (final f in x.adjacentTo(hulk).toList()) {
        await x.damage(f, 1);
      }
    }),
    'LEGALESE': CardScript(after: (x) async {
      final chooser = x.won ? x.opp : x.me;
      final i = await x.option(['Both draw a card', 'Both discard a card'], 'Legalese: choose', who: chooser, intent: Intent.none);
      if (i == 0) {
        await x.draw(1);
        await x.draw(1, x.opp);
      } else {
        await x.discard(x.me, 1, chooser: x.me);
        await x.discard(x.opp, 1, chooser: x.opp);
      }
    }),
    'THE DEFENSE RESTS': CardScript(after: (x) async {
      if (x.defending && x.damageDealt > 0) await x.draw(x.damageDealt);
    }),
    'THE SAVAGE SHE-HULK': CardScript(during: (x) async {
      if (x.game.active != x.me || x.game.actions <= 0) return;
      if (await x.yesNo('The Savage She-Hulk: spend an extra action to make this card 9?', intent: Intent.help)) {
        x.game.actions--;
        await x.game.emit(ActionsChanged(x.me, x.game.actions, -1));
        x.setValue(9);
      }
    }),
  };
}

// =============================================================================== Spider-Man

/// SPIDEY-SENSE: when an opponent attacks Spider-Man, before you play a defense card, they must
/// tell you the printed value of their card.
class SpiderMan extends HeroScript {
  Fighter get spidey => me.heroFighter;

  @override
  Future<void> beforeDefense(Game g, Combat c) async {
    if (c.defender.fighter != spidey || c.attacker.card == null) return;
    final v = c.attacker.card!.def.value;
    await g.emit(StatusChanged(me, 'Spidey-Sense: the attack card\'s printed value is ${v ?? 0}.'));
  }

  int _oppValue(Fx x) => x.oppCard == null ? 0 : x.game.valueOf(x.oppSide).total;

  @override
  Map<String, CardScript> get cards => {
    'FRIENDLY NEIGHBORHOOD SPIDER-MAN': CardScript(effect: (x) async {
      await x.heal(spidey, 3);
      if (spidey.onBoard) await x.place(spidey, x.zoneSpaces(spidey), text: 'Place Spider-Man in any space in his zone');
    }),
    'SPIDER-SENSE TINGLING!': CardScript(after: (x) async {
      if (_oppValue(x) >= 4) await x.draw(2);
    }),
    'THWIP!': CardScript(after: (x) async {
      if (x.won && spidey.onBoard) await x.place(spidey, x.zoneSpaces(spidey), text: 'Place Spider-Man in any space in his zone');
    }),
    'DISARMING SHOT': CardScript(after: (x) async {
      if (x.attacking && x.damageDealt > 0) await x.draw(x.damageDealt);
    }),
    'SNARK': CardScript(after: (x) async {
      if (x.adjacent(x.fighter, x.oppFighter)) await x.draw(1);
    }),
    'WALL CRAWLER': CardScript(after: (x) async {
      if (spidey.onBoard) await x.place(spidey, x.zoneSpaces(spidey), text: 'Place Spider-Man in any space in his zone');
    }),
    'WITH GREAT POWER': CardScript(effect: (x) async {
      x.game.addTurnMod(TurnMod(
        name: 'With Great Power',
        valueOpsFn: (g, s) => s.player == me && s.isAttacker && s.fighter == spidey ? const [ValueOp.add(1, 'With Great Power')] : const [],
      ));
      await x.draw(1);
      x.gainActions(1);
    }),
    'COUNTER-ATTACK': CardScript(after: (x) async {
      if (_oppValue(x) >= 4 && x.oppFighter.onBoard) await x.damage(x.oppFighter, 2);
    }),
    'RIGHT IN THE FACE!': CardScript(immediately: (x) async {
      final o = x.opp;
      x.game.addTurnMod(_NoDraw(o));
    }),
    'SWINGING KICK': CardScript(after: (x) async {
      if (x.attacking && x.damageDealt > 0 && x.oppFighter.onBoard) await x.move(x.oppFighter, x.damageDealt);
    }),
    'WEB SHOOTERS': CardScript(during: (x) async {
      final c = x.combat;
      x.game.addTurnMod(TurnMod(
        name: 'Web Shooters',
        modifyDamageFn: (g, t, amount, info) => info.combat && t == spidey && g.combat == c ? math.min(amount, 2) : amount,
      ));
    }),
  };
}

class _NoDraw extends TurnMod {
  _NoDraw(this.who) : super(name: "Right in the Face! (can't draw)");
  final Player who;
  @override
  bool canDraw(Game g, Player p) => p != who;
}

// ============================================================================ Black Panther

/// VIBRANIUM SUIT: whenever you BOOST, draw 1 card. Cards stored in the suit (face up, revealed
/// from opponents' decks) can only be used to BOOST; once used they go to their owner's discard
/// pile. Cards with no BOOST stay in the suit.
class BlackPanther extends HeroScript {
  Fighter get panther => me.heroFighter;
  Fighter? get shuri => me.fighters.where((f) => f.isSidekick).firstOrNull;

  @override
  List<String> status() => [if (stored.isNotEmpty) 'Vibranium Suit: ${stored.length}'];

  @override
  Future<void> afterBoost() async {
    await game.say('Vibranium Suit: Black Panther draws 1 card.');
    await game.draw(me, 1);
  }

  /// Reveals the top [n] cards of [p]'s deck and stores them in the suit.
  Future<void> storeTop(Player p, int n) async {
    final cards = p.deck.take(n).toList();
    if (cards.isEmpty) return;
    p.deck.removeRange(0, cards.length);
    stored.addAll(cards);
    await game.emit(Revealed(p, cards, ' and Black Panther stores ${cards.length == 1 ? 'it' : 'them'} in his Vibranium Suit'));
  }

  @override
  Map<String, CardScript> get cards => {
    'CAT-LIKE REFLEXES': CardScript(after: (x) async {
      if (x.won) await moveCombatant(x, 3);
    }),
    'EVADE': drawAfter(1),
    'NANOTRIAGE PROCESSOR': CardScript(after: (x) async {
      final s = shuri;
      if (s == null || !s.alive) return;
      await x.heal(s, 1);
      if (panther.onBoard && s.onBoard && x.sameZone(panther, s)) await x.heal(panther, 1);
    }),
    'ANCESTRAL INSIGHT': CardScript(after: (x) async {
      if (x.won) await storeTop(x.opp, 1);
    }),
    'MICROWEAVE MESH': boostable,
    'TACTICAL REMOTE SCANNING': CardScript(effect: (x) => storeTop(x.opp, 2)),
    'ANALYZE AND ADJUST': CardScript(after: (x) => storeTop(x.opp, 1)),
    'ANTI-METAL CLAWS': CardScript(during: (x) async {
      final c = x.oppCard;
      if (c != null && !c.virtual) x.addValue(x.game.boostValueOf(c), 'BOOST of ${c.title}');
      await x.boostThis();
    }),
    'STALKING PANTHER': CardScript(effect: (x) async {
      await moveEach(x, x.myFighters, 3, through: true);
      x.gainActions(1);
    }),
    'VIBRANIUM SHOCKWAVE': boostable,
    'WAKANDA FOREVER!': CardScript(during: (x) async {
      for (var i = 0; i < 2; i++) {
        if (!await x.boostThis(text: 'Wakanda Forever! BOOST (${i + 1} of up to 2)?')) break;
      }
    }),
  };
}

// =========================================================================== Winter Soldier

/// BRAINWASHED: effects on Winter Soldier's cards cannot be canceled. Effects marked RED ROOM are
/// ignored for the rest of the turn after A Boy Named Bucky.
class WinterSoldier extends HeroScript {
  Fighter get bucky => me.heroFighter;
  bool get redRoom => game.turn.flags['boyNamedBucky'] != me;

  @override
  bool uncancelable(Game g, Side s) => s.player == me;

  @override
  Map<String, CardScript> get cards => {
    'A BOY NAMED BUCKY': CardScript(effect: (x) async {
      x.game.turn.flags['boyNamedBucky'] = x.me;
      x.gainActions(1);
    }),
    'PROGRAMMED TO KILL': CardScript(after: (x) async {
      if (redRoom && x.won && bucky.alive) await x.damage(bucky, 2);
    }),
    'COMPLETE THE MISSION': CardScript(
      during: (x) async => x.boostThis(),
      after: (x) async {
        if (x.defending && x.damageDealt > 0 && x.oppFighter.onBoard) await x.damage(x.oppFighter, x.damageDealt);
      },
    ),
    'REFLEX MEMORIES': CardScript(after: (x) async {
      if (!redRoom) return;
      await x.discard(x.me, 2, random: true);
      await x.draw(2);
    }),
    'REPROGRAM': CardScript(after: (x) async {
      final n = math.min(3, x.me.discard.length);
      if (n == 0) return;
      final cards = await x.game.chooseCards(x.me, x.me.discard, n, n, 'Reprogram: choose $n cards to shuffle into your deck', intent: Intent.help);
      for (final c in cards) {
        await x.game.toDeck(c, shuffle: true);
      }
    }),
    'BIONIC ARM': CardScript(
      during: (x) async {
        if (x.adjacent(bucky, x.oppFighter)) x.setValue(6);
      },
      after: (x) async {
        if (redRoom) await _opponentMovesEach(x.game, x.opp, 5);
      },
    ),
    'BORN IN THE BARRACKS': CardScript(after: (x) async {
      if (x.won) await x.heal(bucky, 2);
    }),
    'MANIPULATION': CardScript(effect: (x) async {
      final n = 5 - x.me.hand.length;
      if (n > 0) await x.draw(n);
      if (!redRoom) return;
      for (final o in x.opponents.toList()) {
        final m = 5 - o.hand.length;
        if (m > 0 && await x.yesNo('Manipulation: draw up to 5 cards?', who: o)) await x.draw(m, o);
      }
    }),
    'MARKSMAN': CardScript(during: (x) async {
      if (!bucky.onBoard || !x.oppFighter.onBoard) return;
      final between = x.board.distance(bucky.space!, x.oppFighter.space!) - 1;
      if (between > 0) x.addValue(between, '$between space${between == 1 ? '' : 's'} between');
    }),
    'WITHOUT REMORSE': CardScript(after: (x) async {
      if (redRoom && await x.yesNo('Without Remorse: draw 1 card?', who: x.opp)) await x.draw(1, x.opp);
    }),
  };
}
