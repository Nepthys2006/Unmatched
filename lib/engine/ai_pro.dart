part of 'ai.dart';

// The Pro level: Insane's judgement plus a game plan, chosen at each action the way a seasoned
// player thinks about the hand race:
//
// 1. Hand first. Don't attack every turn: whoever rushes in runs out of cards to defend with.
//    Apart, maneuver (twice) until the hand is full, out of the opponent's reach: whoever
//    charges first is at a disadvantage.
// 2. Head to head, press the attack only with more cards than the opponent and a card left to
//    defend with after attacking. With fewer cards than them, make distance.
// 3. An opponent who didn't defend an attack (and hasn't drawn since) is out of defenses: hit
//    hard, prefer attacks that gain an action, finish them.
// 4. Prefer attacks that draw (when my hand is low) or make them discard (when theirs is).
//
// Every Pro rule is gated on [AiLevel.pro]: the other levels play exactly as before.
//
// Measured (tool/ai_arena.dart, 4000 games against Insane playing random heroes): the plan alone,
// playing Achilles, wins 83.0% (Insane playing Achilles 83.4%); over all heroes Pro and Insane are
// even. Holding back after the hand is full (waiting for them to come) lost: 72.7%. The hero
// plays below lift Achilles to 89.5%. Add plays for more heroes there, and measure with
//     dart run tool/ai_arena.dart --a=pro --b=insane --a-hero=achilles --games=4000

/// What a Pro is trying to do this turn.
enum ProMode {
  /// Apart: draw up to the hand limit, out of their reach.
  build,

  /// Head to head with more cards: attack, keeping a card to defend with.
  press,

  /// Head to head with fewer cards than them: get away and draw.
  retreat,

  /// They let an attack through (or hold no cards): hit hard, finish them.
  finish,

  /// No plan: play like Insane.
  even,

  /// A hero play: attack all out, hand size no matter (Achilles once Patroclus has fallen).
  aggro,

  /// A hero play: don't attack; keep out of reach and keep the hand full (maneuver, then a
  /// scheme), so they must come (Sherlock, until he holds 3 cards more than them).
  hold,
}

/// The heroes Pro has been taught so far. Pro plays any hero, but when its hero is drawn at
/// random it plays one of these.
const proHeroes = ['achilles', 'sherlock-holmes'];

/// Near the end of my deck a Pro stops waiting (two Pros would otherwise wait forever).
const _proLowDeck = 8;

extension _Pro on AiAgent {
  bool get _isPro => level == AiLevel.pro;

  /// The opposing hero to play against: the nearest one (in 1 v 1, the only one).
  Fighter? _proFoe(Game g, Player me) {
    final hero = me.heroFighter;
    if (!hero.onBoard) return null;
    final foes = g.enemyFighters(me).where((e) => e.isHero && e.onBoard).toList()
      ..sort((a, b) => g.board.distance(hero.space!, a.space!).compareTo(g.board.distance(hero.space!, b.space!)));
    return foes.firstOrNull;
  }

  /// Either hero can attack the other without moving.
  bool _engaged(Game g, Fighter hero, Fighter foe) => g.inReach(hero, foe) || g.inReach(foe, hero);

  /// [opp] let the last attack on them through without a defense card, and hasn't drawn since:
  /// they are (almost surely) out of defenses.
  bool _noBlock(Game g, Player opp) {
    for (final e in g.log.reversed) {
      if (e is CardsDrawn && e.player == opp) return false;
      if (e is CombatEnded && e.combat.defender.player == opp) return e.combat.defender.card == null;
    }
    return false;
  }

  /// After attacking with [attack], [me] still holds a card [hero] can defend with.
  bool _keepsDefense(Game g, Player me, Fighter hero, Card attack) =>
      me.hand.any((c) => c != attack && g.canDefendWith(c, hero));

  bool _canPress(Game g, Player me, Fighter hero) =>
      me.hand.any((c) => g.canAttackWith(c, hero) && _keepsDefense(g, me, hero, c));

  /// This turn's plan (the four rules at the top of this file, unless a hero play says otherwise).
  ProMode _proMode(Game g, Player me) {
    final play = _proPlays[me.hero.id]?.mode?.call(this, g, me);
    if (play != null) return play;
    final hero = me.heroFighter;
    final foe = _proFoe(g, me);
    if (foe == null) return ProMode.even;
    final opp = foe.owner;
    if (opp.hand.isEmpty || _noBlock(g, opp)) return ProMode.finish;
    // BOOSTed a maneuver this turn to reach them (rather than overflow the hand): attack.
    if (_reachTurn == g.turnNumber && g.actions == 0) return ProMode.even;
    final mine = me.hand.length, theirs = opp.hand.length;
    if (_engaged(g, hero, foe)) {
      if (mine > theirs && _canPress(g, me, hero)) return ProMode.press;
      if (theirs > mine) return ProMode.retreat;
      return ProMode.even;
    }
    if (me.deck.length <= _proLowDeck) return ProMode.even;
    // Apart: fill the hand out of their reach; with a full hand, engage.
    return mine < handLimit(g, me) ? ProMode.build : ProMode.even;
  }

  /// Rule 3 and 4: what an attack card is worth beyond Insane's estimate.
  double _proCardBonus(Game g, Player me, Fighter attacker, Fighter target, Card c, ProMode mode) {
    final t = c.def.text.values.join(' ').toLowerCase();
    var b = 0.0;
    if (t.contains('draw') && me.hand.length - 1 <= 3) b += 4.0;
    if (t.contains('discard') && t.contains('opponent') && target.owner.hand.length <= 2) b += 4.0;
    if (mode == ProMode.finish) {
      // No defense coming: the printed attack lands in full.
      final v = _estimatedValue(g, null, Side(Combat(attacker, target), true, attacker), c);
      b += v * 2.0;
      if (v >= target.hp) b += _killValue(target);
      if (t.contains('gain') && t.contains('action')) b += 6.0;
      if (t.contains('relentless') || t.contains('atk')) b += 4.0;
    } else if (mode != ProMode.aggro && !_keepsDefense(g, me, attacker.owner.heroFighter, c)) {
      b -= 6.0; // never spend the last card that could defend
    }
    return b;
  }

  /// Rule 1 to 4 for the turn's actions, then the hero's plays.
  double _proActionBonus(Game g, Player me, ActionChoice a) {
    final mode = _proTurn = _proMode(g, me);
    return _proPlanBonus(g, me, a, mode) + (_proPlays[me.hero.id]?.action?.call(this, g, me, a, mode) ?? 0.0);
  }

  double _proPlanBonus(Game g, Player me, ActionChoice a, ProMode mode) {
    switch (a.kind) {
      case ActionKind.maneuver:
        return switch (mode) {
          ProMode.build => 12.0,
          ProMode.retreat => 15.0,
          ProMode.press || ProMode.aggro => -3.0,
          // Draw while a scheme can still bring the hand back to the limit by the end of the turn.
          ProMode.hold => me.hand.length < handLimit(g, me) + g.actions ? 12.0 : -4.0,
          _ => 0.0,
        };
      case ActionKind.scheme:
        // Holding with a full hand: a scheme keeps it full (the hero's plays say when).
        return mode == ProMode.hold && me.hand.length >= handLimit(g, me) ? 6.0 : 0.0;
      case ActionKind.attack:
        final f = a.fighter!, t = a.target!;
        final cards = me.hand.where((c) => g.canAttackWith(c, f) && g.canTargetWith(c, f, t)).toList();
        if (cards.isEmpty) return 0.0;
        final best = cards.map((c) => _proCardBonus(g, me, f, t, c, mode)).reduce(max);
        return best +
            switch (mode) {
              ProMode.finish => t.isHero ? 25.0 : 5.0,
              ProMode.aggro => t.isHero ? 20.0 : 4.0,
              ProMode.press => t.isHero && cards.any((c) => _keepsDefense(g, me, me.heroFighter, c)) ? 15.0 : 0.0,
              ProMode.build || ProMode.retreat => -10.0,
              ProMode.hold => -20.0,
              ProMode.even => 0.0,
            };
    }
  }

