/// The Witcher – Realms Fall (Eredin, Philippa, Yennefer & Triss) and Redemption Row (Moon Knight).
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

bool _noAttack(Game g, Ongoing m) => g.turn.attacks == 0;

// =================================================================================== Eredin

/// King of the Wild Hunt: while all Red Riders are defeated Eredin is ENRAGED: +1 to the value
/// of your combat cards, and your move value is 3.
class Eredin extends HeroScript {
  Fighter get eredin => me.heroFighter;
  Iterable<Fighter> get riders => me.fighters.where((f) => f.isSidekick);
  bool get enraged => riders.every((r) => r.defeated);

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player == me && enraged) yield const ValueOp.add(1, 'Eredin is ENRAGED');
  }

  @override
  int moveValue(Game g, Fighter f, int v) => f.owner == me && enraged ? 3 : v;

  @override
  List<String> status() => [if (enraged) 'ENRAGED' else '${riders.where((r) => !r.defeated).length} Red Riders'];

  Future<bool> sacrificeRider(Fx x, String why) async {
    final alive = riders.where((r) => r.onBoard).toList();
    if (alive.isEmpty) return false;
    final r = await x.chooseFighter(alive, 'Defeat a Red Rider to $why?', optional: true, intent: Intent.none);
    if (r == null) return false;
    await x.game.defeat(r);
    return true;
  }

  @override
  Map<String, CardScript> get cards => {
        'BRUTAL STRIKE': CardScript(
          uncancelable: true,
          during: (x) async {
            final oc = x.oppCard;
            if (oc != null && oc.def.text.containsKey('immediately')) x.ignoreOpponentValue();
          },
        ),
        'UNYIELDING HORDES': CardScript(
          immediately: (x) async => x.game.summon(x.me, riders.first.id, x.allSpaces, text: 'Return a defeated Red Rider to any space'),
          during: (x) async {
            final n = friendsAdjacentTo(x, x.oppFighter, except: x.fighter);
            if (n > 0) x.addValue(n, 'Friendly fighters adjacent');
          },
        ),
        'PORTAL DEFENSE': CardScript(
          immediately: (x) async {
            if (x.fighter != eredin) return;
            final friends = x.adjacentTo(eredin).where((f) => f.owner == x.me).toList();
            final f = await x.chooseFighter(friends, 'Eredin swaps with an adjacent friendly fighter, who becomes the defender', intent: Intent.none);
            if (f != null && await x.game.swap(eredin, f)) x.mySide.fighter = f;
          },
          after: (x) async {
            if (enraged) await x.draw(2);
          },
        ),
        'ICY GUILE': CardScript(
          immediately: (x) async {
            if (enraged) x.cancelOpponent();
          },
          during: (x) async {
            if (x.oppCard != null && await sacrificeRider(x, "ignore the value of your opponent's card")) x.ignoreOpponentValue();
          },
        ),
        'CLOSE FOR THE KILL': CardScript(effect: (x) async {
          await x.draw(2);
          await moveEach(x, x.myFighters, 3, through: true);
        }),
        'BACKHAND': CardScript(after: (x) async {
          if (x.opp.hand.isEmpty) return;
          final c = x.opp.hand[x.game.rng.nextInt(x.opp.hand.length)];
          if (enraged) {
            await x.game.discardCard(c, reason: ' (Backhand)', byOpponent: true);
          } else {
            await x.game.toDeck(c);
          }
        }),
        'FOUL PURPOSE': CardScript(
          target: (g, a, t) => enraged && a.owner == me,
          after: (x) async {
            if (await sacrificeRider(x, 'return Foul Purpose to your hand')) await x.game.returnPlayedToHand(x.card!);
          },
        ),
        'IMPLACABLE': CardScript(alsoAttack: (g, f) => enraged, during: (x) => x.boostThis()),
        'MIGHT OF THE AEN ELLE': CardScript(
          effect: (x) async {
            await x.draw(1);
            x.gainActions(1);
          },
          ongoing: (g, card, f) => Ongoing(
            card,
            discardIf: _noAttack,
            modifyDamageFn: (g, t, n, info) => t == eredin && !info.combat && !info.exhaustion ? 0 : n,
          ),
        ),
        'WILD HUNT': CardScript(after: (x) async {
          final targets = x.enemies.where((e) => x.adjacentTo(e).any((o) => o.owner == x.me)).toList();
          for (final f in targets) {
            await x.damage(f, enraged ? 2 : 1);
          }
        }),
      };
}

