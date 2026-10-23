/// The rules engine: setup, turns, actions, combat and every effect primitive cards use.
///
/// Rules follow the Unmatched rulebook plus the official rulings collected by The Unmatched Club:
/// * 2 actions a turn (maneuver, scheme, attack; repeats allowed, none skipped); hand limit 7.
/// * Maneuver: draw 1 (an empty deck deals 2 damage to each of your fighters instead), optionally
///   BOOST by discarding a card, then move each fighter up to the move value. Fighters pass
///   through friends, never through enemies, and never end in an occupied space.
/// * Melee attacks reach adjacent fighters; ranged attacks also reach anyone in a shared zone.
/// * Combat: both cards revealed, then IMMEDIATELY, DURING, damage, AFTER COMBAT, then other game
///   effects (abilities). The defender's effects resolve first in each step. The attacker wins
///   only if the attack itself dealt 1+ damage.
/// * Winners are checked after AFTER COMBAT effects; if both heroes fall the active player wins.
library;

import 'dart:math';

import 'combat.dart';
import 'defs.dart';
import 'events.dart';
import 'hero_script.dart';
import 'heroes/common.dart';
import 'heroes/registry.dart';
import 'prompt.dart';
import 'state.dart';

class GameOverSignal implements Exception {
  const GameOverSignal();
}

typedef Presenter = Future<void> Function(GameEvent e);

class Game {
  Game({
    required this.data,
    required MapDef map,
    required List<String> heroIds,
    required this.agents,
    int? seed,
    Random? random,
    this.presenter,
    this.firstSeat,
    List<int>? teams,
    HeroScript Function(String heroId)? scripts,
  })  : // Real games shuffle with the OS's cryptographic RNG so decks can't be predicted;
        // a seed is only for reproducible tests.
        // [random] overrides both (multiplayer passes a PortableRandom so every platform agrees).
        rng = random ?? (seed == null ? Random.secure() : Random(seed)),
        board = Board(map) {
    final make = scripts ?? createHeroScript;
    for (var i = 0; i < heroIds.length; i++) {
      final def = data.hero(heroIds[i]);
      final script = make(def.id);
      final p = Player(i, def, script)..team = teams?[i] ?? i;
      script
        ..game = this
        ..me = p;
      for (final fd in def.fighters) {
        for (var k = 1; k <= fd.count; k++) {
          p.fighters.add(Fighter(_uid++, fd, p, k));
        }
      }
      players.add(p);
    }
  }

  final GameData data;
  final Board board;
  final Random rng;
  final List<Agent> agents;
  final Presenter? presenter;

  /// Seat that goes first; random when null.
  final int? firstSeat;
  final List<Player> players = [];
  final List<GameEvent> log = [];
  final Map<String, CardScript> commonCards = commonCardScripts;

  /// Ongoing and temporary mods (hero abilities are the players' scripts).
  final List<Mod> mods = [];
  final List<Card> _inCombat = [];
  int _uid = 0;

  late TurnInfo turn;
  int turnNumber = 0;
  int actions = 0;
  Combat? combat;
  Player? winner;

  /// The winning team (every player on it won).
  int? winningTeam;
  bool over = false;
  late Player first;

  /// Seats in turn order (A1, B1, A2, B2... in team play). Index + 1 is the start space number.
  final List<Player> order = [];

  /// Free-for-all: more than two players, everyone on their own team.
  bool get isFreeForAll => players.length > 2 && players.map((p) => p.team).toSet().length == players.length;

  /// Players who are still in the game and opposing [p].
  Iterable<Player> enemiesOf(Player p) => players.where((o) => o.isEnemyOf(p) && !o.eliminated);

  /// Opposing fighters on the board from [p]'s point of view.
  Iterable<Fighter> enemyFighters(Player p) => onBoard.where((f) => f.isEnemyOf(p));

  /// The next player in turn order after [p] who is still in the game.
  Player nextPlayer(Player p) {
    var i = order.indexOf(p);
    for (var k = 0; k < order.length; k++) {
      i = (i + 1) % order.length;
      if (!order[i].eliminated) return order[i];
    }
    return p;
  }

  /// Set by "End the turn": stops every further effect this turn.
  bool get turnEnded => turn.flags['endTurn'] == true;
  Player get active => turn.player;
  Iterable<Mod> get allMods sync* {
    for (final p in players) {
      yield p.script;
    }
    yield* mods;
  }

  Iterable<Fighter> get fighters => players.expand((p) => p.fighters);
  Iterable<Fighter> get onBoard => fighters.where((f) => f.onBoard);

  Future<void> emit(GameEvent e) async {
    log.add(e);
    if (presenter != null) await presenter!(e);
  }

  Future<void> say(String text) => emit(LogEvent(text));

  // =================================================================================== lifecycle

  Future<Player?> run() async {
    try {
      await setup();
      while (true) {
        await playTurn(turnNumber == 0 ? first : nextPlayer(active));
      }
    } on GameOverSignal {
      return winner;
    }
  }

  Future<void> setup() async {
    // Seats are already in table order (alternating teams); rotating keeps the alternation.
    final k = firstSeat ?? rng.nextInt(players.length);
    order
      ..clear()
      ..addAll([...players.skip(k), ...players.take(k)]);
    first = order.first;
    await say('${first.name} goes first.');
    for (final p in order) {
      await p.script.beforeDeck();
      var copy = <String, int>{};
      for (final def in p.script.deckCards()) {
        final n = copy[def.key] = (copy[def.key] ?? -1) + 1;
        p.deck.add(Card(_uid++, def, n, p));
      }
      p.deck.shuffle(rng);
    }
    for (var i = 0; i < order.length; i++) {
      final p = order[i];
      final hero = p.heroFighter;
      hero.space = board.startSpace(i + 1) ?? board.startSpaces.elementAt(i);
      p.startSpace = hero.space!;
      await emit(FighterPlacedAtStart(hero));
      for (final f in p.fighters) {
        if (f.isSidekick && p.script.startsInReserve(f)) f.reserve = true;
      }
      await p.script.afterHeroPlaced();
    }
    for (final p in order) {
      await p.script.placeSidekicks();
    }
    for (final p in order) {
      await p.script.beforeStartingHand();
      final n = p.script.startingHand;
      p.hand.addAll(p.deck.take(n));
      p.deck.removeRange(0, min(n, p.deck.length));
      await emit(CardsDrawn(p, List.of(p.hand)));
    }
  }

