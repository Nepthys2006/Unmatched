// Test helpers: data loading, a scripted agent and a scenario builder on a small test board.
import 'dart:convert';
import 'dart:io';

import 'package:unmatched_game/engine/combat.dart';
import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';

GameData? _data;
GameData loadData() => _data ??= GameData.fromJson(
      jsonDecode(File('assets/data/heroes.json').readAsStringSync()) as List,
      jsonDecode(File('assets/data/maps.json').readAsStringSync()) as Map<String, dynamic>,
    );

/// A straight line of 12 spaces: 0-1-2-...-11, plus a side space 12 hanging off 5.
/// Zones: a = 0..3, b = 3..7 (+12), c = 8..11. Start 1 at space 0, start 2 at space 11.
MapDef lineMap() => MapDef(
      id: 'line',
      name: 'Test Line',
      modes: const ['1v1'],
      theme: 'garden',
      blurb: '',
      zones: {'a': ZoneDef('a', 'A', '#f00'), 'b': ZoneDef('b', 'B', '#0f0'), 'c': ZoneDef('c', 'C', '#00f')},
      spaces: [
        for (var i = 0; i < 12; i++)
          SpaceDef(i, i.toDouble(), 0, {if (i <= 3) 'a', if (i >= 3 && i <= 7) 'b', if (i >= 8) 'c'},
              i == 0 ? 1 : (i == 11 ? 2 : null)),
        SpaceDef(12, 5, 1, {'b'}, null),
      ],
      links: [for (var i = 0; i < 11; i++) (i, i + 1), (5, 12)],
    );

typedef Answer = Object?;

/// Answers prompts from a queue: an int index, a String (matches a choice label), a List of
/// either, [skip], or a function of the prompt. With an empty queue: first choice, or skip
/// when optional.
class ScriptedAgent implements Agent {
  final List<Answer> queue = [];
  final List<Prompt> asked = [];
  Agent? fallback;

  void then(Answer a) => queue.add(a);

  @override
  Future<List<int>> decide(Game game, Prompt p) async {
    asked.add(p);
    if (queue.isEmpty) {
      if (fallback != null) return fallback!.decide(game, p);
      if (p.ask == Ask.cards) return List.generate(p.min, (i) => i);
      return p.optional ? const [] : const [0];
    }
    final a = queue.removeAt(0);
    return _resolve(a, p);
  }

  List<int> _resolve(Answer a, Prompt p) {
    if (a == skip) return const [];
    if (a is int) return [a];
    if (a is String) {
      var i = p.choices.indexWhere((c) => c.label == a);
      if (i < 0) i = p.choices.indexWhere((c) => c.label.toLowerCase().contains(a.toLowerCase()));
      if (i < 0) throw StateError('No choice "$a" in $p');
      return [i];
    }
    if (a is List) return [for (final x in a) ..._resolve(x, p)];
    if (a is List<int> Function(Prompt)) return a(p);
    if (a is Fighter) {
      final i = p.choices.indexWhere((c) => c.value == a);
      if (i < 0) throw StateError('Fighter $a not offered in $p');
      return [i];
    }
    if (a is SpaceAnswer) {
      final i = p.choices.indexWhere((c) => c.value == a.space);
      if (i < 0) throw StateError('Space ${a.space} not offered in $p');
      return [i];
    }
    if (a is CardAnswer) {
      final i = p.choices.indexWhere((c) => c.value is Card && (c.value as Card).def.upperTitle == normTitle(a.title));
      if (i < 0) throw StateError('Card ${a.title} not offered in $p');
      return [i];
    }
    throw ArgumentError('Bad answer $a');
  }
}

const skip = #skip;

class SpaceAnswer {
  const SpaceAnswer(this.space);
  final int space;
}

class CardAnswer {
  const CardAnswer(this.title);
  final String title;
}

SpaceAnswer sp(int s) => SpaceAnswer(s);
CardAnswer card(String t) => CardAnswer(t);

/// A game set up by hand: fighters placed where a test wants them, chosen hands and decks.
class Scenario {
  Scenario(String hero1, String hero2, {MapDef? map}) {
    game = Game(
      data: loadData(),
      map: map ?? lineMap(),
      heroIds: [hero1, hero2],
      agents: [a1, a2],
      seed: 1,
      presenter: (e) async => events.add(e),
      firstSeat: 0,
    );
    p1 = game.players[0];
    p2 = game.players[1];
    p1.startSpace = 0;
    p2.startSpace = 11;
    game.first = p1;
    game.order.addAll([p1, p2]);
    for (final p in game.players) {
      for (final f in p.fighters) {
        f.space = null;
        f.reserve = true;
      }
      // Filler so effects that draw don't trigger exhaustion unless a test empties the deck.
      deck(p, List.filled(10, p.hero.cards.first.title));
    }
    startTurn(p1);
  }

  late final Game game;
  late final Player p1;
  late final Player p2;
  final a1 = ScriptedAgent();
  final a2 = ScriptedAgent();
  final List<GameEvent> events = [];
  int _uid = 10000;

  ScriptedAgent agentOf(Player p) => p == p1 ? a1 : a2;
  Fighter hero(Player p) => p.heroFighter;
  Fighter sidekick(Player p, [int n = 1]) => p.fighters.where((f) => f.isSidekick).elementAt(n - 1);

  void place(Fighter f, int space) {
    f
      ..space = space
      ..reserve = false
      ..defeated = false
      ..offBoard = false;
    game.turn.startSpace[f] = space;
  }

  Card make(Player p, String title) {
    final def = p.hero.card(title);
    return Card(_uid++, def, 0, p);
  }

  Card give(Player p, String title) {
    final c = make(p, title);
    p.hand.add(c);
    return c;
  }

  void deck(Player p, List<String> titles) {
    p.deck
      ..clear()
      ..addAll([for (final t in titles) make(p, t)]);
  }

  void discardPile(Player p, List<String> titles) {
    p.discard.addAll([for (final t in titles) make(p, t)]);
  }

  void startTurn(Player p) {
    game.turnNumber++;
    game.turn = TurnInfo(p, game.turnNumber);
    for (final f in game.fighters) {
      game.turn.startSpace[f] = f.space;
    }
    game.actions = 2;
  }

  /// Runs an attack with the given cards (defense null = no defense). Extra answers for effects
  /// go in [then1] / [then2] after the card choices.
  Future<Combat> fight(Fighter a, Fighter t, String attack, String? defense,
      {List<Answer> then1 = const [], List<Answer> then2 = const []}) async {
    final atk = give(a.owner, attack);
    final def = defense == null ? null : give(t.owner, defense);
    final aa = agentOf(a.owner), da = agentOf(t.owner);
    aa.queue.insert(0, card(atk.def.title));
    if (def != null) {
      da.queue.insert(0, card(def.def.title));
    } else if (t.owner.hand.any((c) => game.canDefendWith(c, t))) {
      da.queue.insert(0, skip); // only asked when there is something to defend with
    }
    aa.queue.addAll(then1);
    da.queue.addAll(then2);
    return game.resolveCombat(a, t);
  }

  List<String> get log => [for (final e in events) e.log].where((s) => s.isNotEmpty).toList();
}
