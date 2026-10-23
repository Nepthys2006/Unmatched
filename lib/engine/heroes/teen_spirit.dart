/// Marvel Teen Spirit: Cloak & Dagger, Ms. Marvel (Squirrel Girl is in squirrel_girl.dart).
library;

import 'dart:math' as math;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ============================================================================ Cloak & Dagger

/// Two heroes (8 health each); you lose when both are defeated.
/// UMBRA: after you attack, if Cloak dealt at least 2 combat damage, your opponent discards 1.
/// REFRACTION: after you attack, if Dagger dealt at least 2 combat damage, gain 1 action.
class CloakDagger extends HeroScript {
  Fighter get cloak => me.fighters.firstWhere((f) => f.id == 'cloak');
  Fighter get dagger => me.fighters.firstWhere((f) => f.id == 'dagger');
  Combat? _lastAttack;

  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (c.attacker.player == me) _lastAttack = c;
  }

  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    final c = _lastAttack;
    _lastAttack = null;
    if (p != me || kind != ActionKind.attack || c == null || c.combatDamage < 2) return;
    if (c.attacker.fighter == cloak) {
      await g.say('Umbra: Cloak dealt ${c.combatDamage} combat damage.');
      await g.discardFromHand(c.defender.player, 1, by: me);
    } else if (c.attacker.fighter == dagger) {
      await g.say('Refraction: Dagger dealt ${c.combatDamage} combat damage, gain 1 action.');
      g.gainActions(me, 1);
    }
  }

  @override
  Map<String, CardScript> get cards => {
    'CHANNEL THE DARK': CardScript(after: (x) async {
      final o = x.oppFighter;
      if (x.fighter != cloak || !dagger.onBoard || !o.onBoard) return;
      final room = x.board.neighbours(dagger.space!).where(x.game.isEmpty);
      if (room.isEmpty) return; // IF/THEN: no room next to Dagger, no action either
      if (await x.place(o, room, text: 'Channel the Dark: place ${o.name} next to Dagger')) x.gainActions(1);
    }),
    'PERFECT BALANCE': CardScript(during: (x) async {
      final o = x.oppFighter;
      if (x.adjacent(cloak, o) && x.adjacent(dagger, o)) x.setValue(6);
    }),
    'TRAVERSE THE DARKFORCE': CardScript(after: (x) => moveEach(x, x.myFighters, 2)),
    'CHOSEN FATE': CardScript(effect: (x) async {
      final mine = x.myFighters.toList();
      final f = await x.chooseFighter(mine, 'Chosen Fate: choose one of your fighters to take up to 4 damage', intent: Intent.loseOwn);
      if (f != null) {
        final n = await x.game.chooseNumber(x.me, 0, 4, 'Chosen Fate: how much damage to ${f.name}? The other recovers that much.');
        if (n > 0) {
          await x.damage(f, n);
          final other = f == cloak ? dagger : cloak;
          if (other.alive && !other.offBoard) await x.heal(other, n);
        }
      }
      await x.draw(2);
    }),
    'DARKFORCE DIMENSION': CardScript(after: (x) async {
      if (x.oppFighter.onBoard) await x.place(x.oppFighter, x.allSpaces, text: 'Darkforce Dimension: place ${x.oppFighter.name} in any space');
      await x.discard(x.opp, 1);
    }),
    'INTO THE VOID': boostable,
    'THE LIVING LIGHT': CardScript(after: (x) async {
      if (x.fighter == cloak && x.defending && dagger.alive) await x.heal(dagger, 2);
      if (x.fighter == dagger && x.attacking && cloak.alive) await x.heal(cloak, 2);
    }),
    'INTO DARKNESS': CardScript(after: (x) => moveCombatant(x, 3)),
    'LIGHTFORCE BARRAGE': CardScript(
      uncancelable: true,
      after: (x) async {
        if (x.won && x.damageDealt > 0 && x.fighter.alive) await x.damage(x.fighter, x.damageDealt);
      },
    ),
    'LIVING SHADOW': CardScript(during: (x) async {
      if (x.fighter != dagger || !cloak.onBoard) return;
      if (await x.game.swap(dagger, cloak)) {
        x.mySide.fighter = cloak;
        x.setValue(4);
      }
    }),
  };
}

// ================================================================================ Ms. Marvel

/// STRETCHY: at the start of your turn, you may move Ms. Marvel 1 space. She can attack from up
/// to 2 spaces away (ignoring zones, even over other fighters).
class MsMarvel extends HeroScript {
  Fighter get kamala => me.heroFighter;

  @override
  bool canAlsoTarget(Game g, Fighter attacker, Fighter target) =>
      attacker == kamala && target.isEnemyOf(me) && attacker.onBoard && target.onBoard &&
      g.board.distance(attacker.space!, target.space!) <= 2;

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active == me && kamala.onBoard) await g.moveFighter(kamala, 1, chooser: me, text: 'Stretchy: you may move Ms. Marvel 1 space');
  }

  bool apart(Fx x) => !x.oppFighter.onBoard || !kamala.onBoard || !x.board.sharesZone(kamala.space!, x.oppFighter.space!);

  @override
  Map<String, CardScript> get cards => {
    'FANGIRL': CardScript(during: (x) async => x.setValue(x.me.hand.length, 'Cards in hand')),
    'SLINGSHOT': CardScript(after: (x) async {
      if (kamala.onBoard) await x.place(kamala, x.zoneSpaces(kamala), text: 'Place Ms. Marvel in any space in her zone');
    }),
    'BIG WIND UP': CardScript(during: (x) async {
      if (apart(x)) await x.boostThis();
    }),
    'EASY PEASY': CardScript(after: (x) async {
      await x.draw(1);
      if (x.me.hand.length < 4 || !kamala.onBoard) return;
      final f = await x.chooseFighter(x.adjacentTo(kamala).toList(), 'Easy Peasy: deal 1 damage to an adjacent fighter', intent: Intent.harm);
      if (f != null) await x.damage(f, 1);
    }),
    'EMBIGGEN': CardScript(during: (x) async {
      final o = x.oppFighter;
      if (kamala.onBoard && o.onBoard && x.board.zoneCount(kamala.space!) > x.board.zoneCount(o.space!)) x.setValue(6);
    }),
    'FRIENDS AND FAMILY': CardScript(effect: (x) async {
      await x.draw(2);
      if (x.game.actions <= 0 || x.me.hand.length >= 7) return;
      if (!await x.yesNo('Friends and Family: spend an extra action to draw up to 7 cards?')) return;
      x.game.actions--;
      await x.game.emit(ActionsChanged(x.me, x.game.actions, -1));
      await x.draw(math.max(0, 7 - x.me.hand.length));
    }),
    'GYRO AND FRIES': CardScript(effect: (x) async {
      await x.heal(kamala, 2);
      if (x.me.hand.length >= 4) x.gainActions(1);
    }),
    "I'M NOT TOUCHING YOU": CardScript(after: (x) async {
      if (apart(x)) await x.draw(2);
    }),
    'SHRINK! SHRINK! SHRINK!': CardScript(after: (x) async {
      Future<void> discard() => x.discard(x.opp, 1);
      Future<void> push() async {
        if (x.oppFighter.onBoard) await x.move(x.oppFighter, 3);
      }

      if (apart(x)) {
        await discard();
        await push();
        return;
      }
      final i = await x.option(['Your opponent discards 1 card', 'Move the opposing fighter up to 3 spaces'], 'Shrink! Shrink! Shrink!: choose one');
      await (i == 0 ? discard() : push());
    }),
  };
}