  Future<void> playTurn(Player p) async {
    turnNumber++;
    turn = TurnInfo(p, turnNumber);
    for (final f in fighters) {
      turn.startSpace[f] = f.space;
    }
    actions = 2;
    await emit(TurnStarted(p, turnNumber));
    await emit(ActionsChanged(p, actions, 0));
    for (final m in [p.script, ...players.where((o) => o != p).map((o) => o.script), ...mods]) {
      if (turnEnded) break;
      await m.startOfTurn(this, p);
    }
    await checkWinner();
    while (actions > 0 && !turnEnded) {
      actions--;
      await emit(ActionsChanged(p, actions, 0));
      await takeAction(p);
      turn.actionsTaken++;
      await checkWinner();
    }
    for (final m in [p.script, ...players.where((o) => o != p).map((o) => o.script), ...mods]) {
      await m.endOfTurn(this, p);
    }
    p.turnsTaken++;
    for (final m in mods.whereType<OngoingMod>().toList()) {
      if (m.owner == p && m.discardAtEndOfTurn(this)) await discardOngoing(m);
    }
    mods.removeWhere((m) => m is TurnMod);
    await checkWinner();
    var limit = 7;
    for (final m in allMods) {
      limit = m.handLimit(this, p, limit);
    }
    if (p.hand.length > limit) {
      final extra = p.hand.length - limit;
      final cards = await chooseCards(p, p.hand, extra, extra,
          'Hand limit is $limit: discard $extra card${extra > 1 ? 's' : ''}', intent: Intent.loseOwn);
      for (final c in cards) {
        await discardCard(c, reason: ' (hand limit)');
      }
    }
  }

  /// Eliminations and the end of the game. Called after AFTER COMBAT effects and after each
  /// action / start / end of turn (the official endgame timing).
  Future<void> checkWinner() async {
    if (over) throw const GameOverSignal();
    for (final p in players.where((p) => !p.eliminated)) {
      // Free-for-all: a defeated hero's player is out and their sidekicks leave the board.
      // Team play: a player continues while any of their fighters remain.
      final out = isFreeForAll ? p.defeated : p.fighters.every((f) => f.defeated || f.reserve);
      if (!out) continue;
      p.eliminated = true;
      for (final f in p.fighters.where((f) => f.onBoard)) {
        f
          ..defeated = true
          ..space = null;
      }
      await emit(StatusChanged(p, '${p.name} is out of the game.'));
    }
    final teamsLeft = players.where((p) => !p.defeated).map((p) => p.team).toSet();
    if (teamsLeft.length > 1) return;
    // Everyone fell at once: the active player's side wins.
    winningTeam = teamsLeft.isEmpty ? active.team : teamsLeft.single;
    winner = players.firstWhere((p) => p.team == winningTeam);
    over = true;
    await emit(GameOver(winner, teamsLeft.isEmpty ? 'Every remaining hero fell at once; the active player wins.' : ''));
    throw const GameOverSignal();
  }

  /// Free-for-all first turn: a hero may only attack the next player in turn order or someone
  /// who has already taken a turn.
  bool mayAttackPlayer(Player attacker, Player target) {
    if (!isFreeForAll || attacker.turnsTaken > 0) return true;
    return target.turnsTaken > 0 || target == nextPlayer(attacker);
  }

  // ===================================================================================== actions

  /// Every legal action for [p] right now.
  List<ActionChoice> legalActions(Player p) {
    final out = <ActionChoice>[const ActionChoice(ActionKind.maneuver)];
    final seen = <String>{};
    for (final c in p.hand) {
      if (!c.def.isScheme || !seen.add(c.def.key)) continue;
      if (schemeFighters(p, c).isNotEmpty) out.add(ActionChoice(ActionKind.scheme, card: c));
    }
    for (final f in p.onBoard) {
      final cards = p.hand.where((c) => canAttackWith(c, f)).toList();
      if (cards.isEmpty) continue;
      for (final t in enemyFighters(p)) {
        if (!mayAttackPlayer(p, t.owner)) continue;
        if (inReach(f, t) || cards.any((c) => scriptOf(c)?.target?.call(this, f, t) ?? false)) {
          out.add(ActionChoice(ActionKind.attack, fighter: f, target: t));
        }
      }
    }
    return out;
  }

  Iterable<Fighter> schemeFighters(Player p, Card c) => p.onBoard.where((f) {
        if (!p.script.fighterMayUse(c, f)) return false;
        final s = scriptOf(c);
        return s?.canPlay?.call(this, p, f) ?? true;
      });

  bool canAttackWith(Card c, Fighter f) {
    if (!f.owner.script.fighterMayUse(c, f)) return false;
    final s = scriptOf(c);
    if (s?.canPlay != null && !s!.canPlay!(this, f.owner, f)) return false;
    return c.def.canAttack || (s?.alsoAttack?.call(this, f) ?? false);
  }

  bool canDefendWith(Card c, Fighter f) {
    if (!f.owner.script.fighterMayUse(c, f)) return false;
    final s = scriptOf(c);
    return c.def.canDefend || (s?.alsoDefense?.call(this, f) ?? false);
  }

  /// Normal attack reach: melee = adjacent, ranged = adjacent or a shared zone.
  bool inReach(Fighter a, Fighter t) {
    if (!a.onBoard || !t.onBoard || !t.isEnemyOf(a.owner)) return false;
    if (board.adjacent(a.space!, t.space!)) return true;
    if (a.isRanged && board.sharesZone(a.space!, t.space!)) return true;
    return allMods.any((m) => m.canAlsoTarget(this, a, t));
  }

  Future<void> takeAction(Player p) async {
    final choices = legalActions(p);
    final pick = await choose<ActionChoice>(
      p,
      Ask.action,
      'Choose an action (${actions + 1} left)',
      [
        for (final a in choices)
          Choice(
            switch (a.kind) {
              ActionKind.maneuver => 'Maneuver',
              ActionKind.scheme => 'Scheme: ${a.card!.title}',
              ActionKind.attack => 'Attack: ${a.fighter!.name} → ${a.target!.name}',
            },
            a,
          )
      ],
      autoSingle: false,
    );
    switch (pick!.kind) {
      case ActionKind.maneuver:
        await maneuver(p);
      case ActionKind.scheme:
        await playScheme(p, pick.card!);
      case ActionKind.attack:
        await attack(pick.fighter!, pick.target!);
    }
  }

  // --------------------------------------------------------------------------------- maneuver

