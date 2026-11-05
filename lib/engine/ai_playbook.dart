/// What the AI knows beyond its general judgement (ai.dart), kept in one place that is easy
/// to read and extend:
///
/// * [groundRules]: choices the AI never makes, at any level. Even Easy's careless moves
///   (and the UMCCC Model's search) stay inside them.
/// * [playbooks]: how to play a particular hero.
/// * [counterplays]: how to play against a particular hero.
///
/// Heroes are keyed by their id in assets/data/heroes.json. Every hook is optional. Scores use
/// the AI's usual scale, where 1 point is about 1 damage to a healthy hero.
///
/// After a change, check that the AI got stronger and not weaker:
///
///     dart run tool/ai_arena.dart --games=1000                      (all heroes)
///     dart run tool/ai_arena.dart --heroes=medusa,dracula,bigfoot   (just the heroes you changed)
library;

import 'combat.dart';
import 'defs.dart';
import 'game.dart';
import 'prompt.dart';
import 'state.dart';

// =================================================================================== the types

/// A hard limit: the AI never picks a choice a rule forbids, unless every choice is forbidden
/// and the prompt can't be declined.
class GroundRule {
  const GroundRule(this.name, this.forbids);

  /// What the rule says, in plain words.
  final String name;

  /// Whether answering [p] with [choice] breaks the rule. [choice] is the value of one of the
  /// prompt's choices (a Card, a Fighter, a space, an ActionChoice...), or null for declining.
  final bool Function(Game g, Prompt p, Object? choice) forbids;
}

/// How to play one hero.
class Playbook {
  const Playbook({
    this.rules = const [],
    this.action,
    this.endTurnAt,
    this.reach = 0,
    this.boostCost = 1.0,
  });

  /// Ground rules that only apply when playing this hero.
  final List<GroundRule> rules;

  /// Extra score for taking action [a] now.
  final double Function(Game g, Player me, ActionChoice a)? action;

  /// Extra score for my fighter [f] ending the turn in [space].
  final double Function(Game g, Fighter f, int space)? endTurnAt;

  /// The hero can attack from up to this many spaces away, ignoring zones (0 = the normal reach).
  final int reach;

  /// How much a card spent on a BOOST costs, relative to other heroes (below 1: boosting
  /// gives something back).
  final double boostCost;
}

/// How to play against one hero.
class Counterplay {
  const Counterplay({
    this.rules = const [],
    this.endTurnAt,
    this.moveTo,
    this.reach = 0,
    this.startMove = 0,
  });

  /// Ground rules that apply when this hero is an opponent.
  final List<GroundRule> rules;

  /// Extra score for my fighter [f] ending my turn in [space], with [foe] (one of this hero's
  /// fighters) on the board.
  final double Function(Game g, Fighter f, int space, Fighter foe)? endTurnAt;

  /// Extra score for my fighter [f] moving to [space] at any time.
  final double Function(Game g, Fighter f, int space, Fighter foe)? moveTo;

  /// The hero can attack from up to this many spaces away, ignoring zones (0 = the normal reach).
  final int reach;

  /// Spaces their fighters can move at the start of their turn, before taking any action.
  final int startMove;
}

// =============================================================================== ground rules

/// The maneuver BOOST ground rule, for every level but Pro.
final maneuverBoostRule = GroundRule(
  "Don't BOOST a maneuver without a reason. The only reasons: get my hurt hero out of every "
  "enemy's reach (their move without a BOOST, then an attack) as the turn ends; or the hand limit would "
  'discard a card at the end of the turn anyway (maneuvering again would go over it, and no '
  'attack or scheme this turn would keep it under). Not to reach an attack: in the arena that '
  'lost games (49% against the old AI, 58% without it).',
  (g, p, c) => c is Card && isManeuverBoost(p) && !maneuverBoost(g, p.player).allows(g, c),
);

/// Pro's maneuver BOOST rule: the same reasons, plus reaching an attack on the first action
/// when maneuvering twice would go over the hand limit ([reachAttack]).
final proManeuverBoostRule = GroundRule(
  "Don't BOOST a maneuver without a reason: get my hurt hero out of reach as the turn ends; the "
  'hand limit would discard a card anyway; or, on the first action, reach an attack for the second '
  'when maneuvering twice would go over the hand limit (not a hurt hero with no defense, and only '
  'with a card worth attacking with).',
  (g, p, c) => c is Card && isManeuverBoost(p) && !maneuverBoost(g, p.player, reach: true).allows(g, c),
);