// ================================================================================= Philippa

/// Two Steps Ahead: at the end of your turn, you may draw until you have a hand of 4 cards.
class Philippa extends HeroScript {
  Fighter get philippa => me.heroFighter;

  @override
  Future<void> endOfTurn(Game g, Player active) async {
    if (active != me || me.hand.length >= 4) return;
    if (await g.yesNo(me, 'Two Steps Ahead: draw up to 4 cards in hand?')) await g.draw(me, 4 - me.hand.length);
  }

  @override
  Map<String, CardScript> get cards => {
        'OWLFORM': CardScript(during: (x) async {
          final cards = await x.game.chooseCards(x.me, x.me.hand, 0, x.me.hand.length, 'Owlform: discard any number of cards (+1 each)',
              intent: Intent.boost);
          for (final c in cards) {
            await x.game.discardCard(c, reason: ' (Owlform)');
          }
          if (cards.isNotEmpty) x.addValue(cards.length, 'Owlform: ${cards.length} discarded');
        }),
        'LIGHTNING BOLT': CardScript(after: (x) async {
          if (x.game.active != x.me || x.game.turn.maneuvers > 0) return;
          for (final f in enemiesInZone(x, philippa).toList()) {
            await x.damage(f, 1);
          }
        }),
        'SPELLBREAKER': CardScript(immediately: (x) async => x.cancelOpponent(), after: (x) async => x.game.endTurn()),
        'REDANIAN PLOT': CardScript(immediately: (x) async {
          final pay = x.opp.hand.isNotEmpty &&
              await x.yesNo("Redanian Plot: discard 1 card, or your card's value is ignored?", who: x.opp, intent: Intent.help);
          if (pay) {
            await x.discard(x.opp, 1);
          } else {
            x.ignoreOpponentValue();
          }
        }),
        "SPYMASTER'S RUSE": CardScript(effect: (x) async {
          final o = x.opp;
          final shown = await x.game.chooseCards(o, o.hand, o.hand.length < 4 ? o.hand.length : 4, 4, 'Reveal 4 cards from your hand',
              intent: Intent.loseOwn);
          if (shown.isEmpty) return;
          await x.game.emit(Revealed(o, shown, " (Spymaster's Ruse)"));
          final picks = await x.game.chooseCards(x.me, shown, shown.length < 2 ? shown.length : 2, 2, 'Choose 2 for them to discard',
              intent: Intent.loseEnemy);
          for (final c in picks) {
            await x.game.discardCard(c, byOpponent: true);
          }
          await x.draw(2, o);
        }),
        'BACKUP PLAN': CardScript(effect: (x) async {
          if (await x.option(["Set Philippa's health to 5", 'Draw 3 cards'], 'Backup Plan: choose one') == 0) {
            await x.game.setHealth(philippa, 5);
          } else {
            await x.draw(3);
          }
        }),
        'BLINDING DUST': CardScript(after: (x) async {
          final c = await x.game.chooseCard(x.me, x.me.hand.where((c) => c.def.boost != null), 'Blinding Dust: discard a card to deal its BOOST in damage?',
              optional: true, skipLabel: 'No', intent: Intent.boost);
          if (c == null) return;
          await x.game.discardCard(c, reason: ' (Blinding Dust)');
          await x.damage(x.oppFighter, c.def.boost ?? 0);
        }),
        'CHAIN LIGHTNING': CardScript(after: (x) async {
          if (!philippa.onBoard) return;
          final zones = x.board.zonesOf(philippa.space!).toList();
          final i = zones.length == 1
              ? 0
              : await x.option([for (final z in zones) x.board.def.zones[z]?.name ?? z], 'Chain Lightning: choose a zone Philippa is in');
          for (final f in x.enemies.where((f) => x.board.zonesOf(f.space!).contains(zones[i])).toList()) {
            await x.damage(f, 1);
          }
        }),
        'CUNNING': CardScript(after: (x) async {
          final pay = x.opp.hand.isNotEmpty &&
              await x.yesNo('Cunning: discard 1 card, or take 2 damage on the opposing fighter?', who: x.opp, intent: Intent.harm);
          if (pay) {
            await x.discard(x.opp, 1);
          } else {
            await x.damage(x.oppFighter, 2);
          }
        }),
        'POLYMORPHY': CardScript(
          effect: (x) => x.place(philippa, x.allSpaces, text: 'Place Philippa in any space'),
          ongoing: (g, card, f) => Ongoing(
            card,
            moveValueFn: (g, f, v) => f == philippa ? 5 : v,
            discardIf: (g, m) => !philippa.onBoard || !g.fightersInZoneOf(philippa).any((o) => o.isEnemyOf(me)),
          ),
        ),
      };
}