  /// Rule 1 and 2 for movement: while building or retreating, stay out of their reach (where
  /// they can strike next turn), close enough to strike back when they come. All out: close in
  /// on their hero. Then the hero's plays.
  double _proSpaceBonus(Game g, Fighter f, int s) {
    final mode = _proTurn;
    var b = _proPlays[f.owner.hero.id]?.space?.call(this, g, f, s, mode) ?? 0.0;
    if (mode == ProMode.aggro && f.isHero) {
      final foe = _proFoe(g, f.owner);
      if (foe != null) b -= 1.0 * min(_walk(g, s, foe.space!), 12);
    }
    // Rule 6: a sidekick that matters ends the turn out of reach unless it can defend.
    if (_proActionsLeft(g, f.owner) == 0 && _exposedSidekick(g, f.owner, f)) {
      // Worse to lose with cards only it can play.
      final own = [...f.owner.hand, ...f.owner.deck].any((c) => c.def.fighters.length == 1 && c.def.fighters.single == f.id);
      for (final e in g.enemyFighters(f.owner).where((e) => e.onBoard)) {
        final (now, later) = _strikeZones(g, e);
        final w = (e.isHero ? 1.0 : 0.5) * (own ? 1.5 : 1.0);
        if (now.contains(s)) {
          b -= 6 * w;
        } else if (later.contains(s)) {
          b -= 3 * w;
        }
      }
    }
    if (mode != ProMode.build && mode != ProMode.retreat && mode != ProMode.hold) return b;
    b += _proDistance(g, f, s);
    for (final e in g.enemyFighters(f.owner).where((e) => e.onBoard)) {
      final (now, later) = _strikeZones(g, e);
      final w = (e.isHero ? 1.0 : 0.35) * (f.isHero ? 1.0 : 0.3);
      if (now.contains(s)) {
        b -= 12 * w;
      } else if (later.contains(s)) {
        b -= 8 * w;
      }
      if (mode == ProMode.build && e.isHero && f.isHero) b -= 0.3 * min(_walk(g, s, e.space!), 12);
    }
    return b;
  }

  /// The ground rules of [me]'s hero plays.
  List<GroundRule> _proRules(Player me) => _proPlays[me.hero.id]?.rules?.call(this) ?? const [];

  // ----------------------------------------------------------- general rules (all heroes)
  //
  // 5. Whose action comes next decides where a fighter should move (Skirmish, Dash and other
  //    moves during combat): if theirs, get my fighters out of reach, or move theirs away from
  //    mine (most of all one next to several of mine); if mine, line up attacks (next to them,
  //    next to several, or in a ranged fighter's zone but out of melee) or corner them.
  // 6. A sidekick that matters (not one a hero play spends freely, like Patroclus or the Red
  //    Riders) stays out of reach at the end of the turn when it holds no defense: losing it
  //    early leaves its cards dead in the hand.
  // 7. Making distance with fewer cards than them: count their move (with passives), reach and
  //    range, and keep further away the fewer cards I hold.
  //
  // Measured (4000 games against Insane, seeds 41 / 47), rules 5-7 on vs off: random heroes
  // 53.3% / 53.3% vs 51.7% / 52.3%; Pro playing Achilles 91.1% / 90.0% vs 90.9% / 89.6%.
  // 8. A holding turn (it won't attack) ends wherever its maneuver does, even the first of two:
  //    move as if ending the turn, and then as far beyond their reach as the move goes (they
  //    BOOST too: up to 3 spaces past their move). Measured: Sherlock 78.8% / 76.5% vs 75.9% /
  //    76.3%. On building and retreating turns too it cost the others (random heroes 49.1% vs
  //    52.8%, Achilles 89.0% vs 90.9%): there, staying near pays for the attacks to come.

  /// My turn, and I'm holding: where a maneuver ends is where the turn ends (rule 8).
  bool _proQuietTurn(Game g, Player me) => g.turnNumber > 0 && g.active.isAllyOf(me) && _proTurn == ProMode.hold;

  /// [_proMyActions], or none on a quiet turn (rule 8): what positioning plans for.
  int _proActionsLeft(Game g, Player me) => _proQuietTurn(g, me) ? 0 : _proMyActions(g, me);

  /// Actions [me] takes before the opponent's next one: the rest of my turn; during theirs,
  /// none while they still have one, else my full turn if it comes next.
  int _proMyActions(Game g, Player me) {
    if (g.turnNumber == 0) return g.actions;
    if (g.active.isAllyOf(me)) return g.actions;
    if (g.actions > 0) return 0;
    return g.nextPlayer(g.active).isAllyOf(me) ? 2 : 0;
  }

  /// Actions an opponent takes before my next one.
  int _proTheirActions(Game g, Player me) {
    if (g.turnNumber == 0) return 2;
    if (g.active.isAllyOf(me)) return g.actions > 0 ? 0 : 2;
    if (g.actions > 0) return g.actions;
    return g.nextPlayer(g.active).isAllyOf(me) ? 0 : 2;
  }

  /// Long reach of [f] (ai_playbook.dart: Bullseye and others), 0 for none.
  int _reachOf(Fighter f) => f.isHero ? _book(f.owner)?.reach ?? _counter(f.owner)?.reach ?? 0 : 0;

  /// [a] standing in [from] can attack a fighter in [to] without moving.
  bool _hitsFrom(Game g, Fighter a, int from, int to) {
    if (g.board.adjacent(from, to)) return true;
    if (a.isRanged && g.board.sharesZone(from, to)) return true;
    final r = _reachOf(a);
    return r > 0 && _near(g, from, r).contains(to);
  }

  /// Movement [a] in [from] needs to attack a fighter in [to] (fighters ignored).
  int _moveToHit(Game g, Fighter a, int from, int to) {
    if (_hitsFrom(g, a, from, to)) return 0;
    final r = _reachOf(a);
    final spots = {
      ...g.board.neighbours(to),
      if (a.isRanged) ...g.board.zoneOf(to),
      if (r > 0) ..._near(g, to, r),
    };
    return spots.isEmpty ? 1 << 20 : spots.map((x) => _walk(g, from, x)).reduce(min);
  }

  /// A sidekick worth keeping alive (rule 6): not one my hero play spends freely, not a
  /// 1-health swarm.
  bool _preciousSidekick(Fighter f) =>
      f.isSidekick && f.maxHp > 1 && !_spentSidekicks.contains(f.owner.hero.id);

  /// [me]'s sidekick [f] could be lost: precious, and no card in hand it can defend with.
  bool _exposedSidekick(Game g, Player me, Fighter f) =>
      _preciousSidekick(f) && !me.hand.any((c) => g.canDefendWith(c, f));