final schemeBoostRule = GroundRule(
  "Don't BOOST with a scheme card: play it instead. Except when no fighter can play it, when "
  'the hand limit would discard a card at the end of this turn anyway, or when the BOOST '
  'decides a fight (it can defeat their hero, or saves mine).',
  (g, p, c) =>
      p.intent == Intent.boost &&
      c is Card &&
      c.def.isScheme &&
      !isDeadCard(c, p.player) &&
      spareCards(g, p.player) == 0 &&
      !_decisiveBoost(g, p, c),
);

final groundRules = <GroundRule>[
  maneuverBoostRule,
  schemeBoostRule,
  GroundRule(
    'Always defend a hero that the attack could defeat.',
    (g, p, c) => c == null && p.intent == Intent.defenseCard && _mayBeLethal(p.subject as Combat),
  ),
  GroundRule(
    'Take an attack that is sure to defeat the last opposing hero.',
    (g, p, c) => p.ask == Ask.action && c is ActionChoice && !_isSureWin(g, p.player, c) && _sureWinExists(g, p),
  ),
  GroundRule(
    "Don't maneuver with an empty deck while another action is possible: drawing from it deals "
    '2 damage to each of my fighters.',
    (g, p, c) =>
        p.ask == Ask.action &&
        c is ActionChoice &&
        c.kind == ActionKind.maneuver &&
        p.player.deck.isEmpty &&
        p.choices.length > 1,
  ),
];

// ================================================================================== playbooks

final playbooks = <String, Playbook>{
  // Spear Throw (his only scheme) deals 2 damage to an opposing fighter in Achilles' zone: with
  // nobody there it does nothing.
  'achilles': Playbook(rules: [
    GroundRule(
      "Don't play Spear Throw with no opposing fighter in Achilles' zone.",
      (g, p, c) => c is ActionChoice && c.kind == ActionKind.scheme && c.card!.title == 'Spear Throw' && spearTargets(g, p.player).isEmpty,
    ),
  ]),

  // At the start of her turn Medusa may deal 1 damage to an opposing fighter in her zone.
  'medusa': Playbook(
    endTurnAt: (g, f, s) => f.isHero && _foes(g, f.owner).any((e) => g.board.sharesZone(s, e.space!)) ? 2.0 : 0.0,
  ),

  // Bigfoot draws at the end of the turn if no opposing fighter is in his zone.
  'bigfoot': Playbook(
    endTurnAt: (g, f, s) => f.isHero && !_foes(g, f.owner).any((e) => g.board.sharesZone(s, e.space!)) ? 2.0 : 0.0,
  ),

  // Golden Bat's attacks are +2 until he maneuvers this turn: attack first, then move.
  'golden-bat': Playbook(
    action: (g, me, a) => a.kind == ActionKind.maneuver &&
            g.turn.maneuvers == 0 &&
            g.legalActions(me).any((x) => x.kind == ActionKind.attack && x.fighter!.isHero)
        ? -4.0
        : 0.0,
  ),

  // Bloody Mary gains an action at the start of her turn with exactly 3 cards in hand.
  'bloody-mary': Playbook(
    action: (g, me, a) {
      if (g.actions > 0) return 0.0;
      final after = me.hand.length + (a.kind == ActionKind.maneuver ? 1 : -1);
      return after == 3 ? 3.0 : 0.0;
    },
  ),

  // Each VOYAGE card in Sinbad's discard pile adds 1 to every maneuver: sail early.
  'sinbad': Playbook(
    action: (g, me, a) => a.kind == ActionKind.scheme && a.card!.title.startsWith('Voyage') ? 2.5 : 0.0,
  ),

  // Black Panther draws a card whenever he BOOSTs.
  'black-panther': Playbook(boostCost: 0.3),

  'bullseye': Playbook(reach: 5),
  'ms-marvel': Playbook(reach: 2),
  'muhammad-ali': Playbook(reach: 2),
  't-rex': Playbook(reach: 2),
};

// =============================================================================== counterplays

