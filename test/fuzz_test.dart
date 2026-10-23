// Plays many complete games (AI vs AI and random vs random) for every implemented hero pairing
// and checks game invariants after every single event. Also reports which cards' effects fired.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/common.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

const _maxTurns = 400;

void main() {
  final data = loadData();
  final heroes = data.heroes.keys.where(isImplemented).toList()..sort();
  final maps = data.mapsFor('1v1');
  final fired = <String>{};
  var checks = 0;

  Future<Game> play(String a, String b, int seed, {required bool random, List<String>? more, List<int>? teams, MapDef? map}) async {
    late Game g;
    final totals = <int, int>{};
    void check(GameEvent e) {
      if (e is TurnStarted && e.number > _maxTurns) throw StateError('Game did not end in $_maxTurns turns');
      if (e is EffectResolving) fired.add(e.side.card!.def.key);
      if (e is SchemePlayed) fired.add(e.card.def.key);
      final seen = <int>{};
      for (final f in g.fighters) {
        expect(f.hp, inInclusiveRange(0, f.maxHp), reason: '$f hp');
        if (f.onBoard && !seen.add(f.space!)) {
          final tail = g.log.reversed.take(12).toList().reversed.map((e) => '${e.runtimeType}: ${e.log}').join('\n  ');
          fail('${g.players.map((p) => p.hero.id).join(' vs ')} (seed $seed): two fighters on space ${f.space} after $e\n  $tail');
        }
        if (f.tail != null) expect(seen.add(f.tail!), isTrue, reason: "a large fighter's back overlaps another fighter");
        if (f.defeated) expect(f.space, isNull);
      }
      int count(Player p) =>
          p.deck.length + g.players.fold<int>(0, (n, h) => n + h.hand.where((c) => c.owner == p).length) +
          p.discard.length + p.inPlay.length + p.removed.length + g.playedCards.where((c) => c.owner == p).length;
      // Decks exist from the first draw on; nothing can have been lost before then.
      if (totals.isEmpty && e is CardsDrawn) {
        for (final p in g.players) {
          totals[p.seat] = count(p);
        }
      }
      if (totals.isEmpty) return;
      checks++;
      for (final p in g.players) {
        if (count(p) != totals[p.seat]) {
          final tail = g.log.reversed.take(25).toList().reversed.map((e) => '${e.runtimeType}: ${e.log}').join('\n  ');
          fail('${p.name} card count ${count(p)} != ${totals[p.seat]} after ${e.runtimeType}\n  $tail\n'
              'deck ${p.deck.length} hand ${p.hand.length} discard ${p.discard.length} inPlay ${p.inPlay} removed ${p.removed.length}');
        }
      }
    }

    final ids = [a, b, ...?more];
    g = Game(
      data: data,
      map: map ?? maps[seed % maps.length],
      heroIds: ids,
      teams: teams,
      agents: [for (var i = 0; i < ids.length; i++) random ? RandomAgent(seed + i) : AiAgent(seed: seed + 7 * i)],
      seed: seed,
      presenter: (e) async => check(e),
    );
    final w = await g.run();
    expect(g.over, isTrue);
    expect(w, isNotNull);
    expect(totals, isNotEmpty);
    return g;
  }

  test('AI vs AI: every pairing, every 1v1 map', () async {
    var games = 0, turns = 0;
    final wins = <String, int>{};
    for (final a in heroes) {
      for (final b in heroes) {
        if (a == b) continue;
        for (var seed = 0; seed < 6; seed++) {
          final g = await play(a, b, seed * 31 + a.length * 7 + b.length, random: false);
          games++;
          turns += g.turnNumber;
          wins.update(g.winner!.hero.id, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }
    // ignore: avoid_print
    print('AI games: $games, average ${(turns / games).toStringAsFixed(1)} turns, wins: $wins, invariant checks: $checks');
  }, timeout: const Timeout(Duration(minutes: 90)));

  test('random vs random: odd choices everywhere', () async {
    var games = 0;
    for (final a in heroes) {
      for (final b in heroes) {
        if (a == b) continue;
        for (var seed = 0; seed < 12; seed++) {
          await play(a, b, 1000 + seed * 13 + a.length, random: true);
          games++;
        }
      }
    }
    // ignore: avoid_print
    print('random games: $games, invariant checks: $checks');
  }, timeout: const Timeout(Duration(minutes: 90)));

  test('team and free-for-all games: 2v2, 3v3, 3- and 4-player FFA', () async {
    final rng = Random(5);
    var games = 0;
    final setups = <(String, int, List<int>?)>[
      ('2v2', 4, [0, 1, 0, 1]),
      ('3v3', 6, [0, 1, 0, 1, 0, 1]),
      ('ffa', 3, null),
      ('ffa', 4, null),
      ('ffa', 5, null),
    ];
    for (final (mode, n, teams) in setups) {
      for (final m in data.mapsFor(mode).where((m) => m.spaces.where((s) => s.start != null).length >= n)) {
        for (var k = 0; k < 6; k++) {
          final ids = (List.of(heroes)..shuffle(rng)).take(n).toList();
          final g = await play(ids[0], ids[1], 500 + games, random: k.isOdd, more: ids.sublist(2), teams: teams, map: m);
          expect(g.winningTeam, isNotNull);
          if (teams != null) {
            expect(g.players.where((p) => p.team != g.winningTeam).every((p) => p.defeated), isTrue);
          } else {
            expect(g.players.where((p) => !p.defeated), hasLength(lessThanOrEqualTo(1)));
          }
          games++;
        }
      }
    }
    // ignore: avoid_print
    print('multiplayer games: $games');
  }, timeout: const Timeout(Duration(minutes: 90)));

  test('every printed card effect has a script', () {
    final missing = <String>[];
    for (final id in heroes) {
      final script = createHeroScript(id);
      for (final c in data.hero(id).cards) {
        if (c.text.isEmpty) continue;
        if ((script.cards[c.upperTitle] ?? commonCardScripts[c.upperTitle]) == null) missing.add('${c.key} ${c.title}');
      }
    }
    expect(missing, isEmpty, reason: 'cards without a script: $missing');
  });

  test('every scripted card effect fired at least once in the games above', () {
    final missing = <String>[];
    for (final id in heroes) {
      final script = createHeroScript(id);
      for (final c in data.hero(id).cards) {
        final sc = script.cards[c.upperTitle] ?? commonCardScripts[c.upperTitle];
        if (sc == null || sc.noEffects || (!sc.hasCombatEffects && sc.effect == null)) continue;
        if (!fired.contains(c.key)) missing.add('${c.key} ${c.title}');
      }
    }
    expect(missing, isEmpty, reason: 'never resolved: $missing');
  });
}
