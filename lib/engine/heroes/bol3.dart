/// Battle of Legends, Volume Three: Loki, Blackbeard.
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ===================================================================================== Loki

bool isTrick(Card c) => c.def.upperTitle.startsWith('TRICK');

/// Mischief-Monger: after you play a TRICK, put it into your opponent's hand instead of your
/// discard pile. If an opponent discards a TRICK from their hand, return it to your hand or the
/// top of your deck. +1 move for each TRICK in your opponents' hands. Opponents may play your
/// TRICKs as their own; their "Not Loki." effects apply then, and the card goes to your discard.
class Loki extends HeroScript {
  Fighter get loki => me.heroFighter;

  int tricksIn(Player p) => p.hand.where((c) => c.owner == me && isTrick(c)).length;
  int get tricksOut => game.enemiesOf(me).fold(0, (n, p) => n + tricksIn(p));

  @override
  int moveValue(Game g, Fighter f, int v) => f == loki ? v + tricksOut : v;

  @override
  Future<bool> disposePlayed(Card c) async {
    if (!isTrick(c) || c.owner != me || c.playedBy != me) return false;
    final foes = game.enemiesOf(me).toList();
    if (foes.isEmpty) return false;
    final to = foes.length == 1
        ? foes.first
        : foes[await game.chooseOption(me, [for (final p in foes) p.name], 'Put ${c.title} into which opponent\'s hand?', intent: Intent.none)];
    to.hand.add(c);
    await game.emit(StatusChanged(me, '${c.title} goes into ${to.name}\'s hand.'));
    return true;
  }

  @override
  Future<void> onDiscardedFromHand(Game g, Card c, {required bool byOpponent, Player? holder}) async {
    if (c.owner != me || !isTrick(c) || holder == null || holder == me || !me.discard.remove(c)) return;
    if (await g.chooseOption(me, ['Return ${c.title} to your hand', 'Put it on top of your deck'], 'Mischief-Monger', intent: Intent.help) == 0) {
      me.hand.add(c);
      await g.emit(CardMoved(c, Zone.discard, Zone.hand, reason: ' (Mischief-Monger)'));
    } else {
      me.deck.insert(0, c);
      await g.emit(CardMoved(c, Zone.discard, Zone.deck, reveal: false));
    }
  }

  @override
  List<String> status() => ['TRICKS OUT $tricksOut'];

  /// A random card of [p]'s hand ("reveal a card in your opponent's hand").
  Card? blindPick(Player p) => p.hand.isEmpty ? null : p.hand[game.rng.nextInt(p.hand.length)];

