/// Houdini vs. The Genie, and Unmatched Adventures: Tales to Amaze (Annie Christmas,
/// Nikola Tesla, Golden Bat, Dr. Jill Trent).
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ================================================================================ The Genie

class _ThreeWishes extends TurnMod {
  _ThreeWishes(this.owner) : super(name: 'Three Wishes');
  final Player owner;
  @override
  int? fixedValue(Game g, Side s) => s.player == owner ? 4 : null;
}

/// Infinite Power: at the start of your turn, you may discard 1 card to gain 1 action.
class Genie extends HeroScript {
  Fighter get genie => me.heroFighter;

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || me.hand.isEmpty) return;
    final c = await g.chooseCard(me, me.hand, 'Infinite Power: discard a card to gain 1 action?',
        optional: true, skipLabel: 'No', intent: Intent.loseOwn);
    if (c == null) return;
    await g.discardCard(c, reason: ' (Infinite Power)');
    g.gainActions(me, 1);
  }

  Future<void> hitAdjacent(Fx x, int n, {bool enemiesOnly = true, bool optional = false}) async {
    final opts = x.adjacentTo(genie).where((f) => !enemiesOnly || f.isEnemyOf(x.me));
    final f = await x.chooseFighter(opts, 'Deal $n damage to an adjacent ${enemiesOnly ? 'opposing ' : ''}fighter',
        intent: Intent.harm, optional: optional);
    if (f != null) await x.damage(f, n);
  }

  @override
  Map<String, CardScript> get cards => {
        "I'VE MADE SULTANS OUT OF LESS": const CardScript(after: pickDiscard),
        "PRISONER'S TORMENT": CardScript(after: (x) async {
          if (x.defending) await x.draw(x.damageDealt);
        }),
        'I AM FREED': CardScript(after: (x) async {
          if (!genie.onBoard) return;
          await x.place(genie, x.emptySpaces, text: 'Place the Genie in any empty space');
          for (final f in x.adjacentTo(genie).toList()) {
            await x.damage(f, 1);
          }
        }),
        'THIS IS NO PARLOR TRICK': CardScript(during: (x) async {
          final c = x.oppCard;
          if (c != null) x.game.addOp(x.oppSide, ValueOp.set(c.def.boost ?? 0, 'This Is No Parlor Trick: equal to its BOOST'));
        }),
        'WISHING FOR MORE WISHES': CardScript(after: (x) async {
          await x.draw(1, x.opp);
          await x.draw(3);
        }),
        'BACK IN THE LAMP': CardScript(immediately: (x) => x.heal(genie, 4)),
        'CAREFUL WHAT YOU WISH FOR': CardScript(after: (x) async {
          if (x.lost) await hitAdjacent(x, 1);
        }),
        'I GRANT YOU DEATH': CardScript(after: (x) => hitAdjacent(x, 1, enemiesOnly: false, optional: true)),
        'IMPRISONED WRATH': CardScript(after: (x) async {
          if (x.me.hand.length < 2 || !x.enemiesAdjacentTo(genie).isNotEmpty) return;
          if (!await x.yesNo('Imprisoned Wrath: discard 2 cards to deal 2 damage to an adjacent opposing fighter?')) return;
          await x.discard(x.me, 2);
          await hitAdjacent(x, 2);
        }),
        'THREE WISHES': CardScript(effect: (x) async {
          x.gainActions(1);
          final i = await x.option(
              ['Draw 5 cards', "For the rest of your turn, your cards' values are 4 and cannot be changed", 'Each opponent discards 2 cards'],
              'Three Wishes: choose one');
          switch (i) {
            case 0:
              await x.draw(5);
            case 1:
              x.game.addTurnMod(_ThreeWishes(x.me));
            case 2:
              for (final o in x.opponents.toList()) {
                await x.discard(o, 2);
              }
          }
        }),
        'YOUR WISH IS MY COMMAND': CardScript(after: (x) async {
          if (x.won && x.me.hand.length >= 2 && await x.yesNo('Discard 2 cards to gain 1 action?')) {
            await x.discard(x.me, 2);
            x.gainActions(1);
          }
        }),
      };
}

