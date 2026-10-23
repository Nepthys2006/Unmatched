/// More Battle of Legends heroes: Bloody Mary (Vol. 2), Chupacabra and Pandora (Vol. 3).
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ============================================================================== Bloody Mary

/// At the start of your turn, if you have exactly 3 cards in hand, gain 1 action.
class BloodyMary extends HeroScript {
  Fighter get mary => me.heroFighter;

  /// The printed value of the card played against Bloody Requiem (for Bloody Reprise).
  int? _reprise;

  /// "If this is your third action this turn" (actions are counted once they finish).
  bool thirdAction(Game g) => g.active == me && g.turn.actionsTaken == 2;

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active == me && me.hand.length == 3) {
      await g.say('Bloody Mary: exactly 3 cards in hand, gain 1 action.');
      g.gainActions(me, 1);
    }
  }

  @override
  Map<String, CardScript> get cards => {
    'SPEAK THREE TIMES': CardScript(during: (x) async {
      if (thirdAction(x.game)) x.setValue(7, 'Third action');
    }),
    'STOLEN MEMORIES': CardScript(effect: (x) async {
      final t = x.opp;
      if (!await x.game.lookAtHand(x.me, t) || t.hand.isEmpty) return;
      final c = await x.game.chooseCard(x.me, t.hand, 'Stolen Memories: choose a card in ${t.name}\'s hand', intent: Intent.harm, source: x.card);
      if (c == null) return;
      final boost = x.game.boostValueOf(c);
      final drop = await x.game.yesNo(t, 'Stolen Memories: discard ${c.title}? If you keep it, your hero takes $boost damage.', intent: Intent.loseOwn, source: x.card);
      if (drop) {
        await x.game.discardCard(c, reason: ' (Stolen Memories)', byOpponent: true);
      } else if (t.heroFighter.alive) {
        await x.damage(t.heroFighter, boost);
      }
    }),
    'BLOODY REQUIEM': CardScript(after: (x) async {
      _reprise = x.oppCard?.def.value;
      await x.game.bonusAttack(x, 'Bloody Reprise', 0);
    }),
    // The bonus attack printed on Bloody Requiem.
    'BLOODY REPRISE': CardScript(during: (x) async {
      final v = _reprise;
      if (v != null) x.setValue(v, 'Printed value played against Bloody Requiem');
    }),
    'INFINITY MIRROR': CardScript(after: (x) => moveCombatant(x, 4)),
    'OUT OF THE MIRROR': CardScript(
      during: ambush,
      after: (x) async {
        if (thirdAction(x.game)) await x.draw(1);
      },
    ),
    'BROKEN GLASS': CardScript(
      during: (x) async {
        final i = await x.option(['+1', '-1', 'Leave it'], 'Broken Glass: change this card\'s value by 1?');
        if (i == 0) x.addValue(1, 'Broken Glass');
        if (i == 1) x.addValue(-1, 'Broken Glass');
      },
      after: (x) async {
        if (x.oppCard == null) return;
        if (x.game.valueOf(x.mySide).total != x.game.valueOf(x.oppSide).total) return;
        await x.draw(1);
        if (x.oppFighter.onBoard) await x.damage(x.oppFighter, 2);
      },
    ),
    'CLOSER THAN SHE APPEARS': CardScript(effect: (x) async {
      await x.move(mary, 1);
      await x.draw(1);
      x.gainActions(1);
    }),
    'EVADE': drawAfter(1),
    'GHOSTLY TOUCH': CardScript(
      during: (x) async => x.boostThis(),
      after: (x) async {
        if (thirdAction(x.game) && mary.alive) await x.heal(mary, 3);
      },
    ),
    'JUMP SCARE': CardScript(during: (x) async {
      final start = x.game.turn.startSpace[mary];
      if (start != null && mary.onBoard && !x.board.sharesZone(start, mary.space!)) x.setValue(6);
    }),
    'MIRROR IMAGE': CardScript(during: (x) async => x.setValue(x.oppCard?.def.value ?? 0, 'Printed value of the opposing card')),
    'TRICK OF THE LIGHT': CardScript(after: (x) async {
      final o = x.oppFighter;
      if (!mary.onBoard || !o.onBoard) return;
      await x.place(mary, x.board.neighbours(o.space!).where(x.game.isEmpty), text: 'You may place Bloody Mary next to ${o.name}', optional: true);
    }),
  };
}

// =============================================================================== Chupacabra