  /// How good the board is for [me] with [moved] in [s] (rule 5), given whose action is next.
  double _proBoardAfterMove(Game g, Player me, Fighter moved, int s) {
    int at(Fighter x) => x == moved ? s : x.space!;
    final mine = g.onBoard.where((x) => x.isFriendOf(me)).toList();
    final theirs = g.onBoard.where((x) => x.isEnemyOf(me)).toList();
    var score = 0.0;
    if (_proMyActions(g, me) == 0) {
      // They act next: what can they hit? With one action left they can't move first.
      final full = _proTheirActions(g, me) >= 2;
      for (final e in theirs) {
        if (e.owner.hand.isEmpty && e.owner.deck.isEmpty) continue;
        final threat = e.isHero ? 1.0 : 0.5;
        final bonus = g.moveAllowance(e) + (e.owner.hand.isEmpty ? 0 : 1) + (_counter(e.owner)?.startMove ?? 0);
        for (final m in mine) {
          final value = m.isHero ? 1.0 : (_exposedSidekick(g, me, m) ? 0.6 : 0.25);
          final need = _moveToHit(g, e, at(e), at(m));
          if (need == 0) {
            score -= 10 * threat * value;
          } else if (full && need <= bonus) {
            score -= 4 * threat * value;
          }
        }
      }
      return score;
    }
    // My action next: line up attacks.
    final actions = _proMyActions(g, me);
    for (final m in mine) {
      if (!me.hand.any((c) => g.canAttackWith(c, m))) continue;
      for (final e in theirs) {
        final v = e.isHero ? 2.5 : 1.0;
        if (_hitsFrom(g, m, at(m), at(e))) {
          score += 6 * v;
          // A ranged fighter would rather shoot from out of melee.
          if (m.isRanged && !e.isRanged && g.board.adjacent(at(m), at(e))) score -= 2 * v;
        } else if (actions >= 2 && _moveToHit(g, m, at(m), at(e)) <= g.moveAllowance(m)) {
          score += 2 * v;
        }
      }
    }
    // Corner them: an opposing fighter with few spaces to run to.
    if (moved.isEnemyOf(me)) {
      final run = g.moveAllowance(moved);
      final room = g.board.spaceIds.where((x) => _walk(g, s, x) <= run).length;
      score -= 0.3 * room;
    }
    return score;
  }

  /// Skirmish-style "choose a fighter in the combat to move up to n": the one whose best move
  /// leaves the best board (rule 5). Null when [p] isn't one.
  int? _proPickMover(Game g, Prompt p) {
    final m = RegExp(r'in the combat to move up to (\d+)').firstMatch(p.text);
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    final fs = [for (final ch in p.choices) ch.value as Fighter];
    double best(Fighter f) => {f.space!, ...g.reachable(f, n).keys}
        .map((s) => _proBoardAfterMove(g, p.player, f, s))
        .reduce(max);
    return _best(fs.length, (i) => best(fs[i]));
  }

  /// Rule 7: with fewer cards than them, spaces further than their move (passives included),
  /// reach and range can take, the further the fewer cards I hold.
  /// Rule 8: ending a holding turn, up to 3 spaces past their move (heroes; sidekicks count less).
  double _proDistance(Game g, Fighter f, int s) {
    final me = f.owner;
    final foe = _proFoe(g, me);
    if (foe == null || !f.isHero) return 0.0;
    final behind = foe.owner.hand.length > me.hand.length;
    final ending = _proQuietTurn(g, me) && _proActionsLeft(g, me) == 0;
    if (!behind && !ending) return 0.0;
    var want = behind ? (handLimit(g, me) - me.hand.length).clamp(1, 4) : 0;
    if (ending) want = max(want, 3);
    var b = 0.0;
    for (final e in g.enemyFighters(me).where((e) => e.onBoard)) {
      if (!e.isHero && (!ending || (e.owner.hand.isEmpty && e.owner.deck.isEmpty))) continue;
      final spare = _moveToHit(g, e, e.space!, s) - g.moveAllowance(e) - (_counter(e.owner)?.startMove ?? 0);
      b += (e.isHero ? 2.0 : 0.6) * spare.clamp(0, want);
    }
    return b;
  }
}

/// Pro's take on [schemeBoostRule]: a scheme the hero's plays rate below an ordinary card (its
/// `keep` is negative, like Sherlock's Master of Disguise) may BOOST too.
final _proSchemeBoostRule = GroundRule(
  '${schemeBoostRule.name} A weak scheme of the hero (Pro hero plays) may BOOST too.',
  (g, p, c) =>
      schemeBoostRule.forbids(g, p, c) &&
      !(c is Card && (_proPlays[p.player.hero.id]?.keep?.call(c, p.player) ?? 0) < 0),
);

/// Pro's maneuver BOOST rule, plus the cards its hero plays want to be rid of ([_ProPlays.freeBoost]).
final _proManeuverRule = GroundRule(
  '${proManeuverBoostRule.name} Or a card the hero plays want to be rid of.',
  (g, p, c) =>
      proManeuverBoostRule.forbids(g, p, c) &&
      !(c is Card && (_proPlays[p.player.hero.id]?.freeBoost?.call(g, p.player, c) ?? false)),
);

/// Heroes whose sidekicks a hero play spends freely (rule 6 doesn't apply): Patroclus leads
/// Achilles' attacks, Eredin's Red Riders are swapped in to take the hits.
const _spentSidekicks = {'achilles', 'eredin'};

// =========================================================================== hero plays (Pro)

/// How Pro plays one hero, on top of the plan above. Every hook is optional.
class _ProPlays {
  const _ProPlays({
    this.mode,
    this.action,
    this.attackCard,
    this.defenseCard,
    this.space,
    this.yesNo,
    this.takeBack,
    this.keep,
    this.number,
    this.discardTheirs,
    this.moveFirst,
    this.freeBoost,
    this.rules,
  });

  /// The plan for this action, or null for the usual one.
  final ProMode? Function(AiAgent ai, Game g, Player me)? mode;

  /// Extra score for taking action [a] now.
  final double Function(AiAgent ai, Game g, Player me, ActionChoice a, ProMode mode)? action;

  /// Extra score for attacking with [card] in combat [c].
  final double Function(AiAgent ai, Game g, Combat c, Card card)? attackCard;

  /// Extra score for defending with [card] in combat [c].
  final double Function(AiAgent ai, Game g, Combat c, Card card)? defenseCard;

  /// Extra score for my fighter [f] moving to [s].
  final double Function(AiAgent ai, Game g, Fighter f, int s, ProMode mode)? space;

  /// The answer to a yes/no question (0 = yes, 1 = no), or null for the usual one.
  final int? Function(AiAgent ai, Game g, Prompt p)? yesNo;

  /// Which card to take back into the hand ([Intent.gainOwn], e.g. from the discard pile): an
  /// index into [cards], or null for the usual choice (the most useful card).
  final int? Function(AiAgent ai, Game g, Prompt p, List<Card> cards)? takeBack;

  /// How much more [c] is worth keeping than usual (what to BOOST with and discard last). Below
  /// zero, a scheme may BOOST (the ground rule against boosting with schemes lets it).
  final double Function(Card c, Player me)? keep;

  /// The answer to a number prompt (an index into its choices), or null for the usual one.
  final int? Function(AiAgent ai, Game g, Prompt p)? number;

  /// Which of an opponent's cards I make them discard ([Intent.loseEnemy]): indices into
  /// [cards], or null for the usual choice.
  final List<int>? Function(AiAgent ai, Game g, Prompt p, List<Card> cards)? discardTheirs;

  /// Which of my fighters a maneuver moves first (the others follow), or null for the usual.
  final Fighter? Function(AiAgent ai, Game g, Player me, List<Fighter> fs)? moveFirst;

  /// [c] may BOOST a maneuver even without one of the usual reasons (a card to be rid of).
  final bool Function(Game g, Player me, Card c)? freeBoost;

  /// Choices Pro never makes with this hero.
  final List<GroundRule> Function(AiAgent ai)? rules;
}

final _proPlays = <String, _ProPlays>{'achilles': _achilles, 'sherlock-holmes': _sherlock};

