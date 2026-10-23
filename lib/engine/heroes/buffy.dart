/// Buffy the Vampire Slayer: Angel, Buffy, Spike (Willow is in marvel_buffy.dart).
library;

import '../combat.dart';
import '../defs.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ==================================================================================== Angel

/// After Angel or Faith attacks, if you lost the combat, draw 1 card.
class Angel extends HeroScript {
  Fighter get angel => me.heroFighter;
  Fighter? get faith => me.fighters.where((f) => f.isSidekick).firstOrNull;

  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (c.attacker.player == me && !c.attackerWon) {
      await g.say('Angel: the attack was lost, draw 1 card.');
      await g.draw(me, 1);
    }
  }

  @override
  Map<String, CardScript> get cards => {
    'BROODING': CardScript(after: (x) async {
      if (x.lost && x.oppFighter.onBoard) await x.damage(x.oppFighter, 1);
    }),
    'HAUNTED BY THE FACES': CardScript(after: (x) async {
      if (x.lost && angel.onBoard) {
        await x.place(angel, x.zoneSpaces(angel), text: 'You may place Angel in any space in his zone', optional: true);
      }
    }),
    'ANGELUS, SCOURGE OF EUROPE': vanilla,
    'DISENGAGE': CardScript(after: (x) async {
      final f = x.fighter;
      if (!f.onBoard) return;
      final spaces = x.zoneSpaces(f).where((s) => s != f.space && x.game.isEmpty(s));
      await x.place(f, spaces, text: 'Move ${f.name} to another space in their zone');
    }),
    'THE ROGUE SLAYER': CardScript(after: (x) async {
      final fa = faith;
      if (fa != null && fa.onBoard) await damageAdjacentEnemies(x, fa, 1);
    }),
    'CURSED WITH A SOUL': CardScript(after: (x) async {
      if (x.lost) await x.heal(x.fighter, 1);
    }),
    'FIVE BY FIVE': CardScript(after: (x) async {
      final fa = faith;
      if (fa != null && fa.onBoard) await x.move(fa, 5, throughOpp: true);
    }),
    'KILLER OF THE DEAD': CardScript(effect: (x) async {
      final fa = faith;
      if (fa == null || !fa.onBoard) return;
      final f = await x.chooseFighter(x.enemiesAdjacentTo(fa).toList(), 'Killer of the Dead: deal 2 damage', intent: Intent.harm);
      if (f != null) await x.damage(f, 2);
    }),
    'WISDOM OF AGES': drawAfter(1),
  };
}

// ==================================================================================== Buffy

/// Buffy may move through spaces containing opposing fighters (including when moved by effects).
/// Before the game, choose Giles or Xander as her sidekick; only that sidekick's 5 cards are
/// shuffled into the deck (rulebook).
class Buffy extends HeroScript {
  Fighter get buffy => me.heroFighter;
  String sidekick = 'giles';

  @override
  bool movesThroughEnemies(Game g, Fighter f) => f == buffy;

  @override
  Future<void> beforeDeck() async {
    final i = await game.chooseOption(me, ['Giles', 'Xander'], 'Choose Buffy\'s sidekick for this game', intent: Intent.none);
    sidekick = i == 0 ? 'giles' : 'xander';
    final other = sidekick == 'giles' ? 'xander' : 'giles';
    me.fighters.removeWhere((f) => f.id == other);
    await game.emit(StatusChanged(me, 'Buffy fights alongside ${i == 0 ? 'Giles' : 'Xander'}.'));
  }

  @override
  Iterable<CardDef> deckCards() {
    final other = sidekick == 'giles' ? 'xander' : 'giles';
    return super.deckCards().where((c) => !c.fighters.contains(other));
  }

  Fighter? get xander => me.fighters.where((f) => f.id == 'xander').firstOrNull;

  @override
  Map<String, CardScript> get cards => {
    'CARTWHEEL KICK': CardScript(after: (x) async {
      if (!buffy.onBoard) return;
      await x.move(buffy, 3);
      await damageAdjacentEnemies(x, buffy, 1);
    }),
    'INSIGHT': const CardScript(effect: pickDiscard),
    'MR. POINTY': vanilla,
    'TRAINING': CardScript(effect: (x) => x.draw(3)),
    'DARING STRIKE': CardScript(after: (x) async {
      if (x.won) {
        await x.draw(2);
      } else if (x.fighter.alive) {
        await x.damage(x.fighter, 1);
      }
    }),
    "SLAYER'S STRENGTH": CardScript(after: (x) async {
      if (!buffy.onBoard) return;
      final around = x.adjacentTo(buffy).toList();
      if (around.isEmpty || !await x.yesNo("Slayer's Strength: move every fighter adjacent to Buffy to another space in their zone?")) return;
      final moved = <Fighter>[];
      for (final f in around) {
        if (!f.onBoard || x.game.cannotLeave(f)) continue;
        final spaces = x.zoneSpaces(f).where((s) => s != f.space && x.game.isEmpty(s)).toList();
        if (spaces.isEmpty) continue;
        if (await x.place(f, spaces, text: 'Move ${f.name} to another space in their zone')) moved.add(f);
      }
      for (final f in moved) {
        await x.damage(f, 1);
      }
    }),
    'MILITARY KNOWLEDGE': drawAfter(1),
    'RAPID RECOVERY': CardScript(after: (x) => x.heal(buffy, 1)),
    'RIGHT-HAND MAN': CardScript(during: (x) async {
      final xa = xander;
      if (xa != null && xa.onBoard && buffy.onBoard && x.adjacent(xa, buffy)) x.setValue(6);
    }),
  };
}

