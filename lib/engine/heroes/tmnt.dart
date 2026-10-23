/// Teenage Mutant Ninja Turtles: Leonardo, Donatello, Michelangelo (Adventures) and Shredder,
/// Krang (Shredder vs Krang hero decks).
library;

import 'dart:math';

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ================================================================================= Leonardo

/// Team Tactics: at the start of your turn, move any fighter up to 1 space.
class Leonardo extends HeroScript {
  Fighter get leo => me.heroFighter;
  Fighter? get splinter => me.fighters.where((f) => f.isSidekick).firstOrNull;

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me) return;
    final f = await g.chooseFighter(me, g.onBoard, 'Team Tactics: move any fighter up to 1 space?',
        optional: true, skipLabel: 'No', intent: Intent.none);
    if (f != null) await g.moveFighter(f, 1, chooser: me);
  }

  bool fewerZones(Fx x, Fighter than) =>
      than.onBoard && x.oppFighter.onBoard && x.board.zoneCount(x.oppFighter.space!) < x.board.zoneCount(than.space!);

  @override
  Map<String, CardScript> get cards => {
        'PROTECTIVE FATHER': CardScript(effect: (x) async {
          final s = x.fighter;
          final f = await x.chooseFighter(x.myFighters.where((f) => f != s), 'Splinter may swap with another friendly fighter',
              optional: true, intent: Intent.none);
          if (f != null && await x.game.swap(s, f)) {
            await x.heal(s, 2);
            await x.heal(f, 2);
          }
          x.gainActions(1);
        }),
        'SPATIAL AWARENESS': CardScript(after: (x) async {
          if (fewerZones(x, x.fighter)) {
            await x.damage(x.oppFighter, 1);
            await x.draw(1);
          }
        }),
        'WISE BEYOND HIS YEARS': CardScript(after: (x) async {
          if (fewerZones(x, leo)) await x.damage(x.oppFighter, 2);
        }),
        'EAT, SLEEP, AND BREATH NINJUTSU': CardScript(after: (x) async {
          for (final f in x.adjacentTo(x.fighter).toList()) {
            if (!f.onBoard) continue;
            await x.place(f, x.zoneSpaces(f).where((s) => s != f.space && x.game.isEmpty(s)), text: 'Place ${f.name} in another space in their zone');
          }
        }),
        'FEARLESS LEADER': CardScript(during: (x) async {
          final n = friendsAdjacentTo(x, x.oppFighter, except: x.fighter);
          if (n > 0) x.addValue(2 * n, 'Friendly fighters adjacent ($n)');
        }),
        'FOR SENSEI': CardScript(after: (x) async {
          for (final f in [x.fighter, x.oppFighter]) {
            if (f.onBoard) await x.move(f, 1);
          }
          if (x.me.hand.isNotEmpty && await x.yesNo('For Sensei: discard 1 card to gain 1 action?')) {
            await x.discard(x.me, 1);
            x.gainActions(1);
          }
        }),
        'I HAVE A PLAN': CardScript(immediately: (x) async {
          if (x.me.hand.isEmpty || !await x.yesNo("I Have a Plan: discard 1 card to cancel and ignore your opponent's card?")) return;
          await x.discard(x.me, 1);
          x.cancelOpponent();
          x.ignoreOpponentValue();
        }),
        'KATANA': vanilla,
        'LEONARDO LEADS': CardScript(effect: (x) async {
          await moveEach(x, x.myFighters, 3);
          await x.draw(1);
        }),
      };
}

// ================================================================================ Donatello

const _inventions = {'SMOKE BOMB', 'SELF DEFENSE GRID', 'ELECTRO GRENADE'};

/// Inventive: when you maneuver, you may draw 2 cards instead of 1; if you do, put a card from your
/// hand on the bottom of your deck. After you play an invention, tuck it under Donatello's card;
/// its invention bonus applies for the rest of the game (bonuses cannot be canceled).
class Donatello extends HeroScript {
  final Set<String> tucked = {};
  Fighter get don => me.heroFighter;

  @override
  Future<void> maneuverDraw(int n) async {
    if (me.deck.length < 2 || !await game.yesNo(me, 'Inventive: draw 2 cards instead of 1 (then put one on the bottom)?')) {
      await game.draw(me, n);
      return;
    }
    await game.draw(me, n + 1);
    final c = await game.chooseCard(me, me.hand, 'Put a card from your hand on the bottom of your deck', intent: Intent.loseOwn);
    if (c != null) await game.toDeck(c, bottom: true);
  }

