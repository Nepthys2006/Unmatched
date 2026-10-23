/// Jurassic Park: Raptors, Robert Muldoon (InGen vs Raptors), Dr. Sattler, T. Rex (Sattler vs T. Rex).
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ================================================================================== Raptors

/// The Raptors are three fighters and each is a hero (no sidekicks); you lose only when the
/// last one is defeated. Raptors add 1 to the value of their attack cards for each of your other
/// Raptors adjacent to the defender.
class Raptors extends HeroScript {
  Iterable<Fighter> get pack => me.fighters.where((f) => f.isHero);
  Iterable<Fighter> get alive => pack.where((f) => f.onBoard);

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player != me || !s.isAttacker) return;
    final defender = s.other.fighter;
    final n = alive.where((r) => r != s.fighter && g.adjacent(r, defender)).length;
    if (n > 0) yield ValueOp.add(n, 'Pack: $n other Raptor${n == 1 ? '' : 's'} adjacent');
  }

  /// The other two Raptors start in the first one's zone, like sidekicks.
  @override
  Future<void> placeSidekicks() async {
    final first = me.heroFighter;
    for (final f in pack.where((f) => f != first)) {
      final options = game.board.zoneOf(first.space!).where(game.isEmpty).toList();
      final spaces = options.isNotEmpty ? options : game.emptySpaces().toList();
      final s = await game.chooseSpace(me, spaces, 'Place ${f.name} in ${first.name}\'s zone', intent: Intent.moveOwn, subject: f);
      if (s != null) {
        f.space = s;
        await game.emit(FighterPlacedAtStart(f));
      }
    }
  }

  @override
  Map<String, CardScript> get cards => {
    'DISENGAGE': CardScript(after: (x) async {
      final f = x.fighter;
      if (!f.onBoard) return;
      await x.place(f, x.zoneSpaces(f).where((s) => s != f.space && x.game.isEmpty(s)), text: 'Move ${f.name} to another space in her zone');
    }),
    'EVISCERATE': vanilla,
    'PACK HUNTERS': CardScript(after: (x) async {
      final o = x.oppFighter;
      if (!x.won || !o.onBoard) return;
      final n = alive.where((r) => x.adjacent(r, o)).length;
      if (n > 0) await x.damage(o, n);
    }),
    'WORKING THINGS OUT': CardScript(effect: (x) async {
      await moveEach(x, alive, 3, through: true);
      x.gainActions(1);
    }),
    'COORDINATED ATTACK PATTERN': CardScript(effect: (x) async {
      final lead = await x.chooseFighter(alive.toList(), 'Choose one of your Raptors');
      if (lead == null) return;
      for (final r in alive.where((r) => r != lead).toList()) {
        await x.place(r, x.zoneSpaces(lead), text: 'You may place ${r.name} in ${lead.name}\'s zone', optional: true);
      }
    }),
    'DECOY': CardScript(immediately: (x) async {
      final others = alive.where((r) => r != x.fighter).toList();
      final r = await x.chooseFighter(others, 'Decoy: choose one of your other Raptors');
      final o = x.oppFighter;
      if (r == null || !o.onBoard) return;
      await x.place(r, x.board.neighbours(o.space!).where(x.game.isEmpty), text: 'You may place ${r.name} next to ${o.name}', optional: true);
    }),
    'EATEN ALIVE': CardScript(after: (x) async {
      if (!x.won || !x.fighter.onBoard) return;
      final f = await x.chooseFighter(x.enemiesAdjacentTo(x.fighter).toList(), 'Eaten Alive: deal 1 damage to an adjacent opposing fighter', intent: Intent.harm);
      if (f != null) await x.damage(f, 1);
    }),
    'THEY REMEMBER': CardScript(after: (x) async => x.gainActions(1)),
    'CLEVER GIRL': CardScript(after: (x) async {
      if (x.oppFighter.onBoard && alive.any((r) => x.adjacent(r, x.oppFighter))) x.gainActions(1);
    }),
  };
}

// =========================================================================== Robert Muldoon

/// At the start of your turn, you may place a trap (in an unoccupied, token-free space in
/// Muldoon's zone). Muldoon has 8 traps for the whole game. When an opposing fighter enters a
/// trapped space (moving, or moved/placed by anyone) it stops and takes 1 damage, and the trap
/// goes back to the box. Whenever one of your traps returns to the box, draw a card.
class Muldoon extends HeroScript {
  static const totalTraps = 8;
  int placed = 0;
  Fighter get muldoon => me.heroFighter;
  Iterable<Fighter> get workers => me.fighters.where((f) => f.isSidekick);

