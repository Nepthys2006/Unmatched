/// Bruce Lee (Bruce Lee) and Muhammad Ali (Muhammad Ali vs Bruce Lee).
library;

import '../combat.dart';
import '../defs.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ================================================================================ Bruce Lee

/// At the end of your turn, you may move Bruce Lee 1 space.
class BruceLee extends HeroScript {
  Fighter get bruce => me.heroFighter;

  static bool isJkd(Card c) => c.def.upperTitle.startsWith('JEET KUNE DO');

  @override
  Future<void> endOfTurn(Game g, Player active) async {
    if (active != me || !bruce.onBoard) return;
    await g.moveFighter(bruce, 1, chooser: me, text: 'You may move Bruce Lee 1 space (tap him to stay)');
  }

  /// "Choose a JEET KUNE DO card in your discard pile and add it to your hand."
  Future<void> _jkdFromDiscard(Fx x) async {
    final opts = x.me.discard.where(isJkd).toList();
    final c = await x.game.chooseCard(x.me, opts, 'Choose a JEET KUNE DO card to return to your hand', intent: Intent.help, source: x.card);
    if (c != null) await x.game.toHand(c, reason: ' (${x.card!.title})');
  }

  @override
  Map<String, CardScript> get cards => {
    'BE LIKE WATER': CardScript(after: _jkdFromDiscard),
    'JEET KUNE DO: CORKSCREW FINGER JAB': CardScript(after: (x) async {
      if (x.oppFighter.onBoard) await x.damage(x.oppFighter, 1);
      x.gainActions(1);
    }),
    'TASTE OF BLOOD': CardScript(after: (x) async {
      if (bruce.hp <= 5) await x.draw(3);
    }),
    'JEET KUNE DO: DOWNWARD SIDE KICK': CardScript(after: (x) async {
      await x.discard(x.opp, 1, random: true);
      x.gainActions(1);
    }),
    'JEET KUNE DO: INTERCEPTING FIST': CardScript(immediately: (x) async => x.cancelOpponent(), after: (x) async => x.gainActions(1)),
    'ONE-INCH PUNCH': CardScript(effect: (x) async {
      final opts = x.adjacentTo(bruce).toList();
      final f = await x.chooseFighter(opts, 'One-Inch Punch: deal 2 damage to an adjacent fighter', intent: Intent.harm);
      if (f == null) return;
      await x.damage(f, 2);
      if (f.defeated) await x.game.toHand(x.card!, reason: ' (One-Inch Punch defeated ${f.name})');
    }),
    'JEET KUNE DO: WRIST LOCK': CardScript(after: (x) async {
      await x.draw(1);
      x.gainActions(1);
    }),
    'LITTLE DRAGON': CardScript(
      during: (x) async {
        if (x.me.hand.isEmpty) x.setValue(6, 'Little Dragon (empty hand)');
      },
      after: (x) => x.draw(2),
    ),
    '"HOO! WHAAAAAA!"': CardScript(effect: (x) async {
      await _jkdFromDiscard(x);
      x.gainActions(1);
    }),
    'BRING IT ON': CardScript(effect: (x) async {
      final opts = enemiesInZone(x, bruce).toList();
      final f = await x.chooseFighter(opts, 'Bring It On: choose an opposing fighter in Bruce Lee\'s zone', intent: Intent.moveEnemy);
      if (f != null) {
        final spaces = x.board.neighbours(bruce.space!).where(x.game.isEmpty);
        await x.place(f, spaces, text: 'Place ${f.name} adjacent to Bruce Lee');
      }
      x.gainActions(1);
    }),
    'JEET KUNE DO: HIGH STRAIGHT LEAD': CardScript(
      during: (x) async {
        if (x.game.startedTurnElsewhere(x.fighter) || x.game.startedTurnElsewhere(x.oppFighter)) x.setValue(5);
      },
      after: (x) async => x.gainActions(1),
    ),
    'JEET KUNE DO: SHORT LEAD HOOK': CardScript(after: (x) async {
      if (bruce.onBoard && x.oppFighter.onBoard && await x.yesNo('Swap spaces with ${x.oppFighter.name}?', intent: Intent.moveOwn)) {
        await x.game.swap(bruce, x.oppFighter);
      }
      x.gainActions(1);
    }),
    'NUNCHAKU': CardScript(effect: (x) async {
      x.game.addTurnMod(TurnMod(
        name: 'Nunchaku',
        valueOpsFn: (g, s) => s.player == me && s.isAttacker && s.fighter == bruce ? const [ValueOp.add(1, 'Nunchaku')] : const [],
      ));
      x.gainActions(1);
    }),
  };
}

// ============================================================================ Muhammad Ali

/// Begin with your stance on FLOAT LIKE A BUTTERFLY (Ali can attack from 2 spaces away). After
/// you attack, if you won the combat, change stances (STING LIKE A BEE: +2 to your attacks).
/// Effects marked with a butterfly only work in the butterfly stance.
class MuhammadAli extends HeroScript {
  bool butterfly = true;
  Fighter get ali => me.heroFighter;