  @override
  Future<bool> disposePlayed(Card c) async {
    final t = c.def.upperTitle;
    if (c.owner != me || !_inventions.contains(t)) return false;
    me.removed.add(c);
    tucked.add(t);
    await game.emit(CardMoved(c, Zone.combat, Zone.removed, reason: ' (tucked under Donatello: its bonus is permanent)'));
    return true;
  }

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player != me) return;
    if (s.isAttacker && tucked.contains('ELECTRO GRENADE')) yield const ValueOp.add(1, 'Invention: Electro Grenade');
    if (!s.isAttacker && tucked.contains('SELF DEFENSE GRID')) yield const ValueOp.add(1, 'Invention: Self Defense Grid');
  }

  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    if (p == me && kind == ActionKind.scheme && tucked.contains('SMOKE BOMB') && card?.def.upperTitle != 'SMOKE BOMB') {
      g.gainActions(me, 1);
    }
  }

  @override
  List<String> status() => [for (final t in tucked) t.split(' ').map((w) => w[0] + w.substring(1).toLowerCase()).join(' ')];

  Future<int> removeFromDiscard(Fx x, bool Function(Card) which, String text) async {
    final cards = await x.game.chooseCards(x.me, x.me.discard.where(which), 0, 4, text, intent: Intent.loseOwn);
    for (final c in cards) {
      await x.game.removeFromGame(c);
    }
    return cards.length;
  }

  @override
  Map<String, CardScript> get cards => {
        'PARTY WAGON!': CardScript(effect: (x) async {
          final f = await x.chooseFighter(x.myFighters, 'Party Wagon!: move a friendly fighter up to 5 spaces');
          if (f == null) return;
          final path = await x.move(f, 5, throughOpp: true);
          final t = await x.chooseFighter(x.game.movedThrough(path, x.me), 'Deal 2 damage to an opposing fighter they moved through',
              intent: Intent.harm);
          if (t != null) await x.damage(t, 2);
        }),
        'SMOKE BOMB': CardScript(effect: (x) async {
          final n = await removeFromDiscard(x, (c) => c.def.isScheme, 'Smoke Bomb: remove up to 4 schemes in your discard pile (gain that many actions)');
          x.gainActions(n);
        }),
        'SELF DEFENSE GRID': CardScript(after: (x) async {
          final n = await removeFromDiscard(x, (c) => c.def.canDefend, 'Remove up to 4 defense/versatile cards from your discard pile (Donatello heals that much)');
          await x.heal(don, n);
        }),
        'SHIFT FOCUS': CardScript(after: (x) async {
          final f = await x.chooseFighter(x.inZoneOf(don).where((f) => f != don), "Move another fighter in Donatello's zone up to 3 spaces",
              optional: true);
          if (f != null) await x.move(f, 3, throughOpp: true);
        }),
        'SHORT CIRCUIT': CardScript(immediately: (x) async => x.cancelOpponentAfter()),
        'UNTESTED ENHANCEMENTS': CardScript(during: (x) async {
          if (x.me.deck.isEmpty) return;
          final c = x.me.deck.removeLast();
          x.me.discard.add(c);
          await x.game.emit(CardMoved(c, Zone.deck, Zone.discard, reason: ' from the bottom of the deck'));
          x.addValue(c.def.boost ?? 0, '${c.title} (BOOST)');
        }),
        'DONATELLO DOES MACHINES': CardScript(effect: (x) async {
          for (final p in x.game.players.where((p) => p.isAllyOf(x.me) && !p.eliminated)) {
            final c = await x.game.chooseCard(p, p.discard.where((c) => !c.def.isScheme), 'Return an attack, versatile or defense card from your discard pile?',
                optional: true, intent: Intent.gainOwn);
            if (c != null) await x.game.toHand(c);
          }
          await x.draw(1);
        }),
        'THE FUTURE OF NINJUTSU': CardScript(effect: (x) async {
          final decks = x.game.players.where((p) => p.deck.isNotEmpty && !p.eliminated).toList();
          if (decks.isNotEmpty) {
            final i = await x.option([for (final p in decks) "${p.name}'s deck"], 'Look at the top card of any deck', intent: Intent.none);
            final p = decks[i];
            final top = p.deck.first;
            x.me.script.seen([top]);
            if (await x.yesNo('The top card is ${top.title}. Put it on the bottom?', intent: p == x.me ? Intent.none : Intent.harm)) {
              p.deck
                ..removeAt(0)
                ..add(top);
            }
          }
          await x.draw(1);
          x.gainActions(1);
        }),
        'ELECTRO GRENADE': CardScript(during: (x) async {
          final n = await removeFromDiscard(x, (c) => c.def.canAttack, 'Remove up to 4 attack/versatile cards from your discard pile (+1 each)');
          if (n > 0) x.addValue(n, 'Cards removed ($n)');
        }),
        'THINKING AHEAD': CardScript(after: (x) async {
          if (!x.won) return;
          final c = await x.game.chooseCard(x.me, x.me.discard, 'Put a card from your discard pile on the bottom of your deck?',
              optional: true, intent: Intent.gainOwn);
          if (c != null) await x.game.toDeck(c, bottom: true);
        }),
        'BO STAFF': CardScript(after: (x) async {
          final f = await x.chooseFighter(x.enemiesAdjacentTo(don), 'Deal 1 damage to an opposing fighter adjacent to Donatello', intent: Intent.harm);
          if (f != null) await x.damage(f, 1);
          await x.draw(1);
        }),
      };
}