  Future<void> maneuver(Player p) async {
    turn.maneuvers++;
    await emit(ActionTaken(p, 'Maneuver', ''));
    var n = 1;
    for (final m in allMods) {
      n = m.maneuverDraws(this, p, n);
    }
    await p.script.maneuverDraw(n);
    var bonus = 0;
    Card? boost;
    final boostable = p.hand.where((c) => c.def.canBoost).toList();
    if (boostable.isNotEmpty) {
      boost = await chooseCard(p, boostable, 'Discard a card to BOOST your movement?',
          optional: true, skipLabel: "Don't boost", intent: Intent.boost);
      if (boost != null) {
        await discardCard(boost, reason: ' to boost');
        bonus = await boostAmount(boost);
        await emit(Boosted(p, boost, 'their maneuver'));
        turn.flags['maneuverBoost'] = boost;
        await runBoosted(boost);
      }
    }
    for (final m in allMods.toList()) {
      await m.beforeManeuverMoves(this, p);
    }
    final toMove = p.onBoard.toList();
    turn.flags['maneuvering'] = boost != null ? 'boosted' : true;
    while (toMove.isNotEmpty && !turnEnded) {
      final f = toMove.length == 1 && toMove.first.isHero && p.fighters.length == 1
          ? toMove.first
          : await chooseFighter(p, toMove, 'Choose a fighter to move', optional: true, skipLabel: 'Done moving', intent: Intent.moveOwn);
      if (f == null) break;
      toMove.remove(f);
      if (!f.onBoard) continue;
      await p.script.maneuverMove(f, moveAllowance(f) + bonus, boosted: boost != null);
    }
    turn.flags.remove('maneuvering');
    for (final m in allMods.toList()) {
      await m.afterManeuver(this, p);
    }
  }

  int moveValueOf(Fighter f) {
    var v = f.owner.hero.move;
    for (final m in allMods) {
      v = m.moveValue(this, f, v);
    }
    return v;
  }

  int moveAllowance(Fighter f) {
    var v = moveValueOf(f);
    for (final m in allMods) {
      v += m.maneuverBonus(this, f);
    }
    return v;
  }

  /// The script for [c]'s effects: always its owner's (an opponent may play Loki's tricks).
  CardScript? scriptOf(Card c) => c.owner.script.scriptFor(c);

  /// The player whose hand holds [c] (normally its owner).
  Player holderOf(Card c) => players.firstWhere((p) => p.hand.contains(c), orElse: () => c.owner);

  /// The BOOST a card gives when discarded: its printed value, or a die roll for Krang's '?'.
  Future<int> boostAmount(Card c) async {
    if (c.def.dieBoost && c.def.boost == null) {
      var r = await c.owner.script.rollDie('BOOST of ${c.title}');
      for (final m in allMods) {
        r = m.boostValue(this, c, r);
      }
      return r;
    }
    return boostValueOf(c);
  }

  int boostValueOf(Card c) {
    var v = c.def.boost ?? 0;
    for (final m in allMods) {
      v = m.boostValue(this, c, v);
    }
    return v;
  }

  // ----------------------------------------------------------------------------------- scheme

  Future<void> playScheme(Player p, Card card) async {
    final who = schemeFighters(p, card).toList();
    final f = await chooseFighter(p, who, 'Which fighter plays ${card.title}?', intent: Intent.none, source: card);
    p.hand.remove(card);
    card.playedBy = p;
    _inCombat.add(card);
    turn.schemes++;
    turn.played.add(card);
    await emit(ActionTaken(p, 'Scheme', ': ${card.title}'));
    await emit(SchemePlayed(card, f!));
    final s = scriptOf(card);
    // With several opponents, a scheme that refers to "your opponent" is aimed at one of them.
    Player? target;
    final foes = enemiesOf(p).toList();
    if (foes.length > 1 && card.def.text.values.any((t) => t.toLowerCase().contains('opponent'))) {
      target = await choose<Player>(p, Ask.option, '${card.title}: choose an opponent', [for (final o in foes) Choice(o.name, o)],
          intent: Intent.harm, source: card);
    }
    final x = Fx(this, p, card: card, fighter: f, target: target);
    if (s?.effect != null) await s!.effect!(x);
    if (_inCombat.contains(card)) {
      if (s?.ongoing != null) {
        // Each hero can have only one ongoing scheme; a new one replaces the old.
        for (final old in mods.whereType<OngoingMod>().where((m) => m.owner == p).toList()) {
          await discardOngoing(old);
        }
        _inCombat.remove(card);
        p.inPlay.add(card);
        mods.add(s!.ongoing!(this, card, f));
        await emit(CardMoved(card, Zone.combat, Zone.inPlay));
      } else {
        _inCombat.remove(card);
        await disposePlayed(card);
      }
    }
    for (final m in allMods.toList()) {
      await m.afterAction(this, p, ActionKind.scheme, card: card, fighter: f);
    }
  }

  Future<void> discardOngoing(OngoingMod m) async {
    mods.remove(m);
    if (m.owner.inPlay.remove(m.card)) {
      m.owner.discard.add(m.card);
      await emit(CardMoved(m.card, Zone.inPlay, Zone.discard));
    }
  }

  Future<void> disposePlayed(Card c) async {
    if (c.virtual || await c.owner.script.disposePlayed(c)) return;
    c.owner.discard.add(c);
    await emit(CardMoved(c, Zone.combat, Zone.discard));
  }

  // ----------------------------------------------------------------------------------- attack

  Future<void> attack(Fighter a, Fighter t) async {
    final p = a.owner;
    turn.attacks++;
    turn.attacksBy[a] = (turn.attacksBy[a] ?? 0) + 1;
    await emit(ActionTaken(p, 'Attack', ': ${a.name} → ${t.name}'));
    await resolveCombat(a, t);
    while (_bonus != null) {
      final (ba, bt, bc) = _bonus!;
      _bonus = null;
      // Ruling: no bonus attack if either fighter was defeated; range is not checked again.
      if (ba.onBoard && bt.onBoard && !turnEnded) await resolveCombat(ba, bt, attackCard: bc);
    }
    for (final m in allMods.toList()) {
      await m.afterAction(this, p, ActionKind.attack, fighter: a);
    }
  }

