/// Robin Hood vs Bigfoot, and Battle of Legends, Volume Two: Achilles, Yennenga, Sun Wukong.
library;

import '../combat.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ================================================================================== Bigfoot

/// At the end of your turn, if there are no opposing fighters in Bigfoot's zone, you may draw 1.
class Bigfoot extends HeroScript {
  @override
  Future<void> endOfTurn(Game g, Player active) async {
    final b = me.heroFighter;
    if (active != me || !b.onBoard) return;
    if (g.fightersInZoneOf(b).any((f) => f.isEnemyOf(me))) return;
    if (await g.yesNo(me, 'Loner by nature: draw 1 card?')) await g.draw(me, 1);
  }

  @override
  Map<String, CardScript> get cards => {
        'LARGER THAN LIFE': vanilla,
        'CRASH THROUGH THE TREES': CardScript(effect: (x) => x.move(x.hero, 5, throughOpp: true)),
        'HOAX': moveAfter(5, through: true),
        'JACKALOPE HORNS': CardScript(effect: (x) async {
          final j = x.fighter;
          await x.move(j, 5, throughOpp: true);
          final f = await x.chooseFighter(x.adjacentTo(j), 'Deal 2 damage to a fighter adjacent to the Jackalope', intent: Intent.harm);
          if (f != null) await x.damage(f, 2);
        }),
        'DISENGAGE': CardScript(after: (x) async {
          final f = x.fighter;
          if (f.onBoard) await x.place(f, x.zoneSpaces(f).where(x.game.isEmpty), text: "Place ${f.name} in an empty space in its zone");
        }),
      };
}

// =============================================================================== Robin Hood

/// After you attack, you may move your attacking fighter up to 2 spaces.
class RobinHood extends HeroScript {
  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    if (p != me || kind != ActionKind.attack || fighter == null || !fighter.onBoard) return;
    await g.moveFighter(fighter, 2, chooser: me, text: 'Hit and run: move ${fighter.name} up to 2 spaces');
  }

  @override
  Map<String, CardScript> get cards => {
        'A HUNTER\'S EYE': vanilla,
        'SNARK': CardScript(after: (x) async {
          if (x.adjacent(x.fighter, x.oppFighter)) await x.draw(1);
        }),
        'HIGHWAY ROBBERY': CardScript(immediately: (x) async {
          x.cancelOpponent();
          x.ignoreOpponentValue();
        }),
        'DISARMING SHOT': CardScript(after: (x) => x.draw(x.damageDealt)),
        'PIERCING SHOT': drawAfter(2),
        'STEAL FROM THE RICH': CardScript(effect: (x) async {
          await x.draw(1);
          final pay = x.opp.hand.isNotEmpty &&
              await x.yesNo('Steal From the Rich: discard 1 card to stop ${x.me.name} drawing another?', who: x.opp, intent: Intent.harm);
          if (pay) {
            await x.discard(x.opp, 1);
          } else {
            await x.draw(1);
          }
        }),
        'DEFENDERS OF SHERWOOD': CardScript(after: (x) async {
          await x.draw(1);
          if (x.hero.onBoard) {
            await x.game.summon(x.me, 'outlaws', x.zoneSpaces(x.hero), text: "Return an Outlaw to Robin Hood's zone");
          }
        }),
      };
}

// ================================================================================= Achilles

/// When Patroclus is defeated, discard 2 random cards. While he is defeated: +2 to Achilles'
/// attacks, and if Achilles wins a combat, draw 1 card.
class Achilles extends HeroScript {
  Fighter? get patroclus => me.fighters.where((f) => f.isSidekick).firstOrNull;
  bool get patroclusDown => patroclus?.defeated ?? false;