// ============================================================================= Michelangelo

/// Pizza Party: after you attack or scheme, draw 1 card. Your starting and maximum hand size is 3.
class Michelangelo extends HeroScript {
  Fighter get mikey => me.heroFighter;

  @override
  int get startingHand => 3;

  @override
  int handLimit(Game g, Player p, int v) => p == me ? 3 : v;

  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    if (p == me && kind != ActionKind.maneuver) await g.draw(me, 1);
  }

  Future<bool> bottomForAction(Fx x) async {
    if (x.me.hand.isEmpty || !await x.yesNo('Put a card from your hand on the bottom of your deck to gain 1 action?')) return false;
    final c = await x.game.chooseCard(x.me, x.me.hand, 'Which card goes on the bottom?', intent: Intent.loseOwn);
    if (c == null) return false;
    await x.game.toDeck(c, bottom: true);
    x.gainActions(1);
    return true;
  }

  Future<void> shuffleBack(Fx x, int n) async {
    final pool = List.of(x.me.discard)..shuffle(x.game.rng);
    for (final c in pool.take(n)) {
      await x.game.toDeck(c, shuffle: true);
    }
  }

  @override
  Map<String, CardScript> get cards => {
        'BACK FOR SECONDS': CardScript(after: (x) => shuffleBack(x, 2)),
        'HI-YAAAAAH!!': CardScript(after: (x) async {
          final f = await x.chooseFighter(x.enemiesAdjacentTo(x.fighter), 'Deal 1 damage to an adjacent opposing fighter', intent: Intent.harm);
          if (f != null) await x.damage(f, 1);
          await bottomForAction(x);
        }),
        'BOISTEROUS BEATDOWN': CardScript(after: (x) async => x.gainActions(x.won ? 2 : 1)),
        "LET'S GO": CardScript(after: (x) async {
          final f = await x.chooseFighter(x.myFighters, 'Move a friendly fighter up to 3 spaces');
          if (f != null) await x.move(f, 3);
        }),
        'MICHELANGELO IS A PARTY DUDE!!': CardScript(effect: (x) async {
          for (final f in x.game.onBoard.where((f) => f.isFriendOf(x.me)).toList()) {
            await x.heal(f, 1);
          }
        }),
        'COWABUNGA!!': CardScript(during: (x) async {
          final n = x.game.turn.played.where((c) => c != x.card && c.playedBy == x.me && !c.virtual).length;
          if (n > 0) x.addValue(n, 'Other cards played this turn ($n)');
        }),
        'NUNCHAKU': CardScript(effect: (x) async {
          x.game.addTurnMod(TurnMod(
              name: 'Nunchaku',
              valueOpsFn: (g, s) => s.player == me && s.isAttacker && s.fighter == mikey ? const [ValueOp.add(1, 'Nunchaku')] : const []));
          x.gainActions(1);
        }),
        'GUARANTEED DELIVERY': CardScript(
          immediately: (x) async {
            if (x.me.hand.isEmpty || !await x.yesNo("Put a card on the bottom of your deck to cancel your opponent's card?")) return;
            final c = await x.game.chooseCard(x.me, x.me.hand, 'Which card goes on the bottom?', intent: Intent.loseOwn);
            if (c == null) return;
            await x.game.toDeck(c, bottom: true);
            x.cancelOpponent();
          },
          after: (x) async {
            if (x.me.hand.isEmpty) await x.draw(2);
          },
        ),
        'SHELL INSERTION': CardScript(effect: (x) async {
          final picks = await chooseDifferent(x, [
            'Each opponent discards 1 card',
            'Move a friendly fighter up to 2 spaces',
            'Put a card from your hand on the bottom of your deck to gain 1 action',
            'Shuffle 2 random cards from your discard pile back into your deck',
          ], 2, 'Shell Insertion');
          for (final p in picks) {
            switch (p) {
              case 0:
                for (final o in x.opponents.toList()) {
                  await x.discard(o, 1);
                }
              case 1:
                final f = await x.chooseFighter(x.myFighters, 'Move a friendly fighter up to 2 spaces');
                if (f != null) await x.move(f, 2);
              case 2:
                await bottomForAction(x);
              case 3:
                await shuffleBack(x, 2);
            }
          }
        }),
        'TURTLE POWER!!': boostable,
        'HARD-HITTING INVESTIGATION': CardScript(after: (x) async {
          await x.damage(x.oppFighter, 1);
          x.gainActions(1);
        }),
      };
}

