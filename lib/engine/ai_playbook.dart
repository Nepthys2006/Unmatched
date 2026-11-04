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

final groundRules = <GroundRule>[
  GroundRule(
    "Don't BOOST with a scheme card: play it instead. Except when no fighter can play it, when "
    'the hand limit would discard a card at the end of this turn anyway, or when the BOOST '
    'decides a fight (it can defeat their hero, or saves mine).',
    (g, p, c) =>
        p.intent == Intent.boost &&
        c is Card &&
        c.def.isScheme &&
        !isDeadCard(c, p.player) &&
        !overHandLimit(g, p.player) &&
        !_decisiveBoost(g, p, c),
  ),
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

/// More cards than the hand limit on the last action: the extra ones get discarded anyway.
bool overHandLimit(Game g, Player p) => g.actions == 0 && p.hand.length > handLimit(g, p);

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