// ======================================================================== Yennefer & Triss

/// Choose Yennefer or Triss as your hero; the other is your sidekick. Only the chosen hero's
/// ability is used. Sorceress of Vengerberg: IMMEDIATELY, if Yennefer is attacking, you may BOOST
/// her attack (cannot be canceled). Merigold the Fearless: after Triss plays a scheme, deal 2
/// damage to a fighter adjacent to Triss.
class YenneferTriss extends HeroScript {
  bool yenneferHero = true;

  @override
  String get heroName => yenneferHero ? 'Yennefer' : 'Triss';

  @override
  Future<void> beforeDeck() async {
    yenneferHero = await game.chooseOption(me, ['Yennefer', 'Triss'], 'Choose your hero', intent: Intent.none) == 0;
    // The chosen sorceress is the hero; the other one's sidekick token stays.
    me.fighters.removeWhere((f) => f.isSidekick && f.id == (yenneferHero ? 'yennefer' : 'triss'));
    await game.say('${me.name} chooses $heroName as the hero.');
  }

  Fighter? get yennefer => yenneferHero ? me.heroFighter : me.fighters.where((f) => f.id == 'yennefer').firstOrNull;
  Fighter? get triss => yenneferHero ? me.fighters.where((f) => f.id == 'triss').firstOrNull : me.heroFighter;

  @override
  bool fighterMayUse(Card c, Fighter f) {
    final u = c.def.usedBy.toUpperCase();
    if (u.contains('YENNEFER')) return f == yennefer;
    if (u.contains('TRISS')) return f == triss;
    return true;
  }