// ================================================================================= Shredder

typedef Path = (int, int);
Path _norm((int, int) p) => p.$1 < p.$2 ? p : (p.$2, p.$1);

/// Master of the Clan: at the start of your turn, deploy a Foot soldier to a path adjacent to a
/// friendly fighter. Shredder and Bebop & Rocksteady may attack opposing fighters adjacent to Foot
/// soldiers. An opposing hero who boosts their maneuver may remove Foot soldiers they move through.
/// 24 tokens; one per path.
class Shredder extends HeroScript {
  static const supply = 24;
  Fighter get shredder => me.heroFighter;

  Iterable<Token> get feet => game.board.tokens.where((t) => t.kind == 'foot' && t.owner == me);
  int get deployed => feet.length;
  bool hasFoot(Path p) => feet.any((t) => t.path == _norm(p));

  /// Foot soldiers on paths touching [f]'s space.
  int footAdjacent(Fighter f) => f.onBoard ? feet.where((t) => t.path!.$1 == f.space || t.path!.$2 == f.space).length : 0;

  Iterable<Path> freePaths({Iterable<int>? touching}) sync* {
    for (final l in game.board.def.links) {
      final p = _norm(l);
      if (hasFoot(p)) continue;
      if (touching != null && !touching.contains(p.$1) && !touching.contains(p.$2)) continue;
      yield p;
    }
  }

