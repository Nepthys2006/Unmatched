/// Marvel: Ghost Rider, Luke Cage (Redemption Row) and Deadpool.
library;

import 'dart:math' as math;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ============================================================================== Ghost Rider

/// Ghost Rider starts the game with 5 Hellfire. When you maneuver you may spend 1 Hellfire: his
/// move value becomes 4, he may move through opposing fighters, and each one he moves through
/// takes 1 damage.
class GhostRider extends HeroScript {
  int hellfire = 5;
  Fighter get rider => me.heroFighter;

  @override
  List<String> status() => ['Hellfire $hellfire'];

  Future<void> gain(int n) async {
    if (n <= 0) return;
    hellfire += n;
    await game.emit(StatusChanged(me, 'Ghost Rider gains $n Hellfire ($hellfire).'));
  }

  Future<bool> spend(int n, String why) async {
    if (hellfire < n) return false;
    hellfire -= n;
    await game.emit(StatusChanged(me, 'Ghost Rider spends $n Hellfire: $why ($hellfire left).'));
    return true;
  }

  /// "You may spend any amount of Hellfire": the player picks how much.
  Future<int> spendAny(String why) async {
    if (hellfire <= 0) return 0;
    final n = await game.chooseNumber(me, 0, hellfire, '$why: how much Hellfire? (you have $hellfire)');
    if (n > 0) await spend(n, why);
    return n;
  }

  @override
  Future<void> maneuverMove(Fighter f, int allowance, {required bool boosted}) async {
    if (f != rider || hellfire <= 0 || !await game.yesNo(me, 'Spend 1 Hellfire to ride? Move 4, through opposing fighters, burning each one (you have $hellfire).', intent: Intent.help)) {
      return super.maneuverMove(f, allowance, boosted: boosted);
    }
    await spend(1, 'the ride');
    final path = await game.moveFighter(f, allowance - me.hero.move + 4, chooser: me, throughOpp: true);
    for (final o in game.movedThrough(path, me)) {
      await game.damage(o, 1, info: DamageInfo(by: me, source: rider));
    }
  }

  @override
  Map<String, CardScript> get cards => {
    'CONTROL THE DEMON': CardScript(during: (x) async {
      if (hellfire > 0) x.addValue(hellfire, '$hellfire Hellfire');
    }),
    'I BROUGHT THE DEVIL WITH ME': CardScript(after: (x) async {
      if (hellfire >= 2 && await x.yesNo('Spend 2 Hellfire to gain 1 action?') && await spend(2, 'an extra action')) x.gainActions(1);
    }),
    'PENANCE STARE': CardScript(during: (x) async {
      final c = x.oppCard;
      if (c == null || c.virtual) return;
      final b = x.game.boostValueOf(c);
      x.addValue(b, 'BOOST of ${c.title}');
      if (hellfire >= 2 && await x.yesNo('Penance Stare: spend 2 Hellfire to add it again (+$b)?') && await spend(2, 'Penance Stare')) {
        x.addValue(b, 'BOOST of ${c.title} again');
      }
    }),
    'DEAL WITH THE DEVIL': CardScript(during: (x) async {
      final n = await spendAny('Deal With the Devil');
      if (n > 0) x.addValue(n, '$n Hellfire');
    }),
    'HELL RIDES WITH ME': CardScript(effect: (x) async {
      final passenger = rider.onBoard
          ? await x.chooseFighter(x.adjacentTo(rider).toList(), 'Hell Rides With Me: also move an adjacent fighter?', optional: true)
          : null;
      if (rider.onBoard) await x.move(rider, 4);
      if (passenger != null && passenger.onBoard) await x.move(passenger, 4);
      await gain(2);
      x.gainActions(1);
    }),
    'SPIRIT OF VENGEANCE': CardScript(after: (x) async {
      if (hellfire >= 1 && await x.yesNo('Spend 1 Hellfire to draw 2 cards?') && await spend(1, 'draw 2')) await x.draw(2);
    }),
    'BLAZE OF GLORY': CardScript(after: (x) async {
      if (!rider.onBoard) return;
      final n = await spendAny('Blaze of Glory (damage to every fighter in his zone, him too)');
      if (n <= 0) return;
      for (final f in x.inZoneOf(rider).toList()) {
        await x.damage(f, n);
      }
    }),
    'CHAINS OF HELLFIRE': CardScript(effect: (x) async {
      hellfire = 5;
      await x.game.emit(StatusChanged(x.me, 'Hellfire is set to 5.'));
    }),
    'I FINALLY ESCAPED HELL': CardScript(after: (x) async {
      if (rider.onBoard && hellfire >= 1 && await x.yesNo('Spend 1 Hellfire to move Ghost Rider up to 2?') && await spend(1, 'move')) {
        await x.move(rider, 2);
      }
    }),
    'STOKE THE FLAMES': CardScript(after: (x) async {
      if (x.lost && x.defending) await gain(x.damageDealt);
    }),
    'THE WICKED WILL BURN': CardScript(after: (x) async {
      if (x.game.startedTurnElsewhere(rider)) await gain(2);
    }),
  };
}