// ----------------------------------------------------------------------------------- Achilles
//
// 1. Spear Throw only with a target (every level: ai_playbook.dart).
// 2. While Patroclus lives he leads the attacks (his own cards hit hard: play 1-2 of them before
//    he falls); Achilles follows close behind.
// 3. While Patroclus lives Achilles avoids damage: Under Achilles' Helm (swap, Patroclus defends)
//    whenever he can.
// 4. Once Patroclus falls: all out (the passive draws on every win), at their hero; Wily Fighting
//    clears 1-health sidekicks around him.
// 5. Spear Throw is a finisher (2 damage no defense can heal), or a play with a full hand and
//    nobody to attack this turn.
// 6. Achilles' Heel (4, but they gain an action if it loses) only against an attack that can't
//    beat 4, unless it is his only defense card (holding it back then, and taking the full hit,
//    lost games: 88% instead of 90%).
//
// 7. Battle Hardened (versatile, returns a card from the discard pile) is a card to keep. What it
//    returns: Spear Throw when their hero is low enough for it to finish them; else the other
//    Battle Hardened (the pair recycle each other: defenses that never run out, and no early
//    exhaustion); else Brothers In Arms while Patroclus lives (the extra action); else Feint
//    against heroes whose card effects
//    are best canceled ([_cancelWorthy]). Late in the game, with Patroclus fallen, it defends
//    rather than attacks: a won combat draws a card, and his deck runs out.
// 8. Test For Weakness (and its RELENTLESS ASSAULT) once Patroclus falls: two combats, +2 each,
//    a card drawn per win. While he lives, Patroclus may spend one to draw out early defenses
//    when he has nothing better.
// 9. Brothers In Arms early, while Patroclus lives (the extra action; sidekicks rarely defend
//    well): play it first, Patroclus' own cards on the last action.
//
// Measured (4000 games against Insane on random heroes): Pro playing Achilles wins 89.5%, up from
// 83.0% with the plan alone; Insane playing Achilles 84.7%. Each play switched off in turn: all
// out after Patroclus falls is worth ~3 points, Under Achilles' Helm ~1.5, the rest about even.

/// Opposing heroes whose card effects are worth a Feint (Battle Hardened takes one back for them).
const _cancelWorthy = {'sun-wukong', 'jekyll-hyde', 'geralt-of-rivia'};

/// Late in the game: few cards left to draw.
bool _lateGame(Player me) => me.deck.length <= 5;

/// An opposing hero Spear Throw (2 damage) would defeat.
bool _spearCanFinish(Game g, Player me) => g.enemyFighters(me).any((e) => e.isHero && e.onBoard && e.hp <= 2);

Fighter? _patroclus(Player me) => me.fighters.where((f) => f.isSidekick).firstOrNull;

bool _patroclusLives(Player me) {
  final p = _patroclus(me);
  return p != null && p.alive && p.onBoard;
}

/// Spear Throw would defeat their hero, or nothing better can happen this turn with a full hand.
bool _spearThrowFits(AiAgent ai, Game g, Player me) {
  final targets = spearTargets(g, me).toList();
  if (targets.isEmpty) return false;
  if (targets.any((t) => t.isHero && t.hp <= 2 && t.owner.heroes.where((h) => h.alive).length <= 1)) return true;
  final full = me.hand.length >= handLimit(g, me);
  final foes = g.enemyFighters(me).where((e) => e.onBoard).toList();
  final canAttack = me.onBoard.any((f) =>
      me.hand.any((c) => g.canAttackWith(c, f)) &&
      ai._strikeSpots(g, f, foes).any(g.reachable(f, g.moveAllowance(f)).containsKey));
  return full && !canAttack;
}

/// The most the attack in [c] can be worth: its card if I can see it, else the attacker's best
/// attack card still out (plus what is already added to it).
int _maxAttack(AiAgent ai, Game g, Combat c, Player me) {
  final a = c.attacker;
  final known = a.card != null && (a.faceUp || me.script.known.contains(a.card));
  if (known) return g.valueOf(a).total;
  final extra = a.ops.fold(0, (s, o) => s + (o.isSet ? 0 : o.amount));
  return ai._tracker(g, me, a.player).maxAttack(a.fighter) + extra;
}

final _achilles = _ProPlays(
  mode: (ai, g, me) => (_patroclus(me)?.defeated ?? false) ? ProMode.aggro : null,
  action: (ai, g, me, a, mode) {
    switch (a.kind) {
      case ActionKind.attack:
        // Patroclus leads: always attack with him when he can.
        var b = a.fighter!.isSidekick ? 25.0 + (a.target!.isHero ? 5.0 : 0.0) : 0.0;
        // Early on, Brothers In Arms picks off sidekicks (they rarely defend well).
        if (a.target!.isSidekick &&
            _patroclusLives(me) &&
            me.deck.length > 15 &&
            me.hand.any((c) => c.title == 'Brothers In Arms' && g.canAttackWith(c, a.fighter!))) {
          b += 4.0;
        }
        return b;
      case ActionKind.scheme:
        if (a.card!.title != 'Spear Throw') return 0.0;
        final finisher = spearTargets(g, me).any((t) => t.isHero && t.hp <= 2);
        return finisher ? 30.0 : 2.0;
      case ActionKind.maneuver:
        return 0.0;
    }
  },
  attackCard: (ai, g, c, card) {
    final me = c.attacker.player;
    final attacker = c.attacker.fighter;
    final lives = _patroclusLives(me);
    var b = 0.0;
    bool ownCard(Card x) => x.def.fighters.contains('patroclus');
    final brothers = me.hand.any((x) => x != card && x.title == 'Brothers In Arms' && g.canAttackWith(x, attacker));
    // Patroclus plays his own cards: they hit hard, and are dead cards once he falls. Brothers In
    // Arms (an extra action) goes first; his own cards on the last action.
    if (attacker.isSidekick && ownCard(card)) b += brothers && g.actions > 0 ? -5.0 : 6.0;
    if (lives && card.title == 'Brothers In Arms') b += 5.0 + (c.defender.fighter.isSidekick ? 3.0 : 0.0);
    // Test For Weakness: once Patroclus falls, two combats at +2, a card per win (the scores above
    // only see the first, 1 + 2: the RELENTLESS ASSAULT adds another 3 + 2). While he lives, one
    // may draw out their defenses when Patroclus has nothing better.
    if (card.title == 'Test For Weakness') {
      if (!lives && attacker.isHero) b += 14.0;
      if (attacker.isSidekick && !me.hand.any(ownCard) && !me.discard.any((x) => x.title == 'Test For Weakness')) b += 3.0;
    }
    // Late, with Patroclus fallen: Battle Hardened defends instead (a win draws from a thin deck).
    if (card.title == 'Battle Hardened' && !lives && _lateGame(me)) b -= 5.0;
    // Wily Fighting: 1 damage to each opposing fighter next to Achilles after the fight.
    if (card.title == 'Wily Fighting' && c.attacker.fighter.isHero && c.attacker.fighter.onBoard) {
      final around = g.enemyFighters(me).where((e) =>
          e.onBoard && e != c.defender.fighter && e.hp <= 1 && g.board.adjacent(e.space!, c.attacker.fighter.space!));
      b += 2.5 * around.length;
    }
    return b;
  },
  defenseCard: (ai, g, c, card) {
    final me = c.defender.player;
    // Keep Achilles out of harm while Patroclus lives: swap, Patroclus defends.
    if (card.title == "Under Achilles' Helm" && c.defender.fighter.isHero && _patroclusLives(me)) return 40.0;
    // Late, with Patroclus fallen: Battle Hardened takes a card back without winning (no draw).
    if (card.title == 'Battle Hardened' && !_patroclusLives(me) && _lateGame(me)) return 5.0;
    return 0.0;
  },
  space: (ai, g, f, s, mode) {
    final me = f.owner;
    if (!_patroclusLives(me) || mode == ProMode.build || mode == ProMode.retreat) {
      // All out: stand where Wily Fighting would catch the most 1-health fighters.
      if (mode != ProMode.aggro || !f.isHero || !me.hand.any((c) => c.title == 'Wily Fighting')) return 0.0;
      final weak = g.enemyFighters(me).where((e) => e.onBoard && e.hp <= 1 && g.board.adjacent(e.space!, s)).length;
      return 1.5 * weak;
    }
    final foe = ai._proFoe(g, me);
    if (foe == null) return 0.0;
    final patroclus = _patroclus(me)!;
    if (f == patroclus) {
      // Patroclus leads, to strike their hero.
      return g.board.adjacent(s, foe.space!) ? 6.0 : -0.8 * min(ai._walk(g, s, foe.space!), 12);
    }
    if (f.isHero) {
      // Achilles close behind Patroclus, out of their reach where he can.
      var b = -1.0 * max(0, ai._walk(g, s, patroclus.space!) - 2);
      if (ai._strikeZones(g, foe).$1.contains(s)) b -= 4.0;
      return b;
    }
    return 0.0;
  },
  yesNo: (ai, g, p) {
    // The Day of Your Doom: 2 damage to Patroclus makes it a 5, if he survives it.
    if (p.text.startsWith('Deal 2 damage to Patroclus')) return (_patroclus(p.player)?.hp ?? 0) > 2 ? 0 : 1;
    return null;
  },
  takeBack: (ai, g, p, cards) {
    final me = p.player;
    int? find(String title) {
      final i = cards.indexWhere((c) => c.title == title);
      return i < 0 ? null : i;
    }

    if (_spearCanFinish(g, me)) {
      final i = find('Spear Throw');
      if (i != null) return i;
    }
    // The other Battle Hardened: the two recycle each other, an endless supply of defenses that
    // keeps him from exhausting.
    final hardened = find('Battle Hardened');
    if (hardened != null) return hardened;
    if (_patroclusLives(me)) {
      final i = find('Brothers In Arms');
      if (i != null) return i;
    }
    if (g.players.any((o) => o.isEnemyOf(me) && !o.eliminated && _cancelWorthy.contains(o.hero.id))) {
      final i = find('Feint');
      if (i != null) return i;
    }
    return null;
  },
  keep: (c, me) => c.title == 'Battle Hardened' ? 1.5 : 0.0,
  rules: (ai) => [
    GroundRule(
      'Spear Throw only to finish their hero, or with a full hand and nobody to attack this turn.',
      (g, p, c) =>
          c is ActionChoice && c.kind == ActionKind.scheme && c.card!.title == 'Spear Throw' && !_spearThrowFits(ai, g, p.player),
    ),
    GroundRule(
      "Achilles' Heel only against an attack that can't beat 4, unless it is his only defense.",
      (g, p, c) =>
          p.intent == Intent.defenseCard &&
          c is Card &&
          c.title == "Achilles' Heel" &&
          p.choices.any((o) => (o.value as Card).title != "Achilles' Heel") &&
          _maxAttack(ai, g, p.subject as Combat, p.player) > (c.def.value ?? 4),
    ),
  ],
);

