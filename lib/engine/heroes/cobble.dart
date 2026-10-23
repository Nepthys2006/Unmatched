/// Cobble & Fog: Sherlock Holmes, Dracula, Jekyll & Hyde, Invisible Man.
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ========================================================================== Sherlock Holmes

/// Effects on HOLMES and DR. WATSON cards cannot be canceled by an opponent.
class SherlockHolmes extends HeroScript {
  @override
  bool uncancelable(Game g, Side s) => s.player == me && s.card != null && !s.card!.def.isAny;

  @override
  Map<String, CardScript> get cards => {
        'COUNTERPUNCH': CardScript(after: (x) async {
          if (x.adjacent(x.hero, x.oppFighter)) await x.damage(x.oppFighter, 2);
        }),
        'ELIMINATE THE IMPOSSIBLE': const CardScript(effect: pickDiscard),
        'FIXED POINT IN A CHANGING AGE': CardScript(after: (x) async {
          final w = x.fighter;
          if (x.adjacent(w, x.hero)) {
            await x.heal(w, 1);
            await x.heal(x.hero, 1);
          }
        }),
        'CONFIRM SUSPICION': CardScript(effect: (x) async {
          final v = await x.game.chooseNumber(x.me, 0, 8, 'Confirm Suspicion: name a value');
          final matching = x.opp.hand.where((c) => !c.def.isScheme && c.def.value == v).toList();
          if (matching.isEmpty) {
            await x.game.emit(Revealed(x.opp, List.of(x.opp.hand), ' (no card with value $v)'));
            x.me.script.seen(x.opp.hand);
            return;
          }
          final c = await x.game.chooseCard(x.opp, matching, 'Discard a card with value $v', intent: Intent.loseOwn);
          await x.game.discardCard(c!, byOpponent: true);
          await x.damage(x.opp.heroFighter, c.def.boost ?? 0);
        }),
        'ELEMENTARY': CardScript(
          onReveal: (x) async {
            x.mySide
              ..faceUp = true
              ..vars['prediction'] = await x.game.chooseNumber(x.me, 0, 8, "Elementary: predict the printed value of the opponent's attack");
          },
          during: (x) async {
            if (x.oppCard?.def.value == x.mySide.vars['prediction']) {
              x.cancelOpponent();
              x.ignoreOpponentValue();
            }
          },
        ),
        'MASTER OF DISGUISE': CardScript(effect: (x) async {
          final h = x.opp.heroFighter;
          await x.game.swap(x.hero, h);
          await x.damage(h, 1);
        }),
        'SERVICE REVOLVER': vanilla,
        'ADMINISTER AID': CardScript(effect: (x) async {
          if (x.hero.onBoard) {
            await x.place(x.fighter, x.board.neighbours(x.hero.space!), text: 'Place Dr. Watson next to Holmes');
          }
          await x.heal(x.hero, 1);
          await x.draw(1);
        }),
        'EDUCATION NEVER ENDS': CardScript(after: (x) async {
          if (x.won) {
            await x.draw(1, x.opp);
          } else {
            await x.draw(2);
          }
        }),
        'THE GAME IS AFOOT': CardScript(after: (x) => x.move(x.hero, 3)),
        'DEDUCE STRATEGY': CardScript(during: (x) async {
          final c = x.oppCard;
          if (c == null) return;
          final boost = c.def.boost ?? 0;
          final better = boost < x.oppSide.printed;
          if (await x.yesNo("Change the printed value of ${c.title} (${x.oppSide.printed}) to its BOOST value ($boost)?",
              intent: better ? Intent.help : Intent.harm)) {
            x.oppSide.printedOverride = boost;
            x.game.addOp(x.oppSide, ValueOp.add(0, 'Deduce Strategy: printed value is $boost'));
          }
        }),
        'STUDY METHODS': CardScript(after: (x) async {
          if (x.won) await x.game.lookAtHand(x.me, x.opp);
        }),
      };
}

// ================================================================================== Dracula

