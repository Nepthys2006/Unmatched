/// Mutable game state: cards, fighters, players, the board and per-turn bookkeeping.
library;

import 'dart:collection';

import 'defs.dart';
import 'hero_script.dart';

/// One physical card. [copy] tells identical copies apart (Into the Woods prints a different
/// symbol on each copy).
class Card {
  Card(this.uid, this.def, this.copy, this.owner, {this.virtual = false});
  final int uid;
  final CardDef def;
  final int copy;
  final Player owner;

  /// Not a real card: a bonus attack (Relentless Assault, Volley...). Never enters a deck.
  final bool virtual;

  /// Who played it most recently (Loki's tricks can be played by an opponent).
  Player? playedBy;

  String get title => def.title;
  CardType get type => def.type;
  @override
  String toString() => def.title;
}

const _singular = {
  'harpies': 'Harpy',
  'archers': 'Archer',
  'outlaws': 'Outlaw',
  'the sisters': 'Sister',
  'wolves': 'Wolf',
  'clones': 'Clone',
  'red riders': 'Red Rider',
};

class Fighter {
  Fighter(this.uid, this.def, this.owner, this.ordinal) : hp = def.hp, maxHp = def.hp;

  final int uid;
  final FighterDef def;
  final Player owner;

  /// 1-based number among identical sidekicks (Harpy 1..3).
  final int ordinal;
  int hp;
  int maxHp;
  int? space;
  bool defeated = false;

  /// Temporarily off the board but not defeated (Vanish, Vanish Into Murder).
  bool offBoard = false;

  /// Starts the game off the board and joins later (Sun Wukong's Clones, Leshen's Wolves).
  bool reserve = false;

  bool get isHero => def.isHero;
  bool get isSidekick => !def.isHero;
  bool get onBoard => !defeated && !offBoard && !reserve && space != null;
  bool get alive => !defeated && !reserve;
  String get id => def.id;
  AttackType get attack => owner.script.attackTypeOf(this);
  bool get isRanged => attack == AttackType.ranged;

  /// An opposing fighter from [p]'s point of view (different team).
  bool isEnemyOf(Player p) => owner.team != p.team;

  /// A friendly fighter from [p]'s point of view (same team, including p's own).
  bool isFriendOf(Player p) => owner.team == p.team;

  /// Name for one fighter: "Harpy" rather than "Harpies".
  String get name {
    if (isHero) return owner.script.heroName;
    final base = _singular[def.name.toLowerCase()] ?? def.name;
    return def.count > 1 ? '$base $ordinal' : base;
  }

  String get kind => isHero ? owner.script.heroName : (_singular[def.name.toLowerCase()] ?? def.name);

  @override
  String toString() => name;
}

class Player {
  Player(this.seat, this.hero, this.script);

  final int seat;
  final HeroDef hero;
  final HeroScript script;
  final List<Card> deck = [];
  final List<Card> hand = [];
  final List<Card> discard = [];

  /// Removed from the game (Donatello's inventions, Smoke Bomb).
  final List<Card> removed = [];

  /// Ongoing schemes face up in front of the player.
  final List<Card> inPlay = [];
  final List<Fighter> fighters = [];

  /// Players on the same team are allies (2v2, 3v3); in 1v1 and free-for-all everyone is alone.
  int team = 0;

  /// Out of the game: free-for-all hero defeated, or team player with no fighters left.
  bool eliminated = false;
  int turnsTaken = 0;

  /// The start space this player's hero was placed in.
  int startSpace = -1;

  bool isEnemyOf(Player o) => team != o.team;
  bool isAllyOf(Player o) => team == o.team;
  String label = '';
  bool isAI = false;

  Fighter get heroFighter => fighters.firstWhere((f) => f.isHero);
  Iterable<Fighter> get onBoard => fighters.where((f) => f.onBoard);
  Iterable<Fighter> get alive => fighters.where((f) => f.alive);
  bool get defeated => heroFighter.defeated;
  String get name => script.heroName;

  @override
  String toString() => name;
}

/// A token on the board: Invisible Man's fog sits on a space, Shredder's Foot soldiers on a path.
class Token {
  Token(this.kind, this.owner, {this.space, this.path});
  final String kind;
  final Player owner;
  int? space;
  (int, int)? path;
}

class Board {
  Board(this.def) {
    for (final s in def.spaces) {
      _adj[s.id] = <int>{};
    }
    for (final (a, b) in def.links) {
      _adj[a]!.add(b);
      _adj[b]!.add(a);
    }
  }

  final MapDef def;
  final Map<int, Set<int>> _adj = {};
  final List<Token> tokens = [];

  Iterable<int> get spaceIds => _adj.keys;
  SpaceDef space(int id) => def.spaces[id];
  Set<int> neighbours(int id) => _adj[id]!;
  bool adjacent(int a, int b) => _adj[a]!.contains(b);
  Set<String> zonesOf(int id) => def.spaces[id].zones;
  bool sharesZone(int a, int b) => zonesOf(a).any(zonesOf(b).contains);
  int zoneCount(int id) => zonesOf(id).length;
  Iterable<int> inZone(String z) => def.spaces.where((s) => s.zones.contains(z)).map((s) => s.id);

  /// Every space sharing at least one zone with [id] ("in X's zone").
  Set<int> zoneOf(int id) => {for (final z in zonesOf(id)) ...inZone(z)};
  int? startSpace(int n) {
    for (final s in def.spaces) {
      if (s.start == n) return s.id;
    }
    return null;
  }

  Iterable<int> get startSpaces => def.spaces.where((s) => s.start != null).map((s) => s.id);

  /// Shortest path length ignoring fighters (used for "within N spaces").
  int distance(int a, int b) {
    if (a == b) return 0;
    final seen = {a};
    var frontier = [a];
    for (var d = 1; frontier.isNotEmpty; d++) {
      final next = <int>[];
      for (final s in frontier) {
        for (final n in _adj[s]!) {
          if (n == b) return d;
          if (seen.add(n)) next.add(n);
        }
      }
      frontier = next;
    }
    return 1 << 20;
  }

  Iterable<Token> tokensAt(int space, String kind) => tokens.where((t) => t.kind == kind && t.space == space);
  bool hasToken(int space, String kind) => tokens.any((t) => t.kind == kind && t.space == space);
}

/// Bookkeeping that resets at the start of every turn.
class TurnInfo {
  TurnInfo(this.player, this.number);
  final Player player;
  final int number;
  final Map<Fighter, int?> startSpace = HashMap.identity();
  final Set<Fighter> damaged = HashSet.identity();
  final Set<Fighter> leftSpace = HashSet.identity();
  final Map<Fighter, int> attacksBy = HashMap.identity();
  final List<Card> played = [];
  int maneuvers = 0;
  int attacks = 0;
  int schemes = 0;
  int actionsTaken = 0;

  /// Effects that last "this turn" / "for the rest of the turn", keyed by name.
  final Map<String, Object?> flags = {};
}