  Future<void> deploy(Iterable<Path> paths, String text) async {
    if (deployed >= supply) return;
    final opts = paths.toList();
    if (opts.isEmpty) return;
    final p = await game.choose<Path>(me, Ask.path, text, [for (final p in opts) Choice('Path ${p.$1}–${p.$2}', p)], intent: Intent.harm);
    if (p == null) return;
    game.board.tokens.add(Token('foot', me, path: p));
    await game.emit(StatusChanged(me, 'A Foot soldier is deployed ($deployed on the board).'));
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me) return;
    final friendly = g.onBoard.where((f) => f.isFriendOf(me)).map((f) => f.space!).toSet();
    await deploy(freePaths(touching: friendly), 'Master of the Clan: deploy a Foot soldier next to a friendly fighter');
  }

  @override
  bool canAlsoTarget(Game g, Fighter attacker, Fighter target) =>
      attacker.owner == me && footAdjacent(target) > 0 && target.isEnemyOf(me);

  @override
  Future<void> afterMove(Game g, Fighter f, List<int> path) async {
    if (!f.isHero || !f.isEnemyOf(me) || f.owner != g.active || g.turn.flags['maneuvering'] != 'boosted') return;
    for (var i = 0; i + 1 < path.length; i++) {
      final p = _norm((path[i], path[i + 1]));
      final t = feet.where((t) => t.path == p).firstOrNull;
      if (t != null && await g.yesNo(f.owner, 'Remove the Foot soldier on the path you moved through?')) {
        g.board.tokens.remove(t);
        await g.emit(StatusChanged(me, 'A Foot soldier is removed.'));
      }
    }
  }

  @override
  List<String> status() => ['FOOT $deployed/$supply'];

  @override
  Map<String, CardScript> get cards => {
        'GRUFF ESCORT': CardScript(after: (x) async {
          await deploy(freePaths(), 'Gruff Escort: deploy a Foot soldier anywhere (1 of 2)');
          await deploy(freePaths(), 'Gruff Escort: deploy a Foot soldier anywhere (2 of 2)');
          await x.move(shredder, 2);
        }),
        'MASTER OF THE FOOT': CardScript(after: (x) async {
          for (final f in x.enemies.where((e) => footAdjacent(e) > 0).toList()) {
            await x.damage(f, 1);
          }
        }),
        'OBEDIENT SUBJECTS': CardScript(effect: (x) async => x.gainActions(footAdjacent(shredder))),
        'ALL ACCORDING TO PLAN': CardScript(after: (x) async {
          final o = x.opp;
          x.game.gainActions(o, 1);
          final schemesBefore = x.game.turn.schemes;
          x.game.addTurnMod(_PlanMod(o, schemesBefore));
        }),
        'SWARMING STRIKE': CardScript(during: (x) async {
          final n = footAdjacent(x.fighter);
          if (n > 0) x.addValue(n, 'Adjacent Foot soldiers ($n)');
        }),
        'THINK HARD': CardScript(after: (x) => x.draw(footAdjacent(x.oppFighter))),
        'BACK TO WORK!': CardScript(effect: (x) async {
          final b = x.me.fighters.where((f) => f.isSidekick).firstOrNull;
          if (b == null) return;
          if (b.onBoard) {
            await x.heal(b, 3);
            return;
          }
          if (!shredder.onBoard) return;
          // "As close as possible to Shredder": the nearest empty spaces.
          final empty = x.emptySpaces.toList();
          if (empty.isEmpty) return;
          final d = empty.map((s) => x.board.distance(s, shredder.space!)).reduce(min);
          final s = await x.chooseSpace(empty.where((s) => x.board.distance(s, shredder.space!) == d), 'Place Bebop & Rocksteady as close as possible to Shredder',
              intent: Intent.moveOwn, subject: b);
          if (s != null) await x.game.revive(b, s, hp: 3);
        }),
        'GANG UP': valueIf((x) => footAdjacent(x.oppFighter) >= 2, 6),
        'MASTERFUL DEFENSE': CardScript(after: (x) => x.heal(shredder, footAdjacent(shredder))),
        'PERPLEXING TACTICS': CardScript(immediately: (x) async {
          x.cancelOpponent();
          if (deployed >= 10) x.ignoreOpponentValue();
        }),
      };
}

/// All According to Plan: at the end of this turn, if they didn't play a scheme, they discard 2.
class _PlanMod extends TurnMod {
  _PlanMod(this.target, this.schemesBefore) : super(name: 'All According to Plan');
  final Player target;
  final int schemesBefore;
  @override
  Future<void> endOfTurn(Game g, Player active) async {
    final playedScheme = active == target && g.turn.schemes > schemesBefore;
    if (!playedScheme) await g.discardFromHand(target, 2);
  }
}

// ==================================================================================== Krang

/// DOOOOM!: 3 doomsday machines, one active at the start. After rolling the Die of Ultimate
/// Destruction you may deactivate an active machine to reroll. +1 move per active machine.
class Krang extends HeroScript {
  int machines = 1;
  Fighter get krang => me.heroFighter;

  Future<void> activate([int n = 1]) async {
    final before = machines;
    machines = min(3, machines + n);
    if (machines != before) await game.emit(StatusChanged(me, 'Krang has $machines doomsday machine${machines == 1 ? '' : 's'} active.'));
  }