final counterplays = <String, Counterplay>{
  // Medusa deals 1 damage to a fighter in her zone at the start of her turn.
  'medusa': Counterplay(
    endTurnAt: (g, f, s, foe) => foe.isHero && g.board.sharesZone(s, foe.space!) ? -1.5 * _worry(f) : 0.0,
  ),

  // Dracula deals 1 damage to an adjacent fighter at the start of his turn, and draws.
  'dracula': Counterplay(
    endTurnAt: (g, f, s, foe) => foe.isHero && g.board.adjacent(s, foe.space!) ? -2.0 * _worry(f) : 0.0,
  ),

  // Tesla's charged coils deal 1 damage to each adjacent fighter at the start of his turn.
  'nikola-tesla': Counterplay(
    endTurnAt: (g, f, s, foe) => g.board.adjacent(s, foe.space!) ? -1.5 * _worry(f) : 0.0,
  ),

  // She-Hulk throws a discarded card at a fighter in her zone at the start of her turn.
  'she-hulk': Counterplay(
    endTurnAt: (g, f, s, foe) => g.board.sharesZone(s, foe.space!) ? -1.5 * _worry(f) : 0.0,
  ),

  // A hero leaving Tomoe Gozen's zone takes 1 damage.
  'tomoe-gozen': Counterplay(
    moveTo: (g, f, s, foe) =>
        f.isHero && g.board.sharesZone(f.space!, foe.space!) && !g.board.sharesZone(s, foe.space!) ? -1.5 : 0.0,
  ),

  // Long reach, or a free move before acting: they strike from farther than it looks.
  'bullseye': Counterplay(reach: 5),
  'ms-marvel': Counterplay(reach: 2, startMove: 1),
  'muhammad-ali': Counterplay(reach: 2),
  't-rex': Counterplay(reach: 2),
  'moon-knight': Counterplay(startMove: 2),
  'leonardo': Counterplay(startMove: 1),
};

// ==================================================================================== helpers

/// The hand limit [p] discards down to at the end of their turn.
int handLimit(Game g, Player p) {
  var limit = 7;
  for (final m in g.allMods) {
    limit = m.handLimit(g, p, limit);
  }
  return limit;
}

/// Cards the hand limit will discard at the end of this turn whatever [p] does with the actions
/// left: each one could BOOST for free. The other actions shed a card each if [p] can attack
/// (after moving normally) or play a scheme, and draw one each (maneuvering) if not.
int spareCards(Game g, Player p) {
  var hand = p.hand.length;
  final left = g.actions;
  if (left > 0) {
    final canPlay = g.legalActions(p).any((a) => a.kind == ActionKind.scheme) || _canAttackAfterMoving(g, p);
    hand += canPlay ? -left : (p.deck.length < left ? p.deck.length : left);
  }
  final over = hand - handLimit(g, p);
  return over > 0 ? over : 0;
}

/// Whether [p] can attack this turn after moving normally (no BOOST).
bool _canAttackAfterMoving(Game g, Player p) {
  final foes = _foes(g, p).toList();
  if (foes.isEmpty) return false;
  return p.onBoard.any((f) =>
      p.hand.any((c) => g.canAttackWith(c, f)) && _strikeSpots(g, f, foes).any(g.reachable(f, g.moveAllowance(f)).containsKey));
}

// ============================================================================ maneuver BOOSTs

/// A hero with this much health or less BOOSTs a maneuver to get out of reach. (In the arena,
/// escaping at any health boosted twice as often and won 57% instead of 58% of games.)
const escapeHealth = 6;

/// Whether [p] asks for the BOOST of a maneuver.
bool isManeuverBoost(Prompt p) => p.intent == Intent.boost && p.ask == Ask.card && p.text == Game.maneuverBoostText;

/// What a maneuver BOOST could buy [me] right now (the ground rule above).
class ManeuverBoost {
  ManeuverBoost._(this.spare, this.escape, this.reach);

  /// Cards the hand limit discards at the end of the turn anyway ([spareCards]).
  final int spare;

  /// Getting the hero out of reach: the hero, the least BOOST that does it, and which spaces are
  /// safe (null if the normal move already gets there, no BOOST would, or it isn't the last action).
  final (Fighter, int, bool Function(int))? escape;

  /// Reaching an attack for the turn's other action, when maneuvering again would go over the
  /// hand limit: the fighter, the least BOOST that gets it there, and the spaces it can attack
  /// from ([reachAttack]).
  final (Fighter, int, Set<int>)? reach;

  /// Whether boosting with [c] buys something.
  bool allows(Game g, Card c) => spare > 0 || (escape != null && g.boostValueOf(c) >= escape!.$2) || reaches(g, c);

  /// Whether boosting with [c] gets [reach]'s fighter to an attack, with a card left worth it.
  bool reaches(Game g, Card c) {
    final r = reach;
    if (r == null || g.boostValueOf(c) < r.$2) return false;
    return r.$1.owner.hand.any((a) => a != c && g.canAttackWith(a, r.$1) && worthAttacking(a));
  }