/// At the start of your turn, you may deal 1 damage to a fighter adjacent to Dracula. If you
/// do, draw a card.
class Dracula extends HeroScript {
  Iterable<Fighter> get sisters => me.fighters.where((f) => f.isSidekick);

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    final d = me.heroFighter;
    if (active != me || !d.onBoard) return;
    final f = await g.chooseFighter(me, g.adjacentFighters(d), 'Bloodthirsty: deal 1 damage to a fighter next to Dracula and draw?',
        optional: true, skipLabel: 'No', intent: Intent.harm);
    if (f == null) return;
    await g.damage(f, 1, info: DamageInfo(source: d, by: me));
    await g.draw(me, 1);
  }

  @override
  Map<String, CardScript> get cards => {
        'PREY UPON': CardScript(effect: (x) async {
          var dealt = 0;
          for (final f in x.enemiesAdjacentTo(x.hero).toList()) {
            dealt += await x.damage(f, 1);
          }
          await x.heal(x.hero, dealt);
        }),
        'THIRST FOR SUSTENANCE': CardScript(after: (x) async {
          if (!x.won || !x.oppFighter.onBoard || !x.hero.onBoard) return;
          await x.place(x.hero, x.board.neighbours(x.oppFighter.space!), text: 'Place Dracula next to the opposing fighter');
        }),
        'BEASTFORM': CardScript(during: (x) async {
          final cards = await x.game.chooseCards(x.me, x.me.hand, 0, x.me.hand.length, 'Beastform: discard any number of cards (+1 each)',
              intent: Intent.boost);
          for (final c in cards) {
            await x.game.discardCard(c, reason: ' (Beastform)');
          }
          if (cards.isNotEmpty) x.addValue(cards.length, 'Beastform: ${cards.length} discarded');
        }),
        'MISTFORM': CardScript(effect: (x) async {
          await x.place(x.hero, x.allSpaces, text: 'Place Dracula in any space');
          x.gainActions(1);
        }),
        'BAPTISM OF BLOOD': CardScript(effect: (x) async {
          await x.heal(x.hero, 2);
          if (x.hero.onBoard) await x.game.summon(x.me, 'the-sisters', x.zoneSpaces(x.hero), text: "Return a Sister to Dracula's zone");
        }),
        'FEEDING FRENZY': CardScript(during: (x) async {
          final n = sisters.where((s) => s.onBoard && x.sameZone(s, x.oppFighter)).length;
          if (n > 0) x.addValue(n, 'Sisters in the zone');
        }),
        'LOOK INTO MY EYES': CardScript(during: (x) async {
          final b = x.oppCard?.def.boost ?? 0;
          if (b > 0) x.addValue(b, "BOOST of the opponent's attack");
        }),
        'RAVENING SEDUCTION': CardScript(effect: (x) async {
          final f = await x.chooseFighter(x.game.onBoard, 'Ravening Seduction: move any fighter up to 2 spaces', intent: Intent.none);
          if (f == null) return;
          await x.move(f, 2);
          if (!f.onBoard) return;
          final n = x.adjacentTo(f).where((o) => sisters.contains(o)).length;
          if (n > 0) await x.damage(f, n);
        }),
      };
}

// ============================================================================ Jekyll & Hyde

/// Starts as Dr. Jekyll. At the start of your turn, you may transform. While Mr. Hyde, take 1
/// damage after you maneuver. Dr. Jekyll cards need Jekyll, Mr. Hyde cards need Hyde.
class JekyllHyde extends HeroScript {
  bool hyde = false;

  @override
  String get heroName => hyde ? 'Mr. Hyde' : 'Dr. Jekyll';

  @override
  bool fighterMayUse(Card c, Fighter f) {
    final u = c.def.usedBy.toUpperCase();
    if (u.contains('JEKYLL')) return !hyde;
    if (u.contains('HYDE')) return hyde;
    return true;
  }