/// THE HUNGER: after you attack, you may draw a card.
class Chupacabra extends HeroScript {
  Fighter get chupa => me.heroFighter;
  bool get wounded => chupa.hp <= 7;

  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (c.won(me)) g.turn.flags['chupaWon'] = true;
  }

  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    if (p == me && kind == ActionKind.attack && await g.yesNo(me, 'The Hunger: draw a card?', intent: Intent.help)) await g.draw(me, 1);
  }

  @override
  Map<String, CardScript> get cards => {
    'WOUNDED BEAST': CardScript(during: (x) async {
      if (wounded) x.setValue(5);
    }),
    'BLOOD IN THE AIR': CardScript(during: (x) async {
      if (x.game.turn.flags['chupaWon'] == true) await x.boostThis();
    }),
    'FEEDING': CardScript(after: (x) async {
      if (!wounded) return;
      x.gainActions(1);
      await x.heal(chupa, 1);
    }),
    'NATURAL TOUGHNESS': CardScript(after: (x) async {
      if (x.lost) await x.game.toHand(x.card!, reason: ' (Natural Toughness)');
    }),
    'RAVENOUS LUNGE': CardScript(after: (x) => x.heal(chupa, x.won ? 2 : 1)),
    'TRAVELER OF THE NIGHT': CardScript(effect: (x) async {
      await x.move(x.fighter, 4, throughOpp: true);
      x.gainActions(1);
    }),
    'THE MORE THEY STRUGGLE': CardScript(during: (x) async => x.setValue(2 * (x.oppCard?.def.value ?? 0), 'Twice the printed value of their card')),
    'UNSETTLE': CardScript(effect: (x) async {
      if (!chupa.onBoard) return;
      final valid = x.opponents.where((o) => o.onBoard.any((f) => x.sameZone(f, chupa))).toList();
      if (valid.isEmpty) return;
      final t = valid.contains(x.target) ? x.target! : (valid.length == 1 ? valid.first : null) ??
          await x.game.choose<Player>(x.me, Ask.option, 'Unsettle: choose an opponent with a fighter in Chupacabra\'s zone',
              [for (final o in valid) Choice(o.name, o)], intent: Intent.harm, source: x.card);
      if (t == null) return;
      final hurt = chupa.hp > 2 && await x.yesNo('Unsettle: deal 2 damage to Chupacabra to make ${t.name} discard 2 cards?', intent: Intent.loseOwn);
      if (hurt) await x.damage(chupa, 2);
      await x.discard(t, hurt ? 2 : 1);
    }),
    'TOOTH AND TAIL': CardScript(after: (x) async {
      if (!chupa.onBoard) return;
      // Up to 2 adjacent fighters, chosen one at a time.
      var healed = 0;
      final left = x.adjacentTo(chupa).toList();
      for (var k = 0; k < 2 && left.isNotEmpty; k++) {
        final f = await x.chooseFighter(left, 'Tooth and Tail: deal 1 damage to a fighter next to Chupacabra (${k + 1} of up to 2)',
            intent: Intent.harm, optional: k > 0);
        if (f == null) break;
        left.remove(f);
        if (await x.damage(f, 1) > 0) healed++;
      }
      if (healed > 0) await x.heal(chupa, healed);
    }),
  };
}

// ================================================================================== Pandora

/// One card of Pandora's Box.
typedef Misery = ({String name, int feathers, String text});

const miseries = <Misery>[
  (name: 'Toil', feathers: 1, text: "Add +1 to the value of Pandora's attacks this turn."),
  (name: 'Greed', feathers: 1, text: 'Draw 1 card.'),
  (name: 'Pain', feathers: 1, text: 'Deal 1 damage to each opposing fighter adjacent to Pandora.'),
  (name: 'Misfortune', feathers: 2, text: ''),
  (name: 'Woe', feathers: 0, text: "Summon a Kakodaemon in Pandora's zone."),
  (name: 'Confusion', feathers: 0, text: 'Move Pandora up to 1 space.'),
  (name: 'Hope', feathers: 0, text: "Look at the top card of Pandora's Box before deciding whether to reveal it."),
];

/// PANDORA'S BOX: Kakodaemons don't start on the board. At the start of your turn, open the box:
/// reveal the top MISERY and resolve it; keep revealing one at a time until you stop. At 3 or
/// more feathers revealed you must stop, and Pandora takes 1 damage per revealed MISERY. At the
/// end of your turn the revealed MISERIES are shuffled back in.
class Pandora extends HeroScript {
  Fighter get pandora => me.heroFighter;
  Iterable<Fighter> get kakos => me.fighters.where((f) => f.isSidekick);
  final List<Misery> box = [];
  final List<Misery> revealed = [];
  int get feathers => revealed.fold(0, (n, m) => n + m.feathers);

  @override
  bool startsInReserve(Fighter f) => f.isSidekick;

  @override
  Future<void> beforeDeck() async {
    box
      ..addAll(miseries)
      ..shuffle(game.rng);
  }