// ----------------------------------------------------------------------------- Sherlock Holmes
//
// Sherlock wears them down: he makes them discard their best cards, and looks at their hand to
// pick them.
// 1. Confirm Suspicion (name a value: they discard a card of it and their hero takes its BOOST
//    in damage; with none, they reveal their hand) names the value with the best expected
//    result, from the cards he has seen in their hand, else from the cards they may hold. What
//    to make them lose, in order: (a) a high BOOST, (b) taking cards back from the discard pile,
//    (c) healing, (d) making him discard, (e) 6+ damage. Holmes low: 6+ damage first. Their hero
//    low: healing and high BOOSTs first (above all a BOOST that defeats them).
// 2. Eliminate the Impossible (look at their hand, they discard the card he picks) before
//    Confirm Suspicion. Not against fewer than 5 cards, unless it leaves them defenseless before
//    a finishing attack (their hero low and next to Holmes, who holds a 5 to attack with; they
//    hold 1-2 cards). It can discard schemes: the same order, schemes first, BOOST aside (high
//    BOOSTs are left for Confirm Suspicion while he still has one).
// 3. Administer Aid whenever Holmes is hurt and safe: a maneuver that also heals (and Watson
//    may fall, losing it). Better still with Watson away from Holmes (after Master of Disguise).
// 4. Master of Disguise only to finish a 1-health hero or to escape when surrounded; otherwise
//    the first card to discard or BOOST with.
// 5. Hold: he attacks only holding 3 cards more than them (or when they are out of defenses).
//    Otherwise he keeps out of reach with a full hand: maneuver away, then a scheme, so the hand
//    stays at 7 and they must come (Master of Disguise first, then the maneuver, against a hero
//    with no sidekicks on the board). Confirm Suspicion blind: the likely cards.
// 6. Counterpunch on defense against a melee attacker next to Holmes (the defender's effects go
//    first: they can't step away from the 2 damage); on attack only against a 1-health sidekick
//    crowding Holmes, as it is easily dodged.
// 7. Study Methods on defense (ties go to the defender; a win shows their hand); Watson attacks
//    with it only at a target sure not to defend.
// 8. Elementary predicts their strongest attack among the cards he has seen (their hero low: a
//    heal, else an escape); blind, the value that blocks the most on average. It defends by the
//    chance the prediction is right.
// 9. The Game is Afoot attacks (its move can't be canceled), early also at a strong sidekick.
// 10. Fixed Point in a Changing Age: Watson next to Holmes, both hurt (or Holmes at 10 or less);
//     better on defense. Service Revolver whenever Watson can (he shoots even while holding).
// 11. Deduce Strategy both ways, on attack if they may hold a card that changes values.
// 12. Education Never Ends on defense (lose, draw 2: his only draw, keep 4 to 7 cards); Watson's
//     bluff with a low hand; never Holmes attacking with it (a win hands them a card).
// 13. Holmes and Watson stay next to each other (Watson follows). The one with nothing to defend
//     with (Holmes; or Watson while he still holds cards only he can play) moves first, and the
//     other stands where they can reach him from fewer spaces.
// 14. Fewer than 3 schemes: at 3, schemes are played (Eliminate the Impossible against any hand),
//     discarded and BOOSTed first; Master of Disguise may BOOST a defenseless Holmes away.
// 15. At 7 cards with a scheme he attacks (out of reach: maneuver in first); The Game is Afoot's
//     move then takes Holmes out of their reach.
// 16. No Study Methods on defense against an attack its hero passively adds to (Achilles without
//     Patroclus, BIG Alice, ENRAGED Eredin: a 3 that loses to everything), unless it is the only
//     defense. (Turns without attacks end out of reach: general rule 8.)
//
// Measured (4000 games against Insane on random heroes, seeds 41 / 47): Pro playing Sherlock
// wins 75.9% / 76.3% with 13-15 (even: fewer hits taken with no defense, more losses to an
// empty deck; neither attacking nor holding back once the deck is low changed it); before them
// 76.5% / 77.3%; with the schemes only (1-4) 73.3% / 73.4%; without his plays 38.9% / 39.5%;
// Insane playing Sherlock 32.5% / 32.6% (the other levels name 8 for Confirm Suspicion and
// Elementary: number prompts take the highest). The hold (5) measures even against Insane
// (77.2% / 77.0% without it).

String _txt(CardDef d) => d.text.values.join(' ').toLowerCase();

bool _takesBack(CardDef d) {
  final t = _txt(d);
  return t.contains('discard pile') && (t.contains('hand') || t.contains('return'));
}

bool _healsCard(CardDef d) {
  final t = _txt(d);
  return (t.contains('recover') && t.contains('health')) || t.contains('heal');
}

bool _makesDiscard(CardDef d) {
  final t = _txt(d);
  return t.contains('discard') && !_takesBack(d) && (t.contains('opponent') || t.contains('them') || t.contains('their'));
}

bool _bigHit(CardDef d) => d.canAttack && (d.value ?? 0) >= 6;

/// The opposing hero (1 v 1).
Fighter? _foeHero(Game g, Player me) => g.enemyFighters(me).where((e) => e.isHero && e.alive).firstOrNull;