  /// Runs one full combat. Also used for bonus attacks.
  Future<Combat> resolveCombat(Fighter a, Fighter t, {Card? attackCard}) async {
    final c = Combat(a, t);
    combat = c;
    await emit(CombatStarted(c));
    for (final m in allMods.toList()) {
      await m.onAttacked(this, c);
    }
    t = c.defender.fighter;
    final p = a.owner, o = t.owner;
    final reach = inReach(a, t);
    var card = attackCard;
    if (card == null) {
      final options = p.hand
          .where((x) => canAttackWith(x, a) && (reach || (scriptOf(x)?.target?.call(this, a, t) ?? false)))
          .toList();
      card = await chooseCard(p, options, 'Choose an attack card', intent: Intent.attackCard, subject: c, autoSingle: false);
    }
    p.hand.remove(card);
    card?.playedBy = p;
    c.attacker.card = card;
    _inCombat.add(card!);
    if (!reach) c.attacker.faceUp = true;
    await p.script.onAttackCardChosen(c);
    final defOptions = o.hand.where((x) => canDefendWith(x, c.defender.fighter)).toList();
    final d = await chooseCard(o, defOptions, 'Play a defense card or skip', optional: true, skipLabel: 'No defense',
        intent: Intent.defenseCard, subject: c, autoSingle: false);
    if (d != null) {
      o.hand.remove(d);
      d.playedBy = o;
      c.defender.card = d;
      _inCombat.add(d);
    }
    for (final s in c.sides) {
      final sc = s.card == null ? null : scriptOf(s.card!);
      if (sc?.onReveal != null) await sc!.onReveal!(Fx(this, s.player, card: s.card, side: s));
    }
    turn.played.addAll([card, if (d != null) d]);
    c.phase = Phase.reveal;
    await emit(CardsRevealed(c));

    await _phase(c, Phase.immediately, 'immediately');
    for (final m in allMods.toList()) {
      if (turnEnded) break;
      await m.combatImmediately(this, c);
    }
    await _phase(c, Phase.during, 'during');

    c.phase = Phase.damage;
    c.attackValue = valueOf(c.attacker).total;
    c.defenseValue = valueOf(c.defender).total;
    await emit(ValuesChanged(c));
    final dmg = max(0, c.attackValue - c.defenseValue);
    if (dmg > 0 && c.defender.fighter.alive && !turnEnded) {
      if (c.flags['preventAll'] == true) {
        await say('All damage is prevented.');
      } else if (c.flags['reflect'] == true) {
        await damage(c.attacker.fighter, dmg, info: DamageInfo(source: c.defender.fighter, combat: true, by: o));
      } else {
        c.combatDamage = await damage(c.defender.fighter, dmg,
            info: DamageInfo(source: c.attacker.fighter, combat: true, card: card, by: p));
      }
    }
    c.attackerWon = c.combatDamage > 0;
    c.resolved = true;
    await emit(CombatResolved(c));

    await _phase(c, Phase.after, 'after');
    for (final m in allMods.toList()) {
      if (turnEnded) break;
      await m.afterCombat(this, c);
    }
    c.phase = Phase.done;
    for (final x in List.of(_inCombat)) {
      _inCombat.remove(x);
      await disposePlayed(x);
    }
    combat = null;
    await emit(CombatEnded(c));
    await checkWinner();
    return c;
  }

  Future<void> _phase(Combat c, Phase phase, String timing) async {
    c.phase = phase;
    await emit(PhaseChanged(c, phase));
    for (final s in c.sides) {
      await _resolve(s, timing);
    }
  }

  Future<void> _resolve(Side s, String timing) async {
    Card? done;
    while (s.card != null && s.card != done && !turnEnded) {
      final card = done = s.card!;
      if (s.canceled || (timing == 'after' && s.afterCanceled)) return;
      final sc = scriptOf(card);
      final fn = switch (timing) { 'immediately' => sc?.immediately, 'during' => sc?.during, _ => sc?.after };
      if (fn == null) {
        if (timing != 'immediately') return;
        continue;
      }
      await emit(EffectResolving(s, timing, card.def.text[timing] ?? ''));
      await fn(Fx(this, s.player, card: card, side: s));
      // A card swapped in during IMMEDIATELY resolves its own IMMEDIATELY effect.
      if (timing != 'immediately') return;
    }
  }

  // ------------------------------------------------------------------------------ card values

  bool isUncancelable(Side s) {
    if (s.card == null) return true;
    final sc = scriptOf(s.card!);
    if (sc == null || sc.noEffects || sc.uncancelable) return true;
    return allMods.any((m) => m.uncancelable(this, s));
  }

  /// Cancels all effects on [s]'s card (or only its AFTER COMBAT effects).
  void cancel(Side s, {bool afterOnly = false}) {
    if (s.card == null || isUncancelable(s)) return;
    if (afterOnly) {
      if (scriptOf(s.card!)?.after == null) return;
      s.afterCanceled = true;
    } else {
      // Ruling: a card is only "canceled" if it had an effect to cancel (Excalibur can't be).
      if (!(scriptOf(s.card!)?.hasCombatEffects ?? false)) return;
      s.canceled = true;
      // King Arthur: a canceled attack loses its face-down boost.
      s.ops.removeWhere((o) => o.label.startsWith('BOOST: King Arthur'));
    }
    emit(Canceled(s, afterOnly: afterOnly));
  }

  void ignoreValue(Side s) {
    if (s.card == null) return;
    s.ignored = true;
    emit(ValuesChanged(s.combat));
  }

  void addOp(Side s, ValueOp op) {
    s.ops.add(op);
    emit(ValuesChanged(s.combat));
  }

  ({int total, List<(String, int)> lines}) valueOf(Side s) {
    if (s.card == null) return (total: 0, lines: const []);
    final lines = <(String, int)>[('Card base value', s.printed)];
    if (s.lockZero) return (total: 0, lines: [...lines, ('Fixed at 0', -s.printed)]);
    for (final m in allMods) {
      final f = m.fixedValue(this, s);
      if (f != null) return (total: f, lines: [...lines, ('${m.label}: fixed at $f', f - s.printed)]);
    }
    var v = s.printed;
    if (!s.lockPrinted) {
      void apply(ValueOp op) {
        final before = v;
        v = op.apply(v);
        lines.add((op.isSet ? '${op.label} (set to ${op.amount})' : op.label, v - before));
      }

      s.ops.forEach(apply);
      for (final m in allMods) {
        m.valueOps(this, s).forEach(apply);
      }
    } else {
      lines.add(('Printed value only', 0));
    }
    if (s.ignored) {
      lines.add(('Value ignored', -v));
      v = 0;
    }
    return (total: max(0, v), lines: lines);
  }