  @override
  Future<void> onDefeated(Game g, Fighter f) async {
    if (f == patroclus) await g.discardFromHand(me, 2, random: true);
  }

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player == me && s.isAttacker && s.fighter.isHero && patroclusDown) {
      yield const ValueOp.add(2, 'Patroclus is defeated');
    }
  }

  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (!patroclusDown || !c.involves(me.heroFighter)) return;
    if (c.sideOfFighter(me.heroFighter).player == me && c.won(me)) await g.draw(me, 1);
  }

  @override
  List<String> status() => patroclusDown ? const ['Patroclus fell: +2'] : const [];

  @override
  Map<String, CardScript> get cards => {
        "ACHILLES' HEEL": CardScript(after: (x) async {
          if (x.lost) x.game.gainActions(x.opp, 1);
        }),
        'BROTHERS IN ARMS': CardScript(after: (x) async {
          if (!patroclusDown) x.gainActions(1);
        }),
        "UNDER ACHILLES' HELM": CardScript(immediately: (x) async {
          final p = patroclus;
          if (p == null || !p.onBoard || !x.hero.onBoard) return;
          if (!await x.yesNo('Swap Achilles and Patroclus? Patroclus becomes the defender.', intent: Intent.none)) return;
          if (await x.game.swap(x.hero, p)) x.mySide.fighter = p;
        }),
        'TEST FOR WEAKNESS': CardScript(after: (x) => x.game.bonusAttack(x, 'Relentless Assault', 3)),
        'BATTLE FRENZY': CardScript(after: (x) async {
          for (final f in [x.fighter, x.oppFighter]) {
            await x.damage(f, 2);
          }
        }),
        'SPEAR THROW': CardScript(effect: (x) async {
          final f = await x.chooseFighter(enemiesInZone(x, x.hero), "Deal 2 damage to an opposing fighter in Achilles' zone",
              intent: Intent.harm);
          if (f != null) await x.damage(f, 2);
        }),
        'THE DAY OF YOUR DOOM': CardScript(during: (x) async {
          final p = patroclus;
          if (p == null || !p.alive) return;
          if (await x.yesNo('Deal 2 damage to Patroclus to make this attack 5?', intent: p.hp > 2 ? Intent.help : Intent.harm)) {
            await x.damage(p, 2);
            x.setValue(5);
          }
        }),
        'BATTLE HARDENED': CardScript(after: (x) async {
          final c = await x.game.chooseCard(x.me, x.me.discard, 'Return a card from your discard pile to your hand',
              intent: Intent.gainOwn);
          if (c != null) await x.game.toHand(c, reason: ' (Battle Hardened)');
        }),
        'BLESSED BY HERMES': CardScript(after: (x) => moveEach(x, x.myFighters, 3, through: true)),
      };
}

// ================================================================================= Yennenga

/// If Yennenga would take damage, you may assign any of it to Archers in her zone (no more than
/// each Archer's remaining health).
class Yennenga extends HeroScript {
  Iterable<Fighter> get archers => me.fighters.where((f) => f.isSidekick);

  @override
  Future<Map<Fighter, int>> splitDamage(Fighter f, int n, DamageInfo info) async {
    if (f != me.heroFighter || !f.onBoard) return {f: n};
    final out = <Fighter, int>{};
    var left = n;
    for (final a in archers.where((a) => a.onBoard && game.board.sharesZone(a.space!, f.space!))) {
      if (left <= 0) break;
      final cap = a.hp < left ? a.hp : left;
      final k = await game.chooseNumber(me, 0, cap, 'Assign how much of $left damage to ${a.name} (${a.hp} health)?');
      if (k > 0) {
        out[a] = k;
        left -= k;
      }
    }
    out[f] = left;
    return out;
  }

  Future<bool> returnArcher(Fx x, Iterable<int> spaces, String text) =>
      x.game.summon(x.me, 'archers', spaces, text: text);

  @override
  Map<String, CardScript> get cards => {
        'SURPRISE VOLLEY': CardScript(immediately: (x) async {
          final down = archers.where((a) => a.defeated);
          var returned = false;
          if (down.isNotEmpty && x.oppFighter.onBoard &&
              await x.yesNo("Return a defeated Archer to the opposing fighter's zone as the attacker?", intent: Intent.none)) {
            final a = down.first;
            final s = await x.chooseSpace(x.zoneSpaces(x.oppFighter).where(x.game.isEmpty), 'Place the Archer',
                intent: Intent.moveOwn, subject: a);
            if (s != null && await x.game.revive(a, s)) {
              x.mySide.fighter = a;
              returned = true;
            }
          }
          if (!returned) x.gainActions(1);
        }),
        'RAIN OF ARROWS': CardScript(after: (x) => x.game.bonusAttack(x, 'Volley', 3)),
        'PIN THE PREY': CardScript(after: (x) async {
          await pushOpponent(x, 4);
          await x.discard(x.opp, 1);
        }),
        'DIVIDE AND CONQUER': valueIf((x) => !x.hero.onBoard || !x.sameZone(x.fighter, x.hero), 4),
        'POINT BLANK': CardScript(after: (x) async {
          if (x.adjacent(x.oppFighter, x.hero)) await x.damage(x.oppFighter, 2);
        }),
        'JAWS OF THE BEAST': CardScript(during: (x) async {
          if (x.oppFighter.onBoard) x.addValue(x.board.zoneCount(x.oppFighter.space!), 'Zones the opposing fighter is in');
        }),
        'STALLION CHARGE': CardScript(after: (x) async {
          final path = await x.move(x.hero, 5, throughOpp: true);
          for (final f in x.game.movedThrough(path, x.me)) {
            await x.damage(f, 1);
          }
        }),
        'SHIELD FORMATION': CardScript(immediately: (x) async {
          final pay = x.opp.hand.isNotEmpty &&
              await x.yesNo('Shield Formation: discard a card to stop an Archer returning?', who: x.opp, intent: Intent.harm);
          if (pay) {
            await x.discard(x.opp, 1);
          } else if (x.hero.onBoard) {
            await returnArcher(x, x.zoneSpaces(x.hero), "Return an Archer to Yennenga's zone");
          }
        }),
        'ONE WITH THE LAND': CardScript(effect: (x) async {
          await moveEach(x, x.myFighters, 2);
          for (final f in x.myFighters.toList()) {
            await x.heal(f, 1);
          }
          await x.draw(1);
        }),
        'MASTER OF THE HUNT': CardScript(effect: (x) async => x.gainActions(2)),
      };
}