// ============================================================================ Harry Houdini

const _bess = 'AND THE BEAUTIFUL BESS!';
const _magician = 'A MAGICIAN NEVER REVEALS HIS SECRETS';

/// Escape Artist: when you maneuver and BOOST, you may place Houdini in any space instead of
/// moving him (Bess moves as normal).
class Houdini extends HeroScript {
  Fighter get houdini => me.heroFighter;
  Fighter? get bess => me.fighters.where((f) => f.isSidekick).firstOrNull;

  @override
  Future<void> maneuverMove(Fighter f, int allowance, {required bool boosted}) async {
    if (boosted && f == houdini &&
        await game.yesNo(me, 'Escape Artist: place Houdini in any space instead of moving?', intent: Intent.none)) {
      await game.placeFighter(f, game.board.spaceIds, chooser: me, text: 'Place Houdini in any space');
      return;
    }
    await super.maneuverMove(f, allowance, boosted: boosted);
  }

  @override
  Future<bool> blocksHandLook(Game g, Player target, Player viewer) async {
    if (target != me || viewer == me) return false;
    final c = me.hand.where((c) => c.def.upperTitle == _magician).firstOrNull;
    if (c == null || !await g.yesNo(me, 'Reveal A Magician Never Reveals His Secrets to stop them looking at your hand?')) return false;
    await g.emit(Revealed(me, [c], ' and cancels the effect'));
    return true;
  }

  @override
  Future<void> onDiscardedFromHand(Game g, Card c, {required bool byOpponent, Player? holder}) async {
    if (c.owner == me && byOpponent && c.def.upperTitle == _bess) await g.draw(me, 1);
  }

  @override
  Map<String, CardScript> get cards => {
        _magician: CardScript(effect: (x) async {
          await x.draw(2);
          x.gainActions(1);
        }),
        _bess: CardScript(boosted: (x) async {
          if (x.game.active == x.me) x.gainActions(1);
        }),
        'ALL PART OF THE SHOW': CardScript(
          uncancelable: true,
          boosted: (x) => x.heal(houdini, 2),
          after: (x) async {
            final f = x.fighter;
            if (!f.defeated) return;
            final s = await x.chooseSpace(x.emptySpaces, 'All Part of the Show: place ${f.name} in any space', intent: Intent.moveOwn, subject: f);
            if (s != null) await x.game.revive(f, s, hp: 4);
          },
        ),
        'FLOURISH': CardScript(boosted: (x) => x.draw(1), during: (x) => x.boostThis()),
        'AN ILLUSION OF MY OWN DESIGN': CardScript(
          immediately: (x) async {
            if (x.oppCard != null) await x.game.boostCard(x.oppSide, text: 'An Illusion of My Own Design: you may BOOST your card');
          },
          during: (x) => x.boostThis(),
        ),
        'GRAND ESCAPE': CardScript(
          during: (x) => x.boostThis(),
          after: (x) async {
            if (x.won && x.fighter.onBoard) await x.place(x.fighter, x.allSpaces, text: 'Grand Escape: place your fighter in any space');
          },
        ),
        'SET THE STAGE': CardScript(
          boosted: (x) => pickDiscard(x),
          effect: (x) async {
            await x.draw(3);
            final c = await x.game.chooseCard(x.me, x.me.hand, 'Put a card from your hand on top of your deck', intent: Intent.loseOwn);
            if (c != null) await x.game.toDeck(c);
          },
        ),
        'SLEIGHT OF HAND': CardScript(
          boosted: (x) => x.draw(1),
          immediately: (x) async {
            final f = x.fighter;
            final opts = x.me.hand.where((c) => c.def.upperTitle != 'SLEIGHT OF HAND' &&
                (x.attacking ? x.game.canAttackWith(c, f) : x.game.canDefendWith(c, f)));
            final c = await x.game.chooseCard(x.me, opts, 'Sleight of Hand: play a different card instead?',
                optional: true, skipLabel: 'Keep Sleight of Hand', intent: Intent.gainOwn);
            if (c != null) await x.game.replaceCard(x.mySide, c);
          },
        ),
        'THE BIG REVEAL': CardScript(
          during: (x) async {
            if (await x.boostThis(text: 'The Big Reveal: BOOST (1 of 2)?')) await x.boostThis(text: 'The Big Reveal: BOOST again?');
          },
          after: (x) async {
            final boosted = x.mySide.boosts.where((c) => x.me.discard.contains(c)).toList();
            final c = await x.game.chooseCard(x.me, boosted, 'Return a card you boosted with to your hand', intent: Intent.gainOwn);
            if (c != null) await x.game.toHand(c);
          },
        ),
        'FOR MY NEXT TRICK': CardScript(after: (x) async {
          final f = await x.chooseFighter(x.myFighters, 'Move one of your fighters up to 1 space');
          if (f != null) await x.move(f, 1);
          await x.draw(1);
          x.gainActions(1);
        }),
        'MISDIRECTION': CardScript(
          boosted: (x) async {
            final f = await x.chooseFighter(x.game.onBoard, 'Misdirection: deal 2 damage to any fighter', intent: Intent.harm);
            if (f != null) await x.damage(f, 2);
          },
          immediately: (x) async => x.cancelOpponent(),
        ),
        'SMOKE AND MIRRORS': CardScript(immediately: (x) async {
          final b = bess;
          if (b == null || !b.onBoard || !houdini.onBoard) return;
          final other = x.fighter == houdini ? b : houdini;
          if (await x.yesNo('Swap Houdini and Bess? ${other.name} enters the combat.', intent: Intent.none) && await x.game.swap(houdini, b)) {
            x.mySide.fighter = other;
          }
        }),
        'VANISHING ACT': CardScript(after: (x) => moveCombatant(x, 3, through: true)),
      };
}

