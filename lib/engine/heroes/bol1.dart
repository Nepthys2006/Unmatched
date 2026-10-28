/// Battle of Legends, Volume One: King Arthur, Alice, Medusa, Sinbad.
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ============================================================================== King Arthur

/// When King Arthur attacks, you may BOOST that attack, playing the BOOST card face down with
/// the attack card. If the opponent cancels the attack card's effects, the BOOST is discarded
/// without effect.
class KingArthur extends HeroScript {
  @override
  Future<void> onAttackCardChosen(Combat c) async {
    final s = c.attacker;
    if (!s.fighter.isHero || s.player != me) return;
    final options = me.hand.where((x) => x.def.canBoost).toList();
    final b = await game.chooseCard(me, options, 'King Arthur may BOOST this attack (face down)',
        optional: true, skipLabel: "Don't boost", intent: Intent.boost, subject: s);
    if (b == null) return;
    game.stash(b);
    s.boosts.add(b);
    s.ops.add(ValueOp.add(game.boostValueOf(b), 'BOOST: King Arthur (${b.title})'));
  }

  @override
  Map<String, CardScript> get cards => {
        'NOBLE SACRIFICE': boostable,
        'EXCALIBUR': vanilla,
        'THE AID OF MORGANA': drawAfter(2),
        'DIVINE INTERVENTION': CardScript(after: (x) => x.move(x.hero, 5)),
        'THE HOLY GRAIL': CardScript(after: (x) async {
          final a = x.hero;
          if (a.alive && a.hp <= 4) await x.game.setHealth(a, 8);
        }),
        'THE LADY OF THE LAKE': CardScript(effect: (x) async {
          final inDiscard = x.me.discard.where((c) => c.def.titleHas('EXCALIBUR')).firstOrNull;
          if (inDiscard != null) {
            await x.game.toHand(inDiscard, reason: ' (The Lady of the Lake)');
            return;
          }
          final inDeck = x.me.deck.where((c) => c.def.titleHas('EXCALIBUR')).firstOrNull;
          if (inDeck != null) await x.game.toHand(inDeck, reason: ' (The Lady of the Lake)');
          await x.game.shuffleDeck(x.me);
        }),
        'PROPHECY': CardScript(effect: (x) async {
          final top = x.me.deck.take(4).toList();
          if (top.isEmpty) return;
          // "Add 2 of them to your hand" (all of them if there are fewer), the others back on top in
          // the order you choose.
          final n = top.length < 2 ? top.length : 2;
          final keep = await x.game.chooseCards(x.me, top, n, n, 'Prophecy: add 2 cards to your hand', intent: Intent.gainOwn, source: x.card);
          for (final c in keep) {
            await x.game.toHand(c, reason: ' (Prophecy)');
          }
          final rest = top.where((c) => !keep.contains(c)).toList();
          final order = <Card>[];
          while (rest.length > 1) {
            final c = await x.game.chooseCard(x.me, rest, 'Prophecy: which card goes on top of your deck?', intent: Intent.gainOwn, source: x.card);
            if (c == null) break;
            rest.remove(c);
            order.add(c);
          }
          order.addAll(rest);
          x.me.deck
            ..removeWhere(order.contains)
            ..insertAll(0, order);
        }),
        'AID THE CHOSEN ONE': CardScript(after: (x) async {
          if (x.won) await x.draw(2);
        }),
        'RESTLESS SPIRITS': CardScript(effect: (x) async {
          final merlin = x.fighter;
          final s = await x.chooseSpace(x.zoneSpaces(merlin), "Restless Spirits: choose a space in Merlin's zone", intent: Intent.harm);
          if (s == null) return;
          final adj = await x.chooseSpace(x.board.neighbours(s), 'Choose one space adjacent to it', intent: Intent.harm);
          var defeated = 0;
          for (final sp in {s, ?adj}) {
            final f = x.game.fighterAt(sp);
            if (f != null && f.isEnemyOf(x.me)) {
              await x.damage(f, 2);
              if (f.defeated) defeated++;
            }
          }
          if (defeated > 0) await x.draw(1);
        }),
        'COMMAND THE STORMS': CardScript(effect: (x) => moveEach(x, x.game.onBoard.toList(), 3)),
      };
}

// ==================================================================================== Alice

/// Choose BIG or SMALL when placed. BIG: +2 to her attack cards. SMALL: +1 to her defense cards.
class Alice extends HeroScript {
  bool big = true;

  @override
  Future<void> afterHeroPlaced() async {
    big = await game.chooseOption(me, ['BIG', 'SMALL'], 'Alice starts the game…') == 0;
    await game.emit(StatusChanged(me, 'Alice starts ${big ? 'BIG' : 'SMALL'}.'));
  }