  /// Where to move each fighter after boosting with [c], to get what the BOOST was for (none
  /// for a spare card).
  Map<Fighter, Set<int>> goals(Game g, Card c) {
    final b = g.boostValueOf(c);
    final r = reach;
    if (r != null && reaches(g, c)) {
      return {r.$1: g.reachable(r.$1, g.moveAllowance(r.$1) + b).keys.where(r.$3.contains).toSet()};
    }
    final e = escape;
    if (e == null || b < e.$2) return const {};
    return {e.$1: g.reachable(e.$1, g.moveAllowance(e.$1) + b).keys.where(e.$3).toSet()};
  }
}

/// A card worth attacking with: an attack card, or a versatile one of value 3 or more.
bool worthAttacking(Card c) => c.def.type == CardType.attack || (c.def.value ?? 0) >= 3;

/// The third reason to BOOST a maneuver: on the first action, when a second maneuver would go
/// over the hand limit (a card lost anyway), BOOST this one to get next to them and attack with
/// the other action instead. Not when nothing in hand is worth attacking with, nor for a hurt
/// hero with nothing to defend with (it would rather keep away).
(Fighter, int, Set<int>)? reachAttack(Game g, Player me) {
  if (g.actions != 1 || me.hand.length + 1 <= handLimit(g, me)) return null;
  final hero = me.heroFighter;
  if (hero.onBoard && hero.hp <= escapeHealth && !me.hand.any((c) => g.canDefendWith(c, hero))) return null;
  final foes = _foes(g, me).toList();
  if (foes.isEmpty) return null;
  final most = g.boostOptions(me).map(g.boostValueOf).fold(0, (a, b) => a > b ? a : b);
  for (final f in me.onBoard) {
    if (!me.hand.any((c) => g.canAttackWith(c, f) && worthAttacking(c))) continue;
    final spots = _strikeSpots(g, f, foes);
    // Within the normal move: no BOOST needed.
    if (g.reachable(f, g.moveAllowance(f)).keys.any(spots.contains)) return null;
    for (var b = 1; b <= most; b++) {
      if (g.reachable(f, g.moveAllowance(f) + b).keys.any(spots.contains)) return (f, b, spots);
    }
  }
  return null;
}

final _boostCache = Expando<(Object, ManeuverBoost)>();

/// What a maneuver BOOST could buy [me] now (worked out once per game state). [reach]: also
/// reaching an attack (Pro only).
ManeuverBoost maneuverBoost(Game g, Player me, {bool reach = false}) {
  final key = (g.log.length, g.actions, reach, Object.hashAll(me.hand), Object.hashAll(g.fighters.map((f) => (f.space, f.hp))));
  final cached = _boostCache[me];
  if (cached != null && cached.$1 == key) return cached.$2;
  final foes = _foes(g, me).toList();
  (Fighter, int, bool Function(int))? escape;
  final hero = me.heroFighter;
  // Only a hurt hero runs: escaping at any health boosted twice as often and won fewer games.
  if (g.actions == 0 && hero.onBoard && hero.hp <= escapeHealth && foes.isNotEmpty) {
    // Their reach next turn without a BOOST: move (and any free move first), then attack. The
    // hero is about to move, so it doesn't block their way.
    final Set<int> danger;
    hero.offBoard = true;
    try {
      danger = {
        for (final e in foes)
          if (e.owner.hand.isNotEmpty || e.owner.deck.isNotEmpty) ..._enemyReach(g, e),
      };
    } finally {
      hero.offBoard = false;
    }
    bool safe(int s) => !danger.contains(s);
    // The least BOOST that gets the hero to a safe space, if the normal move doesn't.
    if (!g.reachable(hero, g.moveAllowance(hero)).keys.any(safe)) {
      final most = g.boostOptions(me).map(g.boostValueOf).fold(0, (a, b) => a > b ? a : b);
      for (var b = 1; b <= most; b++) {
        if (g.reachable(hero, g.moveAllowance(hero) + b).keys.any(safe)) {
          escape = (hero, b, safe);
          break;
        }
      }
    }
  }

  final mb = ManeuverBoost._(spareCards(g, me), escape, reach ? reachAttack(g, me) : null);
  _boostCache[me] = (key, mb);
  return mb;
}

/// Spaces [e] can attack next turn without boosting: from wherever its move (and any move at the
/// start of its turn, from its counterplay) takes it.
Set<int> _enemyReach(Game g, Fighter e) {
  final cp = counterplays[e.owner.hero.id];
  final reach = e.isHero ? cp?.reach ?? 0 : 0;
  return {
    for (final s in g.reachable(e, g.moveAllowance(e) + (cp?.startMove ?? 0)).keys) ..._attackable(g, s, e.isRanged, reach),
  };
}