  Future<void> transform(bool toHyde) async {
    if (hyde == toHyde) return;
    hyde = toHyde;
    await game.emit(StatusChanged(me, 'He transforms into $heroName.'));
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || !me.heroFighter.onBoard) return;
    final i = await g.chooseOption(me, ['Stay as $heroName', 'Transform into ${hyde ? 'Dr. Jekyll' : 'Mr. Hyde'}'],
        'The Serum: transform?', intent: Intent.none);
    if (i == 1) await transform(!hyde);
  }

  @override
  Future<void> afterManeuver(Game g, Player p) async {
    if (p == me && hyde) await g.damage(me.heroFighter, 1, info: DamageInfo(by: me));
  }

  @override
  List<String> status() => [heroName.toUpperCase()];

  @override
  Map<String, CardScript> get cards => {
        'FOREVER HYDE': CardScript(during: (x) async {
          final jekyll = x.me.hand.where((c) => c.def.usedBy.toUpperCase().contains('JEKYLL'));
          final cards = await x.game.chooseCards(x.me, jekyll, 0, jekyll.length, 'Forever Hyde: discard Dr. Jekyll cards (+2 each)',
              intent: Intent.boost);
          for (final c in cards) {
            await x.game.discardCard(c, reason: ' (Forever Hyde)');
          }
          if (cards.isNotEmpty) x.addValue(2 * cards.length, 'Forever Hyde: ${cards.length} discarded');
        }),
        'PURE EVIL': CardScript(effect: (x) async {
          await x.place(x.hero, x.zoneSpaces(x.hero), text: 'Place Mr. Hyde in any space in his zone');
          for (final f in x.adjacentTo(x.hero).toList()) {
            await x.damage(f, 2);
          }
        }),
        'DISTRACTED TRIAGE': CardScript(after: (x) async {
          if (x.won) await x.heal(x.hero, 2);
        }),
        'STRANGE CASE': CardScript(effect: (x) async {
          if (x.me.deck.isEmpty) return;
          final c = x.me.deck.first;
          await x.game.emit(Revealed(x.me, [c], ' (Strange Case)'));
          final f = await x.chooseFighter(x.adjacentTo(x.hero), 'Deal ${c.def.boost ?? 0} damage to an adjacent fighter', intent: Intent.harm);
          if (f != null) await x.damage(f, c.def.boost ?? 0);
          await x.game.toHand(c);
        }),
        'SUCCUMB TO COMPULSION': CardScript(after: (x) async {
          await x.move(x.hero, 2);
          await transform(true);
        }),
        'CALMING RESEARCH': CardScript(effect: (x) async {
          await x.heal(x.hero, 2);
          final n = await x.game.chooseNumber(x.me, 1, 3, 'Calming Research: draw up to 3 cards');
          final drawn = <Card>[];
          for (var i = 0; i < n && x.me.deck.isNotEmpty; i++) {
            drawn.add(x.me.deck.removeAt(0));
          }
          if (drawn.isEmpty) return;
          x.me.hand.addAll(drawn);
          await x.game.emit(CardsDrawn(x.me, drawn));
          final keep = await x.game.chooseCard(x.me, drawn, 'Keep one card', intent: Intent.gainOwn);
          var rest = drawn.where((c) => c != keep).toList();
          while (rest.isNotEmpty) {
            final next = await x.game.chooseCard(x.me, rest, 'Put a card on the bottom of your deck (first goes deepest)', intent: Intent.none);
            rest.remove(next);
            await x.game.toDeck(next!, bottom: true);
          }
        }),
        'MADNESS RELENTS': CardScript(after: (x) => transform(false)),
        'RECOILING BLOW': CardScript(after: (x) async {
          if (x.hero.onBoard) await x.place(x.hero, x.zoneSpaces(x.hero), text: 'Place Mr. Hyde in any space in his zone');
          await transform(false);
        }),
        'WITH HASTE!': CardScript(after: (x) => x.move(x.hero, 4)),
        'SCIENTIFIC METHOD': CardScript(after: (x) async {
          if (x.defending) await x.draw(x.damageDealt);
        }),
        'DUALITY OF MAN': CardScript(during: (x) async {
          if ((!hyde && x.defending) || (hyde && x.attacking)) x.setValue(6);
        }),
      };
}

// ============================================================================ Invisible Man

