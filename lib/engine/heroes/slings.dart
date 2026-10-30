/// Slings & Arrows: Hamlet, Titania, Shakespeare, The Wayward Sisters.
library;

import '../combat.dart';
import '../defs.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../open_cards.dart';
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
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || glamour != null || glamourDeck.isEmpty) return;
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
  Future<void> endOfTurn(Game g, Player active) async {
    if (active == me && this.active('GREED') && await g.yesNo(me, 'Glamour of Greed: draw 1 card?')) await g.draw(me, 1);
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

  static OpenCard _face(String g) => OpenCard(title: 'Glamour of ${_cap(g)}', text: glamours[g]!);

  /// The face-up glamour is ongoing; the glamour deck is face down; discarded glamours lie face up.
  @override
  List<OpenZone> openZones() => [
    OpenZone(
      id: 'glamour',
      label: 'GLAMOUR',
      kind: OpenZoneKind.active,
      cards: [if (glamour != null) _face(glamour!)],
      hidden: glamourDeck.length,
      hiddenLabel: 'in the glamour deck',
      note: glamour == null ? (glamourDeck.isEmpty ? 'The glamour deck is empty.' : 'Flips a glamour at the start of the next turn.') : 'Ongoing while face up.',
    ),
    if (glamourDiscard.isNotEmpty)
      OpenZone(id: 'glamour-discard', label: 'DISCARDED GLAMOURS', short: 'DISCARDED', cards: [for (final g in glamourDiscard) _face(g)], alwaysShow: false),
  ];

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

// ============================================================================== Shakespeare

typedef _Completion = Future<void> Function(Fx x, Card c);

/// Iambic Pentameter: after Shakespeare or an Actor attacks or defends, the card goes face up
/// into his line (his in-play row) instead of the discard pile. At exactly 10 syllables the last
/// card's completion effect resolves (even if its other effects were canceled), then the line is
/// discarded; past 10 the line is discarded with no completion.
class Shakespeare extends HeroScript {
  Fighter get bard => me.heroFighter;
  Iterable<Fighter> get actors => me.fighters.where((f) => f.id == 'actor');

  /// The line, left to right.
  List<Card> get line => me.inPlay;
  int get syllables => line.fold(0, (n, c) => n + (c.def.syllables ?? 0));

  @override
  List<String> status() => ['Line: $syllables/10 syllables'];

  @override
  List<OpenZone> openZones() => [
    OpenZone(
      id: 'line',
      label: 'THE LINE',
      cards: [for (final c in line) OpenCard.of(c, tag: '${c.def.syllables ?? 0} syl.')],
      note: '$syllables of 10 syllables',
    ),
  ];

  @override
  List<String> reference() => [
        'Cards Shakespeare or an Actor attack or defend with go into the line instead of the discard pile.',
        'Exactly 10 syllables: resolve the COMPLETION effect of the last card, then discard the line. Over 10: discard it with no completion.',
        line.isEmpty ? 'The line is empty.' : 'Line so far: ${line.map((c) => '${c.title} (${c.def.syllables})').join(' · ')} = $syllables syllables.',
      ];

  @override
  Future<bool> disposePlayed(Card c) async {
    final g = game, combat = g.combat;
    if (c.owner != me || c.virtual || combat == null || combat.sideOf(me).card != c) return false;
    line.add(c);
    await g.emit(CardMoved(c, Zone.combat, Zone.inPlay, reason: ' (added to the line: $syllables syllables)'));
    final n = syllables;
    if (n < 10) return true;
    if (n == 10) {
      await g.say('Shakespeare: "${line.map((c) => c.title).join(', ')}!"');
      final done = _completions[c.def.upperTitle];
      if (done != null) {
        await g.say('Completion — ${c.title}: ${c.def.text['completion'] ?? ''}');
        await done(Fx(g, me, card: c, side: combat.sideOf(me)), c);
      }
    } else {
      await g.say('The line runs to $n syllables: it is discarded with no completion.');
    }
    for (final l in List.of(line)) {
      line.remove(l);
      g.toDiscardPile(l);
      await g.emit(CardMoved(l, Zone.inPlay, Zone.discard, reason: ' (line finished)'));
    }
    return true;
  }

  Future<void> returnActors(Fx x, {required bool all}) async {
    do {
      if (!bard.onBoard || !actors.any((f) => f.defeated)) return;
      if (!await x.game.summon(me, 'actor', x.zoneSpaces(bard), text: "Return a defeated Actor to Shakespeare's zone")) return;
    } while (all);
  }

  Map<String, _Completion> get _completions => {
        'HORROR': (x, c) async {
          final n = line.length - 1;
          if (n > 0 && x.oppFighter.alive) await x.damage(x.oppFighter, n);
        },
        'ONCE MORE UNTO THE BREACH': (x, c) => returnActors(x, all: true),
        'DECEIVE': (x, c) async {
          line.remove(c);
          me.hand.add(c);
          await x.game.emit(CardMoved(c, Zone.inPlay, Zone.hand, reason: ' (Deceive)'));
        },
        'REVISE': (x, c) => moveEach(x, x.game.onBoard, 2),
        'MY KINGDOM FOR A HORSE': (x, c) async => x.gainActions(2),
        'AGAIN': (x, c) => x.draw(1),
        'ALAS': (x, c) async {
          await x.draw(2);
          await x.heal(bard, 2);
        },
        'PLACES, PLACES!': (x, c) async {
          final busy = {for (final a in actors.where((a) => a.onBoard)) ...x.board.zonesOf(a.space!)};
          final spaces = x.allSpaces.where((s) => x.board.zonesOf(s).any((z) => !busy.contains(z)));
          if (bard.onBoard) await x.place(bard, spaces, text: 'Place Shakespeare in a zone with no Actors');
        },
        'THE IDES OF MARCH': (x, c) async {
          final f = await x.chooseFighter(x.enemies.toList(), 'The Ides of March: deal 2 damage to any opposing fighter', intent: Intent.harm);
          if (f != null) await x.damage(f, 2);
        },
        'ALL ARE PUNISHED': (x, c) => x.draw(1),
        'ET TU, BRUTE?': (x, c) async {
          for (final f in x.myFighters.toList()) {
            await x.place(f, x.allSpaces, text: 'Et Tu, Brute?: place ${f.name} in any space', optional: true);
          }
        },
        'SUCH SWEET SORROW': (x, c) => x.draw(1),
      };

  @override
  Map<String, CardScript> get cards => {
        'HORROR': CardScript(during: (x) async {
          final n = line.where((c) => c.def.upperTitle == 'HORROR').length;
          if (n > 0) x.addValue(n, 'HORROR cards in the line ($n)');
        }),
        'ONCE MORE UNTO THE BREACH': CardScript(after: (x) => returnActors(x, all: false)),
        'DECEIVE': cancelCard,
        'REVISE': CardScript(after: (x) => x.draw(x.won ? 2 : 1)),
        'MY KINGDOM FOR A HORSE': const CardScript(),
        'AGAIN': CardScript(after: (x) async {
          if (line.isEmpty) return;
          final first = line.first;
          if (!await x.yesNo('Again: return ${first.title} (first card of your line) to your hand?')) return;
          line.remove(first);
          me.hand.add(first);
          await x.game.emit(CardMoved(first, Zone.inPlay, Zone.hand, reason: ' (Again)'));
        }),
        'ALAS': CardScript(after: (x) async {
          if (x.lost) await x.heal(bard, 1);
        }),
        'PLACES, PLACES!': CardScript(after: (x) => moveEach(x, actors, 3)),
        'THE IDES OF MARCH': const CardScript(),
        'ALL ARE PUNISHED': CardScript(after: (x) async {
          for (final f in x.inZoneOf(x.fighter).where((f) => f != x.fighter).toList()) {
            await x.damage(f, 1);
          }
        }),
        'ET TU, BRUTE?': CardScript(during: (x) async {
          final n = x.myFighters.where((f) => x.adjacent(f, x.oppFighter)).length;
          if (n > 0) x.addValue(n, 'Your fighters adjacent ($n)');
        }),
        'SUCH SWEET SORROW': moveAfter(2),
      };
}

// ======================================================================= The Wayward Sisters

typedef SisterSpell = ({String name, Set<String> needs, String text});

/// Bubbling Brew: their cards go into the cauldron instead of the discard pile. After they
/// attack, they may cast one spell they have the ingredients for; then the whole cauldron is
/// discarded. Three Sisters of 6 health; any Sister plays any card; they lose when all fall.
///
/// UNVERIFIED: the spells come from a fan hero guide (gridbeast.gg), not the printed card:
/// snake+bat, snake+lizard, lizard+bat and all three.
class WaywardSisters extends HeroScript {
  List<Card> get cauldron => aside;

  static const List<SisterSpell> spells = [
    (name: 'Snake, bat and lizard', needs: {'snake', 'bat', 'lizard'}, text: 'Gain 1 action.'),
    (name: 'Lizard and bat', needs: {'lizard', 'bat'}, text: 'Deal 1 damage to a fighter that shares a zone with any of your fighters.'),
    (name: 'Snake and bat', needs: {'snake', 'bat'}, text: 'Draw 1 card. One of your fighters recovers 1 health.'),
    (name: 'Snake and lizard', needs: {'snake', 'lizard'}, text: 'Move any fighter up to 3 spaces.'),
  ];

  Set<String> get ingredients => {for (final c in cauldron) ?c.def.ingredient};

  @override
  List<Card> discardPileFor(Card c) => c.owner == me ? cauldron : c.owner.discard;

  @override
  List<String> reference() => [
        'Cards you would discard (played, boosted, discarded) go into the cauldron. After you attack you may cast one spell you have the ingredients for, then the cauldron is discarded.',
        for (final s in spells) 'Spell · ${s.name}: ${s.text}',
        'Cauldron: ${cauldron.isEmpty ? 'empty' : cauldron.map((c) => '${c.title} (${c.def.ingredient})').join(', ')}.',
        'Three Sisters with their own health; you lose when the last one falls.',
      ];

  @override
  List<OpenZone> openZones() => [
    OpenZone(
      id: 'cauldron',
      label: 'CAULDRON',
      cards: [for (final c in cauldron) OpenCard.of(c, tag: c.def.ingredient)],
      note: ingredients.isEmpty ? '' : 'Ingredients: ${(ingredients.toList()..sort()).join(', ')}',
    ),
  ];

  @override
  List<String> status() => [
        'Cauldron: ${cauldron.length}${ingredients.isEmpty ? '' : ' (${(ingredients.toList()..sort()).join(', ')})'}',
      ];

  @override
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {
    if (p != me || kind != ActionKind.attack || g.turnEnded) return;
    final have = ingredients;
    final castable = spells.where((s) => have.containsAll(s.needs)).toList();
    if (castable.isEmpty) return;
    final i = await g.chooseOption(me, [for (final s in castable) '${s.name}: ${s.text}', "Don't cast a spell"], 'Bubbling Brew: cast a spell?');
    if (i >= castable.length) return;
    await cast(castable[i]);
    for (final c in List.of(cauldron)) {
      cauldron.remove(c);
      me.discard.add(c);
      await g.emit(CardMoved(c, Zone.inPlay, Zone.discard, reason: ' (cauldron emptied)'));
    }
  }

  Future<void> cast(SisterSpell s) async {
    final g = game;
    await g.say('The Wayward Sisters cast a spell: ${s.text}');
    final x = Fx(g, me, fighter: me.heroFighter);
    switch (spells.indexOf(s)) {
      case 0:
        x.gainActions(1);
      case 1:
        final mine = x.myFighters.toList();
        final targets = g.onBoard.where((f) => mine.any((m) => g.sameZone(m, f))).toList();
        final f = await x.chooseFighter(targets, 'Deal 1 damage to a fighter in a zone with one of your fighters', intent: Intent.harm);
        if (f != null) await x.damage(f, 1);
      case 2:
        await x.draw(1);
        final f = await x.chooseFighter(x.myFighters.toList(), 'One of your fighters recovers 1 health', intent: Intent.help);
        if (f != null) await x.heal(f, 1);
      default:
        final f = await x.chooseFighter(g.onBoard.toList(), 'Move any fighter up to 3 spaces', intent: Intent.none);
        if (f != null) await x.move(f, 3);
    }
  }

  /// "Return a card in your discard pile to your cauldron."
  Future<void> discardToCauldron(Fx x) async {
    final c = await x.game.chooseCard(x.me, x.me.discard, 'Return a card from your discard pile to your cauldron',
        intent: Intent.gainOwn, source: x.card);
    if (c == null) return;
    x.me.discard.remove(c);
    cauldron.add(c);
    await x.game.emit(CardMoved(c, Zone.discard, Zone.inPlay, reason: ' (into the cauldron)'));
  }

  Future<void> toCauldron(Card c, String why) async {
    me.deck.remove(c) || me.hand.remove(c);
    cauldron.add(c);
    await game.emit(CardMoved(c, Zone.deck, Zone.inPlay, reason: ' ($why: into the cauldron)'));
  }

  int distinct(Fx x) => ingredients.length;

  @override
  Map<String, CardScript> get cards => {
        'FIRE BURN AND CAULDRON BUBBLE': CardScript(immediately: discardToCauldron),
        'SOMETHING WICKED THIS WAY COMES': CardScript(effect: (x) async {
          final first = await x.option([for (final s in spells) '${s.name}: ${s.text}'], 'Something Wicked: cast any spell');
          await cast(spells[first]);
          final rest = [for (final s in spells) if (s != spells[first]) s];
          final second = await x.option([for (final s in rest) '${s.name}: ${s.text}'], 'Something Wicked: cast a different spell');
          await cast(rest[second]);
        }),
        'WARD': CardScript(after: (x) async {
          if (x.oppFighter.onBoard && x.fighter.onBoard) {
            await x.place(x.oppFighter, x.zoneSpaces(x.fighter), text: "Ward: place ${x.oppFighter.name} in your fighter's zone");
          }
        }),
        'CURIOUS FAMILIAR': CardScript(after: (x) async {
          final c = await x.game.chooseCard(x.me, cauldron, 'Curious Familiar: return a card from your cauldron to your hand',
              intent: Intent.gainOwn, source: x.card);
          if (c == null) return;
          cauldron.remove(c);
          x.me.hand.add(c);
          await x.game.emit(CardMoved(c, Zone.inPlay, Zone.hand, reason: ' (from the cauldron)'));
        }),
        'PRICKING OF MY THUMBS': CardScript(after: (x) async {
          if (x.defending && x.damageDealt > 0 && x.oppFighter.alive) await x.damage(x.oppFighter, x.damageDealt);
        }),
        'TOIL AND TROUBLE': CardScript(during: (x) async {
          if (distinct(x) > 0) x.addValue(distinct(x), 'Ingredients in the cauldron');
        }),
        'DOUBLE, DOUBLE': CardScript(during: (x) async {
          if (distinct(x) > 0) x.addValue(distinct(x), 'Ingredients in the cauldron');
        }),
        'PROPHECY': CardScript(effect: (x) async {
          final top = x.me.deck.take(4).toList();
          if (top.isEmpty) return;
          final keep = await x.game.chooseCards(x.me, top, 2, 2, 'Prophecy: put 2 in your hand', intent: Intent.gainOwn, source: x.card);
          x.me.deck.removeWhere(top.contains);
          x.me.hand.addAll(keep);
          final rest = top.where((c) => !keep.contains(c)).toList();
          final order = <Card>[];
          while (rest.isNotEmpty) {
            final c = rest.length == 1
                ? rest.first
                : await x.game.chooseCard(x.me, rest, 'Prophecy: which card goes on top?', intent: Intent.gainOwn, source: x.card);
            rest.remove(c);
            order.add(c!);
          }
          x.me.deck.insertAll(0, order);
          await x.game.emit(CardsDrawn(x.me, keep));
        }),
        'UNNATURAL REMEDY': CardScript(immediately: (x) async {
          final cards = await x.game.chooseCards(x.me, cauldron, 0, 3, 'Unnatural Remedy: discard up to 3 cards from your cauldron',
              intent: Intent.gainOwn, source: x.card);
          for (final c in cards) {
            cauldron.remove(c);
            x.me.discard.add(c);
            await x.game.emit(CardMoved(c, Zone.inPlay, Zone.discard, reason: ' (from the cauldron)'));
            final f = await x.chooseFighter(x.game.onBoard.toList(), 'Unnatural Remedy: a fighter recovers 1 health', intent: Intent.help);
            if (f != null) await x.heal(f, 1);
          }
        }),
        'HURLY-BURLY': CardScript(during: (x) async {
          if (x.me.deck.isEmpty) return;
          final c = x.me.deck.first;
          await x.game.emit(Revealed(x.me, [c], ' from the top of their deck (Hurly-Burly)'));
          final boost = c.def.boost ?? 0;
          // The opponent chooses; the option that is worse for the Sisters comes first for the AI.
          final opts = ['Put ${c.title} in their hand', 'Put ${c.title} in their cauldron (+$boost to the attack)'];
          final order = boost >= 2 ? [0, 1] : [1, 0];
          final i = order[await x.option([for (final k in order) opts[k]], 'Hurly-Burly: choose one', who: x.opp, intent: Intent.harm)];
          if (i == 0) {
            x.me.deck.remove(c);
            x.me.hand.add(c);
            await x.game.emit(CardsDrawn(x.me, [c]));
          } else {
            await toCauldron(c, 'Hurly-Burly');
            if (boost > 0) x.addValue(boost, '${c.title} (BOOST)');
          }
        }),
        'ALL-SEEING FAMILIAR': CardScript(
          immediately: discardToCauldron,
          after: (x) async {
            if (!x.won || x.me.deck.isEmpty) return;
            final c = x.me.deck.first;
            await x.game.emit(Revealed(x.me, [c], ' (All-Seeing Familiar)', viewer: x.me));
            final i = await x.option(['Put ${c.title} in your hand', 'Put ${c.title} in your cauldron'], 'All-Seeing Familiar');
            if (i == 0) {
              x.me.deck.remove(c);
              x.me.hand.add(c);
              await x.game.emit(CardsDrawn(x.me, [c]));
            } else {
              await toCauldron(c, 'All-Seeing Familiar');
            }
          },
        ),
        'THE STARS ALIGN': CardScript(during: (x) async {
          final zones = {for (final f in x.myFighters) for (final s in f.spaces) ...x.board.zonesOf(s)};
          x.setValue(zones.length, 'Zones your fighters are in');
        }),
      };
}