// =============================================================================== Sun Wukong

const _forms = ['OX FORM', 'TORTOISE FORM', 'PHOENIX FORM'];

/// At the start of your turn, you may take 1 damage to summon a Clone in an empty space adjacent
/// to Sun Wukong. No Clones start on the board. (Clones may play all of his cards.)
class SunWukong extends HeroScript {
  @override
  bool startsInReserve(Fighter f) => true;

  @override
  bool fighterMayUse(Card c, Fighter f) => true;

  Iterable<Fighter> get clones => me.fighters.where((f) => f.isSidekick);

  Future<void> summonClone(Iterable<int> spaces) =>
      game.summon(me, 'clones', spaces, moveIfNone: true, text: 'Summon a Clone');

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    final sw = me.heroFighter;
    if (active != me || !sw.onBoard || sw.hp <= 1) return;
    final spaces = g.board.neighbours(sw.space!).where(g.isEmpty);
    if (spaces.isEmpty) return;
    if (!await g.yesNo(me, 'Take 1 damage to summon a Clone next to Sun Wukong?')) return;
    await g.damage(sw, 1, info: DamageInfo(by: me));
    if (sw.onBoard) await summonClone(g.board.neighbours(sw.space!));
  }

  @override
  Map<String, CardScript> get cards => {
        'INFINITE STRIKES': CardScript(
          during: (x) async {
            final n = friendsAdjacentTo(x, x.oppFighter, except: x.fighter);
            if (n > 0) x.addValue(n, 'Friendly fighters adjacent');
          },
          after: (x) async => x.gainActions(1),
        ),
        'RUYI JINGO BANG': CardScript(after: (x) async {
          if (x.oppCard != null) await x.game.bonusAttack(x, 'Tricked You', 4);
        }),
        'TAUNTING LAUGHTER': CardScript(immediately: (x) async {
          final pay = x.opp.hand.isNotEmpty &&
              await x.yesNo('Taunting Laughter: discard 1 card, or your card\'s value is ignored?', who: x.opp, intent: Intent.help);
          if (pay) {
            await x.discard(x.opp, 1);
          } else {
            x.ignoreOpponentValue();
          }
        }),
        'OX FORM': CardScript(
          uncancelable: true,
          during: (x) async {
            if (x.oppCard != null) await x.game.boostCard(x.oppSide, text: 'Ox Form: you may BOOST your card');
          },
        ),
        'TORTOISE FORM': CardScript(during: (x) async {
          await x.game.boostCard(x.oppSide, text: 'Tortoise Form: you may BOOST your attack');
        }),
        '72 TRANSFORMATIONS': CardScript(after: (x) async {
          final forms = x.me.discard.where((c) => _forms.contains(c.def.upperTitle));
          final c = await x.game.chooseCard(x.me, forms, 'Return a FORM card to your hand', intent: Intent.gainOwn);
          if (c != null) await x.game.toHand(c, reason: ' (72 Transformations)');
        }),
        'SLY MONKEY': CardScript(after: (x) async {
          final sw = x.hero;
          if (x.fighter != sw || !sw.onBoard) return;
          final from = sw.space!;
          final moved = await x.place(sw, x.zoneSpaces(sw).where((s) => s != from), text: 'Place Sun Wukong in a space in his zone');
          if (moved) await summonClone([from]);
        }),
        'GOLDEN CHAIN MAIL': CardScript(during: (x) async {
          if (x.defending) x.combat.flags['reflect'] = true;
        }),
        'FIERY EYES THAT SEE': CardScript(effect: (x) async {
          if (await x.game.lookAtHand(x.me, x.opp)) {
            final c = await x.game.chooseCard(x.me, x.opp.hand, "Put one of your opponent's cards on the bottom of their deck",
                intent: Intent.loseEnemy);
            if (c != null) await x.game.toDeck(c, bottom: true);
          }
          await x.draw(1);
          await x.draw(1, x.opp);
        }),
        'PHOENIX FORM': CardScript(effect: (x) => x.heal(x.hero, clones.where((c) => c.onBoard).length)),
      };
}