  @override
  List<String> status() => [butterfly ? 'Float like a butterfly' : 'Sting like a bee'];

  @override
  bool canAlsoTarget(Game g, Fighter attacker, Fighter target) =>
      butterfly && attacker == ali && target.isEnemyOf(me) && g.board.distance(attacker.space!, target.space!) <= 2;

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (!butterfly && s.player == me && s.isAttacker && s.fighter == ali) yield const ValueOp.add(2, 'Sting like a bee');
  }

  @override
  Future<void> onDamaged(Game g, Fighter f, int amount, DamageInfo info) async {
    // The Greatest counts the combat damage you dealt this turn.
    if (info.combat && info.source?.owner == me) {
      g.turn.flags['aliCombatDamage'] = ((g.turn.flags['aliCombatDamage'] as int?) ?? 0) + amount;
    }
  }

  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (c.won(me)) g.turn.flags['aliWon'] = true;
    if (c.attacker.player == me && c.attackerWon) {
      butterfly = !butterfly;
      await g.emit(StatusChanged(me, 'Ali changes stance: ${butterfly ? 'FLOAT LIKE A BUTTERFLY' : 'STING LIKE A BEE'}.'));
    }
  }

  @override
  Map<String, CardScript> get cards => {
    'JAB': CardScript(after: (x) async {
      await x.draw(1);
      x.gainActions(1);
      if (butterfly && x.fighter.onBoard) await x.move(x.fighter, 2);
    }),
    'ANSWER THE BELL': CardScript(effect: (x) async {
      await x.move(ali, 3);
      await x.heal(ali, 2);
      x.gainActions(1);
    }),
    'STICK AND MOVE': CardScript(
      during: (x) async {
        if (butterfly) x.oppSide.lockPrinted = true;
      },
      after: (x) async {
        if (!x.fighter.onBoard) return;
        final f = await x.chooseFighter(x.adjacentTo(x.fighter).toList(), 'Deal 1 damage to an adjacent fighter', intent: Intent.harm);
        if (f != null) await x.damage(f, 1);
      },
    ),
    'ALI SHUFFLE': CardScript(
      during: (x) async {
        if (butterfly) await x.boostThis();
      },
      after: (x) async {
        if (!x.won) return;
        final opts = x.me.discard.where((c) => c.def.type != CardType.scheme).toList();
        final c = await x.game.chooseCard(x.me, opts, 'Ali Shuffle: shuffle a non-scheme card from your discard pile into your deck',
            intent: Intent.help, source: x.card);
        if (c != null) await x.game.toDeck(c, shuffle: true);
      },
    ),
    'CLOSE AND CLINCH': CardScript(immediately: (x) async {
      final opp = x.oppFighter;
      if (!ali.onBoard || !opp.onBoard) return;
      final spaces = {
        ...x.board.neighbours(opp.space!).where(x.game.isEmpty),
        if (x.board.adjacent(ali.space!, opp.space!)) ali.space!,
      };
      await x.place(ali, spaces, text: 'Place Ali adjacent to ${opp.name}');
      x.game.addTurnMod(TurnMod(name: 'Close and Clinch', cannotLeaveFn: (g, f) => f == ali || f == opp));
    }),
    'FANCY FOOTWORK': CardScript(
      immediately: (x) async => x.move(ali, 1),
      during: (x) async {
        if (ali.onBoard && x.oppFighter.onBoard && !x.sameZone(ali, x.oppFighter)) x.ignoreOpponentValue();
      },
    ),
    'HARD TO BE HUMBLE': CardScript(
      during: (x) async {
        if (butterfly) await x.game.lookAtHand(x.me, x.opp);
      },
      after: (x) async => x.move(ali, 2),
    ),
    'LOUISVILLE LIP': CardScript(effect: (x) async {
      await x.heal(ali, 1);
      await x.draw(2);
      if (x.game.turn.flags['aliWon'] == true) {
        for (final o in x.opponents.toList()) {
          await x.discard(o, 1, random: true);
        }
      }
    }),
    'ROPE-A-DOPE': CardScript(after: (x) async {
      if (butterfly && x.lost) await x.heal(ali, 3);
    }),
    'CHAMPION OF THE WORLD': CardScript(after: (x) async {
      await moveCombatant(x, 2);
      if (butterfly) await x.draw(1);
    }),
    'STRONGER THAN THE SKILL': CardScript(after: (x) async {
      final looked = await x.game.lookAtHand(x.me, x.opp);
      if (!x.won || !looked || x.opp.hand.isEmpty) return;
      final c = await x.game.chooseCard(x.me, x.opp.hand, 'Shuffle one of ${x.opp.name}\'s cards into their deck',
          intent: Intent.harm, source: x.card);
      if (c != null) await x.game.toDeck(c, shuffle: true);
    }),
    'THE GREATEST': CardScript(after: (x) async {
      if (((x.game.turn.flags['aliCombatDamage'] as int?) ?? 0) >= 6) x.gainActions(2);
    }),
  };
}