// ==================================================================================== Spike

/// At the start of your turn, you may place a Shadow token in any space adjacent to Spike or
/// Drusilla. Spike has 3 shadow tokens; with all 3 on the board, he may move one instead. A
/// space may hold more than one token (rulebook).
class Spike extends HeroScript {
  static const tokens = 3;
  Fighter get spike => me.heroFighter;
  Fighter? get drusilla => me.fighters.where((f) => f.isSidekick).firstOrNull;

  Iterable<Token> get shadows => game.board.tokens.where((t) => t.kind == 'shadow' && t.owner == me);
  bool shadowAt(int? space) => space != null && shadows.any((t) => t.space == space);
  bool onShadow(Fighter f) => f.onBoard && shadowAt(f.space);

  @override
  List<String> status() => ['${tokens - shadows.length} shadow token${tokens - shadows.length == 1 ? '' : 's'} left'];

  /// Puts a shadow token on [space]: a new one while any are left, otherwise one moved from the
  /// board (the player picks which).
  Future<void> putShadow(Game g, int space, {Set<int> keep = const {}}) async {
    if (shadows.length < tokens) {
      g.board.tokens.add(Token('shadow', me, space: space));
    } else {
      final movable = shadows.where((t) => !keep.contains(t.space)).toList();
      if (movable.isEmpty) return;
      final from = await g.chooseSpace(me, {for (final t in movable) t.space!}, 'All 3 shadow tokens are out: choose one to move',
          intent: Intent.none);
      if (from == null) return;
      movable.firstWhere((t) => t.space == from).space = space;
    }
    await g.emit(StatusChanged(me, 'A shadow token falls on a space.'));
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me) return;
    final near = {
      for (final f in [spike, drusilla])
        if (f != null && f.onBoard) ...g.board.neighbours(f.space!),
    };
    if (near.isEmpty) return;
    final s = await g.chooseSpace(me, near, shadows.length < tokens ? 'You may place a shadow token next to Spike or Drusilla' : 'You may move a shadow token next to Spike or Drusilla',
        intent: Intent.none, optional: true);
    if (s != null) await putShadow(g, s);
  }

  @override
  Map<String, CardScript> get cards => {
    'ALWAYS SURPRISING': CardScript(during: (x) async {
      final top = x.me.deck.firstOrNull;
      if (top == null) return;
      final doubled = drusilla != null && onShadow(drusilla!);
      if (await x.boostThis(blind: true, text: 'Always Surprising: BLIND BOOST') && doubled) {
        x.addValue(x.game.boostValueOf(top), 'Shadow: BOOST doubled');
      }
    }),
    'BLOODY HELL!': CardScript(after: (x) async {
      final o = x.oppFighter;
      if (!o.onBoard) return;
      final extra = x.board.neighbours(o.space!).where(shadowAt).length;
      await x.damage(o, 1 + extra);
    }),
    'THE SIGHT': CardScript(effect: (x) async {
      final t = x.opp;
      if (!await x.game.lookAtHand(x.me, t)) return;
      final n = t.onBoard.any(onShadow) ? 2 : 1;
      await x.discard(t, n, chooser: x.me);
    }),
    'ARROGANCE': CardScript(during: (x) async {
      if (!await x.yesNo('Arrogance: discard your whole hand to make this card 6?', intent: Intent.loseOwn)) return;
      for (final c in List.of(x.me.hand)) {
        await x.game.discardCard(c, reason: ' (Arrogance)');
      }
      x.setValue(6);
    }),
    'EMPATHY': CardScript(after: (x) => x.draw(onShadow(x.oppFighter) ? 3 : 1)),
    "LET'S DANCE": CardScript(during: (x) async {
      if (onShadow(spike) || onShadow(x.oppFighter)) await x.boostThis();
    }),
    'SEEK THE SHADOWS': CardScript(effect: (x) async {
      await x.draw(2);
      if (!spike.onBoard) return;
      // Spike's space first, then the adjacent spaces in the order the player picks, while
      // tokens last (moving ones already elsewhere once the 3 are out).
      final targets = <int>{spike.space!};
      if (!shadowAt(spike.space)) await putShadow(x.game, spike.space!, keep: targets);
      final left = x.board.neighbours(spike.space!).where((s) => !shadowAt(s)).toList();
      bool tokenAvailable() => shadows.length < tokens || shadows.any((t) => !targets.contains(t.space));
      while (left.isNotEmpty && tokenAvailable()) {
        final s = left.length == 1 ? left.first : await x.chooseSpace(left, 'Place a shadow token next to Spike', intent: Intent.none);
        if (s == null) break;
        left.remove(s);
        targets.add(s);
        await putShadow(x.game, s, keep: targets);
      }
    }),
    'THE RUSH': CardScript(during: (x) async {
      if (onShadow(spike) || onShadow(x.oppFighter)) x.setValue(5);
    }),
  };
}