  Iterable<Token> get traps => game.board.tokens.where((t) => t.kind == 'trap' && t.owner == me);
  bool trapAt(int s) => traps.any((t) => t.space == s);
  int get supply => totalTraps - placed;

  @override
  List<String> status() => ['$supply trap${supply == 1 ? '' : 's'} left'];

  Iterable<int> get trapSpaces {
    if (!muldoon.onBoard) return const [];
    return game.board.zoneOf(muldoon.space!).where((s) => game.isEmpty(s) && !game.board.tokens.any((t) => t.space == s));
  }

  Future<bool> placeTrap({bool optional = true, String? text}) async {
    if (supply <= 0) return false;
    final s = await game.chooseSpace(me, trapSpaces, text ?? "You may place a trap in Muldoon's zone", intent: Intent.none, optional: optional);
    if (s == null) return false;
    game.board.tokens.add(Token('trap', me, space: s));
    placed++;
    await game.emit(StatusChanged(me, 'Muldoon sets a trap ($supply left).'));
    return true;
  }

  /// A trap leaves the board: it goes back in the box and Muldoon draws a card.
  Future<void> returnTrap(Token t) async {
    game.board.tokens.remove(t);
    await game.say('A trap is returned to the box.');
    await game.draw(me, 1);
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active == me) await placeTrap();
  }

  @override
  int? stopMove(Game g, Fighter f, List<int> path) {
    if (!f.isEnemyOf(me)) return null;
    // Only where it could end its move: passing through a fighter standing on a trap doesn't
    // stop it there.
    for (var i = 1; i < path.length; i++) {
      if (trapAt(path[i]) && (g.fighterAt(path[i]) == null || g.fighterAt(path[i]) == f)) return i;
    }
    return null;
  }

  @override
  Future<void> entered(Game g, Fighter f, int space) async {
    if (!f.isEnemyOf(me)) return;
    final t = traps.where((t) => t.space == space).firstOrNull;
    if (t == null) return;
    await g.say('${f.name} springs a trap!');
    await g.damage(f, 1, info: DamageInfo(by: me));
    await returnTrap(t);
  }

  @override
  Map<String, CardScript> get cards => {
    'CALL FOR BACKUP': CardScript(effect: (x) async {
      const options = ['Place up to 3 traps', "Place all defeated InGen Workers in Muldoon's zone", 'Draw 2 cards'];
      for (final i in await chooseDifferent(x, options, 2, 'Call for Backup: choose 2 different effects')) {
        switch (i) {
          case 0:
            for (var k = 0; k < 3; k++) {
              if (!await placeTrap(text: 'Place a trap (${k + 1} of up to 3)')) break;
            }
          case 1:
            for (final w in workers.where((w) => w.defeated).toList()) {
              if (!muldoon.onBoard) break;
              final spaces = x.zoneSpaces(muldoon).where(x.game.isEmpty).toList();
              final s = await x.chooseSpace(spaces, "Place ${w.name} in Muldoon's zone", intent: Intent.moveOwn, subject: w);
              if (s != null) await x.game.revive(w, s);
            }
          case 2:
            await x.draw(2);
        }
      }
    }),
    'SHOOT HER!': CardScript(during: (x) async {
      if (x.game.turn.actionsTaken == 0 && x.game.active == x.me) x.setValue(5);
    }),
    'REMOTE DETONATION': CardScript(effect: (x) async {
      final zone = {
        for (final w in workers.where((w) => w.onBoard)) ...x.game.board.zoneOf(w.space!),
      };
      final opts = {for (final t in traps.where((t) => zone.contains(t.space))) t.space!};
      final s = await x.chooseSpace(opts, 'Remote Detonation: choose a trap to set off', intent: Intent.harm);
      if (s == null) return;
      for (final f in x.enemies.where((f) => f.onBoard && x.board.adjacent(f.space!, s)).toList()) {
        await x.damage(f, 1);
      }
      final t = traps.where((t) => t.space == s).firstOrNull;
      if (t != null) await returnTrap(t);
    }),
    'THEY SHOULD ALL BE DESTROYED': CardScript(during: (x) async {
      final o = x.oppFighter;
      if (!o.onBoard) return;
      final n = traps.where((t) => x.board.adjacent(t.space!, o.space!)).length;
      if (n > 0) x.addValue(n, '$n trap${n == 1 ? '' : 's'} next to ${o.name}');
    }),
    "I'VE HUNTED MOST THINGS THAT CAN HUNT YOU": CardScript(after: (x) => moveEach(x, x.myFighters, 5, through: true)),
    'RENDING SHOT': CardScript(after: (x) => pushOpponent(x, 3)),
    'TACTICAL ADVANCE': CardScript(after: (x) => moveEach(x, workers, 2)),
    'SECOND SHOT': boostable,
  };
}