  @override
  Map<String, CardScript> get cards => {
        "TRICK: BALDR'S DOWNFALL": CardScript(after: (x) async {
          if (x.me == me) {
            await x.draw(1);
          } else {
            await x.damage(x.me.heroFighter, 2);
          }
        }),
        "TRICK: FREYJA'S RESCUE": CardScript(
          during: (x) async {
            if (x.me != me || x.oppCard == null) return;
            final mine = x.game.valueOf(x.mySide).total, theirs = x.game.valueOf(x.oppSide).total;
            x.setValue(theirs, "Freyja's Rescue: swapped");
            x.game.addOp(x.oppSide, ValueOp.set(mine, "Freyja's Rescue: swapped"));
          },
          after: (x) async {
            if (x.me != me) await x.heal(loki, 3);
          },
        ),
        'SHAPESHIFTER': CardScript(during: (x) async {
          final n = x.opp.hand.length;
          if (await x.option(['+$n (one per card in your opponent\'s hand)', 'Gain 1 action'], 'Shapeshifter: choose one') == 0) {
            if (n > 0) x.addValue(n, "Cards in opponent's hand");
          } else {
            x.gainActions(1);
          }
        }),
        'RAGNAROK': CardScript(
          uncancelable: true,
          during: (x) async {
            final n = tricksIn(x.opp);
            if (n > 0) x.addValue(3 * n, "TRICKs in opponent's hand ($n)");
          },
        ),
        'GOD OF MISCHIEF': CardScript(immediately: (x) async {
          final oc = x.oppCard;
          if (oc == null) return;
          if (isTrick(oc)) {
            x.ignoreOpponentValue();
          } else {
            x.cancelOpponent();
          }
        }),
        'LAEVATEINN': CardScript(during: (x) async {
          final c = blindPick(x.opp);
          if (c == null) return;
          await x.game.emit(Revealed(x.opp, [c], ' (Lævateinn)'));
          x.addValue(c.def.boost ?? 0, '${c.title} (BOOST)');
          if (isTrick(c) && c.owner == me) {
            x.opp.hand.remove(c);
            me.hand.add(c);
            await x.game.emit(StatusChanged(me, 'Loki takes ${c.title} back.'));
          }
        }),
        'LOOKING FOR TROUBLE': CardScript(immediately: (x) async {
          final s = x.oppSide;
          final old = s.card;
          if (old == null || old.virtual) return;
          final g = x.game;
          final f = s.fighter;
          await g.replaceCard(s, null);
          final looked = await g.lookAtHand(x.me, x.opp);
          final opts = x.opp.hand.where((c) => s.isAttacker ? g.canAttackWith(c, f) : g.canDefendWith(c, f)).toList();
          if (opts.isEmpty) return;
          final pick = looked ? await g.chooseCard(x.me, opts, 'Choose a card for them to play', intent: Intent.forceEnemy) : opts.first;
          await g.replaceCard(s, pick);
        }),
        'MALICIOUS FLYTING': CardScript(after: (x) async {
          final oc = x.oppCard;
          await x.draw(oc != null && isTrick(oc) ? 2 : 1);
        }),
        "TRICK: SINDRI'S BET": CardScript(
          during: (x) async {
            if (x.me != me || x.oppCard == null) return;
            final pay = x.opp.hand.isNotEmpty &&
                await x.yesNo("Sindri's Bet: discard a card, or subtract 3 from your card's value?", who: x.opp, intent: Intent.help);
            if (pay) {
              await x.discard(x.opp, 1);
            } else {
              x.game.addOp(x.oppSide, const ValueOp.add(-3, "Sindri's Bet"));
            }
          },
          after: (x) async {
            if (x.me == me) return;
            final top = me.discard.lastOrNull;
            if (top != null) await x.game.toHand(top, reason: " (Sindri's Bet)");
          },
        ),
        "TRICK: SVADILFARI'S LURE": CardScript(effect: (x) async {
          if (x.me == me) {
            if (!loki.onBoard) return;
            final f = await x.chooseFighter(x.enemies, 'Place an opposing fighter adjacent to Loki', intent: Intent.moveEnemy);
            if (f != null) await x.place(f, x.board.neighbours(loki.space!));
          } else {
            final c = blindPick(x.me);
            if (c == null) return;
            await x.game.emit(Revealed(x.me, [c], " (Svaðilfari's Lure)"));
            await x.game.discardCard(c, byOpponent: true);
          }
        }),
        'UNDERHANDED': valueIf((x) => x.opp.hand.length > x.me.hand.length, 6),
      };
}

// =============================================================================== Blackbeard

/// Privateer Turned Pirate: 3 doubloons, 1 in the Treasury and 2 with Blackbeard. At the start of
/// your turn you may pay 1 to gain 1 action. When Blackbeard takes combat damage, pay 1. Gold
/// effects marked with doubloons happen unless an opponent pays that ransom: the doubloons come
/// from the Treasury to Blackbeard.
class Blackbeard extends HeroScript {
  int treasury = 1;
  int doubloons = 2;
  Fighter get bb => me.heroFighter;

  Future<void> pay(int n) async {
    final k = n < doubloons ? n : doubloons;
    if (k <= 0) return;
    doubloons -= k;
    treasury += k;
    await game.emit(StatusChanged(me, 'Blackbeard pays $k doubloon${k == 1 ? '' : 's'} to the Treasury ($doubloons left).'));
  }

