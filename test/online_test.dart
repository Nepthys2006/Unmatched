// Online lobbies integration test through Supabase.
@Tags(['online'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:unmatched_game/net/online.dart';
import 'package:unmatched_game/net/session.dart';

import 'net_test.dart' show Copy, until;
import 'support.dart';

/// The service-role client from the local .env if present.
SupabaseClient? admin() {
  final f = File('.env');
  if (!f.existsSync()) return null;
  final env = {
    for (final l in f.readAsLinesSync())
      if (l.contains('=') && !l.startsWith('#')) l.substring(0, l.indexOf('=')).trim(): l.substring(l.indexOf('=') + 1).trim(),
  };
  final url = env['SUPABASE_URL'], key = env['SUPABASE_SERVICE_ROLE_KEY'] ?? env['SUPABASE_KEY'];
  return url == null || key == null || key.isEmpty ? null : SupabaseClient(url, key);
}

void main() {
  test('a password lobby: listed, wrong password refused, match played, then wiped', () async {
    final client = admin();
    if (!isOnlineConfigured && client == null) {
      return;
    }
    final targetClient = client ?? newSupabaseClient();
    final data = loadData();
    final tag = 'Test ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final hostLink = await OnlineHost.create(
      name: tag,
      hostName: 'Host',
      password: 'sesame',
      info: (mode: 'duel', players: 2, open: 1, playing: false, status: 'matching'),
      client: targetClient,
    );
    final host = HostSession(hostLink, data, name: 'Host', dataVersion: 'test');

    final listed = (await listLobbies(client: targetClient)).where((l) => l.name == tag).toList();
    expect(listed, hasLength(1));
    expect(listed.single.locked, isTrue);
    expect(listed.single.open, 1);

    await expectLater(
      OnlineClient.join(listed.single.id, password: 'wrong', client: targetClient),
      throwsA(predicate((e) => '$e'.contains('Wrong password'))),
    );

    final c = ClientSession(
      await OnlineClient.join(listed.single.id, password: 'sesame', client: targetClient),
      data,
      name: 'Guest',
      dataVersion: 'test',
      address: tag,
    );
    await until(() => c.mySeat != null && c.lobby != null, timeout: const Duration(seconds: 20));
    host.pickHero('achilles');
    c.pickHero('alice');
    await until(() => host.lobby!.seats[1].hero == 'alice', timeout: const Duration(seconds: 20));
    c.setReady(true);
    await until(() => host.notReady == null, timeout: const Duration(seconds: 20));
    host.start();
    await until(() => c.match != null, timeout: const Duration(seconds: 20));

    // A started match leaves the lobby list.
    await Future<void>.delayed(const Duration(seconds: 1));
    expect((await listLobbies(client: targetClient)).where((l) => l.name == tag), isEmpty);

    final a = Copy(host.match!), b = Copy(c.match!);
    await Future.wait([a.game.run(), b.game.run()]).timeout(const Duration(minutes: 4));
    expect(b.summary, a.summary);
    expect(b.log, a.log);

    final winner = a.game.winner?.hero.name;
    await host.match!.reportResult(winner: winner, players: ['Host', 'Guest']);
    final sb = admin();
    if (sb != null) {
      final lobby = await sb.from('lobbies').select('id').eq('name', tag);
      expect(lobby, isEmpty, reason: 'the lobby row is deleted when the match ends');
      final results = await sb.from('match_results').select().order('id', ascending: false).limit(1);
      expect(results.single['players'], ['Host', 'Guest']);
      expect(results.single['winner'], winner);
      expect(results.single.keys.toSet(), {'id', 'winner', 'players', 'finished_at'}, reason: 'only who won and who played is kept');
    }
    await c.leave();
    await host.leave();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