  @override
  Future<void> combatImmediately(Game g, Combat c) async {
    if (!yenneferHero || c.attacker.player != me || c.attacker.fighter != yennefer) return;
    await g.boostCard(c.attacker, text: 'Sorceress of Vengerberg: BOOST her attack?');
  }

  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    final t = triss;
    if (yenneferHero || p != me || kind != ActionKind.scheme || fighter != t || t == null || !t.onBoard) return;
    final f = await g.chooseFighter(me, g.adjacentFighters(t), 'Merigold the Fearless: deal 2 damage to a fighter adjacent to Triss',
        intent: Intent.harm);
    if (f != null) await g.damage(f, 2, info: DamageInfo(source: t, by: me));
  }

  @override
  Map<String, CardScript> get cards => {
        "MERIGOLD'S HAILSTORM": CardScript(after: (x) async {
          final o = x.opp;
          final i = await x.option(['Discard 2 cards', 'Deal 3 damage to your hero', 'Discard the top 4 cards of your deck'],
              "Merigold's Hailstorm: choose one", who: o, intent: Intent.none);
          switch (i) {
            case 0:
              await x.discard(o, 2);
            case 1:
              await x.damage(o.heroFighter, 3);
            case 2:
              for (var k = 0; k < 4; k++) {
                await x.game.discardTopOfDeck(o);
              }
          }
        }),
        'QUICK AND READY': CardScript(after: (x) async {
          if (x.fighter.onBoard) await x.place(x.fighter, x.zoneSpaces(x.fighter), text: 'Place your fighter in any space in their zone');
          await x.draw(1);
        }),
        'INCINERATE': CardScript(
          uncancelable: true,
          during: (x) async {
            if (x.opp.hand.length >= 2 && await x.yesNo("Incinerate: discard 2 cards to ignore its value?", who: x.opp, intent: Intent.help)) {
              await x.discard(x.opp, 2);
              x.game.ignoreValue(x.mySide);
            }
          },
        ),
        'MAGICAL BARRIER': CardScript(immediately: (x) => x.heal(x.fighter, 1)),
        'PORTAL TO ANYWHERE': CardScript(after: (x) async {
          final f = await x.chooseFighter([x.fighter, x.oppFighter].where((f) => f.onBoard), 'Place a fighter in the combat in any space');
          if (f != null) await x.place(f, x.allSpaces);
          x.gainActions(1);
        }),
        'BALL LIGHTNING': CardScript(after: (x) async {
          if (x.won) {
            await x.discard(x.opp, 1);
          } else {
            await x.discard(x.opp, 1);
            await x.discard(x.me, 1);
          }
        }),
        'ECHOING BLAST': CardScript(after: (x) async {
          if (x.won) await x.game.returnPlayedToHand(x.card!);
        }),
        'LODGE OF SORCERESSES': CardScript(effect: (x) async {
          final g = x.game;
          final players = [x.me, ...x.opponents];
          final drawn = <Player, int>{};
          for (final p in players) {
            if (p.hand.isEmpty) {
              drawn[p] = 0;
              continue;
            }
            final c = await g.chooseCard(p, p.hand, 'Lodge of Sorceresses: reveal a card (draw its BOOST)', intent: Intent.none);
            await g.emit(Revealed(p, [c!], ' (Lodge of Sorceresses)'));
            drawn[p] = c.def.boost ?? 0;
          }
          for (final p in players) {
            await g.draw(p, drawn[p]!);
          }
          final most = drawn.values.fold(0, (a, b) => a > b ? a : b);
          if (most == 0) return;
          for (final p in players.where((p) => drawn[p] == most)) {
            await g.damage(p.heroFighter, most, info: DamageInfo(by: x.me));
          }
        }),
        'ADVISOR TO THE KING': CardScript(
          effect: (x) async {
            for (final f in x.myFighters.toList()) {
              await x.heal(f, 1);
            }
            await x.draw(1);
          },
          ongoing: (g, card, f) => Ongoing(card, boostBonus: 1, discardIf: _noAttack),
        ),
        'TELEPATHY': CardScript(immediately: (x) async {
          final pay = x.opp.hand.isNotEmpty &&
              await x.yesNo('Telepathy: discard 1 card, or all effects on your card are canceled?', who: x.opp, intent: Intent.help);
          if (pay) {
            await x.discard(x.opp, 1);
          } else {
            x.cancelOpponent();
          }
        }),
      };
}

// ============================================================================== Moon Knight

enum MoonForm { moonKnight, khonshu, mrKnight }

/// Moon Knight: at the start of your turn, move up to 2 spaces. Khonshu: +2 to his attack cards,
/// takes no damage except combat damage. Mr. Knight: +1 to his defense values. At the end of
/// your turn, change to your next identity (Moon Knight → Khonshu → Mr. Knight → ...).
class MoonKnight extends HeroScript {
  MoonForm form = MoonForm.moonKnight;
  Fighter get mk => me.heroFighter;

  @override
  String get heroName => switch (form) { MoonForm.moonKnight => 'Moon Knight', MoonForm.khonshu => 'Khonshu', MoonForm.mrKnight => 'Mr. Knight' };