/// What making them lose [d] is worth to Sherlock. [suspicion]: by Confirm Suspicion, where a
/// high BOOST matters (it is the damage); else by Eliminate the Impossible.
double _sherlockThreat(Game g, Player me, CardDef d, {required bool suspicion}) {
  final foe = _foeHero(g, me);
  final theyLow = foe != null && foe.hp <= 5;
  final holmesLow = me.heroFighter.hp <= 6;
  final boost = d.boost ?? 0;
  final kinds = <double>[
    if (suspicion && boost >= 3) 50 + 5.0 * (boost - 3) + (theyLow ? 10 : 0),
    if (_takesBack(d)) 40,
    if (_healsCard(d)) theyLow ? 55 : 30,
    if (_makesDiscard(d)) 20,
    if (_bigHit(d)) holmesLow ? 65 : 10 + 2.0 * (d.value! - 6),
  ];
  final top = kinds.isEmpty ? 0.0 : kinds.reduce(max);
  final rest = kinds.fold(0.0, (a, b) => a + b) - top;
  return top + 0.1 * rest + 0.5 * (d.value ?? 0) + 0.5 * boost;
}

/// Confirm Suspicion making them discard [d]: the card, its BOOST in damage, their defeat.
double _suspicionScore(Game g, Player me, CardDef d) {
  final foe = _foeHero(g, me);
  final boost = d.boost ?? 0;
  return _sherlockThreat(g, me, d, suspicion: true) + 3.0 * boost + (foe != null && boost >= foe.hp ? 200 : 0);
}

/// The value Confirm Suspicion should name against [opp], and how good it is: from the cards
/// Holmes has seen in their hand (sure), else the odds over the cards they may hold. They choose
/// which matching card to lose, so count on the one that hurts them least.
(int, double) _suspicionPick(AiAgent ai, Game g, Player me, Player opp) {
  final known = [for (final c in opp.hand) if (me.script.known.contains(c)) c.def];
  final unknown = opp.hand.length - known.length;
  final pool = List.of(ai._tracker(g, me, opp)._remaining);
  for (final d in known) {
    pool.remove(d);
  }
  var best = (0, -1.0);
  for (var v = 0; v <= 8; v++) {
    bool fits(CardDef d) => !d.isScheme && d.value == v;
    final sure = known.where(fits).toList();
    final double score;
    if (sure.isNotEmpty) {
      score = sure.map((d) => _suspicionScore(g, me, d)).reduce(min);
    } else {
      final maybe = [for (final d in pool) if (fits(d)) _suspicionScore(g, me, d)];
      final hit = unknown <= 0 || maybe.isEmpty ? 0.0 : 1 - _OpponentTracker.noneOf(pool.length, maybe.length, unknown);
      final likely = maybe.isEmpty ? 0.0 : (maybe.reduce(min) + maybe.reduce((a, b) => a + b) / maybe.length) / 2;
      // A miss reveals their hand: worth something while it holds a few cards.
      score = hit * likely + (1 - hit) * (unknown >= 2 ? 6.0 : 1.0);
    }
    if (score > best.$2) best = (v, score);
  }
  return best;
}

/// Eliminate the Impossible's exception: their hero is low and next to Holmes, who holds a 5 to
/// attack with and has an action left, and they hold 1-2 cards: see them, discard the defense,
/// attack.
bool _defenselessFinish(Game g, Player me) {
  final holmes = me.heroFighter, foe = _foeHero(g, me);
  if (foe == null || !holmes.onBoard || !foe.onBoard || g.actions < 1) return false;
  final n = foe.owner.hand.length;
  return n >= 1 &&
      n <= 2 &&
      foe.hp <= 5 &&
      g.board.adjacent(holmes.space!, foe.space!) &&
      me.hand.any((c) => g.canAttackWith(c, holmes) && (c.def.value ?? 0) >= 5);
}

/// Master of Disguise defeats their hero (1 damage).
bool _disguiseFinishes(Game g, Player me) {
  final f = _foeHero(g, me);
  return f != null && f.onBoard && f.hp <= 1;
}

/// Opposing fighters that could attack Holmes in [s] without moving, their hero [foe] in [foeAt].
int _threatsAt(AiAgent ai, Game g, Player me, int s, Fighter foe, int foeAt) =>
    g.enemyFighters(me).where((e) => e.onBoard && ai._hitsFrom(g, e, e == foe ? foeAt : e.space!, s)).length;

/// Master of Disguise gets Holmes out of a crowd: two or more can attack him now, fewer after.
bool _disguiseEscapes(AiAgent ai, Game g, Player me) {
  final holmes = me.heroFighter, foe = _foeHero(g, me);
  if (foe == null || !holmes.onBoard || !foe.onBoard) return false;
  final now = _threatsAt(ai, g, me, holmes.space!, foe, foe.space!);
  return now >= 2 && _threatsAt(ai, g, me, foe.space!, foe, holmes.space!) < now;
}

Fighter? _watson(Player me) => me.fighters.where((f) => f.isSidekick).firstOrNull;

/// The hold standoff with a full hand on the first action: Master of Disguise first (swap, 1
/// damage), then maneuver away. Not with their sidekicks on the board (Holmes lands among them).
bool _disguiseOpens(Game g, Player me) {
  final foe = _foeHero(g, me);
  return foe != null &&
      foe.onBoard &&
      me.heroFighter.onBoard &&
      g.actions == 1 &&
      me.hand.length >= handLimit(g, me) &&
      !g.enemyFighters(me).any((e) => e.isSidekick && e.onBoard);
}

/// Fixed Point in a Changing Age (Watson next to Holmes: each recovers 1): what the heal is worth.
double _fixedPoint(Game g, Player me, Fighter watson) {
  final holmes = me.heroFighter;
  if (!holmes.onBoard || !watson.onBoard || !g.board.adjacent(holmes.space!, watson.space!)) return -3.0;
  if (holmes.hp <= 10) return 4.0; // Holmes needs it, Watson full or not
  final hurt = (holmes.hp < holmes.maxHp ? 1 : 0) + (watson.hp < watson.maxHp ? 1 : 0);
  return const [-3.0, 1.0, 3.0][hurt];
}

/// [opp] may still hold a card that changes values during combat (Momentous Shift): it beats
/// Deduce Strategy on defense.
bool _valueChangersLeft(AiAgent ai, Game g, Player me, Player opp) =>
    ai._tracker(g, me, opp)._remaining.any((d) => (d.canAttack || d.canDefend) && _txt(d).contains('value'));

/// What Elementary should predict, Holmes defending in [c], and the chance it is the attack's
/// printed value. With cards seen in their hand: their strongest attack (their hero low: a heal,
/// else an escape); blind: the value that blocks the most on average.
(int, double) _elementaryPick(AiAgent ai, Game g, Combat c, Player me) {
  final a = c.attacker;
  final opp = a.player, f = a.fighter;
  if (a.card != null && a.faceUp) return (a.card!.def.value ?? 0, 1.0);
  bool usable(CardDef d) => d.canAttack && (d.isAny || d.fighters.isEmpty || d.fighters.contains(f.id));
  // The attack is one of the cards that were in their hand: seen ones or unseen ones.
  final hidden = [...opp.hand, if (a.card != null) a.card!];
  final seen = [for (final x in hidden) if (me.script.known.contains(x)) x.def];
  final unseen = hidden.length - seen.length;
  final pool = List.of(ai._tracker(g, me, opp)._remaining);
  for (final d in seen) {
    pool.remove(d);
  }
  final w = <CardDef, double>{};
  for (final d in seen.where(usable)) {
    w[d] = (w[d] ?? 0) + 1;
  }
  if (unseen > 0 && pool.isNotEmpty) {
    for (final d in pool.where(usable)) {
      w[d] = (w[d] ?? 0) + unseen / pool.length;
    }
  }
  if (w.isEmpty) return (0, 0.0);
  final total = w.values.fold(0.0, (s, x) => s + x);
  double chance(int v) => w.entries.where((e) => (e.key.value ?? 0) == v).fold(0.0, (s, e) => s + e.value) / total;
  final known = seen.where(usable).toList();
  int? pick;
  if (known.isNotEmpty) {
    if ((_foeHero(g, me)?.hp ?? 99) <= 5) {
      final heals = known.where(_healsCard).toList();
      final runs = known.where((d) => _txt(d).contains('move')).toList();
      final from = heals.isNotEmpty ? heals : runs;
      if (from.isNotEmpty) pick = from.map((d) => d.value ?? 0).reduce(max);
    }
    pick ??= known.map((d) => d.value ?? 0).reduce(max);
  } else {
    var best = -1.0;
    for (var v = 0; v <= 8; v++) {
      if (chance(v) * v > best) {
        best = chance(v) * v;
        pick = v;
      }
    }
  }
  return (pick!, chance(pick));
}

