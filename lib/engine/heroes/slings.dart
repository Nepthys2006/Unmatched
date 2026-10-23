/// Slings & Arrows: Hamlet, Titania.
library;

import '../combat.dart';
import '../defs.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// =================================================================================== Hamlet

/// The Question: at the start of your turn choose TO BE or NOT TO BE (you may keep the same
/// side). NOT TO BE deals 2 damage to one of your fighters. TO BE: maneuvers draw 1 more card.
/// NOT TO BE: +2 to Hamlet's attacks.
class Hamlet extends HeroScript {
  bool toBe = true;
  Fighter get hamlet => me.heroFighter;

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me) return;
    final i = await g.chooseOption(me, ['TO BE (draw 1 more when you maneuver)', 'NOT TO BE (+2 to Hamlet\'s attacks; 2 damage to one of your fighters)'],
        'The Question', intent: Intent.none);
    toBe = i == 0;
    await g.emit(StatusChanged(me, toBe ? 'Hamlet chooses TO BE.' : 'Hamlet chooses NOT TO BE.'));
    if (!toBe) {
      final f = await g.chooseFighter(me, me.onBoard, 'NOT TO BE: deal 2 damage to one of your fighters', intent: Intent.harm);
      if (f != null) await g.damage(f, 2, info: DamageInfo(by: me));
    }
  }

  @override
  int maneuverDraws(Game g, Player p, int n) => p == me && toBe ? n + 1 : n;

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player == me && s.isAttacker && s.fighter == hamlet && !toBe) yield const ValueOp.add(2, 'NOT TO BE');
  }

  @override
  List<String> status() => [toBe ? 'TO BE' : 'NOT TO BE'];

  @override
  Map<String, CardScript> get cards => {
        'THE GHOST': CardScript(effect: (x) async {
          final i = await x.option(['Hamlet recovers 2 health', 'Place Hamlet in any space in his zone and gain 1 action'], 'The Ghost: choose one');
          if (i == 0) {
            await x.heal(hamlet, 2);
          } else {
            await x.place(hamlet, x.zoneSpaces(hamlet), text: 'Place Hamlet in his zone');
            x.gainActions(1);
          }
        }),
        'THE READINESS IS ALL': CardScript(after: (x) async {
          final f = await x.chooseFighter([x.fighter, x.oppFighter].where((f) => f.onBoard), 'Place a fighter in the combat in any space');
          if (f == null) return;
          await x.place(f, x.allSpaces);
          x.game.addTurnMod(TurnMod(name: 'The Readiness Is All', cannotLeaveFn: (g, o) => o == f));
        }),
        'TO SLEEP, PERCHANCE TO DREAM': CardScript(after: (x) async {
          if (x.won) {
            if (x.damageDealt > 0) await pushOpponent(x, x.damageDealt);
          } else {
            await x.heal(hamlet, 1);
          }
        }),
        'BLOOD WILL HAVE BLOOD': CardScript(after: (x) async {
          if (x.game.turn.damaged.contains(hamlet)) await x.damage(x.oppFighter, 1);
        }),
        'MADDENING INSIGHT': CardScript(
          during: (x) async => x.setValue(x.me.hand.length, 'Cards in hand'),
          after: (x) async {
            if (x.won) await x.discard(x.opp, 1);
          },
        ),
        'NOTHING EITHER GOOD OR BAD': CardScript(after: (x) async {
          if (x.oppCard?.type == CardType.versatile) await x.damage(x.oppFighter, 2);
        }),
        'OUTRAGEOUS FORTUNE': CardScript(
          during: (x) async => x.mySide.vars['fortune'] = await discardTopAndAdd(x),
          after: (x) async {
            final c = x.mySide.vars['fortune'] as Card?;
            if (x.lost && c != null && x.me.discard.contains(c)) await x.game.toHand(c, reason: ' (Outrageous Fortune)');
          },
        ),
        "THE PLAY'S THE THING": CardScript(after: (x) async {
          final d = await x.discard(x.opp, 1, random: true);
          if (x.won && d.isNotEmpty) await x.heal(hamlet, d.first.def.boost ?? 0);
        }),
        'THE REST IS SILENCE': CardScript(after: (x) async => x.game.endTurn()),
        'UNCERTAIN DOOM': CardScript(during: (x) async {
          if (x.oppCard?.type == CardType.versatile) x.ignoreOpponentValue();
        }),
        'CRUEL TO BE KIND': boostable,
        'METHOD IN THE MADNESS': CardScript(effect: (x) async {
          final cards = await x.game.chooseCards(x.me, x.me.hand, 0, x.me.hand.length,
              'Method in the Madness: put any number of cards on the bottom of your deck', intent: Intent.loseOwn);
          for (final c in cards) {
            await x.game.toDeck(c, bottom: true);
          }
          if (cards.isNotEmpty) {
            final n = await x.game.chooseNumber(x.me, 0, cards.length, 'Draw up to ${cards.length} cards');
            await x.draw(n);
          }
          x.gainActions(1);
        }),
      };
}

