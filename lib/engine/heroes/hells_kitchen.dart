/// Marvel Hell's Kitchen: Bullseye, Daredevil, Elektra.
library;

import '../combat.dart';
import '../defs.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ================================================================================= Bullseye

/// Bullseye can attack from up to 5 spaces away (ignoring zones).
class Bullseye extends HeroScript {
  Fighter get bullseye => me.heroFighter;
  bool wonThisTurn(Game g) => g.turn.flags['bullseyeWon'] == true;

  @override
  bool canAlsoTarget(Game g, Fighter attacker, Fighter target) =>
      attacker == bullseye && target.isEnemyOf(me) && attacker.onBoard && target.onBoard &&
      g.board.distance(attacker.space!, target.space!) <= 5;

  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (c.won(me)) g.turn.flags['bullseyeWon'] = true;
  }

  @override
  Map<String, CardScript> get cards => {
    "I'M BETTER AND I'LL PROVE IT": CardScript(during: (x) async {
      if (wonThisTurn(x.game)) x.setValue(6);
    }),
    'ARROGANT BUT EFFECTIVE': CardScript(after: (x) async {
      x.combat.flags['alsoWon'] = x.me;
      if (bullseye.onBoard) await x.move(bullseye, 2);
    }),
    "WORLD'S GREATEST ASSASSIN": CardScript(immediately: (x) async {
      if (wonThisTurn(x.game)) x.ignoreOpponentValue();
    }),
    'TACTICAL RETREAT': CardScript(after: (x) async {
      if (!bullseye.onBoard) return;
      final here = bullseye.space!;
      final spaces = x.allSpaces.where((s) => !x.board.sharesZone(s, here) && x.game.isEmpty(s));
      await x.place(bullseye, spaces, text: 'Place Bullseye in a space that shares no zones with his space');
    }),
    'FOR MY NEXT TRICK': CardScript(after: (x) async {
      if (bullseye.onBoard) await x.move(bullseye, 1);
      await x.draw(1);
      x.gainActions(1);
    }),
    'I NEVER MISS': CardScript(during: (x) async {
      if (!await x.boostThis()) await x.draw(1);
    }),
    'I PLANNED TO BE HERE': CardScript(during: (x) async {
      if (bullseye.onBoard && x.game.turn.startSpace[bullseye] == bullseye.space) x.setValue(5);
    }),
    'RICOCHET': CardScript(after: (x) async {
      final o = x.oppFighter;
      if (o.defeated || !o.onBoard) return;
      final f = await x.chooseFighter(x.inZoneOf(o).toList(), "Ricochet: deal 1 damage to a fighter in ${o.name}'s zone", intent: Intent.harm);
      if (f != null) await x.damage(f, 1);
    }),
    'MASTER STRATEGIST': CardScript(after: (x) async {
      if (!bullseye.onBoard || x.game.cannotLeave(bullseye)) return;
      // Exactly 4 spaces: only destinations whose path takes exactly 4 steps.
      final reach = x.game.reachable(bullseye, 4, throughOpp: true);
      final exact = reach.entries.where((e) => e.value.length == 5).map((e) => e.key).toList();
      if (exact.isEmpty) return;
      final s = await x.chooseSpace(exact, 'Master Strategist: move Bullseye exactly 4 spaces', intent: Intent.moveOwn, subject: bullseye);
      if (s != null) {
        final path = reach[s]!;
        bullseye.space = s;
        x.game.turn.leftSpace.add(bullseye);
        await x.game.emit(FighterMoved(bullseye, path));
      }
    }),
    'RIGHT BETWEEN THE EYES': CardScript(immediately: (x) async {
      if (wonThisTurn(x.game)) await x.discard(x.opp, 1);
    }),
    'STUDY THE TARGET': CardScript(effect: (x) async {
      final won = wonThisTurn(x.game);
      await x.draw(won ? 3 : 2);
      if (won) x.gainActions(1);
    }),
  };
}

// ================================================================================ Daredevil

