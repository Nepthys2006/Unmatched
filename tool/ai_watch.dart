// Prints one AI match move by move, with every choice each AI made, to look for bad play.
//
//     dart run tool/ai_watch.dart [--a=insane] [--b=baseline] [--heroes=medusa,bigfoot] [--map=sarpedon] [--seed=1]
import 'dart:convert';
import 'dart:io';

import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/prompt.dart';

import 'ai_arena.dart' show makeAgent;

class _Telling implements Agent {
  _Telling(this.inner, this.name);
  final Agent inner;
  final String name;

  @override
  Future<List<int>> decide(Game game, Prompt p) async {
    final r = await inner.decide(game, p);
    if (p.choices.length > 1 || p.optional) {
      final picked = r.isEmpty ? (p.skipLabel ?? 'skip') : r.map((i) => p.choices[i].label).join(', ');
      stdout.writeln('      [$name] ${p.text}: $picked   (of ${p.choices.length}${p.optional ? ', optional' : ''})');
    }
    return r;
  }
}

Future<void> main(List<String> args) async {
  final opt = {
    for (final a in args)
      if (a.startsWith('--')) a.substring(2).split('=').first: a.contains('=') ? a.substring(a.indexOf('=') + 1) : 'true',
  };
  final data = GameData.fromJson(
    jsonDecode(File('assets/data/heroes.json').readAsStringSync()) as List,
    jsonDecode(File('assets/data/maps.json').readAsStringSync()) as Map<String, dynamic>,
  );
  final heroes = (opt['heroes'] ?? 'medusa,bigfoot').split(',');
  final map = data.maps[opt['map'] ?? 'sarpedon'] ?? data.mapsFor('1v1').first;
  final seed = int.parse(opt['seed'] ?? '1');
  final specs = [opt['a'] ?? 'insane', opt['b'] ?? 'baseline'];
  late Game g;
  g = Game(
    data: data,
    map: map,
    heroIds: heroes,
    agents: [for (var i = 0; i < 2; i++) _Telling(makeAgent(specs[i], seed + i), '${specs[i]}/${heroes[i]}')],
    seed: seed,
    firstSeat: 0,
    presenter: (e) async {
      if (e is TurnStarted) {
        stdout.writeln('\n=== Turn ${e.number}: ${e.player.name}');
        for (final p in g.players) {
          stdout.writeln('    ${p.name}: hand ${p.hand.length}, deck ${p.deck.length}; '
              '${p.fighters.map((f) => '${f.name} ${f.hp}hp @${f.space ?? '-'}').join(', ')}');
        }
      } else if (e.log.isNotEmpty) {
        stdout.writeln('  ${e.log}');
      }
    },
  );
  final w = await g.run();
  stdout.writeln('\nWinner: ${w?.name} after ${g.turnNumber} turns');
}