// ================================================================================ Luke Cage

/// Luke Cage takes 2 less combat damage from attacks.
class LukeCage extends HeroScript {
  Fighter get luke => me.heroFighter;
  Fighter? get misty => me.fighters.where((f) => f.isSidekick).firstOrNull;

  @override
  int modifyDamage(Game g, Fighter target, int amount, DamageInfo info) =>
      info.combat && target == luke ? math.max(0, amount - 2) : amount;

  @override
  Map<String, CardScript> get cards => {
    'PUSHBACK': CardScript(after: (x) => pushOpponent(x, 3)),
    'SKIN LIKE TITANIUM': CardScript(after: (x) async {
      if (x.lost && x.defending && x.damageDealt > 0 && x.oppFighter.onBoard) await x.damage(x.oppFighter, x.damageDealt);
    }),
    "WHERE'S MY MONEY?": CardScript(effect: (x) async {
      if (luke.onBoard) {
        final foes = x.enemies.where((f) => f.onBoard).toList();
        if (foes.isNotEmpty) {
          final d = foes.map((f) => x.board.distance(luke.space!, f.space!)).reduce(math.min);
          final nearest = foes.where((f) => x.board.distance(luke.space!, f.space!) == d);
          final spaces = {
            for (final f in nearest) ...x.board.neighbours(f.space!).where((s) => x.game.isEmpty(s) || s == luke.space),
          };
          await x.place(luke, spaces, text: "Where's My Money?: place Luke Cage next to the nearest opposing fighter");
        }
      }
      x.gainActions(1);
    }),
    'GOT MY BACK?': CardScript(immediately: (x) async {
      final m = misty;
      if (m == null || x.fighter != m || !luke.onBoard) return;
      if (await x.yesNo('Got My Back?: swap Misty Knight with Luke Cage? Luke becomes the defender.') && await x.game.swap(m, luke)) {
        x.mySide.fighter = luke;
      }
    }),
    'TRASH TALK': CardScript(
      immediately: (x) async => x.cancelOpponent(),
      after: (x) async {
        if (x.won) x.game.endTurn();
      },
    ),
    'DAUGHTER OF THE DRAGON': CardScript(during: (x) async {
      final m = misty;
      if (m != null && x.adjacent(m, x.oppFighter)) x.setValue(6);
    }),
    'GET PAID': CardScript(after: (x) async {
      if (x.won) await x.draw(2);
    }),
    'HERO FOR HIRE': boostable,
    'SWEET CHRISTMAS!': vanilla,
    'POWER MAN': CardScript(after: (x) async {
      final o = x.oppFighter;
      if (!o.onBoard) return;
      // Through "other opposing fighters": the moved fighter's own allies, which movement already
      // allows; they and each one passed take 1 damage.
      final path = await x.move(o, 3);
      final passed = <Fighter>[
        if (path != null)
          for (final s in path.skip(1).take(math.max(0, path.length - 2)))
            if (x.game.fighterAt(s) case final f? when f.isEnemyOf(x.me) && f != o) f,
      ];
      if (o.onBoard) await x.damage(o, 1);
      for (final f in passed) {
        await x.damage(f, 1);
      }
    }),
    'STILL STANDING': CardScript(after: (x) async {
      if (!x.won || x.me.discard.isEmpty) return;
      final n = math.min(2, x.me.discard.length);
      final cards = await x.game.chooseCards(x.me, x.me.discard, n, n, 'Still Standing: choose $n cards to shuffle into your deck', intent: Intent.help);
      for (final c in cards) {
        await x.game.toDeck(c, shuffle: true);
      }
    }),
  };
}

// ================================================================================= Deadpool

/// After you attack, Deadpool recovers 1 health. Also, if your opponent's real name is Logan, all
/// your attacks are +5. Several cards refer to the real world (food on the table, sounds,
/// sleeves): the player answers, and an AI Deadpool answers the way the card hopes.
class Deadpool extends HeroScript {
  Fighter get wade => me.heroFighter;

  /// Names written on Call Me (by card).
  final Map<int, Set<String>> callMe = {};