/// Spaces [f] could attack one of [foes] from (with its playbook's long reach).
Set<int> _strikeSpots(Game g, Fighter f, Iterable<Fighter> foes) {
  final reach = f.isHero ? playbooks[f.owner.hero.id]?.reach ?? 0 : 0;
  return {for (final foe in foes) ..._attackable(g, foe.space!, f.isRanged, reach)};
}

/// Spaces a fighter in [s] can attack (or, the same thing, attack [s] from): adjacent ones, its
/// zone if ranged, and any within [reach] spaces.
Set<int> _attackable(Game g, int s, bool ranged, int reach) => {
      s,
      ...g.board.neighbours(s),
      if (ranged) ...g.board.zoneOf(s),
      if (reach > 0)
        for (final x in g.board.spaceIds)
          if (g.board.distance(s, x) <= reach) x,
    };

/// Opposing fighters Achilles' Spear Throw could hit: in Achilles' zone.
Iterable<Fighter> spearTargets(Game g, Player achilles) {
  final hero = achilles.heroFighter;
  if (!hero.onBoard) return const [];
  return _foes(g, achilles).where((e) => g.board.sharesZone(hero.space!, e.space!));
}

/// No living fighter of [p] can play [c]: it is only good for a BOOST.
bool isDeadCard(Card c, Player p) => !p.alive.any((f) => p.script.fighterMayUse(c, f));

Iterable<Fighter> _foes(Game g, Player me) => g.enemyFighters(me).where((e) => e.onBoard);

/// How much losing health matters to [f]: a hurt hero most.
double _worry(Fighter f) => !f.isHero ? 0.4 : (f.hp <= 6 ? 2.0 : 1.0);

/// A BOOST in combat that turns the fight: enough to defeat the defending hero, or the only way
/// to keep my defending hero alive.
bool _decisiveBoost(Game g, Prompt p, Card c) {
  if (p.subject is! Side) return false;
  final s = p.subject as Side;
  final b = g.boostValueOf(c);
  // A card played face down counts only once it's revealed (or I saw it).
  final o = s.other;
  final seen = o.card == null || o.faceUp || p.player.script.known.contains(o.card);
  final mine = g.valueOf(s).total, theirs = seen ? g.valueOf(o).total : 0;
  if (s.isAttacker) {
    final t = s.combat.defender.fighter;
    return t.isHero && mine < t.hp + theirs && mine + b >= t.hp + theirs;
  }
  final f = s.combat.defender.fighter;
  return f.isHero && theirs - mine >= f.hp && theirs - mine - b < f.hp;
}

/// The attack could defeat the defending hero: its card is known and strong enough, or it is
/// hidden and the attacker's deck holds a card that would be.
bool _mayBeLethal(Combat c) {
  final f = c.defender.fighter;
  if (!f.isHero) return false;
  final a = c.attacker;
  final extra = a.ops.fold(0, (s, o) => s + (o.isSet ? 0 : o.amount));
  final known = a.card != null && (a.faceUp || c.defender.player.script.known.contains(a.card));
  if (known) return a.card!.def.value != null && a.card!.def.value! + extra >= f.hp;
  if (c.toldAttackValue != null) return c.toldAttackValue! + extra + 2 >= f.hp; // Spidey-Sense; + 2 for abilities
  final best = a.player.hero.cards.where((d) => d.canAttack).map((d) => d.value ?? 0).fold(0, (x, y) => x > y ? x : y);
  return best + extra + 2 >= f.hp; // + 2 for abilities that add to attacks
}

/// Attacking with [a] defeats the last opposing hero for sure: they hold no cards to defend
/// with and my best attack card is enough.
bool _isSureWin(Game g, Player me, ActionChoice a) {
  if (a.kind != ActionKind.attack) return false;
  final f = a.fighter!, t = a.target!;
  if (!t.isHero || t.owner.hand.isNotEmpty) return false;
  if (t.owner.heroes.where((h) => h.alive).length > 1) return false;
  final side = Side(Combat(f, t), true, f);
  for (final c in me.hand) {
    if (!g.canAttackWith(c, f) || !g.canTargetWith(c, f, t)) continue;
    side.card = c;
    if (g.valueOf(side).total >= t.hp) return true;
  }
  return false;
}

bool _sureWinExists(Game g, Prompt p) =>
    p.choices.any((ch) => ch.value is ActionChoice && _isSureWin(g, p.player, ch.value as ActionChoice));