/// DURING COMBAT: if you have 2 or fewer cards in your hand, you may BLIND BOOST your attack or
/// defense.
class Daredevil extends HeroScript {
  Fighter get dd => me.heroFighter;

  @override
  Future<void> duringCombat(Game g, Combat c) async {
    if (!c.involves(dd) || me.hand.length > 2 || me.deck.isEmpty) return;
    final s = c.sideOfFighter(dd);
    if (s.card == null) return;
    await g.boostCard(s, blind: true, text: 'Daredevil: BLIND BOOST (you have ${me.hand.length} card${me.hand.length == 1 ? '' : 's'} in hand)?');
  }

  @override
  Map<String, CardScript> get cards => {
    'TAKE A KNEE': CardScript(after: (x) async {
      final c = await x.game.discardTopOfDeck(x.me);
      if (c != null && dd.alive) await x.heal(dd, x.game.boostValueOf(c));
    }),
    'MAN WITHOUT FEAR': CardScript(during: (x) async => x.boostThis(blind: true, text: 'Man Without Fear: BLIND BOOST?')),
    'SON OF A BOXER': CardScript(after: (x) async {
      if (!x.lost || !dd.onBoard) return;
      final f = await x.chooseFighter(x.adjacentTo(dd).toList(), 'Son of a Boxer: deal 2 damage to a fighter next to Daredevil', intent: Intent.harm);
      if (f != null) await x.damage(f, 2);
    }),
    'BREATHER': CardScript(effect: (x) async {
      final opts = x.me.discard.where((c) => c.def.type != CardType.scheme).toList();
      final c = await x.game.chooseCard(x.me, opts, 'Breather: return an attack, defense or versatile card to your hand', intent: Intent.help, source: x.card);
      if (c != null) await x.game.toHand(c, reason: ' (Breather)');
    }),
    "DEVIL OF HELL'S KITCHEN": CardScript(
      during: (x) async {
        if (x.me.deck.isEmpty) x.setValue(8);
      },
      after: (x) async {
        final top4 = x.me.discard.reversed.take(4).toList();
        await x.game.toDeck(x.card!, shuffle: true);
        for (final c in top4) {
          await x.game.toDeck(c, shuffle: true);
        }
      },
    ),
    'GRAPPLING HOOK': CardScript(after: (x) async {
      if (dd.onBoard) await x.move(dd, 2);
    }),
    'THROUGH ADVERSITY': CardScript(effect: (x) async {
      final path = await x.move(dd, 4, throughOpp: true);
      for (final f in x.game.movedThrough(path, x.me)) {
        await x.damage(f, 1);
      }
    }),
  };
}

// ================================================================================== Elektra

/// The first time Elektra would be defeated, she and every Hand on the board are removed (she is
/// not defeated). At the start of your next turn she RESURRECTS: her health dial flips to 9, your
/// discard pile is shuffled into your deck, and she and those Hand return to the board, each in a
/// different zone. Effects with the RESURRECTED symbol only work after that.
class Elektra extends HeroScript {
  static const resurrectedHealth = 9;
  Fighter get elektra => me.heroFighter;
  Iterable<Fighter> get hand => me.fighters.where((f) => f.isSidekick);
  bool resurrected = false;
  bool _gone = false;
  final List<Fighter> _removedHand = [];

  @override
  List<String> status() => [if (resurrected) 'Resurrected' else if (_gone) 'Will resurrect next turn'];

