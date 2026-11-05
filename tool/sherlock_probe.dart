// TEMPORARY: why does Pro Sherlock lose? Plays Pro Sherlock against Insane and compares losses
// with wins. dart run tool/sherlock_probe.dart --games=600 --seed=41 [--a=pro] [--vs=raphael,...]
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';

class _TooLong implements Exception {}

class Stats {
  final m = <String, double>{};
  int games = 0;
  void add(String k, num v) => m[k] = (m[k] ?? 0) + v;
}

/// Records what the Sherlock seat decides.
class Spy implements Agent {
  Spy(this.inner, this.s);
  final Agent inner;
  final Map<String, double> s;
  @override
  Future<List<int>> decide(Game g, Prompt p) async {
    final r = await inner.decide(g, p);
    if (p.ask == Ask.action && r.isNotEmpty) {
      final a = p.choices[r.first].value as ActionChoice;
      final k = switch (a.kind) {
        ActionKind.scheme => 'scheme ${a.card!.title}',
        ActionKind.attack => 'attack by ${a.fighter!.isHero ? 'Holmes' : 'Watson'}',
        ActionKind.maneuver => 'maneuver',
      };
      s[k] = (s[k] ?? 0) + 1;
      s['hand at action'] = (s['hand at action'] ?? 0) + p.player.hand.length;
      s['actions'] = (s['actions'] ?? 0) + 1;
    }
    if (p.ask == Ask.card && p.intent == Intent.defenseCard) {
      final k = r.isEmpty ? 'defend: none' : 'defend: ${(p.choices[r.first].value as Card).title}';
      s[k] = (s[k] ?? 0) + 1;
    }
    if (p.ask == Ask.card && p.intent == Intent.attackCard && r.isNotEmpty) {
      final k = 'attack card: ${(p.choices[r.first].value as Card).title}';
      s[k] = (s[k] ?? 0) + 1;
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
  final level = AiLevel.values.firstWhere((l) => l.name == (opt['a'] ?? 'pro'));
  final heroes = opt['vs']?.split(',') ?? (data.heroes.keys.where(isImplemented).where((h) => h != 'sherlock-holmes').toList()..sort());
  final maps = data.mapsFor('1v1');
  final rng = Random(int.parse(opt['seed'] ?? '41'));
  final n = int.parse(opt['games'] ?? '600');
  final won = Stats(), lost = Stats();
  final how = <String, int>{};
  for (var k = 0; k < n; k++) {
    final foe = heroes[rng.nextInt(heroes.length)];
    final map = maps[rng.nextInt(maps.length)];
    final seed = rng.nextInt(1 << 30);
    final seat = k & 1;
    final ids = seat == 0 ? ['sherlock-holmes', foe] : [foe, 'sherlock-holmes'];
    final mine = <String, double>{};
    final ev = <GameEvent>[];
    final g = Game(
      data: data,
      map: map,
      heroIds: ids,
      agents: [
        for (var i = 0; i < 2; i++)
          i == seat ? Spy(AiAgent(level: level, seed: seed + i), mine) : AiAgent(level: AiLevel.insane, seed: seed + i),
      ],
      seed: seed,
      firstSeat: seed & 1,
      presenter: (e) async {
        ev.add(e);
        if (e is TurnStarted && e.number > 300) throw _TooLong();
      },
    );
    Player? w;
    try {
      w = await g.run();
    } on _TooLong {
      continue;
    }
    final me = g.players[seat], opp = g.players[1 - seat];
    final s = w == me ? won : lost;
    s.games++;
    for (final e in mine.entries) {
      s.add(e.key, e.value);
    }
    s.add('turns', g.turnNumber);
    s.add('Holmes hp at end', me.heroFighter.hp);
    s.add('their hero hp at end', opp.heroFighter.hp);
    s.add('my deck at end', me.deck.length);
    s.add('their deck at end', opp.deck.length);
    s.add('Watson defeated', me.fighters.where((f) => f.isSidekick).any((f) => f.defeated) ? 1 : 0);
    for (final e in ev) {
      if (e is Exhausted) s.add(e.player == me ? 'I was exhausted (times)' : 'they were exhausted (times)', 1);
      if (e is Damaged) {
        final mineHurt = e.fighter.owner == me;
        final who = mineHurt ? (e.fighter.isHero ? 'Holmes' : 'Watson') : (e.fighter.isHero ? 'their hero' : 'their sidekicks');
        s.add('damage to $who (${e.combat ? 'combat' : 'other'})', e.amount);
      }
      if (e is Healed) s.add('healed ${e.fighter.owner == me ? 'mine' : 'theirs'}', e.amount);
      if (e is CombatResolved) {
        final c = e.combat;
        final iAttacked = c.attacker.player == me;
        final iWon = iAttacked ? c.attackerWon : !c.attackerWon;
        s.add(iAttacked ? 'my attacks' : 'their attacks', 1);
        s.add(iAttacked ? 'my attacks won' : 'their attacks I won', iWon ? 1 : 0);
        if (!iAttacked && c.defender.card == null && c.defender.fighter.isHero) {
          s.add('z undefended: hand size', me.hand.length);
          s.add('z undefended: deck size', me.deck.length);
          for (final x in me.hand) {
            s.add('z undefended holding: ${x.title}', 1);
          }
        }
        if (!iAttacked) {
          final k ='z def ${c.defender.fighter.isHero ? 'H' : 'W'} ${c.defender.card?.title ?? '(none)'}';
          s.add('$k: n', 1);
          s.add('$k: won', iWon ? 1 : 0);
          s.add('$k: damage taken', c.combatDamage);
          s.add('$k: attack value', c.attackValue);
        }
        if (!iAttacked && c.defender.card?.title == 'Elementary') {
          s.add('Elementary played', 1);
          if (c.defender.vars['prediction'] == c.attacker.card?.def.value) s.add('Elementary right', 1);
        }
      }
      if (e is SchemePlayed && e.card.title == 'Confirm Suspicion' && e.fighter.owner == me) s.add('CS played', 1);
      if (e is Revealed && e.why.contains('no card with value') && e.player == opp) s.add('CS missed', 1);
    }
    if (w != me) {
      final d = me.heroFighter.defeated ? 'Holmes defeated' : 'other';
      final exh = ev.any((e) => e is Exhausted && e.player == me);
      final key = '$d${exh ? ' (after exhausting)' : ''}';
      how[key] = (how[key] ?? 0) + 1;
    }
  }
  stdout.writeln('won ${won.games}, lost ${lost.games}; how lost: $how');
  final keys = {...won.m.keys, ...lost.m.keys}.toList()..sort();
  stdout.writeln('${'per game'.padRight(44)} ${'won'.padLeft(8)} ${'lost'.padLeft(8)}');
  for (final k in keys) {
    String f(Stats s) => s.games == 0 ? '-' : ((s.m[k] ?? 0) / s.games).toStringAsFixed(2);
    stdout.writeln('${k.padRight(44)} ${f(won).padLeft(8)} ${f(lost).padLeft(8)}');
  }
}