/// Places 3 fog tokens in his zone at the start. On a fog space his defense cards are +1, and he
/// may move between fog spaces as if they were adjacent.
class InvisibleMan extends HeroScript {
  bool vanished = false;
  bool startedOnFog = false;

  Fighter get im => me.heroFighter;
  Iterable<Token> get fog => game.board.tokens.where((t) => t.kind == 'fog');
  bool onFog([int? space]) => (space ?? im.space) != null && game.board.hasToken((space ?? im.space)!, 'fog');
  Token? fogAt(int? space) => space == null ? null : game.board.tokensAt(space, 'fog').firstOrNull;

  @override
  Future<void> afterHeroPlaced() async {
    for (var i = 0; i < 3; i++) {
      final spaces = game.board.zoneOf(im.space!).where((s) => game.isEmpty(s) && !onFog(s)).toList();
      final options = spaces.isNotEmpty ? spaces : game.emptySpaces().where((s) => !onFog(s)).toList();
      final t = Token('fog', me);
      final s = await game.chooseSpace(me, options, 'Place fog token ${i + 1} in Invisible Man\'s zone', intent: Intent.moveOwn, subject: t);
      t.space = s;
      game.board.tokens.add(t);
      await game.emit(StatusChanged(me, ''));
    }
  }

  @override
  Iterable<int> extraSteps(Game g, Fighter f, int from) =>
      f == im && onFog(from) ? fog.map((t) => t.space!).where((s) => s != from) : const [];

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player == me && !s.isAttacker && s.fighter == im && onFog()) yield const ValueOp.add(1, 'Invisible Man on fog');
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    startedOnFog = im.onBoard && onFog();
    if (active != me || !vanished) return;
    vanished = false;
    im.offBoard = false;
    final from = im.space;
    final s = await g.chooseSpace(me, g.board.spaceIds.where(g.isEmpty), 'Place Invisible Man in any space',
        intent: Intent.moveOwn, subject: im);
    im.space = s ?? from;
    await g.emit(Returned(im));
  }

  @override
  List<String> status() => [if (vanished) 'VANISHED', if (!vanished && im.onBoard && onFog()) 'ON FOG'];

  /// [who] moves one fog token up to [n] spaces (along the lines; never onto another fog).
  Future<void> moveFog(Player who, int n, {Token? only, Token? except, bool anywhere = false}) async {
    final tokens = only != null ? [only] : fog.where((t) => t != except).toList();
    if (tokens.isEmpty) return;
    final t = tokens.length == 1
        ? tokens.first
        : await game.choose<Token>(who, Ask.space, 'Choose a fog token to move', [for (final t in tokens) Choice('Fog at ${t.space}', t)],
            intent: Intent.none);
    if (t == null) return;
    final dest = anywhere
        ? game.board.spaceIds.where((s) => s != t.space && !onFog(s)).toList()
        : _within(t.space!, n).where((s) => s == t.space || !onFog(s)).toList();
    final s = await game.chooseSpace(who, dest, 'Move the fog token', intent: who == me ? Intent.moveOwn : Intent.moveEnemy, subject: t);
    if (s != null && s != t.space) {
      t.space = s;
      await game.emit(StatusChanged(me, ''));
    }
  }

  Set<int> _within(int from, int n) {
    final out = {from};
    var frontier = {from};
    for (var i = 0; i < n; i++) {
      frontier = {for (final s in frontier) ...game.board.neighbours(s)}..removeAll(out);
      out.addAll(frontier);
    }
    return out;
  }

  @override
  Map<String, CardScript> get cards => {
        'INTO THIN AIR': CardScript(after: (x) async {
          await x.move(im, 1);
          await moveFog(x.opp, 3);
        }),
        'CONFOUND': CardScript(after: (x) async {
          final pay = x.opp.hand.isNotEmpty &&
              await x.yesNo('Confound: discard 1 card to stop the fog moving?', who: x.opp, intent: Intent.harm);
          if (pay) {
            await x.discard(x.opp, 1);
            return;
          }
          for (final t in fog.toList()) {
            if (await x.yesNo('Move the fog at space ${t.space} to another space?', intent: Intent.none)) {
              await moveFog(x.me, 0, only: t, anywhere: true);
            }
          }
        }),
        'DREAMING OF REVENGE': CardScript(after: (x) async {
          if (!onFog()) return;
          for (final f in x.enemies.where((f) => onFog(f.space)).toList()) {
            await x.damage(f, 1);
          }
        }),
        'IMPOSSIBLE TO SEE': CardScript(immediately: (x) async {
          if (x.oppCard != null) x.oppSide.lockZero = true;
        }),
        'ROLLING FOG': CardScript(effect: (x) async {
          await moveFog(x.me, 0, anywhere: true);
          x.gainActions(1);
        }),
        'STEP LIGHTLY': CardScript(effect: (x) async {
          final f = await x.chooseFighter(x.adjacentTo(im), 'Deal ${onFog() ? 3 : 1} damage to an adjacent fighter', intent: Intent.harm);
          if (f != null) await x.damage(f, onFog() ? 3 : 1);
          await moveFog(x.opp, 2);
        }),
        'SURPRISE ATTACK': CardScript(
          immediately: (x) async => x.cancelOpponent(),
          after: (x) async {
            final t = fogAt(im.space);
            if (t != null) await moveFog(x.me, 0, only: t, anywhere: true);
          },
        ),
        'CODED NOTES': CardScript(after: (x) async {
          await x.draw(3);
          final picks = await x.game.chooseCards(x.me, x.me.hand, 2, 2, 'Coded Notes: put 2 cards on top of your deck (first = top)',
              intent: Intent.loseOwn);
          for (final c in picks.reversed) {
            await x.game.toDeck(c);
          }
        }),
        'COVERT PREPARATION': CardScript(after: (x) async {
          await x.draw(1);
          final before = {for (final t in fog) t: t.space};
          await moveFog(x.me, 2);
          final moved = fog.where((t) => t.space != before[t]).firstOrNull;
          await moveFog(x.opp, 2, except: moved ?? fog.first);
        }),
        'EMERGE FROM MIST': valueIf((x) => startedOnFog, 5),
        'LURKING': CardScript(after: (x) async {
          await x.draw(1);
          final i = await x.option(['Move Invisible Man to a space with a fog token', 'Move 1 fog token up to 3 spaces'], 'Lurking: choose 1');
          if (i == 0) {
            if (im.onBoard) await x.place(im, fog.map((t) => t.space!), text: 'Move Invisible Man to a fog space');
          } else {
            await moveFog(x.me, 3);
          }
        }),
        'VANISH': CardScript(effect: (x) async {
          await x.heal(im, 1);
          vanished = true;
          im.offBoard = true;
          await x.game.emit(StatusChanged(x.me, 'Invisible Man vanishes from the board.'));
          if (x.game.turn.actionsTaken == 0) x.game.endTurn();
        }),
        'REIGN OF TERROR': CardScript(effect: (x) async {
          if (!onFog()) return;
          final f = await x.chooseFighter(x.enemies, 'Deal 2 damage to any one opposing fighter', intent: Intent.harm);
          if (f != null) await x.damage(f, 2);
        }),
        'SLIP AWAY': CardScript(after: (x) async {
          if (fog.isEmpty || !im.onBoard) return;
          final t = fog.length == 1
              ? fog.first
              : await x.game.choose<Token>(x.me, Ask.space, 'Choose a fog token', [for (final t in fog) Choice('Fog at ${t.space}', t)]);
          final dest = x.game.emptySpaces().where((s) => !onFog(s) || s == t!.space).toList();
          final s = await x.chooseSpace(dest, 'Move the fog to a space without a fighter; Invisible Man goes there', intent: Intent.moveOwn, subject: im);
          if (s == null) return;
          t!.space = s;
          if (!x.game.cannotLeave(im)) {
            final from = im.space!;
            im.space = s;
            x.game.turn.leftSpace.add(im);
            await x.game.emit(FighterMoved(im, [from, s], placed: true));
          }
        }),
      };
}