  @override
  Future<int> rollDie(String why) async {
    var v = await super.rollDie(why);
    while (machines > 0 &&
        await game.yesNo(me, 'Rolled ${v == 0 ? 'blank' : v}. Deactivate a doomsday machine to reroll? ($machines active)',
            intent: v <= 1 ? Intent.help : Intent.harm)) {
      machines--;
      v = await super.rollDie(why);
    }
    return v;
  }

  @override
  int moveValue(Game g, Fighter f, int v) => f == krang ? 1 + machines : v;

  @override
  List<String> status() => ['MACHINES $machines/3'];

  @override
  Map<String, CardScript> get cards => {
        'ANDROID ARMS: WINGS': CardScript(effect: (x) async {
          final n = await rollDie('Wings');
          final path = await x.move(krang, n, throughOpp: true);
          for (final f in x.game.movedThrough(path, x.me)) {
            await x.damage(f, 1);
          }
          x.gainActions(1);
        }),
        'MOLECULAR AMPLIFICATION UNIT': CardScript(
          immediately: (x) => activate(),
          during: (x) async {
            final n = await rollDie('Molecular Amplification Unit');
            if (n > 0) x.addValue(n, 'Die of Ultimate Destruction');
          },
        ),
        'ANDROID ARMS: MISSILES': CardScript(
          target: (g, a, t) => a == krang && a.onBoard && t.onBoard && g.board.sharesZone(a.space!, t.space!),
          during: (x) async {
            final n = await rollDie('Missiles');
            if (n > 0) x.addValue(n, 'Die of Ultimate Destruction');
          },
        ),
        'WARLORD OF DIMENSION X': CardScript(after: (x) async {
          if (x.me.deck.isEmpty) return;
          final mine = x.me.deck.first;
          final theirs = x.opp.deck.firstOrNull;
          await x.game.emit(Revealed(x.me, [mine], ' from the top of their deck'));
          if (theirs != null) await x.game.emit(Revealed(x.opp, [theirs], ' from the top of their deck'));
          int len(Card c) => c.def.upperTitle.replaceAll(RegExp('[^A-Z0-9]'), '').length;
          if (theirs == null || len(mine) > len(theirs)) await x.draw(1);
        }),
        'ANDROID ARMS: CHAIN FLAIL': CardScript(after: (x) async {
          final oc = x.oppCard;
          if (oc == null) {
            await x.discard(x.opp, 2);
            return;
          }
          final n = await rollDie('Chain Flail');
          if ((oc.def.value ?? 0) < n) await x.discard(x.opp, 2);
        }),
        'ANDROID ARMS: POWERBOMB': CardScript(
          during: (x) => x.boostThis(),
          after: (x) async {
            if (x.damageDealt > 0) await pushOpponent(x, x.damageDealt);
          },
        ),
        'IQ OF 968': CardScript(effect: (x) async {
          await activate(3);
          await x.draw(await rollDie('IQ of 968: draw'));
          await x.heal(krang, await rollDie('IQ of 968: recover'));
        }),
        'MINIMIZER': CardScript(
          immediately: (x) async {
            if (x.oppCard != null) x.game.addOp(x.oppSide, const ValueOp.add(-4, 'Minimizer'));
          },
          after: (x) async => x.game.endTurn(),
        ),
        'PAN-DIMENSIONAL PORTAL': CardScript(after: (x) async {
          final f = await x.chooseFighter([x.fighter, x.oppFighter].where((f) => f.onBoard), 'Place a fighter in the combat in any space');
          if (f != null) {
            await x.place(f, x.allSpaces);
            x.game.addTurnMod(TurnMod(name: 'Pan-dimensional Portal', cannotLeaveFn: (g, o) => o == f));
          }
          final n = await rollDie('Pan-dimensional Portal');
          for (final p in [x.me, x.opp]) {
            final pick = (List.of(p.hand)..shuffle(x.game.rng)).take(n).toList();
            for (final c in pick) {
              await x.game.toDeck(c, bottom: true);
            }
          }
          await x.draw(2);
          await x.draw(2, x.opp);
        }),
        'WELCOME TO THE TECHNODROME!': CardScript(immediately: (x) async {
          if (await x.option(["Cancel all effects on your opponent's card", 'Activate a machine'], 'Welcome to the Technodrome!: choose one') == 0) {
            x.cancelOpponent();
          } else {
            await activate();
          }
        }),
      };
}