// ========================================================================= Annie Christmas

/// Necklace of Pearls: +2 to Annie's attacks if she has less health than the defender.
class AnnieChristmas extends HeroScript {
  Fighter get annie => me.heroFighter;
  Fighter? get charlie => me.fighters.where((f) => f.isSidekick).firstOrNull;

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player == me && s.isAttacker && s.fighter == annie && annie.hp < s.other.fighter.hp) {
      yield const ValueOp.add(2, 'Necklace of Pearls');
    }
  }

  @override
  Map<String, CardScript> get cards => {
        "CAPTAIN'S ORDERS": CardScript(effect: (x) async {
          await x.place(annie, x.zoneSpaces(annie).where(x.game.isEmpty), text: 'Place Annie in an empty space in her zone');
          final f = await x.chooseFighter(x.myFighters.where((f) => f != annie), 'Place another friendly fighter in her zone');
          if (f != null && annie.onBoard) await x.place(f, x.zoneSpaces(annie).where(x.game.isEmpty));
          x.gainActions(1);
        }),
        'LAGNIAPPE': CardScript(immediately: (x) async {
          final n = await x.game.chooseNumber(x.me, 0, annie.hp > 2 ? 2 : annie.hp - 1, 'Lagniappe: deal up to 2 damage to Annie to draw that many');
          if (n <= 0) return;
          await x.damage(annie, n);
          await x.draw(n);
        }),
        'A FEW MORE PEARLS': CardScript(effect: (x) => damageAdjacentEnemies(x, annie, 2)),
        'SLICK TALKER': CardScript(immediately: (x) async {
          final c = charlie;
          if (c == null || !c.onBoard || !annie.onBoard) return;
          final other = x.fighter == annie ? c : annie;
          if (await x.yesNo('Swap Annie and Charlie? ${other.name} becomes the defender.', intent: Intent.none) && await x.game.swap(annie, c)) {
            x.mySide.fighter = other;
          }
        }),
        'THE TURN AND THE RIVER': drawAfter(2),
        'QUITE A PAIR': CardScript(immediately: (x) async {
          final names = <String, List<Card>>{};
          for (final c in x.me.hand) {
            names.putIfAbsent(c.def.upperTitle, () => []).add(c);
          }
          final pairs = names.values.where((l) => l.length >= 2).toList();
          if (pairs.isEmpty || !await x.yesNo("Reveal a pair to cancel all effects on your opponent's card?")) return;
          await x.game.emit(Revealed(x.me, pairs.first.take(2).toList(), ' (Quite a Pair)'));
          x.cancelOpponent();
        }),
        'BETTER TOGETHER': CardScript(after: (x) async {
          final f = x.fighter;
          final friends = x.adjacentTo(f).where((o) => o.isFriendOf(x.me)).toList();
          if (friends.isEmpty) return;
          for (final t in [f, ...friends]) {
            await x.heal(t, 1);
          }
        }),
        'BOTTOM DEALING': CardScript(during: (x) async {
          if (x.me.deck.isEmpty) return;
          final c = x.me.deck.last;
          await x.game.emit(Revealed(x.me, [c], ' from the bottom of their deck'));
          x.addValue(c.def.boost ?? 0, '${c.title} (BOOST)');
          if (await x.option(['Put it on the top of your deck', 'Leave it on the bottom'], 'Bottom Dealing', intent: Intent.none) == 0) {
            x.me.deck
              ..removeLast()
              ..insert(0, c);
          }
        }),
        'KEEP YOUR HANDS TO YOURSELF': CardScript(after: (x) => moveEach(x, [x.fighter, x.oppFighter], 2)),
        'MISSISSIPPI QUEEN': CardScript(immediately: (x) async {
          x.game.addTurnMod(TurnMod(name: 'Mississippi Queen', minHealthFn: (g, f) => f == annie ? 1 : 0));
        }),
        'STRIKING BEAUTY': CardScript(after: (x) => x.damage(x.oppFighter, x.won ? 2 : 1)),
      };
}