// ================================================================================== Titania

const glamours = {
  'GREED': 'At the end of your turn, you may draw 1 card.',
  'INVISIBILITY': 'Your fighters may move through opposing fighters.',
  'JEALOUSY': 'When Titania or Oberon is attacked, before playing a card, they may swap spaces. If they do, your other fighter is now the defender.',
  'LOVE': 'When you maneuver, you may move an opposing fighter 1 space before moving your fighters.',
  'RHYME': 'After you play a scheme, gain 1 action.',
  'SLEEP': 'Your fighters do not take damage other than combat damage.',
};

/// Fairy Magic: if you have no face-up glamour at the start of your turn, flip the top card of
/// your glamour deck face up; its effect is ongoing while face up. Only Titania's own cards
/// discard glamours; an empty glamour deck is not reshuffled.
class Titania extends HeroScript {
  final List<String> glamourDeck = [];
  final List<String> glamourDiscard = [];
  String? glamour;
  Fighter get titania => me.heroFighter;
  Fighter? get oberon => me.fighters.where((f) => f.isSidekick).firstOrNull;
  bool active(String g) => glamour == g;

  @override
  Future<void> beforeDeck() async {
    glamourDeck
      ..addAll(glamours.keys)
      ..shuffle(game.rng);
  }

  @override
  Future<void> startOfTurn(Game g, Player p) async {
    if (p != me || glamour != null || glamourDeck.isEmpty) return;
    glamour = glamourDeck.removeAt(0);
    await g.emit(StatusChanged(me, 'Titania reveals the Glamour of ${_cap(glamour!)}: ${glamours[glamour]}'));
  }

  static String _cap(String s) => s[0] + s.substring(1).toLowerCase();

  Future<bool> discardGlamour(Fx x, String why) async {
    if (glamour == null || !await x.yesNo('Discard your Glamour of ${_cap(glamour!)} to $why?')) return false;
    glamourDiscard.add(glamour!);
    await x.game.emit(StatusChanged(me, 'Glamour of ${_cap(glamour!)} is discarded.'));
    glamour = null;
    return true;
  }

  // -- glamour effects ---------------------------------------------------------------------------
  @override
  Future<void> endOfTurn(Game g, Player p) async {
    if (p == me && active('GREED') && await g.yesNo(me, 'Glamour of Greed: draw 1 card?')) await g.draw(me, 1);
  }

  @override
  bool movesThroughEnemies(Game g, Fighter f) => f.owner == me && active('INVISIBILITY');

  @override
  Future<void> onAttacked(Game g, Combat c) async {
    final d = c.defender.fighter, o = oberon;
    if (!active('JEALOUSY') || d.owner != me || o == null || !o.onBoard || !titania.onBoard) return;
    final other = d == titania ? o : titania;
    if (await g.yesNo(me, 'Glamour of Jealousy: swap Titania and Oberon? ${other.name} becomes the defender.', intent: Intent.none) &&
        await g.swap(titania, o)) {
      c.defender.fighter = other;
    }
  }