/// Schemes in [me]'s hand (Sherlock keeps fewer than 3).
int _schemes(Player me) => me.hand.where((c) => c.def.isScheme).length;

/// What [s]'s passives add to its value (Achilles without Patroclus +2, BIG Alice +2, ENRAGED
/// Eredin +1 and the like): public, unlike the card.
int _passiveBonus(Game g, Side s) {
  var n = 0;
  for (final m in g.allMods) {
    for (final op in m.valueOps(g, s)) {
      if (!op.isSet && !op.isTotal && op.amount > 0) n += op.amount;
    }
  }
  return n;
}

/// The fighter the other one shields: Holmes with no card to defend him; else Watson with no
/// card to defend him while he still has cards only he can play (losing him kills them).
Fighter? _shielded(Game g, Player me) {
  final holmes = me.heroFighter, watson = _watson(me);
  if (watson == null || !watson.onBoard || !holmes.onBoard) return null;
  if (!me.hand.any((c) => g.canDefendWith(c, holmes))) return holmes;
  final his = me.hand.any((c) => c.def.fighters.length == 1 && c.def.fighters.single == watson.id);
  if (his && !me.hand.any((c) => g.canDefendWith(c, watson))) return watson;
  return null;
}

/// Spaces from which their fighters could attack [target] after one maneuver (with a BOOST),
/// with my fighter [mover] standing in [s] (blocking their way, or not); heroes count double.
int _exposure(AiAgent ai, Game g, Player me, Fighter target, Fighter mover, int s) {
  final old = mover.space;
  mover.space = s;
  try {
    final ts = target.space!;
    var n = 0;
    for (final e in g.enemyFighters(me).where((e) => e.onBoard)) {
      if (e.owner.hand.isEmpty && e.owner.deck.isEmpty) continue;
      final r = ai._reachOf(e);
      final spots = {...g.board.neighbours(ts), if (e.isRanged) ...g.board.zoneOf(ts), if (r > 0) ...ai._near(g, ts, r)};
      final moves = g.moveAllowance(e) + (e.owner.hand.isEmpty ? 0 : 1) + (ai._counter(e.owner)?.startMove ?? 0);
      n += g.reachable(e, moves).keys.where(spots.contains).length * (e.isHero ? 2 : 1);
    }
    return n;
  } finally {
    mover.space = old;
  }
}