// ============================================================================= Nikola Tesla

/// Electrical Overflow: start with 1 coil charged; charge 1 at the end of your turn; at the
/// start of your turn, if both are charged, deal 1 damage to each opposing fighter adjacent to
/// Tesla and move them up to 1 space.
class Tesla extends HeroScript {
  int coils = 1;
  Fighter get tesla => me.heroFighter;

  Future<void> charge(int n) async {
    final before = coils;
    coils = (coils + n).clamp(0, 2);
    if (coils != before) await game.emit(StatusChanged(me, 'Tesla has $coils coil${coils == 1 ? '' : 's'} charged.'));
  }

  /// "You may discharge coils": returns how many were discharged (0, 1 or 2).
  Future<int> discharge(String one, String two) async {
    if (coils == 0) return 0;
    final opts = ["Don't discharge", '1 coil: $one', if (coils == 2) '2 coils: $two'];
    final i = await game.chooseOption(me, opts, 'Discharge coils? ($coils charged)');
    if (i > 0) await charge(-i);
    return i;
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || coils < 2 || !tesla.onBoard) return;
    for (final f in g.adjacentFighters(tesla).where((f) => f.isEnemyOf(me)).toList()) {
      await g.damage(f, 1, info: DamageInfo(source: tesla, by: me));
      if (f.onBoard) await g.moveFighter(f, 1, chooser: me);
    }
  }

  @override
  Future<void> endOfTurn(Game g, Player active) async {
    if (active == me) await charge(1);
  }

  @override
  List<String> status() => ['COILS $coils/2'];

  @override
  Map<String, CardScript> get cards => {
        'DEATH RAY': CardScript(during: (x) async {
          final n = await discharge('this card is 5', 'this card is 7');
          if (n > 0) x.setValue(n == 1 ? 5 : 7);
        }),
        'INTENSE EXPERIMENTATION': CardScript(after: (x) async {
          final n = await discharge('draw 2 instead', 'draw 3 and Tesla recovers 1');
          await x.draw(n + 1);
          if (n == 2) await x.heal(tesla, 1);
        }),
        'LIGHTNING STORM': CardScript(after: (x) async {
          final n = await discharge('1 damage to each opposing fighter in your zone', '2 damage instead');
          if (n == 0) return;
          for (final f in enemiesInZone(x, x.fighter).toList()) {
            await x.damage(f, n);
          }
        }),
        'POLYPHASE COILS': CardScript(immediately: (x) async {
          final n = await discharge("cancel all effects on your opponent's card", 'also ignore its value');
          if (n >= 1) x.cancelOpponent();
          if (n == 2) x.ignoreOpponentValue();
        }),
        'X-RAY RADIATION': CardScript(during: (x) async {
          if (x.opp.deck.isEmpty) return;
          final c = x.opp.deck.first;
          await x.game.emit(Revealed(x.opp, [c], ' from the top of their deck'));
          final n = await discharge('discard that card', "also add its BOOST to this card's value");
          if (n >= 1) await x.game.discardTopOfDeck(x.opp);
          if (n == 2) x.addValue(c.def.boost ?? 0, '${c.title} (BOOST)');
        }),
        '7 HERTZ': CardScript(after: (x) async {
          final n = await discharge('gain 1 action', 'also draw 1 card');
          if (n >= 1) x.gainActions(1);
          if (n == 2) await x.draw(1);
        }),
        'REPULSION BLAST': CardScript(after: (x) async {
          await pushOpponent(x, 2);
          final n = await discharge('also move Tesla up to 2', 'also your opponent discards 1 random card');
          if (n >= 1) await x.move(tesla, 2);
          if (n == 2) await x.discard(x.opp, 1, random: true);
        }),
        'FULLY CHARGED': CardScript(effect: (x) async {
          await charge(2);
          x.gainActions(1);
        }),
        'KINETIC INDUCTION': CardScript(after: (x) => charge(x.won ? 2 : 1)),
        'REMOTE CONTROL': CardScript(effect: (x) async {
          await moveEach(x, x.enemies, 2);
          x.gainActions(1);
        }),
        'THE ALTERNATING CURRENT': CardScript(after: (x) async {
          final opts = ['Charge both coils', if (coils == 2) 'Discharge both coils: Tesla recovers 2 health'];
          if (await x.option(opts, 'The Alternating Current: choose one') == 0) {
            await charge(2);
          } else {
            await charge(-2);
            await x.heal(tesla, 2);
          }
        }),
      };
}