  @override
  Future<bool> preventDefeat(Game g, Fighter f) async {
    if (f != elektra || resurrected || _gone) return false;
    _gone = true;
    f
      ..hp = 0
      ..offBoard = true
      ..space = null;
    _removedHand
      ..clear()
      ..addAll(hand.where((h) => h.onBoard));
    for (final h in _removedHand) {
      h
        ..offBoard = true
        ..space = null;
    }
    await g.emit(StatusChanged(me, 'Elektra falls... and vanishes with the Hand. She will rise again.'));
    return true;
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || !_gone || resurrected) return;
    resurrected = true;
    _gone = false;
    elektra
      ..maxHp = resurrectedHealth
      ..hp = resurrectedHealth;
    me.deck
      ..addAll(me.discard)
      ..shuffle(g.rng);
    me.discard.clear();
    await g.emit(Shuffled(me));
    await g.emit(StatusChanged(me, 'Elektra RESURRECTS with $resurrectedHealth health.'));
    // Each fighter in a different zone: a space sharing no zone with the ones used so far.
    final used = <String>{};
    for (final f in [elektra, ..._removedHand]) {
      var options = g.emptySpaces().where((s) => !g.board.zonesOf(s).any(used.contains)).toList();
      if (options.isEmpty) options = g.emptySpaces().toList();
      final s = await g.chooseSpace(me, options, 'Resurrection: place ${f.name} (each fighter in a different zone)', intent: Intent.moveOwn, subject: f);
      if (s == null) continue;
      f.offBoard = false;
      f.space = s;
      used.addAll(g.board.zonesOf(s));
      await g.emit(Returned(f));
    }
    _removedHand.clear();
  }

  @override
  Map<String, CardScript> get cards => {
    'MYSTIC ASSASSIN': CardScript(after: (x) async {
      if (!resurrected && elektra.alive && !elektra.offBoard) await x.damage(elektra, 3);
    }),
    'HANDS OF RED': CardScript(after: (x) async {
      final dead = hand.where((h) => h.defeated).toList();
      if (dead.isEmpty || !elektra.onBoard) return;
      final spaces = x.zoneSpaces(elektra).where(x.game.isEmpty).toList();
      final s = await x.chooseSpace(spaces, "Hands of Red: return a defeated Hand to Elektra's zone", intent: Intent.moveOwn, subject: dead.first);
      if (s != null) await x.game.revive(dead.first, s);
    }),
    'SNAKEROOT CLAN': CardScript(immediately: (x) async {
      if (x.fighter != elektra || !elektra.onBoard) return;
      final hands = hand.where((h) => h.onBoard).toList();
      final h = await x.chooseFighter(hands, 'Snakeroot Clan: swap Elektra with a Hand? That Hand becomes the defender', optional: true);
      if (h != null && await x.game.swap(elektra, h)) x.mySide.fighter = h;
    }),
    'CLOAKED IN SHADOW': CardScript(
      immediately: (x) async => x.cancelOpponent(),
      after: (x) async {
        if (resurrected && elektra.onBoard) await x.move(elektra, 3);
      },
    ),
    'INTERCEPT': CardScript(during: (x) async {
      if (!resurrected) return;
      final sai = x.me.hand.where((c) => c.def.upperTitle == 'SAI').firstOrNull;
      if (sai == null || !await x.yesNo('Intercept: reveal a SAI from your hand to make this card 5?')) return;
      await x.game.emit(Revealed(x.me, [sai], ' (Intercept)'));
      x.setValue(5);
    }),
    'MESMERIZE': CardScript(effect: (x) async {
      final looked = await x.game.lookAtHand(x.me, x.opp);
      x.gainActions(1);
      if (resurrected && looked) await x.discard(x.opp, 1, chooser: x.me);
    }),
    'SAI': vanilla,
    'WHIRLWIND': CardScript(after: (x) async {
      if (resurrected && x.fighter.onBoard) await damageAdjacentEnemies(x, x.fighter, 1);
    }),
    'NINJITSU': CardScript(after: (x) async {
      if (x.fighter.onBoard) await x.place(x.fighter, x.allSpaces, text: 'Place ${x.fighter.name} in any space');
    }),
    'THE FIST': CardScript(after: (x) async {
      final f = x.fighter;
      if (!f.alive || !await x.yesNo('The Fist: deal 1 damage to ${f.name} to return this card to your hand and gain 1 action?', intent: Intent.loseOwn)) return;
      await x.damage(f, 1);
      await x.game.toHand(x.card!, reason: ' (The Fist)');
      x.gainActions(1);
    }),
  };
}