// ==================================================================================== T. Rex

/// T. Rex is a large fighter: she occupies her space and the one she last moved from, is in all
/// zones of both and adjacent to everything next to either, may start a move from either, and
/// can attack up to 2 spaces away (even over fighters). At the end of your turn, draw a card.
class TRex extends HeroScript {
  Fighter get rex => me.heroFighter;

  @override
  bool isLarge(Fighter f) => f == rex;

  @override
  Future<void> afterHeroPlaced() => game.placeTail(rex, me);

  @override
  bool canAlsoTarget(Game g, Fighter attacker, Fighter target) {
    if (attacker != rex || !target.isEnemyOf(me) || !rex.onBoard || !target.onBoard) return false;
    return rex.spaces.any((a) => target.spaces.any((b) => g.board.distance(a, b) <= 2));
  }

  @override
  Future<void> endOfTurn(Game g, Player active) async {
    if (active == me) await g.draw(me, 1);
  }

  @override
  Map<String, CardScript> get cards => {
    'RIPPLES IN THE WATER': CardScript(effect: (x) async {
      if (!rex.onBoard) return;
      await x.place(rex, x.zoneSpaces(rex), text: 'Place T. Rex in any space in her zone');
      for (final o in x.opponents.toList()) {
        if (o.onBoard.any((f) => x.adjacent(f, rex))) await x.discard(o, 1, random: true);
      }
    }),
    "YOU'RE JUST MAKING HER ANGRY": CardScript(
      during: (x) async => x.boostThis(),
      after: (x) async {
        if (x.won) await x.game.toHand(x.card!, reason: " (You're Just Making Her Angry)");
      },
    ),
    '65 MILLION YEARS OF GUT INSTINCT': CardScript(effect: (x) async {
      final opts = x.me.discard.where((c) => c.def.upperTitle != '65 MILLION YEARS OF GUT INSTINCT').toList();
      final c = await x.game.chooseCard(x.me, opts, 'Return a card from your discard pile to your hand', intent: Intent.help, source: x.card);
      if (c != null) await x.game.toHand(c, reason: ' (65 Million Years of Gut Instinct)');
    }),
    '15,000 POUNDS OF MUSCLE': CardScript(
      during: (x) async => x.ignoreOpponentValue(),
      after: (x) async {
        if (rex.alive) await x.damage(rex, 2);
      },
    ),
    'CLOSER THAN SHE APPEARS': CardScript(effect: (x) async {
      await x.move(rex, 1);
      await x.draw(1);
      x.gainActions(1);
    }),
    'RECKLESS LUNGE': CardScript(after: (x) async {
      if (x.oppFighter.onBoard) await x.damage(x.oppFighter, 3);
      if (rex.alive) await x.damage(rex, 3);
    }),
    'TERRIFYING ROAR': CardScript(immediately: (x) async {
      x.game.addTurnMod(TurnMod(name: 'Terrifying Roar', cannotLeaveFn: (g, f) => true));
    }),
    'THRASH': CardScript(
      during: (x) async => x.boostThis(),
      after: (x) async {
        if (!x.won || !rex.onBoard) return;
        for (final f in enemiesInZone(x, rex).toList()) {
          await x.damage(f, 1);
        }
      },
    ),
    'WHEN DINOSAURS RULED THE EARTH': CardScript(
      during: (x) async => x.boostThis(),
      after: (x) async {
        if (!x.won) return;
        await x.draw(1);
        x.gainActions(1);
        if (rex.alive) await x.damage(rex, 2);
      },
    ),
  };
}

// ============================================================================== Dr. Sattler

/// Whenever Dr. Sattler or Dr. Malcolm moves to a new space (not when placed), put an insight
/// token there. 5 tokens; they may share spaces; removed ones go back to the supply; with none
/// in supply, nothing happens.
class Sattler extends HeroScript {
  static const totalInsight = 5;
  Fighter get sattler => me.heroFighter;
  Fighter? get malcolm => me.fighters.where((f) => f.isSidekick).firstOrNull;