  @override
  Future<void> beforeManeuverMoves(Game g, Player p) async {
    if (p != me || !active('LOVE')) return;
    final f = await g.chooseFighter(me, g.enemyFighters(me), 'Glamour of Love: move an opposing fighter 1 space?',
        optional: true, skipLabel: 'No', intent: Intent.none);
    if (f != null) await g.moveFighter(f, 1, chooser: me);
  }

  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    if (p == me && kind == ActionKind.scheme && active('RHYME')) g.gainActions(me, 1);
  }

  @override
  int modifyDamage(Game g, Fighter target, int amount, DamageInfo info) =>
      target.owner == me && active('SLEEP') && !info.combat ? 0 : amount;

  @override
  List<String> status() => [glamour == null ? 'No glamour' : 'Glamour: ${_cap(glamour!)}', '${glamourDiscard.length} discarded'];

  @override
  Map<String, CardScript> get cards => {
        'AS WISE AS BEAUTIFUL': CardScript(after: (x) async {
          await x.draw(await discardGlamour(x, 'draw 2 cards instead of 1') ? 2 : 1);
        }),
        'MET BY MOONLIGHT': CardScript(after: (x) async {
          final o = oberon;
          if (o != null && o.onBoard && titania.onBoard) {
            await x.place(o, x.board.neighbours(titania.space!), text: 'Place Oberon next to Titania');
          }
        }),
        'PROTECTION OF THE FAIRY WOODS': CardScript(immediately: (x) async {
          if (await discardGlamour(x, "cancel all effects on your opponent's card")) x.cancelOpponent();
        }),
        'THE MOON LOOKS DOWN': CardScript(after: (x) async {
          if (glamourDiscard.isEmpty) return;
          final i = await x.option([for (final g in glamourDiscard) 'Glamour of ${_cap(g)}'],
              'Put a discarded glamour on the bottom of your glamour deck');
          glamourDeck.add(glamourDiscard.removeAt(i));
        }),
        'WHAT FOOLS THESE MORTALS BE': CardScript(effect: (x) async {
          if (!await x.game.lookAtHand(x.me, x.opp)) return;
          final c = await x.game.chooseCard(x.me, x.opp.hand, 'Choose a card for them to shuffle into their deck', intent: Intent.loseEnemy);
          if (c != null) await x.game.toDeck(c, shuffle: true);
        }),
        'FAIRY SONG': CardScript(during: (x) async {
          if (await discardGlamour(x, 'make Fairy Song 5')) x.setValue(5);
        }),
        'A MOMENTARY GLANCE': CardScript(effect: (x) async {
          final f = await x.chooseFighter(x.inZoneOf(titania), "Deal 2 damage to any fighter in Titania's zone", intent: Intent.harm);
          if (f != null) await x.damage(f, 2);
        }),
        'BUT A DREAM': CardScript(
          immediately: (x) async {
            x.cancelOpponent();
            x.ignoreOpponentValue();
            final c = x.oppCard;
            if (c != null && !c.virtual) await x.game.returnPlayedToHand(c);
          },
          after: (x) => x.draw(1),
        ),
        'GIFT OF THE FAIR FOLK': CardScript(effect: (x) async {
          final picks = await chooseDifferent(
              x, ['One fighter recovers 2 health', 'Draw 2 cards', 'Move two fighters up to 2 spaces each'], 2, 'Gift of the Fair Folk');
          for (final p in picks) {
            switch (p) {
              case 0:
                final f = await x.chooseFighter(x.game.onBoard, 'Which fighter recovers 2 health?', intent: Intent.help);
                if (f != null) await x.heal(f, 2);
              case 1:
                await x.draw(2);
              case 2:
                final moved = <Fighter>[];
                for (var i = 0; i < 2; i++) {
                  final f = await x.chooseFighter(x.game.onBoard.where((f) => !moved.contains(f)), 'Move a fighter up to 2 spaces',
                      optional: true);
                  if (f == null) break;
                  moved.add(f);
                  await x.move(f, 2);
                }
            }
          }
        }),
        'PARTING GIFT': CardScript(after: (x) async {
          if (await x.yesNo('Parting Gift: deal 2 damage to each fighter in the combat?', intent: Intent.none)) {
            for (final f in [x.fighter, x.oppFighter]) {
              await x.damage(f, 2);
            }
          }
        }),
        'QUEEN OF THE FAIRIES': CardScript(during: (x) async {
          if (glamourDiscard.isNotEmpty) x.addValue(glamourDiscard.length, 'Glamours in the discard pile');
        }),
        'WHISKED AWAY': CardScript(after: (x) async {
          await x.move(x.fighter, 2);
          if (x.fighter.onBoard && await discardGlamour(x, 'place your fighter in any space')) {
            await x.place(x.fighter, x.allSpaces);
          }
        }),
      };
}