// =============================================================================== Golden Bat

/// The First Superhero: if you haven't taken a maneuver action this turn, +2 to Golden Bat's
/// attacks.
class GoldenBat extends HeroScript {
  Fighter get bat => me.heroFighter;

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player == me && s.isAttacker && s.fighter == bat && g.active == me && g.turn.maneuvers == 0) {
      yield const ValueOp.add(2, 'The First Superhero');
    }
  }

  @override
  Map<String, CardScript> get cards => {
        'TERRIFYING ROAR': CardScript(immediately: (x) async {
          x.game.addTurnMod(TurnMod(name: 'Terrifying Roar', cannotLeaveFn: (g, f) => true));
        }),
        'VAPORIZING EYEBEAMS': oppDiscardsAfter(1, random: true),
        'ALPINE FORTRESS': CardScript(effect: (x) async {
          final c = await x.game.chooseCard(x.me, x.me.discard, 'Shuffle a card from your discard pile into your deck', intent: Intent.gainOwn);
          if (c != null) await x.game.toDeck(c, shuffle: true);
          await x.draw(2);
          await x.move(bat, 4);
        }),
        'HE LAUGHS AT YOUR FEEBLENESS': vanilla,
        'LIKE A FLASH OF GOLDEN LIGHT': CardScript(
          during: (x) async {
            final start = x.game.turn.startSpace[bat];
            if (start != null && bat.onBoard && !x.board.sharesZone(start, bat.space!)) x.setValue(4);
          },
          after: (x) => x.move(bat, 5),
        ),
        'A PUNCH TO SHAKE THE EARTH': CardScript(after: (x) async {
          for (final f in enemiesInZone(x, bat).toList()) {
            await x.damage(f, x.won ? 2 : 1);
          }
        }),
        'ARRIVE JUST IN TIME': CardScript(effect: (x) => x.place(bat, x.allSpaces, text: 'Place Golden Bat in any space')),
        'INSIGHT OF THE ANCIENTS': CardScript(after: (x) async {
          if (!x.won || x.me.discard.isEmpty) return;
          final c = x.me.discard[x.game.rng.nextInt(x.me.discard.length)];
          await x.game.toHand(c, reason: ' (at random)');
        }),
        'SIGHT BEYOND SIGHT': CardScript(after: (x) async {
          final top = x.opp.deck.take(3).toList();
          if (top.isEmpty) return;
          x.me.script.seen(top);
          final order = <Card>[];
          final left = List.of(top);
          while (left.length > 1) {
            final c = await x.game.chooseCard(x.me, left, "Put back on top of your opponent's deck (first chosen = top)", intent: Intent.forceEnemy);
            left.remove(c);
            order.add(c!);
          }
          order.addAll(left);
          x.opp.deck
            ..removeRange(0, top.length)
            ..insertAll(0, order);
        }),
        'SUPER STRENGTH': vanilla,
      };
}