  /// Returns true if the effect happens (nobody paid the ransom).
  Future<bool> ransom(Fx x, int cost, String what) async {
    if (treasury < cost) return true;
    for (final o in x.opponents.toList()) {
      if (await x.yesNo('Pay $cost doubloon${cost == 1 ? '' : 's'} from the Treasury to stop: $what?', who: o, intent: Intent.help)) {
        treasury -= cost;
        doubloons += cost;
        await x.game.emit(StatusChanged(o, '${o.name} pays the ransom; Blackbeard collects $cost doubloon${cost == 1 ? '' : 's'}.'));
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active == me && doubloons > 0 && await g.yesNo(me, 'Pay 1 doubloon to gain 1 action?', intent: doubloons > 1 ? Intent.help : Intent.none)) {
      await pay(1);
      g.gainActions(me, 1);
    }
  }

  @override
  Future<void> onDamaged(Game g, Fighter f, int amount, DamageInfo info) async {
    if (f == bb && info.combat && amount > 0) await pay(1);
  }

  @override
  List<String> status() => ['DOUBLOONS $doubloons', 'TREASURY $treasury'];

  Future<void> summonSeaDog(Fx x, Iterable<int> spaces) =>
      x.game.summon(x.me, 'seadog', spaces, moveIfNone: true, text: 'Summon a Sea Dog');

  @override
  Map<String, CardScript> get cards => {
        'LIGHT THE FUSE': CardScript(after: (x) async {
          final f = x.fighter;
          await x.move(f, 2);
          for (final o in x.adjacentTo(f).toList()) {
            await x.damage(o, 1);
          }
        }),
        'PLUNDER': CardScript(effect: (x) async {
          await moveEach(x, x.myFighters, 3, through: true);
          if (treasury > 0) {
            treasury--;
            doubloons++;
            await x.game.emit(StatusChanged(me, 'Blackbeard steals a doubloon from the Treasury.'));
          }
        }),
        'A BRACE OF PRIMED PISTOLS': CardScript(after: (x) async {
          final targets = enemiesInZone(x, bb).toList();
          if (targets.isEmpty || !await ransom(x, 2, "3 damage to a fighter in Blackbeard's zone")) return;
          final f = await x.chooseFighter(targets, "Deal 3 damage to an opposing fighter in Blackbeard's zone", intent: Intent.harm);
          if (f != null) await x.damage(f, 3);
        }),
        'SCOURGE OF THE SEVEN SEAS': CardScript(effect: (x) async {
          if (await ransom(x, 1, 'Blackbeard recovers 2 health')) await x.heal(bb, 2);
          if (await ransom(x, 1, 'Blackbeard summons a Sea Dog')) await summonSeaDog(x, x.allSpaces);
          if (await ransom(x, 1, 'Blackbeard gains 1 action')) x.gainActions(1);
        }),
        'AVAST YE!': CardScript(
          immediately: (x) async {
            if (x.opp.hand.isNotEmpty && await ransom(x, 1, 'discard 1 random card')) await x.discard(x.opp, 1, random: true);
          },
          after: (x) async {
            final targets = enemiesInZone(x, bb).toList();
            if (targets.isEmpty || !await ransom(x, 1, "1 damage to each opposing fighter in Blackbeard's zone")) return;
            for (final f in targets) {
              await x.damage(f, 1);
            }
          },
        ),
        'GIVE NO QUARTER': CardScript(
          during: (x) async {
            if (friendsAdjacentTo(x, x.oppFighter, except: x.fighter) > 0) x.setValue(5);
          },
          after: (x) async {
            if (await ransom(x, 1, 'Blackbeard gains 1 action')) x.gainActions(1);
          },
        ),
        'PARLEY': CardScript(immediately: (x) async {
          if (x.oppCard != null && await ransom(x, 2, 'cancel all effects on your card')) x.cancelOpponent();
        }),
        'FEARSOME AND CALCULATING': CardScript(immediately: (x) async {
          if (x.opp.hand.isNotEmpty && await ransom(x, 1, 'Blackbeard picks a card from your hand to discard')) await pickDiscard(x);
        }),
        'INTIMIDATING VISAGE': CardScript(after: (x) async {
          if (x.enemiesAdjacentTo(bb).isNotEmpty) await x.heal(bb, 2);
        }),
        'SHOW A LEG!': CardScript(after: (x) async {
          if (bb.onBoard) await summonSeaDog(x, x.zoneSpaces(bb));
        }),
        'NO PREY, NO PAY': CardScript(
          during: (x) => x.boostThis(),
          after: (x) async {
            if (x.won) await x.draw(1);
          },
        ),
        "QUEEN ANNE'S REVENGE": CardScript(
          uncancelable: true,
          during: (x) async {
            if (treasury <= 0) return;
            final n = await x.game.chooseNumber(x.opp, 0, treasury, "Queen Anne's Revenge: pay doubloons from the Treasury (-2 each)");
            if (n <= 0) return;
            treasury -= n;
            doubloons += n;
            x.addValue(-2 * n, '$n doubloon${n == 1 ? '' : 's'} paid');
          },
        ),
      };
}