  @override
  List<String> status() => [
    if (revealed.isNotEmpty) 'Box: ${revealed.map((m) => m.name).join(', ')} (${'🪶' * feathers})',
  ];

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || !pandora.onBoard) return;
    await g.say("Pandora opens Pandora's Box.");
    var first = true;
    while (box.isNotEmpty) {
      if (!first) {
        final hope = revealed.any((m) => m.name == 'Hope');
        final peek = hope ? ' (Hope: the next one is ${box.first.name})' : '';
        if (!await g.yesNo(me, "Reveal another MISERY?$peek  $feathers feather${feathers == 1 ? '' : 's'} so far; at 3 you must stop and take 1 damage per MISERY.",
            intent: Intent.none)) {
          break;
        }
      }
      first = false;
      final m = box.removeAt(0);
      revealed.add(m);
      await g.emit(StatusChanged(me, 'MISERY: ${m.name.toUpperCase()}${m.feathers > 0 ? ' (${'🪶' * m.feathers})' : ''}${m.text.isEmpty ? '' : ' - ${m.text}'}'));
      await _resolve(g, m);
      if (feathers >= 3) {
        await g.say('Three feathers: the box slams shut. Pandora takes ${revealed.length} damage.');
        await g.damage(pandora, revealed.length, info: DamageInfo(by: me));
        break;
      }
      if (!pandora.onBoard) break;
    }
  }

  Future<void> _resolve(Game g, Misery m) async {
    switch (m.name) {
      case 'Toil':
        g.addTurnMod(TurnMod(
          name: 'Toil',
          valueOpsFn: (g, s) => s.player == me && s.isAttacker && s.fighter == pandora ? const [ValueOp.add(1, 'Toil')] : const [],
        ));
      case 'Greed':
        await g.draw(me, 1);
      case 'Pain':
        for (final f in g.adjacentFighters(pandora).where((f) => f.isEnemyOf(me)).toList()) {
          await g.damage(f, 1, info: DamageInfo(by: me, source: pandora));
        }
      case 'Woe':
        final k = kakos.where((f) => f.defeated || f.reserve).firstOrNull;
        if (k == null || !pandora.onBoard) return;
        final spaces = g.board.zoneOf(pandora.space!).where(g.isEmpty).toList();
        final s = await g.chooseSpace(me, spaces, "Woe: summon a Kakodaemon in Pandora's zone", intent: Intent.moveOwn, subject: k);
        if (s != null) await g.revive(k, s);
      case 'Confusion':
        await g.moveFighter(pandora, 1, chooser: me);
    }
  }

  @override
  Future<void> endOfTurn(Game g, Player active) async {
    if (active != me || revealed.isEmpty) return;
    box
      ..addAll(revealed)
      ..shuffle(g.rng);
    revealed.clear();
    await g.emit(StatusChanged(me, "The MISERIES are shuffled back into Pandora's Box."));
  }

  @override
  Map<String, CardScript> get cards => {
    'DIVINE INTERVENTION': CardScript(after: (x) async {
      if (pandora.onBoard) await x.move(pandora, 5);
    }),
    'FORGED BY HEPHAESTUS': CardScript(effect: (x) async {
      await x.place(x.fighter, x.allSpaces, text: 'Place ${x.fighter.name} in any space');
      x.gainActions(1);
    }),
    "HERA'S CURIOSITY": CardScript(
      during: (x) async {
        if (revealed.isNotEmpty) x.addValue(revealed.length, '${revealed.length} revealed MISERIES');
      },
      after: (x) async => x.game.lookAtHand(x.me, x.opp),
    ),
    'SPITE': CardScript(after: (x) async {
      if (!x.fighter.onBoard) return;
      for (final f in x.adjacentTo(x.fighter).toList()) {
        await x.damage(f, 1);
      }
    }),
    'HINDSIGHT': CardScript(after: (x) async {
      if (!x.won || x.me.discard.isEmpty) return;
      final c = await x.game.chooseCard(x.me, x.me.discard, 'Hindsight: put a card from your discard pile on top of your deck', intent: Intent.help, source: x.card);
      if (c != null) await x.game.toDeck(c);
    }),
    'MALICE': oppDiscardsAfter(1),
    'OFFERING TO THE GODS': CardScript(
      during: (x) async => x.boostThis(),
      after: (x) async {
        if (x.won && x.oppFighter.onBoard) await x.damage(x.oppFighter, 2);
      },
    ),
    "ZEUS'S MISCHIEF": CardScript(effect: (x) async {
      if (revealed.isNotEmpty) await x.draw(revealed.length);
      final f = await x.chooseFighter(x.enemies.toList(), "Zeus's Mischief: move an opposing fighter up to 1 space", intent: Intent.moveEnemy);
      if (f != null) await x.move(f, 1);
      x.gainActions(1);
    }),
    "APHRODITE'S BEAUTY": CardScript(
      immediately: (x) async => x.cancelOpponent(),
      after: (x) async {
        if (revealed.isNotEmpty && pandora.alive) await x.heal(pandora, revealed.length);
      },
    ),
    'GUIDED BY THE FATES': CardScript(
      during: (x) async => discardTopAndAdd(x),
      after: (x) async {
        if (x.won && pandora.alive) await x.heal(pandora, 2);
      },
    ),
    'CELESTIAL RAIMENTS': CardScript(during: (x) async => x.ignoreOpponentValue()),
  };
}