  /// "You may BOOST this card": discard a card from hand (or, blind, the top of the deck) and add
  /// its BOOST value. Returns whether a boost happened.
  Future<bool> boostCard(Side s, {bool blind = false, String? text, bool optional = true}) async {
    final p = s.player;
    Card? b;
    if (blind) {
      if (p.deck.isEmpty) return false;
      if (optional && !await yesNo(p, text ?? 'BLIND BOOST ${s.card?.title}?', intent: Intent.help)) return false;
      b = p.deck.removeAt(0);
      p.discard.add(b);
      await emit(CardMoved(b, Zone.deck, Zone.discard, reason: ' (blind boost)'));
    } else {
      final options = p.hand.where((c) => c.def.canBoost).toList();
      b = await chooseCard(p, options, text ?? 'Discard a card to BOOST ${s.card?.title}?',
          optional: optional, skipLabel: "Don't boost", intent: Intent.boost, subject: s);
      if (b == null) return false;
      await discardCard(b, reason: ' to boost');
    }
    s.boosts.add(b);
    final v = blind ? boostValueOf(b) : await boostAmount(b);
    addOp(s, ValueOp.add(v, '${blind ? 'Blind boosted' : 'Boosted'} by ${b.title.toUpperCase()}'));
    await emit(Boosted(p, b, s.card?.title ?? 'the card', blind: blind));
    if (!blind) await runBoosted(b);
    return true;
  }

  /// Houdini's cards do something extra when discarded to boost.
  Future<void> runBoosted(Card c) async {
    final sc = scriptOf(c);
    if (sc?.boosted != null) {
      await emit(LogEvent('${c.title} — BOOSTED WITH: ${c.def.text['boosted'] ?? ''}'));
      await sc!.boosted!(Fx(this, c.owner, card: c, fighter: c.owner.heroFighter));
    }
  }

  /// Replaces the card on [s] (Do My Bidding, Sleight of Hand). The old card goes to [oldTo].
  Future<void> replaceCard(Side s, Card? newCard, {Zone oldTo = Zone.hand}) async {
    final old = s.card;
    if (old != null && !old.virtual) {
      _inCombat.remove(old);
      if (oldTo == Zone.hand) {
        (old.playedBy ?? old.owner).hand.add(old);
      } else {
        old.owner.discard.add(old);
      }
    }
    s.clearCard();
    s.card = newCard;
    if (newCard != null) {
      s.player.hand.remove(newCard) || newCard.owner.hand.remove(newCard);
      newCard.owner.deck.remove(newCard);
      newCard.playedBy = s.player;
      _inCombat.add(newCard);
      turn.played.add(newCard);
    }
    await emit(CardSwapped(s, old));
  }

  /// Takes a played card back out of the combat (e.g. "return this card to your hand").
  Future<void> returnPlayedToHand(Card c) async {
    if (!c.virtual && _inCombat.remove(c)) {
      (c.playedBy ?? c.owner).hand.add(c);
      await emit(CardMoved(c, Zone.combat, Zone.hand));
    }
  }

  bool isInPlay(Card c) => _inCombat.contains(c);

  /// Cards currently played into a combat or scheme (not yet discarded).
  List<Card> get playedCards => List.unmodifiable(_inCombat.where((c) => !c.virtual));

  (Fighter, Fighter, Card)? _bonus;

  /// A bonus attack printed on [x]'s card (BoL Vol. 2): after this combat, the same attacker
  /// attacks the same defender again with a card of [value] that has the source card's BOOST.
  Future<void> bonusAttack(Fx x, String name, int value) async {
    final def = CardDef(
      heroId: x.me.hero.id,
      index: 0,
      title: name,
      type: CardType.attack,
      value: value,
      boost: x.card?.def.boost,
      copies: 1,
      fighters: const [],
      usedBy: 'ANY',
      text: const {},
    );
    _bonus = (x.fighter, x.oppFighter, Card(_uid++, def, 0, x.me, virtual: true));
    await say('BONUS ATTACK: ${name.toUpperCase()} ($value)');
  }

  /// Opposing fighters on the spaces a path passes through (not its start or end).
  List<Fighter> movedThrough(List<int>? path, Player mover) => [
        if (path != null)
          for (final s in path.skip(1).take(max(0, path.length - 2)))
            if (fighterAt(s) case final f? when f.isEnemyOf(mover)) f
      ];

  /// Puts a sidekick that is off the board (reserve or defeated) into one of [spaces]. If all of
  /// that kind are already on the board and [moveIfNone], one of them moves there instead.
  Future<bool> summon(Player p, String fighterId, Iterable<int> spaces, {bool moveIfNone = false, String? text}) async {
    final options = spaces.where(isEmpty).toList();
    if (options.isEmpty) return false;
    final kind = p.fighters.where((f) => f.id == fighterId);
    var f = kind.where((f) => !f.onBoard && !f.offBoard).firstOrNull;
    if (f == null && moveIfNone) {
      f = await chooseFighter(p, kind.where((f) => f.onBoard), 'All are on the board: choose one to move', intent: Intent.none);
      if (f == null) return false;
      final s = await chooseSpace(p, options, text ?? 'Choose a space', intent: Intent.moveOwn, subject: f);
      if (s == null) return false;
      final from = f.space!;
      f.space = s;
      await emit(FighterMoved(f, [from, s], placed: true));
      return true;
    }
    if (f == null) return false;
    final s = await chooseSpace(p, options, text ?? 'Summon ${f.kind}: choose a space', intent: Intent.moveOwn, subject: f);
    return s != null && await revive(f, s);
  }

  /// Plays [c] from its owner's hand face down into the current combat (King Arthur's boost);
  /// it is discarded with the combat cards.
  void stash(Card c) {
    if (holderOf(c).hand.remove(c)) _inCombat.add(c);
  }

  // ===================================================================================== damage

  Future<int> damage(Fighter f, int amount, {DamageInfo info = const DamageInfo()}) async {
    if (!f.alive || f.offBoard || amount <= 0) return 0;
    var n = amount;
    for (final m in allMods) {
      n = m.modifyDamage(this, f, n, info);
    }
    if (n <= 0) return 0;
    final split = await f.owner.script.splitDamage(f, n, info);
    var dealt = 0;
    for (final MapEntry(key: target, value: v) in split.entries) {
      if (v <= 0 || !target.alive) continue;
      var floor = 0;
      for (final m in allMods) {
        floor = max(floor, m.minHealth(this, target));
      }
      final real = floor > 0 ? max(0, min(v, target.hp - floor)) : v;
      if (real <= 0) continue;
      target.hp = max(0, target.hp - real);
      dealt += real;
      turn.damaged.add(target);
      await emit(Damaged(target, real, combat: info.combat));
      for (final m in allMods.toList()) {
        await m.onDamaged(this, target, real, info);
      }
      if (target.hp <= 0 && !target.defeated) await defeat(target);
    }
    return dealt;
  }