  Future<void> nextIdentity() async {
    form = MoonForm.values[(form.index + 1) % 3];
    await game.emit(StatusChanged(me, 'He becomes $heroName.'));
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active == me && form == MoonForm.moonKnight && mk.onBoard) {
      await g.moveFighter(mk, 2, chooser: me, text: 'Moon Knight: move up to 2 spaces');
    }
  }

  @override
  Future<void> endOfTurn(Game g, Player active) async {
    if (active == me) await nextIdentity();
  }

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player != me || s.fighter != mk) return;
    if (form == MoonForm.khonshu && s.isAttacker) yield const ValueOp.add(2, 'Khonshu');
    if (form == MoonForm.mrKnight && !s.isAttacker) yield const ValueOp.add(1, 'Mr. Knight');
  }

  @override
  int modifyDamage(Game g, Fighter target, int amount, DamageInfo info) =>
      target == mk && form == MoonForm.khonshu && !info.combat ? 0 : amount;

  @override
  List<String> status() => [heroName.toUpperCase()];

  @override
  Map<String, CardScript> get cards => {
        'LET YOUR INSANITY GUIDE YOU': CardScript(after: (x) async {
          final c = await x.game.discardTopOfDeck(x.me);
          if (c != null) await x.draw(c.def.boost ?? 0);
        }),
        'TRAVELERS OF THE NIGHT': CardScript(effect: (x) async {
          await x.move(x.fighter, 4, throughOpp: true);
          x.gainActions(1);
        }),
        "THAT'S THE PART I LIKE": CardScript(after: (x) async {
          if (!x.won || x.opp.deck.isEmpty || !await x.yesNo("Look at the top 3 cards of your opponent's deck?")) return;
          final top = x.opp.deck.take(3).toList();
          x.me.script.seen(top);
          final d = await x.game.chooseCard(x.me, top, 'Discard one of them', intent: Intent.loseEnemy);
          if (d == null) return;
          final rest = top.where((c) => c != d).toList();
          x.opp.deck.removeRange(0, top.length);
          x.opp.deck.insertAll(0, rest);
          x.opp.discard.add(d);
          await x.game.emit(CardMoved(d, Zone.deck, Zone.discard));
          if (rest.length == 2 && await x.option(['Keep ${rest[0].title} on top', 'Put ${rest[1].title} on top'], 'Order them', intent: Intent.none) == 1) {
            x.opp.deck
              ..removeRange(0, 2)
              ..insertAll(0, [rest[1], rest[0]]);
          }
        }),
        "WE'RE ALL IN THIS TOGETHER": CardScript(after: (x) async {
          if (x.won) await x.draw(1);
        }),
        "I'M NOT REAL": CardScript(after: (x) async {
          if (await x.yesNo('Change to your next identity?', intent: Intent.none)) await nextIdentity();
        }),
        "THAT'S WHY I ALWAYS WIN": boostable,
        'MADNESS WILL KEEP YOU ALIVE': CardScript(effect: (x) async {
          await x.heal(mk, 2);
          if (x.game.startedTurnElsewhere(mk)) x.gainActions(1);
        }),
        'A TOTALLY SANE THING TO DO': CardScript(after: (x) async {
          if (await x.yesNo('Deal 2 damage to both fighters in the combat?', intent: Intent.none)) {
            for (final f in [x.fighter, x.oppFighter]) {
              await x.damage(f, 2);
            }
          }
        }),
        'FIST OF KHONSHU': CardScript(after: (x) async {
          if (x.won) await pushOpponent(x, 4);
        }),
        'PAST AND PRESENT INTERMINGLE': CardScript(during: (x) async {
          final top = x.me.discard.lastOrNull;
          if (top != null) x.addValue(top.def.boost ?? 0, '${top.title} (top of discard pile)');
        }),
        'GOOD ENOUGH FOR US': CardScript(after: (x) async {
          if (await x.yesNo('Draw 2 cards and take 2 damage?')) {
            await x.draw(2);
            await x.damage(mk, 2);
          }
        }),
      };
}