final _sherlock = _ProPlays(
  mode: (ai, g, me) {
    final foe = _foeHero(g, me);
    if (foe == null) return null;
    final opp = foe.owner;
    final hand = opp.hand;
    // Their hand is known and holds nothing to defend with: finish them.
    if (hand.isNotEmpty && hand.every(me.script.known.contains) && !hand.any((c) => g.canDefendWith(c, foe))) {
      return ProMode.finish;
    }
    // Out of defenses (the usual plan finishes them), or the deck running out (stop waiting).
    if (hand.isEmpty || ai._noBlock(g, opp) || me.deck.length <= _proLowDeck) return null;
    // At 7 cards with a scheme in hand: attack (The Game is Afoot, then away).
    if (me.hand.length >= handLimit(g, me) && _schemes(me) >= 1) return ProMode.press;
    // Otherwise he attacks only holding 3 cards more than them; else he holds and they must come.
    if (me.hand.length - hand.length >= 3) return null;
    return ProMode.hold;
  },
  action: (ai, g, me, a, mode) {
    final hold = mode == ProMode.hold;
    if (a.kind == ActionKind.attack) {
      // Service Revolver: Watson shoots when he can, holding or not.
      final f = a.fighter!;
      return hold && f.isSidekick && me.hand.any((c) => c.title == 'Service Revolver' && g.canAttackWith(c, f)) ? 20.0 : 0.0;
    }
    if (a.kind == ActionKind.maneuver) {
      // Attacking at 7: out of reach, maneuver to it first (the maneuver's draw, then the attack).
      if (mode != ProMode.press || g.actions == 0 || g.legalActions(me).any((x) => x.kind == ActionKind.attack)) return 0.0;
      final foes = g.enemyFighters(me).where((e) => e.onBoard).toList();
      final reach = me.onBoard.any((f) =>
          me.hand.any((c) => g.canAttackWith(c, f)) && ai._strikeSpots(g, f, foes).any(g.reachable(f, g.moveAllowance(f)).containsKey));
      return reach ? 12.0 : 0.0;
    }
    final opp = _foeHero(g, me)?.owner;
    final title = a.card!.title;
    // Three schemes or more: play them down below three.
    final excess = _schemes(me) >= 3;
    final shed = excess ? 12.0 : 0.0;
    // Holding with a full hand: maneuver away first, then the scheme (Master of Disguise first).
    final later = !excess && hold && g.actions > 0 && me.hand.length == handLimit(g, me) && title != 'Master of Disguise' ? -20.0 : 0.0;
    switch (title) {
      case 'Confirm Suspicion':
        if (opp == null) return 0.0;
        var b = _suspicionPick(ai, g, me, opp).$2 / 4;
        // Look at their hand first.
        final seen = opp.hand.every(me.script.known.contains);
        if (!seen && opp.hand.length >= 5 && me.hand.any((c) => c.title == 'Eliminate the Impossible')) b -= 10;
        return b + shed + later;
      case 'Eliminate the Impossible':
        if (_defenselessFinish(g, me)) return 25.0;
        // His main play (over maneuvering to fill the hand), more so with Confirm Suspicion to follow.
        return 14.0 + (me.hand.any((c) => c.title == 'Confirm Suspicion') ? 4.0 : 0.0) + shed + later;
      case 'Administer Aid':
        final holmes = me.heroFighter;
        if (!holmes.onBoard) return shed + later;
        final watson = _watson(me);
        // Watson back next to Holmes (they stay together); a heal when Holmes is hurt and safe.
        final apart = watson != null && watson.onBoard && !g.board.adjacent(watson.space!, holmes.space!);
        final safe = !g.enemyFighters(me).any((e) => e.onBoard && ai._strikeZones(g, e).$1.contains(holmes.space));
        return (holmes.hp < holmes.maxHp && safe ? 16.0 : 0.0) + (apart ? 8.0 : 0.0) + shed + later;
      case 'Master of Disguise':
        if (_disguiseFinishes(g, me)) return 40.0;
        if (_disguiseEscapes(ai, g, me)) return 12.0;
        return hold && _disguiseOpens(g, me) ? 14.0 : 0.0;
    }
    return shed + later;
  },
  attackCard: (ai, g, c, card) {
    final me = c.attacker.player, f = c.attacker.fighter, t = c.defender.fighter;
    final opp = t.owner;
    switch (card.title) {
      case 'Counterpunch':
        // Easily dodged when attacking; but it clears a 1-health sidekick off a crowded Holmes.
        final crowd = f.onBoard ? g.enemyFighters(me).where((e) => e.onBoard && g.board.adjacent(e.space!, f.space!)).length : 0;
        return t.isSidekick && t.hp <= 1 && crowd >= 2 ? 4.0 : -4.0;
      case 'Study Methods':
        // Watson, at a target sure not to defend (out of defenses, or a sidekick they won't save).
        final sure = opp.hand.isEmpty ||
            ai._noBlock(g, opp) ||
            (opp.hand.every(me.script.known.contains) && !opp.hand.any((x) => g.canDefendWith(x, t)));
        return f.isSidekick && (sure || (t.isSidekick && t.hp <= 3)) ? 2.0 : -3.0;
      case 'The Game is Afoot':
        // Its move can't be canceled; early, it takes out a strong sidekick.
        return 3.0 + (t.isSidekick && t.maxHp >= 4 && me.deck.length > 15 ? 2.0 : 0.0);
      case 'Fixed Point in a Changing Age':
        return _fixedPoint(g, me, f) - 1.0; // better on defense
      case 'Service Revolver':
        return 4.0;
      case 'Deduce Strategy':
        return 1.0 + (_valueChangersLeft(ai, g, me, opp) ? 2.0 : 0.0);
      case 'Education Never Ends':
        // Holmes winning hands them a card; Watson's bluff (they defend a 5, he draws 2).
        if (f.isHero) return -3.0;
        return me.hand.length <= 4 ? 2.0 : -1.0;
    }
    return 0.0;
  },
  defenseCard: (ai, g, c, card) {
    final me = c.defender.player, f = c.defender.fighter, att = c.attacker.fighter;
    switch (card.title) {
      case 'Counterpunch':
        // The defender's effects go first: next to Holmes they can't step away from the 2 damage.
        if (f.isHero && f.onBoard && att.onBoard && g.board.adjacent(att.space!, f.space!)) return 4.0 + (att.hp <= 2 ? 4.0 : 0.0);
        return 0.0;
      case 'Study Methods':
        // Ties go to the defender, and a win shows their hand; not against a passive bonus.
        if (_passiveBonus(g, c.attacker) > 0) return -6.0;
        return 2.0 + (att.owner.hand.every(me.script.known.contains) ? 0.0 : 1.5);
      case 'Elementary':
        // A right prediction blocks the whole attack.
        final (v, p) = _elementaryPick(ai, g, c, me);
        return p * (v + 2.0);
      case 'Fixed Point in a Changing Age':
        return _fixedPoint(g, me, f) + 1.0;
      case 'Deduce Strategy':
        return _valueChangersLeft(ai, g, me, att.owner) ? -1.0 : 1.0;
      case 'Education Never Ends':
        // His only draw: lose the combat, draw 2 (keep the hand at 4 to 7).
        return 2.0 + (me.hand.length <= 4 ? 2.0 : 0.0);
    }
    return 0.0;
  },
  // Master of Disguise is the card to let go; with 3 schemes or more, any scheme.
  keep: (c, me) => c.title == 'Master of Disguise' ? -3.0 : (c.def.isScheme && _schemes(me) >= 3 ? -2.0 : 0.0),
  // A scheme over the limit of 2, or Master of Disguise to get a defenseless Holmes away.
  freeBoost: (g, me, c) =>
      c.def.isScheme &&
      (_schemes(me) >= 3 || (c.title == 'Master of Disguise' && !me.hand.any((x) => x != c && g.canDefendWith(x, me.heroFighter)))),
  // The shielded one moves first; the other follows to stand by (and in front of) him.
  moveFirst: (ai, g, me, fs) => _shielded(g, me) ?? (fs.contains(me.heroFighter) ? me.heroFighter : null),
  space: (ai, g, f, s, mode) {
    final me = f.owner;
    final holmes = me.heroFighter, watson = _watson(me);
    if (watson == null || !watson.onBoard || !holmes.onBoard || (f != holmes && f != watson)) return 0.0;
    final partner = f == holmes ? watson : holmes;
    var b = 0.0;
    // Holmes and Watson stay next to each other (Watson follows).
    final w = f == watson ? 1.0 : 0.4;
    b += g.board.adjacent(s, partner.space!) ? 6.0 * w : -1.5 * w * min(ai._walk(g, s, partner.space!), 8);
    // Shield the defenseless one: stand where they can attack him from fewer spaces.
    final shielded = _shielded(g, me);
    if (shielded != null && shielded != f) b -= 1.0 * _exposure(ai, g, me, shielded, f, s);
    // After The Game is Afoot, Holmes' move gets him out of their reach.
    final c = g.combat;
    if (c != null && f == holmes && c.attacker.fighter == holmes) {
      for (final e in g.enemyFighters(me).where((e) => e.onBoard)) {
        final (now, later) = ai._strikeZones(g, e);
        if (now.contains(s)) {
          b -= 10.0;
        } else if (later.contains(s)) {
          b -= 5.0;
        }
      }
    }
    return b;
  },
  number: (ai, g, p) {
    int? index(int v) {
      final i = p.choices.indexWhere((c) => c.value == v);
      return i < 0 ? null : i;
    }

    if (p.text.startsWith('Elementary')) {
      final c = g.combat;
      return c == null ? null : index(_elementaryPick(ai, g, c, p.player).$1);
    }
    if (!p.text.startsWith('Confirm Suspicion')) return null;
    final opp = _foeHero(g, p.player)?.owner;
    return opp == null ? null : index(_suspicionPick(ai, g, p.player, opp).$1);
  },
  discardTheirs: (ai, g, p, cards) {
    final me = p.player;
    final finishing = _defenselessFinish(g, me);
    final suspicionLeft = [...me.hand, ...me.deck].any((c) => c.title == 'Confirm Suspicion');
    double score(Card c) {
      final d = c.def;
      // Leaving them defenseless: their best defense.
      if (finishing) return d.canDefend ? 100.0 + (d.value ?? 0) * 5 : (d.value ?? 0) * 0.1;
      var s = _sherlockThreat(g, me, d, suspicion: false);
      final kind = _takesBack(d) || _healsCard(d) || _makesDiscard(d) || _bigHit(d);
      // Schemes first (Confirm Suspicion can't touch them); high BOOSTs are its job.
      if (d.isScheme) s += kind ? 15.0 : 3.0;
      if (suspicionLeft && !d.isScheme && (d.boost ?? 0) >= 3) s -= 5.0;
      return s;
    }

    final order = List.generate(cards.length, (i) => i)..sort((a, b) => score(cards[b]).compareTo(score(cards[a])));
    return order.take(p.min).toList();
  },
  rules: (ai) => [
    GroundRule(
      'Eliminate the Impossible only against 5 or more cards, to leave a low hero next to Holmes '
      'defenseless before his finishing attack, or to get down below 3 schemes.',
      (g, p, c) =>
          c is ActionChoice &&
          c.kind == ActionKind.scheme &&
          c.card!.title == 'Eliminate the Impossible' &&
          (_foeHero(g, p.player)?.owner.hand.length ?? 0) < (_schemes(p.player) >= 3 ? 1 : 5) &&
          !_defenselessFinish(g, p.player),
    ),
    GroundRule(
      'Master of Disguise only to finish their hero, to escape when surrounded, or to open a '
      'full-hand standoff turn (swap, then maneuver away) against a hero without sidekicks.',
      (g, p, c) =>
          c is ActionChoice &&
          c.kind == ActionKind.scheme &&
          c.card!.title == 'Master of Disguise' &&
          !_disguiseFinishes(g, p.player) &&
          !_disguiseEscapes(ai, g, p.player) &&
          !(_disguiseOpens(g, p.player) && ai._proMode(g, p.player) == ProMode.hold),
    ),
    GroundRule(
      'No Study Methods on defense against an attack its hero passively adds to (Achilles without '
      'Patroclus, BIG Alice, ENRAGED Eredin), unless it is the only defense.',
      (g, p, c) =>
          p.intent == Intent.defenseCard &&
          c is Card &&
          c.title == 'Study Methods' &&
          p.choices.any((o) => (o.value as Card).title != 'Study Methods') &&
          _passiveBonus(g, (p.subject as Combat).attacker) > 0,
    ),
    GroundRule(
      'No Confirm Suspicion against an empty hand.',
      (g, p, c) =>
          c is ActionChoice &&
          c.kind == ActionKind.scheme &&
          c.card!.title == 'Confirm Suspicion' &&
          (_foeHero(g, p.player)?.owner.hand.isEmpty ?? true),
    ),
  ],
);