  Future<void> defeat(Fighter f) async {
    f.defeated = true;
    f.hp = 0;
    f.space = null;
    f.tail = null;
    f.offBoard = false;
    await emit(Defeated(f));
    for (final m in allMods.toList()) {
      await m.onDefeated(this, f);
    }
  }

  Future<int> heal(Fighter f, int n) async {
    if (!f.alive || n <= 0) return 0;
    final gained = min(n, f.maxHp - f.hp);
    if (gained <= 0) return 0;
    f.hp += gained;
    await emit(Healed(f, gained));
    return gained;
  }

  Future<void> setHealth(Fighter f, int hp) async {
    final before = f.hp;
    f.hp = min(hp, f.maxHp);
    if (f.hp > before) await emit(Healed(f, f.hp - before));
    if (f.hp < before) await emit(Damaged(f, before - f.hp));
  }

  /// Puts a defeated or reserve fighter onto the board ("return", "summon", "resurrect").
  Future<bool> revive(Fighter f, int space, {int? hp}) async {
    if (!isEmpty(space)) return false;
    f.defeated = false;
    f.reserve = false;
    f.offBoard = false;
    f.hp = min(hp ?? f.maxHp, f.maxHp);
    f.space = space;
    turn.startSpace.putIfAbsent(f, () => null);
    await emit(Returned(f));
    return true;
  }

  // =================================================================================== cards

  Future<List<Card>> draw(Player p, int n) async {
    final drawn = <Card>[];
    for (var i = 0; i < n; i++) {
      if (p.deck.isEmpty) {
        if (drawn.isNotEmpty) {
          await emit(CardsDrawn(p, List.of(drawn)));
          drawn.clear();
        }
        await emit(Exhausted(p));
        for (final f in p.alive.where((f) => !f.reserve).toList()) {
          await damage(f, 2, info: const DamageInfo(exhaustion: true));
        }
        continue;
      }
      final c = p.deck.removeAt(0);
      p.hand.add(c);
      drawn.add(c);
    }
    if (drawn.isNotEmpty) await emit(CardsDrawn(p, drawn));
    return drawn;
  }

  Future<void> discardCard(Card c, {String reason = '', bool byOpponent = false}) async {
    final holder = holderOf(c);
    if (!holder.hand.remove(c)) return;
    c.owner.discard.add(c);
    await emit(CardMoved(c, Zone.hand, Zone.discard, reason: reason));
    for (final m in allMods.toList()) {
      await m.onDiscardedFromHand(this, c, byOpponent: byOpponent, holder: holder);
    }
  }

  /// [who] discards [n] cards: chosen by [chooser] (default themselves) or at random.
  Future<List<Card>> discardFromHand(Player who, int n,
      {bool random = false, Player? chooser, Player? by, Card? source}) async {
    if (who.hand.isEmpty || n <= 0) return const [];
    if (allMods.any((m) => m.mayIgnoreDiscard(this, who)) &&
        await yesNo(who, 'Ignore having to discard ${n == 1 ? 'a card' : '$n cards'}?', intent: Intent.help, source: source)) {
      await say('${who.name} ignores the discard.');
      return const [];
    }
    final k = min(n, who.hand.length);
    late List<Card> picked;
    if (random) {
      picked = (List.of(who.hand)..shuffle(rng)).take(k).toList();
    } else {
      final c = chooser ?? who;
      picked = await chooseCards(c, who.hand, k, k, c == who ? 'Discard $k card${k > 1 ? 's' : ''}' : 'Choose $k card${k > 1 ? 's' : ''} for ${who.name} to discard',
          intent: c == who ? Intent.loseOwn : Intent.loseEnemy, source: source);
    }
    final byOpp = by != null && by != who;
    for (final c in picked) {
      await discardCard(c, reason: random ? ' at random' : '', byOpponent: byOpp);
    }
    return picked;
  }

  Future<Card?> discardTopOfDeck(Player p, {String reason = ''}) async {
    if (p.deck.isEmpty) return null;
    final c = p.deck.removeAt(0);
    p.discard.add(c);
    await emit(CardMoved(c, Zone.deck, Zone.discard, reason: reason));
    return c;
  }

  Future<void> toHand(Card c, {String reason = ''}) async {
    final p = c.owner;
    final from = p.discard.remove(c)
        ? Zone.discard
        : p.deck.remove(c)
            ? Zone.deck
            : Zone.combat;
    if (from == Zone.combat) _inCombat.remove(c);
    p.hand.add(c);
    await emit(CardMoved(c, from, Zone.hand, reason: reason));
  }

  Future<void> toDeck(Card c, {bool bottom = false, bool shuffle = false}) async {
    final p = c.owner;
    final from = holderOf(c).hand.remove(c)
        ? Zone.hand
        : p.discard.remove(c)
            ? Zone.discard
            : Zone.combat;
    if (from == Zone.combat) _inCombat.remove(c);
    p.deck.remove(c);
    if (shuffle) {
      p.deck.add(c);
      p.deck.shuffle(rng);
    } else if (bottom) {
      p.deck.add(c);
    } else {
      p.deck.insert(0, c);
    }
    await emit(CardMoved(c, from, Zone.deck, reveal: false));
    if (shuffle) await emit(Shuffled(p));
  }

  Future<void> shuffleDeck(Player p) async {
    p.deck.shuffle(rng);
    await emit(Shuffled(p));
  }

  Future<void> removeFromGame(Card c) async {
    final p = c.owner;
    p.discard.remove(c) || holderOf(c).hand.remove(c) || p.deck.remove(c) || _inCombat.remove(c);
    p.removed.add(c);
    await emit(CardMoved(c, Zone.discard, Zone.removed));
  }

  /// [viewer] looks at [target]'s hand. Returns false if an effect stopped it.
  Future<bool> lookAtHand(Player viewer, Player target, {String why = ''}) async {
    for (final m in allMods.toList()) {
      if (await m.blocksHandLook(this, target, viewer)) return false;
    }
    await emit(Revealed(target, List.of(target.hand), ' to ${viewer.name}$why', viewer: viewer));
    viewer.script.seen(target.hand);
    return true;
  }