  bool _isLogan(Player p) => RegExp(r'\blogan\b', caseSensitive: false).hasMatch(p.label) || p.name.toLowerCase() == 'logan';

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player == me && s.isAttacker && _isLogan(s.other.player)) yield const ValueOp.add(5, 'Your real name is Logan');
  }

  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    if (p == me && kind == ActionKind.attack && wade.alive) await g.heal(wade, 1);
  }

  /// A question about the real world. The AI says yes (it always has a chimichanga).
  Future<bool> ask(Fx x, String q) async => me.isAI || await x.yesNo(q, intent: Intent.none);

  Future<void> say(Fx x, String s) => x.game.emit(StatusChanged(x.me, s));

  @override
  Map<String, CardScript> get cards => {
    'NON-RETINAL SCAN ACCESS TO DANGER ROOM': CardScript(after: (x) async {
      await x.game.lookAtHand(x.me, x.opp);
      await x.heal(wade, 1);
    }),
    'AND FOR MY NEXT MOVE...': CardScript(after: (x) async {
      final i = await x.option(['Deal 2 damage to ${x.oppFighter.name}', 'Move Deadpool up to 3 spaces'], 'And For My Next Move...');
      if (i == 0 && x.oppFighter.onBoard) await x.damage(x.oppFighter, 2);
      if (i == 1 && x.fighter.onBoard) await x.move(x.fighter, 3);
    }),
    'CHIMICHANGA BREAK!': CardScript(during: (x) async {
      if (await ask(x, 'Chimichanga Break!: is there food on the table?')) x.setValue(5, 'Food on the table');
    }),
    'EXPLODING CARD!': CardScript(during: (x) async {
      if (await ask(x, 'Exploding Card!: did you make an exploding noise when you revealed this card?')) {
        await say(x, 'KA-BOOOOM!');
        x.setValue(4, 'Exploding noise');
      }
    }),
    'GIMME GIMME CHIMICHANGA': CardScript(after: (x) async {
      await x.draw(1);
      await x.heal(wade, 1);
    }),
    'I ALWAYS GET THE LAST WORD': CardScript(after: (x) async {
      if (x.attacking && x.oppFighter.onBoard) await x.damage(x.oppFighter, 1);
    }),
    'SWEEET!': CardScript(effect: (x) async {
      // Zones whose colour is yellow-ish.
      bool yellow(String c) {
        final v = int.tryParse(c.replaceAll('#', ''), radix: 16);
        if (v == null) return false;
        final r = (v >> 16) & 255, gr = (v >> 8) & 255, b = v & 255;
        return r > 150 && gr > 120 && b < (r + gr) / 3;
      }

      final zones = {for (final e in x.board.def.zones.entries) if (yellow(e.value.color)) e.key};
      Iterable<int> spaces() => x.allSpaces.where((s) => x.board.zonesOf(s).any(zones.contains) && (x.game.isEmpty(s) || s == wade.space));
      if (zones.isEmpty || !wade.onBoard) {
        await say(x, 'Sweeet!... no yellow-ish zones here. Bummer.');
        return;
      }
      await x.place(wade, spaces(), text: 'Sweeet!: move to a space in a yellow-ish zone');
      final first = wade.space;
      await x.place(wade, spaces().where((s) => s != first), text: 'Sweeet!: now a different space in a yellow-ish zone');
    }),
    'TIME OUT TIME OUT TIME OUT!': CardScript(immediately: (x) async {
      await say(x, 'TIME OUT! TIME OUT! TIME OUT!');
      final s = x.mySide;
      final opts = x.me.deck.where((c) => s.isAttacker ? x.game.canAttackWith(c, s.fighter) : x.game.canDefendWith(c, s.fighter)).toList();
      final pick = await x.game.chooseCard(x.me, opts, 'Time out: pick a card from your deck to play instead', intent: Intent.help, source: x.card);
      if (pick == null) return;
      x.me.deck.remove(pick);
      await x.game.replaceCard(s, pick, oldTo: Zone.discard);
      await x.game.shuffleDeck(x.me);
    }),
    "ROB'S POUCH & SHOE EMPORIUM": CardScript(after: (x) async {
      final o = x.oppFighter;
      if (!o.onBoard) return;
      final room = x.board.neighbours(o.space!).where(x.game.isEmpty).toList();
      if (room.isEmpty || x.game.cannotLeave(o)) return;
      final s = await x.chooseSpace(room, 'Move ${o.name} one space. Just one.', intent: Intent.moveEnemy, subject: o);
      if (s != null) await x.place(o, [s]);
    }),
    'TRANSIT CARD': CardScript(after: (x) async {
      if (wade.onBoard) await x.place(wade, x.zoneSpaces(wade), text: 'Transit Card: move to any space in your zone');
    }),
    "I'VE BEEN HACKED!": CardScript(after: (x) async {
      if (!await x.game.lookAtHand(x.opp, x.me)) return;
      await x.discard(x.me, 1, chooser: x.opp);
    }),
    'THEY HAVE AN AMAZING BUFFET': CardScript(after: (x) async {
      await x.heal(wade, 2);
      if (wade.hp >= wade.maxHp) await x.damage(wade, 2);
    }),
    'UNDERRATED SUPER HEROES': vanilla,
    'WANNA BET?': CardScript(after: (x) async => say(x, 'Wanna bet? Loser of the game buys the winner a drink.')),
    'XAVIER INSTITUTE FACULTY': CardScript(
      target: (g, a, t) => a == wade && a.onBoard && t.onBoard && t.isEnemyOf(me) && g.board.sharesZone(a.space!, t.space!),
    ),
    '3 OF HEARTS': drawAfter(1),
    'CALL ME': CardScript(
      during: (x) async {
        final names = callMe[x.card!.uid] ?? const {};
        if (names.contains(x.opp.label.isEmpty ? x.opp.name : x.opp.label)) x.setValue(4, 'Their name is on this card');
      },
      after: (x) async {
        final who = x.opp.label.isEmpty ? x.opp.name : x.opp.label;
        if ((callMe[x.card!.uid] ??= {}).add(who)) await say(x, '$who writes their name on Call Me. 555-3323!');
      },
    ),
    'CHA-CHING!': boostable,
    'DEADPOOL MERC FOR HIRE, LLC': CardScript(after: (x) async {
      // You're playing Deadpool, so you own the set. Probably.
      if (x.oppFighter.onBoard) await x.damage(x.oppFighter, 1);
    }),
    "DUMPSTER DIVIN' DEADPOOL": CardScript(effect: (x) async {
      final n = math.min(5, x.me.discard.length);
      if (n > 0) {
        final cards = await x.game.chooseCards(x.me, x.me.discard, n, n, 'Dumpster Divin\': shuffle $n cards into your deck', intent: Intent.help);
        for (final c in cards) {
          await x.game.toDeck(c, shuffle: true);
        }
      }
      await x.heal(wade, 1);
    }),
    'EAT ME': CardScript(
      immediately: (x) async => say(x, 'Deadpool: "Eat me."'),
      during: (x) async => say(x, 'Deadpool: "Eat me." Tee-hee!'),
      after: (x) async {
        if (x.lost) await say(x, 'Deadpool: "EAT ME."');
      },
    ),
    'EXCUSE ME WHILE I GROW SOME LIMBS.': CardScript(after: (x) => x.discard(x.opp, x.won ? 2 : 1)),
    'FAINT': CardScript(effect: (x) async {
      await say(x, '*thud* Deadpool faints dramatically... and gets back up.');
      await x.heal(wade, 2);
    }),
    'HOLY MACKEREL!': CardScript(effect: (x) async {
      final titles = {for (final c in x.opp.hero.cards) c.title}.toList()..sort();
      final i = await x.option(titles, 'Holy Mackerel!: guess a card in ${x.opp.name}\'s hand', intent: Intent.harm);
      final hits = x.opp.hand.where((c) => c.title == titles[i]).toList();
      if (hits.isEmpty) {
        await say(x, '${x.opp.name}: "Go fish."');
        await x.draw(1);
        return;
      }
      for (final c in hits) {
        await x.game.discardCard(c, reason: ' (Holy Mackerel!)', byOpponent: true);
      }
    }),
    "I'M NOT WEARING PANTS": CardScript(
      // Digital cards are never sleeved.
      during: (x) async => x.setValue(5, 'Not sleeved'),
      after: (x) async => say(x, 'If you\'re not wearing any pants, go put some on.'),
    ),
    "KLUNKIN' HEADS": CardScript(after: (x) async {
      final o = x.oppFighter;
      if (!x.won || !o.onBoard) return;
      for (final f in x.adjacentTo(o).where((f) => f != o && f.isEnemyOf(x.me)).toList()) {
        await x.damage(f, 3);
      }
    }),
    'PUSH TO TELEPORT': drawAfter(1),
    'SUPER FEINT': CardScript(uncancelable: true, immediately: (x) async => x.cancelOpponent(), after: (x) => x.draw(1)),
    'GAZE OF STONE': CardScript(after: (x) async {
      if (x.won && x.oppFighter.onBoard) await x.damage(x.oppFighter, 8);
    }),
  };
}
