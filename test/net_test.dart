// Multiplayer over real sockets: a host and players on this machine (127.0.0.1) play whole
// matches with AIs standing in for the people, and every device's copy must end identically.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/portable_random.dart';
import 'package:unmatched_game/net/lan.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/match/match_config.dart';

import 'support.dart';

Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// One device's copy of the match.
class Copy {
  Copy(NetMatch m, {int humanSeed = 0}) {
    final c = m.config;
    game = Game(
      data: loadData(),
      map: c.map,
      heroIds: c.heroIds,
      teams: c.teams,
      random: PortableRandom(m.seed),
      presenter: (e) async {
        if (e.log.isNotEmpty) log.add(e.log);
      },
      agents: [
        for (var i = 0; i < c.heroIds.length; i++)
          m.agentFor(i, human: AiAgent(level: AiLevel.hard, seed: humanSeed + i), ai: AiAgent(level: AiLevel.medium, seed: 99 + i)),
      ],
    );
  }
  late final Game game;
  final List<String> log = [];

  String get summary => [
    'turns ${game.turnNumber}',
    'winner ${game.winningTeam}',
    for (final p in game.players) '${p.hero.id} hp ${p.heroFighter.hp} hand ${p.hand.length} deck ${p.deck.length}',
  ].join('\n');
}

Future<(HostSession, List<ClientSession>)> lobby(GameMode mode, int players, String map, int clients) async {
  final data = loadData();
  late HostSession host;
  final link = await LanHost.start(describe: () => {'name': 'Host'});
  host = HostSession(link, data, name: 'Host', dataVersion: 'test');
  expect(host.setMode(mode, players), isTrue);
  host.setMap(map);
  final cs = <ClientSession>[];
  for (var i = 0; i < clients; i++) {
    final c = ClientSession(await joinLan('127.0.0.1'), data, name: 'P$i', dataVersion: 'test', address: '127.0.0.1');
    cs.add(c);
    await until(() => c.mySeat != null && c.lobby != null);
  }
  // Remaining open seats become AI.
  for (var i = 0; i < players; i++) {
    if (host.lobby!.seats[i].kind == SeatKind.open) host.toggleSeat(i);
  }
  final heroes = data.heroes.keys.toList();
  host.pickHero(heroes[0]);
  for (var i = 0; i < cs.length; i++) {
    cs[i].pickHero(heroes[i + 1]);
    await until(() => host.lobby!.seats[cs[i].mySeat!].hero != null);
    cs[i].setReady(true);
  }
  await until(() => host.notReady == null);
  host.start();
  await until(() => cs.every((c) => c.match != null));
  return (host, cs);
}

void main() {
  test('a wrong game version is turned away', () async {
    final data = loadData();
    final host = HostSession(await LanHost.start(describe: () => {}), data, name: 'Host', dataVersion: 'a');
    final c = ClientSession(await joinLan('127.0.0.1'), data, name: 'X', dataVersion: 'b', address: '127.0.0.1');
    await until(() => c.closed != null);
    expect(c.closed, contains('version'));
    await c.leave();
    await host.leave();
  });

  for (final (mode, players, map, clients) in [
    (GameMode.duel, 2, 'blossom', 1),
    (GameMode.ffa, 3, 'cross', 2),
    (GameMode.teams2, 4, 'harbor', 1),
  ]) {
    test('${mode.label} with $clients player(s) stays in step on every device', () async {
      final (host, cs) = await lobby(mode, players, map, clients);
      final copies = [Copy(host.match!, humanSeed: 0), for (final c in cs) Copy(c.match!, humanSeed: 0)];
      await Future.wait([for (final c in copies) c.game.run()]).timeout(const Duration(minutes: 3));
      for (final c in copies.skip(1)) {
        expect(c.summary, copies.first.summary);
        expect(c.log, copies.first.log);
      }
      expect(copies.first.game.over, isTrue);
      for (final c in cs) {
        await c.leave();
      }
      await host.leave();
    }, timeout: const Timeout(Duration(minutes: 4)));
  }

  test('when a player leaves mid-match, the AI takes their seat and the match finishes', () async {
    final (host, cs) = await lobby(GameMode.ffa, 3, 'cross', 2);
    final copies = [Copy(host.match!), Copy(cs[0].match!), Copy(cs[1].match!)];
    final runs = [for (final c in copies) c.game.run()];
    // The leaver's own copy stops with an error once they're gone.
    unawaited(runs[2].then((_) {}, onError: (_) {}));
    // Player 2 drops out after a few turns.
    await until(() => copies[0].game.turnNumber >= 3, timeout: const Duration(minutes: 1));
    await cs[1].leave();
    await Future.wait([runs[0], runs[1]]).timeout(const Duration(minutes: 3));
    expect(copies[1].summary, copies[0].summary);
    expect(copies[0].game.over, isTrue);
    expect(host.match!.names.value[cs[1].mySeat!], endsWith('(AI)'));
    await cs[0].leave();
    await host.leave();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