  void gainActions(Player p, int n) {
    if (p != active || n <= 0) return;
    if (!allMods.every((m) => m.canGainActions(this, p))) {
      say("${p.name} can't gain actions.");
      return;
    }
    actions += n;
    emit(ActionsChanged(p, actions, n));
  }

  void endTurn() {
    turn.flags['endTurn'] = true;
    say('The turn ends.');
  }

  void addTurnMod(TurnMod m) => mods.add(m);

  // =================================================================================== board

  Fighter? fighterAt(int space) {
    for (final f in fighters) {
      if (f.onBoard && (f.space == space || f.tail == space)) return f;
    }
    return null;
  }

  bool isEmpty(int space) => fighterAt(space) == null;
  Iterable<int> emptySpaces() => board.spaceIds.where(isEmpty);
  // A large fighter in two spaces is adjacent to every space next to either, and in all zones
  // of both (T. Rex); everyone else has a single space.
  bool adjacent(Fighter a, Fighter b) =>
      a != b && a.onBoard && b.onBoard && a.spaces.any((x) => b.spaces.any((y) => board.adjacent(x, y)));
  bool sameZone(Fighter a, Fighter b) =>
      a.onBoard && b.onBoard && a.spaces.any((x) => b.spaces.any((y) => board.sharesZone(x, y)));
  Iterable<Fighter> adjacentFighters(Fighter f) => f.onBoard ? onBoard.where((o) => adjacent(f, o)) : const [];
  Iterable<Fighter> fightersInZoneOf(Fighter f) => f.onBoard ? onBoard.where((o) => sameZone(f, o)) : const [];
  Iterable<int> zoneSpaces(Fighter f) => f.onBoard ? {for (final s in f.spaces) ...board.zoneOf(s)} : const [];
  bool startedTurnElsewhere(Fighter f) => turn.startSpace.containsKey(f) && turn.startSpace[f] != f.space;
  bool cannotLeave(Fighter f) => allMods.any((m) => m.cannotLeave(this, f));

  /// Spaces [f] can end a move of up to [steps] in, with the path to each. Passing through
  /// opposing fighters is allowed only with [throughOpp]; the path chosen passes through as many
  /// of them as possible (for "deal damage to each fighter moved through").
  Map<int, List<int>> reachable(Fighter f, int steps, {bool throughOpp = false}) {
    // A large fighter may start moving from either space she occupies.
    if (f.tail != null && steps > 0 && !cannotLeave(f)) {
      final fromTail = _reachableFrom(f, f.tail!, steps, throughOpp);
      final fromFront = _reachableFrom(f, f.space!, steps, throughOpp);
      final out = <int, List<int>>{...fromTail};
      for (final e in fromFront.entries) {
        final cur = out[e.key];
        if (cur == null || e.value.length <= cur.length) out[e.key] = e.value;
      }
      return out;
    }
    return _reachableFrom(f, f.space!, steps, throughOpp);
  }

  Map<int, List<int>> _reachableFrom(Fighter f, int start, int steps, bool throughOpp) {
    bool isEmpty(int s) {
      final o = fighterAt(s);
      return o == null || o == f;
    }

    final out = <int, List<int>>{start: [start]};
    if (steps <= 0 || cannotLeave(f)) return out;
    bool enemyAt(int s) {
      final o = fighterAt(s);
      return o != null && o.isEnemyOf(f.owner);
    }

    Iterable<int> next(int s) sync* {
      yield* board.neighbours(s);
      for (final m in allMods) {
        yield* m.extraSteps(this, f, s);
      }
    }

    if (!throughOpp) {
      var frontier = [start];
      final paths = <int, List<int>>{start: [start]};
      for (var d = 0; d < steps && frontier.isNotEmpty; d++) {
        final nxt = <int>[];
        for (final s in frontier) {
          for (final n in next(s)) {
            if (paths.containsKey(n) || enemyAt(n)) continue;
            paths[n] = [...paths[s]!, n];
            nxt.add(n);
          }
        }
        frontier = nxt;
      }
      for (final e in paths.entries) {
        if (e.key == start || isEmpty(e.key)) out[e.key] = e.value;
      }
      return out;
    }
    // Through enemies: explore simple paths, keep the one passing the most enemies.
    final best = <int, (int, List<int>)>{};
    void dfs(int s, List<int> path, int passed) {
      if (path.length - 1 >= steps) return;
      for (final n in next(s)) {
        if (path.contains(n)) continue;
        final p2 = [...path, n];
        final passedHere = passed + (enemyAt(n) ? 1 : 0);
        if (isEmpty(n) || n == start) {
          final enemiesThrough = passed;
          final cur = best[n];
          if (cur == null || enemiesThrough > cur.$1 || (enemiesThrough == cur.$1 && p2.length < cur.$2.length)) {
            best[n] = (enemiesThrough, p2);
          }
        }
        dfs(n, p2, passedHere);
      }
    }

    dfs(start, [start], 0);
    for (final e in best.entries) {
      out[e.key] = e.value.$2;
    }
    return out;
  }

  /// Moves [f] up to [upTo] spaces; [chooser] picks the destination. Returns the path taken
  /// (null if it couldn't move).
  Future<List<int>?> moveFighter(Fighter f, int upTo,
      {Player? chooser, bool throughOpp = false, String? text, Card? source}) async {
    if (!f.onBoard || upTo <= 0) return null;
    if (cannotLeave(f)) {
      await say("${f.name} can't leave their space.");
      return null;
    }
    final who = chooser ?? f.owner;
    final reach = reachable(f, upTo, throughOpp: throughOpp || allMods.any((m) => m.movesThroughEnemies(this, f)));
    final dest = await chooseSpace(who, reach.keys, text ?? 'Move ${f.name} up to $upTo space${upTo == 1 ? '' : 's'}',
        intent: who == f.owner ? Intent.moveOwn : Intent.moveEnemy, subject: f, source: source);
    if (dest == null || dest == f.space) return [f.space!];
    var path = reach[dest]!;
    // Something along the way can stop the move early (a trap).
    for (final m in allMods) {
      final stop = m.stopMove(this, f, path);
      if (stop != null && stop > 0 && stop < path.length - 1) path = path.sublist(0, stop + 1);
    }
    f.space = path.last;
    if (f.owner.script.isLarge(f)) {
      // The back of her base points at the space she just moved from.
      final prev = path.length >= 2 ? path[path.length - 2] : null;
      f.tail = prev != null && (fighterAt(prev) == null || fighterAt(prev) == f) && prev != f.space ? prev : f.tail;
      if (f.tail == f.space) f.tail = null;
    }
    turn.leftSpace.add(f);
    await emit(FighterMoved(f, path));
    for (final m in allMods.toList()) {
      await m.afterMove(this, f, path);
    }
    await _entered(f);
    return path;
  }