  Future<void> changeSize() async {
    big = !big;
    await game.emit(StatusChanged(me, 'Alice becomes ${big ? 'BIG' : 'SMALL'}.'));
  }

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player != me || !s.fighter.isHero) return;
    if (s.isAttacker && big) yield const ValueOp.add(2, "Alice's size (BIG)");
    if (!s.isAttacker && !big) yield const ValueOp.add(1, "Alice's size (SMALL)");
  }

  @override
  List<String> status() => [big ? 'BIG' : 'SMALL'];

  @override
  Map<String, CardScript> get cards => {
        'MAD AS A HATTER': CardScript(after: (x) async {
          await moveEach(x, x.myFighters, 2);
          await changeSize();
        }),
        'DRINK ME': CardScript(effect: (x) async {
          await x.draw(2);
          await changeSize();
        }),
        'JAWS THAT BITE': CardScript(after: (x) async {
          final f = await x.chooseFighter(x.adjacentTo(x.fighter), 'Deal 2 damage to a fighter adjacent to the Jabberwock',
              intent: Intent.harm);
          if (f != null) await x.damage(f, 2);
        }),
        'MANXOME FOE': const CardScript(during: discardTopAndAdd),
        'LOOKING GLASS': CardScript(after: (x) async {
          final picks = await chooseDifferent(
              x, ['Draw 2 cards', 'Alice recovers 3 health', 'Place Alice in any other space'], 2, 'Looking Glass: choose an effect');
          for (final p in picks) {
            switch (p) {
              case 0:
                await x.draw(2);
              case 1:
                await x.heal(x.hero, 3);
              case 2:
                if (x.hero.onBoard) await x.place(x.hero, x.allSpaces.where((s) => s != x.hero.space));
            }
          }
        }),
        'SNICKER-SNACK': CardScript(after: (x) async {
          if (x.won) await pickDiscard(x);
        }),
        'O FRABJOUS DAY!': CardScript(after: (x) => changeSize()),
        'THE OTHER SIDE OF THE MUSHROOM': CardScript(after: (x) async {
          await x.move(x.hero, 3);
          await changeSize();
        }),
        'EAT ME': CardScript(effect: (x) async {
          await x.move(x.hero, 3);
          await changeSize();
        }),
        "I'M LATE, I'M LATE": CardScript(after: (x) async {
          await x.move(x.hero, 5);
          await changeSize();
        }),
      };
}

// =================================================================================== Medusa

/// At the start of your turn, you may deal 1 damage to an opposing fighter in Medusa's zone.
class Medusa extends HeroScript {
  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || !me.heroFighter.onBoard) return;
    final targets = g.fightersInZoneOf(me.heroFighter).where((f) => f.isEnemyOf(me));
    final f = await g.chooseFighter(me, targets, "Medusa's gaze: deal 1 damage to an opposing fighter in her zone?",
        optional: true, skipLabel: 'No', intent: Intent.harm);
    if (f != null) await g.damage(f, 1, info: DamageInfo(source: me.heroFighter, by: me));
  }

  @override
  Map<String, CardScript> get cards => {
        'SECOND SHOT': boostable,
        'A MOMENTARY GLANCE': CardScript(effect: (x) async {
          final f = await x.chooseFighter(x.inZoneOf(x.hero), "Deal 2 damage to any one fighter in Medusa's zone", intent: Intent.harm);
          if (f != null) await x.damage(f, 2);
        }),
        'WINGED FRENZY': CardScript(effect: (x) async {
          await moveEach(x, x.myFighters, 3, through: true);
          final harpy = x.me.fighters.where((f) => f.isSidekick && f.defeated).firstOrNull;
          if (harpy != null && x.hero.onBoard) {
            final s = await x.chooseSpace(x.zoneSpaces(x.hero).where(x.game.isEmpty), "Return a Harpy to Medusa's zone",
                intent: Intent.moveOwn, subject: harpy);
            if (s != null) await x.game.revive(harpy, s);
          }
        }),
        'GAZE OF STONE': CardScript(after: (x) async {
          if (x.won && x.oppFighter.alive) await x.damage(x.oppFighter, 8);
        }),
        'HISS AND SLITHER': oppDiscardsAfter(1),
        'THE HOUNDS OF MIGHTY ZEUS': CardScript(after: (x) => moveEach(x, x.me.fighters.where((f) => f.isSidekick), 3)),
        'CLUTCHING CLAWS': oppDiscardsAfter(1),
      };
}

// =================================================================================== Sinbad

bool _isVoyage(Card c) => c.def.upperTitle.startsWith('VOYAGE');

CardScript _voyage(Effect after) => CardScript(
      during: (x) async {
        final n = x.me.discard.where(_isVoyage).length;
        if (n > 0) x.addValue(n, 'VOYAGE cards in discard pile');
      },
      after: after,
    );

/// When you maneuver, your fighters may move +1 space for each VOYAGE card in your discard pile.
class Sinbad extends HeroScript {
  @override
  int maneuverBonus(Game g, Fighter f) => f.owner == me ? me.discard.where(_isVoyage).length : 0;

  @override
  List<String> status() {
    final n = me.discard.where(_isVoyage).length;
    return n > 0 ? ['$n VOYAGE'] : const [];
  }

  @override
  Map<String, CardScript> get cards => {
        'TOIL AND DANGER': CardScript(after: (x) => x.move(x.hero, 3)),
        'RICHES BEYOND COMPARE': CardScript(effect: (x) => x.draw(3)),
        'BY FORTUNE AND FATE': drawAfter(2),
        'VOYAGE HOME': _voyage((x) async {
          for (final c in x.me.discard.where(_isVoyage).toList()) {
            await x.game.toHand(c, reason: ' (Voyage Home)');
          }
        }),
        'VOYAGE TO THE ISLAND THAT WAS A WHALE': _voyage((x) => x.heal(x.hero, 2)),
        'VOYAGE TO THE VALLEY OF THE GIANT SNAKES': _voyage((x) => x.game.lookAtHand(x.me, x.opp)),
        'VOYAGE TO THE CREATURE WITH EYES LIKE COALS OF FIRE': _voyage((x) => x.discard(x.opp, 1, random: true)),
        'VOYAGE TO THE CANNIBALS WITH THE ROOT OF MADNESS': _voyage((x) => x.move(x.hero, 2)),
        'VOYAGE TO THE CITY OF THE MAN-EATING APES': _voyage((x) => x.damage(x.oppFighter, 2)),
        'VOYAGE TO THE CITY OF THE KING OF SERENDIB': _voyage((x) => x.draw(1)),
      };
}