// =========================================================================== Dr. Jill Trent

enum Gadget { hypnoray, tonic }

/// Gadgetology: at the start of your turn, activate one of your gadgets. Whenever Jill Trent
/// attacks, resolve the active gadget's effect.
/// * Hypnoray Blaster, DURING COMBAT: if your card's printed value is lower than your
///   opponent's, reveal the top card of their deck and add its BOOST to your attack.
/// * Ultrabiotic Tonic, AFTER COMBAT: if your card's printed value is higher than your
///   opponent's, Jill Trent recovers 1 health.
/// Sisters in Arms lets Daisy use the gadget when she attacks next to Jill.
class JillTrent extends HeroScript {
  Gadget? gadget;
  Fighter get jill => me.heroFighter;
  Fighter? get daisy => me.fighters.where((f) => f.id == 'daisy').firstOrNull;

  @override
  List<String> status() => [if (gadget != null) gadget == Gadget.hypnoray ? 'Hypnoray Blaster' : 'Ultrabiotic Tonic'];

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me) return;
    final i = await g.chooseOption(me, ['Hypnoray Blaster', 'Ultrabiotic Tonic'], 'Gadgetology: activate a gadget');
    gadget = Gadget.values[i];
    await g.emit(StatusChanged(me, 'Jill Trent activates the ${status().first}.'));
  }

  /// Whether this attack resolves the active gadget: Jill attacking, or Daisy attacking with
  /// Sisters in Arms next to Jill.
  bool _gadgetApplies(Game g, Combat c) {
    final a = c.attacker;
    if (a.player != me || gadget == null || a.card == null) return false;
    if (a.fighter == jill) return true;
    final d = daisy;
    return d != null && a.fighter == d && a.card!.def.upperTitle == 'SISTERS IN ARMS' && g.adjacent(d, jill);
  }

  @override
  Future<void> duringCombat(Game g, Combat c) async {
    if (gadget != Gadget.hypnoray || !_gadgetApplies(g, c)) return;
    if (c.attacker.printed >= (c.defender.card == null ? 0 : c.defender.printed)) return;
    final opp = c.defender.player;
    if (opp.deck.isEmpty) return;
    final top = opp.deck.first;
    await g.emit(Revealed(opp, [top], ' from the top of their deck (Hypnoray Blaster)'));
    g.addOp(c.attacker, ValueOp.add(top.def.boost ?? 0, 'Hypnoray Blaster: ${top.title} (BOOST)'));
  }

  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (gadget != Gadget.tonic || !_gadgetApplies(g, c)) return;
    if (c.attacker.printed <= (c.defender.card == null ? 0 : c.defender.printed)) return;
    if (jill.alive) await g.heal(jill, 1);
  }

  @override
  Map<String, CardScript> get cards => {
        'BATTLE OF WITS': CardScript(after: (x) async {
          final mine = x.me.deck.firstOrNull, theirs = x.opp.deck.firstOrNull;
          if (mine != null) await x.game.emit(Revealed(x.me, [mine], ' from the top of their deck (Battle of Wits)'));
          if (theirs != null) await x.game.emit(Revealed(x.opp, [theirs], ' from the top of their deck (Battle of Wits)'));
          if (mine != null && (mine.def.boost ?? 0) > (theirs?.def.boost ?? 0) && x.oppFighter.alive) {
            await x.damage(x.oppFighter, 3);
          }
        }),
        'ENERGIZING SPRAY': CardScript(after: (x) async => x.gainActions(1)),
        'HYPNOTIST': CardScript(immediately: (x) async {
          if (gadget == Gadget.hypnoray) x.cancelOpponent();
        }),
        'UTILITY BELT': CardScript(after: (x) async {
          final i = await x.option(['Jill Trent recovers 1 health', 'Move Jill Trent 1 space', 'Draw 1 card'], 'Utility Belt: choose one');
          switch (i) {
            case 0:
              await x.heal(jill, 1);
            case 1:
              if (jill.onBoard) await x.move(jill, 1);
            default:
              await x.draw(1);
          }
        }),
        'HELPFUL ASSISTANT': CardScript(effect: (x) async {
          final cards = await x.game.chooseCards(x.me, x.me.discard.where((c) => c.owner == x.me), 0, 3,
              'Helpful Assistant: shuffle up to 3 cards from your discard pile into your deck', intent: Intent.gainOwn, source: x.card);
          for (final c in cards) {
            await x.game.toDeck(c);
          }
          if (cards.isNotEmpty) await x.game.shuffleDeck(x.me);
          await x.draw(1);
        }),
        'INSIGHTFUL DEDUCTION': CardScript(after: (x) async {
          final t = x.opp;
          final top = t.deck.take(3).toList();
          if (top.isEmpty) return;
          await x.game.emit(Revealed(t, top, ' from the top of their deck (Insightful Deduction)'));
          final bottom = await x.game.chooseCard(x.me, top, 'Insightful Deduction: put one on the bottom of their deck',
              intent: Intent.loseEnemy, source: x.card);
          t.deck.removeWhere(top.contains);
          final rest = top.where((c) => c != bottom).toList();
          final order = <Card>[];
          while (rest.isNotEmpty) {
            final c = rest.length == 1
                ? rest.first
                : await x.game.chooseCard(x.me, rest, 'Insightful Deduction: which card goes on top?', intent: Intent.loseOwn, source: x.card);
            rest.remove(c);
            order.add(c!);
          }
          t.deck
            ..insertAll(0, order)
            ..add(bottom!);
          await x.game.say('${x.me.name} puts one card on the bottom of ${t.name}\'s deck and the rest back on top.');
        }),
        'SISTERS IN ARMS': const CardScript(uncancelable: true),
        'ACE FIGHTER': drawAfter(1),
        'CAUGHT RED-HANDED': CardScript(after: (x) => x.discard(x.opp, x.won ? 2 : 1)),
        'GYROSCOPIC JETPACK': moveAfter(2, through: true),
        'INDESTRUCTIBLE CLOTH': CardScript(immediately: (x) async {
          final f = x.fighter, combat = x.combat;
          x.game.addTurnMod(TurnMod(
            name: 'Indestructible Cloth',
            modifyDamageFn: (g, target, n, info) => target == f && !info.combat && g.combat == combat ? 0 : n,
          ));
        }),
        'LASER PEN': CardScript(after: (x) async {
          if (x.oppFighter.alive) await x.damage(x.oppFighter, 1);
        }),
        'STASIS DIFFUSER': lockOpponent,
      };
}