  Iterable<Token> get insight => game.board.tokens.where((t) => t.kind == 'insight' && t.owner == me);
  int get onBoard => insight.length;

  @override
  List<String> status() => ['${totalInsight - onBoard} insight left'];

  Future<void> putInsight(int space) async {
    if (onBoard >= totalInsight) return;
    game.board.tokens.add(Token('insight', me, space: space));
    await game.emit(StatusChanged(me, 'An insight token is placed ($onBoard on the board).'));
  }

  Future<int> clearInsight() async {
    final n = onBoard;
    game.board.tokens.removeWhere((t) => t.kind == 'insight' && t.owner == me);
    if (n > 0) await game.emit(StatusChanged(me, 'All insight tokens return to the supply.'));
    return n;
  }

  @override
  Future<void> afterMove(Game g, Fighter f, List<int> path) async {
    if (f.owner == me && path.length > 1 && f.onBoard) await putInsight(f.space!);
  }

  @override
  Map<String, CardScript> get cards => {
    'THE CONCEPT OF ATTRACTION': CardScript(after: (x) async {
      final f = x.fighter;
      if (!f.onBoard) return;
      final spaces = {for (final t in insight) t.space!};
      await x.place(f, spaces, text: 'You may place ${f.name} on a space with an insight token', optional: true);
    }),
    "YOU NEVER HAD CONTROL, THAT'S THE ILLUSION": CardScript(during: (x) async {
      final n = onBoard;
      if (n > 0) x.addValue(n, '$n insight token${n == 1 ? '' : 's'}');
      await clearInsight();
    }),
    'CHAOTICIAN': CardScript(after: (x) async {
      if (onBoard >= totalInsight) return;
      final s = await x.chooseSpace(x.allSpaces, 'Chaotician: place an insight token in any space', intent: Intent.none);
      if (s != null) await putInsight(s);
    }),
    'HEY! HEY! HEY!': CardScript(after: (x) async {
      final other = x.myFighters.where((f) => f != x.fighter).firstOrNull;
      if (other != null) await x.move(other, 4);
    }),
    "I THINK WE'RE BACK IN BUSINESS": CardScript(during: (x) async => x.setValue(x.me.hand.length, 'Cards in hand')),
    'LIFE FINDS A WAY': CardScript(after: (x) async {
      final c = await x.game.discardTopOfDeck(x.opp);
      if (c == null) return;
      final n = x.game.boostValueOf(c);
      if (n <= 0) return;
      for (final f in [malcolm, sattler]) {
        if (f != null && f.onBoard) await x.heal(f, n);
      }
    }),
    'LOCK THE DOORS!': CardScript(after: (x) async {
      if (x.oppFighter.onBoard) await x.damage(x.oppFighter, 2);
      if (x.fighter.onBoard) await x.move(x.fighter, 2);
    }),
    'MUST GO FASTER': CardScript(after: (x) async {
      if (!x.won) return;
      for (final f in [malcolm, sattler]) {
        if (f != null && f.onBoard) await x.place(f, x.allSpaces, text: 'You may place ${f.name} in any space', optional: true);
      }
    }),
    'SEXISM IN SURVIVAL SITUATIONS': CardScript(
      during: (x) async {
        if (x.oppFighter.isHero) x.setValue(4);
      },
      after: (x) async {
        if (sattler.onBoard) await x.move(sattler, 1);
      },
    ),
    'THE FUTURE EX-MRS. MALCOLM': CardScript(effect: (x) async {
      await x.draw(2);
      final m = malcolm;
      if (m != null && m.onBoard) await putInsight(m.space!);
      x.gainActions(1);
    }),
    'VIOLENTLY, IF NECESSARY': CardScript(after: (x) async {
      final marked = {for (final t in insight) t.space!};
      bool near(Fighter f) => f.onBoard && (marked.contains(f.space) || marked.any((s) => x.board.adjacent(s, f.space!)));
      for (final f in x.enemies.where(near).toList()) {
        await x.damage(f, 2);
      }
    }),
    'WOMAN INHERITS THE EARTH': CardScript(immediately: (x) async {
      await x.draw(1);
      final n = onBoard;
      if (n > 0 && sattler.onBoard) await x.heal(sattler, n);
      await clearInsight();
    }),
  };
}
