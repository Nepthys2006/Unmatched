// What a LAN / online match needs so that both devices save the SAME match and the server can
// rate it: a match id from the host, each player's account id, and where it was played. Builds
// that don't send these (older ones, guests) must still play, just unranked.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/net/uuid.dart';
import 'package:unmatched_game/ui/match/match_config.dart';

import 'chat_test.dart' show MemoryHost;
import 'net_test.dart' show until;
import 'support.dart';

void main() {
  final data = loadData();
  late MemoryHost link;
  late HostSession host;
  final clients = <ClientSession>[];

  Future<ClientSession> join({String? uid, bool online = false}) async {
    final c = ClientSession(link.connect(), data, name: 'Ann', dataVersion: 'test', address: 'memory', accountId: uid)..online = online;
    clients.add(c);
    await until(() => c.mySeat != null && c.lobby != null);
    return c;
  }

  Future<void> readyUp(ClientSession c) async {
    host.pickHero('alice');
    c.pickHero('medusa');
    await until(() => host.lobby!.seats[c.mySeat!].hero == 'medusa');
    c.setReady(true);
    await until(() => host.notReady == null);
  }

  HostSession makeHost({String? uid}) {
    link = MemoryHost();
    final h = HostSession(link, data, name: 'Host', dataVersion: 'test', accountId: uid);
    expect(h.setMode(GameMode.duel, 2), isTrue);
    h.setMap('blossom');
    return h;
  }

  tearDown(() async {
    for (final c in clients) {
      await c.leave();
    }
    clients.clear();
    await host.leave();
  });

  test('both devices get the same match id from the host, and each other\'s account id', () async {
    host = makeHost(uid: 'host-uid');
    final c = await join(uid: 'client-uid');
    await readyUp(c);
    host.start();
    await until(() => c.match != null);
    final a = host.match!, b = c.match!;
    expect(uuidPattern.hasMatch(a.matchId), isTrue);
    expect(b.matchId, a.matchId);
    expect(a.seatUids, ['host-uid', 'client-uid']);
    expect(b.seatUids, ['host-uid', 'client-uid'], reason: 'the lobby carries it to every device');
  });

  test('each match gets its own id', () async {
    host = makeHost();
    final c = await join();
    await readyUp(c);
    host.start();
    final first = host.match!.matchId;
    final other = LobbySession.matchIdOf(null, 5, ['a', 'b'], 'blossom');
    expect(first, isNot(other));
    expect(uuidPattern.hasMatch(newUuid()), isTrue);
  });

  test('a guest (no account) has no id; the other side still saves the match, unranked', () async {
    host = makeHost(uid: 'host-uid');
    final c = await join(); // no account id
    await readyUp(c);
    host.start();
    await until(() => c.match != null);
    expect(host.match!.seatUids, ['host-uid', null]);
    expect(c.match!.seatUids, ['host-uid', null]);
  });

  test('an older build\'s hello (no id, no capabilities) is accepted; its seat has no account id', () async {
    host = makeHost(uid: 'host-uid');
    final raw = link.connect();
    final got = <Msg>[];
    raw.messages.listen(got.add);
    raw.send({'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'Old'});
    await until(() => got.any((m) => m['t'] == 'welcome'));
    final seat = got.firstWhere((m) => m['t'] == 'welcome')['seat'] as int;
    expect(host.lobby!.seats[seat].uid, isNull);
    // Junk in the field never becomes an id.
    final raw2 = link.connect();
    final got2 = <Msg>[];
    raw2.messages.listen(got2.add);
    raw2.send({'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'Odd', 'uid': 42});
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('a host too old to send a match id: both devices work out the same one from what they share', () async {
    host = makeHost();
    final c = await join(uid: 'x');
    host.pickHero('alice');
    c.pickHero('medusa');
    await until(() => host.lobby!.seats[c.mySeat!].hero == 'medusa');
    link.broadcast({'t': 'start', 'lobby': host.lobby!.toJson(), 'heroes': ['alice', 'medusa'], 'seed': 777});
    await until(() => c.match != null);
    expect(c.match!.matchId, LobbySession.matchIdOf(null, 777, ['alice', 'medusa'], 'blossom'));
    expect(uuidPattern.hasMatch(c.match!.matchId), isTrue);
    // A garbage id is not trusted either.
    expect(LobbySession.matchIdOf('nope', 777, ['alice', 'medusa'], 'blossom'), c.match!.matchId);
  });

  test('where it was played is known to the match (internet or local network)', () async {
    host = makeHost(uid: 'h');
    host.online = true;
    final c = await join(uid: 'c', online: true);
    await readyUp(c);
    host.start();
    await until(() => c.match != null);
    expect(host.match!.online, isTrue);
    expect(c.match!.online, isTrue);
  });

  test('a LAN match is not marked online', () async {
    host = makeHost(uid: 'h');
    final c = await join(uid: 'c');
    await readyUp(c);
    host.start();
    await until(() => c.match != null);
    expect(host.match!.online, isFalse);
    expect(c.match!.online, isFalse);
  });
}