  /// Places [f] in one of [spaces] (only empty ones count, plus its own space).
  Future<bool> placeFighter(Fighter f, Iterable<int> spaces,
      {Player? chooser, String? text, bool optional = false, Card? source}) async {
    if (!f.onBoard) return false;
    if (cannotLeave(f)) {
      await say("${f.name} can't leave their space.");
      return false;
    }
    final options = spaces.where((s) => isEmpty(s) || fighterAt(s) == f).toSet().toList();
    if (options.isEmpty) return false;
    final who = chooser ?? f.owner;
    final s = await chooseSpace(who, options, text ?? 'Place ${f.name}',
        optional: optional, intent: who == f.owner ? Intent.moveOwn : Intent.moveEnemy, subject: f, source: source);
    if (s == null || s == f.space) return false;
    final from = f.space!;
    f.space = s;
    f.tail = null;
    turn.leftSpace.add(f);
    await emit(FighterMoved(f, [from, s], placed: true));
    if (f.owner.script.isLarge(f)) await placeTail(f, who);
    await _entered(f);
    return true;
  }

  /// A large fighter just placed: whoever placed her picks which adjacent empty space the back of
  /// her base covers (none if there is no room).
  Future<void> placeTail(Fighter f, Player who) async {
    final room = board.neighbours(f.space!).where(isEmpty).toList();
    if (room.isEmpty) return;
    f.tail = await chooseSpace(who, room, 'Which space does the back of ${f.name} cover?', intent: Intent.none, subject: f);
  }

  Future<void> _entered(Fighter f) async {
    if (!f.onBoard) return;
    for (final m in allMods.toList()) {
      if (f.onBoard) await m.entered(this, f, f.space!);
    }
  }

  Future<bool> swap(Fighter a, Fighter b) async {
    if (!a.onBoard || !b.onBoard || cannotLeave(a) || cannotLeave(b)) return false;
    // A large fighter swapping ends up in a single space.
    a.tail = null;
    b.tail = null;
    final s = a.space;
    a.space = b.space;
    b.space = s;
    turn.leftSpace
      ..add(a)
      ..add(b);
    await emit(Swapped(a, b));
    await _entered(a);
    await _entered(b);
    return true;
  }

  // ================================================================================== choices

  Future<List<int>> decide(Prompt p) async {
    final r = await agents[p.player.seat].decide(this, p);
    if (r.isEmpty && !p.optional && p.choices.isNotEmpty && p.min > 0) {
      throw StateError('Agent skipped a mandatory prompt: $p');
    }
    for (final i in r) {
      if (i < 0 || i >= p.choices.length) throw StateError('Bad choice $i for $p');
    }
    return r;
  }

  Future<T?> choose<T>(Player who, Ask ask, String text, List<Choice<T>> choices,
      {bool optional = false,
      String? skipLabel,
      Intent intent = Intent.none,
      Object? subject,
      Card? source,
      bool autoSingle = true}) async {
    if (choices.isEmpty) return null;
    if (choices.length == 1 && !optional && autoSingle) return choices.first.value;
    final r = await decide(Prompt(
      player: who,
      ask: ask,
      text: text,
      choices: choices,
      optional: optional,
      skipLabel: skipLabel,
      intent: intent,
      subject: subject,
      source: source,
    ));
    return r.isEmpty ? null : choices[r.first].value;
  }

  Future<Fighter?> chooseFighter(Player who, Iterable<Fighter> options, String text,
          {Intent intent = Intent.none, bool optional = false, String? skipLabel, Card? source}) =>
      choose(who, Ask.fighter, text, [for (final f in options) Choice(f.name, f)],
          optional: optional, skipLabel: skipLabel, intent: intent, source: source);

  Future<int?> chooseSpace(Player who, Iterable<int> options, String text,
          {Intent intent = Intent.none, bool optional = false, Object? subject, Card? source}) =>
      choose(who, Ask.space, text, [for (final s in options) Choice('Space $s', s)],
          optional: optional, intent: intent, subject: subject, source: source);

  Future<Card?> chooseCard(Player who, Iterable<Card> options, String text,
          {bool optional = false,
          String? skipLabel,
          Intent intent = Intent.none,
          Object? subject,
          Card? source,
          bool autoSingle = true}) =>
      choose(who, Ask.card, text, [for (final c in options) Choice(c.title, c)],
          optional: optional,
          skipLabel: skipLabel,
          intent: intent,
          subject: subject,
          source: source,
          autoSingle: autoSingle && intent != Intent.attackCard);

  Future<List<Card>> chooseCards(Player who, Iterable<Card> options, int minN, int maxN, String text,
      {Intent intent = Intent.none, Card? source}) async {
    final list = options.toList();
    if (list.isEmpty || maxN <= 0) return const [];
    if (list.length <= minN) return list;
    final r = await decide(Prompt(
      player: who,
      ask: Ask.cards,
      text: text,
      choices: [for (final c in list) Choice(c.title, c)],
      min: minN,
      max: maxN,
      optional: minN == 0,
      intent: intent,
      source: source,
    ));
    return [for (final i in r) list[i]];
  }

  Future<bool> yesNo(Player who, String text, {Intent intent = Intent.help, Card? source}) async =>
      await choose<bool>(who, Ask.yesNo, text, const [Choice('Yes', true), Choice('No', false)],
          intent: intent, source: source, autoSingle: false) ??
      false;

  Future<int> chooseOption(Player who, List<String> options, String text,
          {Intent intent = Intent.help, Card? source}) async =>
      await choose<int>(who, Ask.option, text, [for (var i = 0; i < options.length; i++) Choice(options[i], i)],
          intent: intent, source: source) ??
      0;

  Future<int> chooseNumber(Player who, int lo, int hi, String text, {Card? source}) async =>
      await choose<int>(who, Ask.number, text, [for (var i = lo; i <= hi; i++) Choice('$i', i)], source: source) ?? lo;
}
