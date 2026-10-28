// AI arena: plays whole matches between two AIs, headless, and reports who wins. Use it to check
// that a change to lib/engine/ai.dart makes the AI stronger. Run from the project folder:
//
//     dart run tool/ai_arena.dart                          (insane vs baseline, 200 games)
//     dart run tool/ai_arena.dart --a=hard --b=medium --games=400
//     dart run tool/ai_arena.dart --heroes=medusa,bigfoot --maps=sarpedon
//     --verbose (one line per game), --heroes-table (A's wins with each hero), --seed=N
//
// Agents: easy, medium, hard, insane (the current AI), baseline or baseline:<level> (the frozen
// copy in tool/ai/baseline_ai.dart; insane by default), random.
//
// Games come in pairs with the same heroes, map, shuffle and first player but the seats
// swapped, so luck and hero strength even out. A side's win rate is only meaningful outside
// the ± margin (95% confidence); more games shrink it.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/prompt.dart';

import 'ai/baseline_ai.dart';

const _maxTurns = 300;

class _TooLong implements Exception {}

Agent makeAgent(String spec, int seed) {
  final [name, ...rest] = spec.split(':');
  AiLevel level(String s) => AiLevel.values.firstWhere((l) => l.name == s, orElse: () => throw ArgumentError('No AI level "$s"'));
  return switch (name) {
    'random' => RandomAgent(seed),
    'baseline' => BaselineAgent(level: level(rest.isEmpty ? 'insane' : rest.first), seed: seed),
    _ => AiAgent(level: level(name), seed: seed),
  };
}

/// Counts what an agent does: its actions, and how often it defends when attacked.
class _Counting implements Agent {
  _Counting(this.inner, this.counts);
  final Agent inner;
  final Map<String, int> counts;

  @override
  Future<List<int>> decide(Game game, Prompt p) async {
    final r = await inner.decide(game, p);
    final key = switch (p.ask) {
      Ask.action when r.isNotEmpty => (p.choices[r.first].value as ActionChoice).kind.name,
      Ask.card when p.intent == Intent.defenseCard => r.isEmpty ? 'no defense' : 'defense',
      _ => null,
    };
    if (key != null) counts[key] = (counts[key] ?? 0) + 1;
    return r;
  }
}

Future<void> main(List<String> args) async {
  final opt = {
    for (final a in args)
      if (a.startsWith('--')) a.substring(2).split('=').first: a.contains('=') ? a.substring(a.indexOf('=') + 1) : 'true',
  };
  if (opt.containsKey('help')) {
    stdout.writeln(File('tool/ai_arena.dart').readAsLinesSync().takeWhile((l) => l.startsWith('//')).map((l) => l.replaceFirst(RegExp(r'^// ?'), '')).join('\n'));
    return;
  }
  final aSpec = opt['a'] ?? 'insane', bSpec = opt['b'] ?? 'baseline';
  final pairs = (int.parse(opt['games'] ?? '200') + 1) ~/ 2;
  final seed0 = int.parse(opt['seed'] ?? '1');
  final verbose = opt.containsKey('verbose');

  final data = GameData.fromJson(
    jsonDecode(File('assets/data/heroes.json').readAsStringSync()) as List,
    jsonDecode(File('assets/data/maps.json').readAsStringSync()) as Map<String, dynamic>,
  );
  final heroes = opt['heroes']?.split(',') ?? (data.heroes.keys.where(isImplemented).toList()..sort());
  final maps = opt['maps'] != null ? [for (final id in opt['maps']!.split(',')) data.maps[id]!] : data.mapsFor('1v1');

  final rng = Random(seed0);
  var aWins = 0, bWins = 0, draws = 0, turns = 0, games = 0;
  final byHero = <String, (int, int)>{}; // hero A played: (games, wins)
  final aActs = <String, int>{}, bActs = <String, int>{};
  final watch = Stopwatch()..start();

  for (var k = 0; k < pairs; k++) {
    final h1 = heroes[rng.nextInt(heroes.length)];
    var h2 = heroes[rng.nextInt(heroes.length)];
    if (heroes.length > 1) {
      while (h2 == h1) {
        h2 = heroes[rng.nextInt(heroes.length)];
      }
    }
    final map = maps[rng.nextInt(maps.length)];
    final seed = rng.nextInt(1 << 30);
    for (final aSeat in [0, 1]) {
      final specs = aSeat == 0 ? [aSpec, bSpec] : [bSpec, aSpec];
      final g = Game(
        data: data,
        map: map,
        heroIds: [h1, h2],
        agents: [for (var i = 0; i < 2; i++) _Counting(makeAgent(specs[i], seed + i), i == aSeat ? aActs : bActs)],
        seed: seed,
        firstSeat: seed & 1,
        presenter: (e) async {
          if (e is TurnStarted && e.number > _maxTurns) throw _TooLong();
        },
      );
      String result;
      try {
        final w = await g.run();
        games++;
        turns += g.turnNumber;
        final aWon = w?.seat == aSeat;
        if (aWon) {
          aWins++;
        } else {
          bWins++;
        }
        final hero = [h1, h2][aSeat];
        final (n, won) = byHero[hero] ?? (0, 0);
        byHero[hero] = (n + 1, won + (aWon ? 1 : 0));
        result = aWon ? 'A' : 'B';
      } on _TooLong {
        games++;
        draws++;
        result = 'draw';
      }
      if (verbose) stdout.writeln('${games.toString().padLeft(4)}  ${map.id.padRight(22)} A=${[h1, h2][aSeat].padRight(16)} B=${[h1, h2][1 - aSeat].padRight(16)} $result');
    }
    if (!verbose && (k + 1) % 10 == 0) stdout.write('\r$games games...');
  }

  final decided = aWins + bWins;
  final p = decided == 0 ? 0.5 : aWins / decided;
  final margin = decided == 0 ? 0 : 1.96 * sqrt(p * (1 - p) / decided);
  String pct(double x) => '${(x * 100).toStringAsFixed(1)}%';
  stdout.writeln('\r$games games in ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, '
      'average ${(turns / max(1, games - draws)).toStringAsFixed(1)} turns${draws > 0 ? ', $draws over $_maxTurns turns (draws)' : ''}');
  stdout.writeln('A ($aSpec) won $aWins, B ($bSpec) won $bWins: A wins ${pct(p)} ± ${pct(margin.toDouble())}');
  stdout.writeln(switch (p - margin > 0.5 ? 1 : (p + margin < 0.5 ? -1 : 0)) {
    1 => '=> A is stronger.',
    -1 => '=> B is stronger.',
    _ => '=> No clear difference yet: play more games (--games=N).',
  });
  String acts(Map<String, int> m) {
    int c(String k) => m[k] ?? 0;
    final actions = max(1, c('maneuver') + c('attack') + c('scheme'));
    return '${[for (final k in ['maneuver', 'attack', 'scheme']) '$k ${pct(c(k) / actions)}'].join(', ')}; '
        'attacked without defending ${pct(c('no defense') / max(1, c('defense') + c('no defense')))}';
  }

  stdout.writeln('Actions  A: ${acts(aActs)}\n         B: ${acts(bActs)}');
  if (opt.containsKey('heroes-table')) {
    final rows = byHero.entries.toList()..sort((x, y) => (x.value.$2 / x.value.$1).compareTo(y.value.$2 / y.value.$1));
    for (final r in rows) {
      stdout.writeln('  ${r.key.padRight(20)} A won ${r.value.$2}/${r.value.$1}');
    }
  }
}
