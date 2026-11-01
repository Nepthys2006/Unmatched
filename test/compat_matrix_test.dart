// Builds of different ages meeting over the network (LAN over real sockets, and the in-memory link
// that online matches share the session code with). The rule: a device is turned away ONLY when the
// network protocol or the game's rules really differ; anything else (a newer app with extra features,
// a different platform, a different app version with the same rules) plays together, with the newer
// features simply off.
//
//   protocol differs      -> rejected, clear message, the host's lobby is untouched, others can still join
//   rules differ          -> rejected, clear message
//   same rules, older caps-> accepted, mulligans off for the whole table, both copies end identically
//   same rules, newer app -> accepted, features on
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/lan.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/match/match_config.dart';

import 'chat_test.dart' show MemoryHost;
import 'net_test.dart' show Copy, until;
import 'support.dart';

void main() {
  final data = loadData();

  group('in memory (what online matches run on)', () {
    late MemoryHost link;
    late HostSession host;
    final clients = <ClientSession>[];

    setUp(() {
      clients.clear();
      link = MemoryHost();
      host = HostSession(link, data, name: 'Host', dataVersion: 'rules-1');
      host.setMode(GameMode.duel, 2);
      host.setMap('blossom');
    });
    tearDown(() async {
      for (final c in clients) {
        await c.leave();
      }
      await host.leave();
    });

    ClientSession client(String name, {String rules = 'rules-1', List<String>? caps}) {
      final c = ClientSession(link.connect(), data, name: name, dataVersion: rules, address: 'memory', caps: caps ?? netCaps);
      clients.add(c);
      return c;
    }

    test('a different network protocol is turned away with a message that says what to do', () async {
      final raw = link.connect();
      final got = <Msg>[];
      raw.messages.listen(got.add);
      raw.send({'t': 'hello', 'v': netProtocol + 1, 'data': 'rules-1', 'name': 'Future'});
      await until(() => got.any((m) => m['t'] == 'reject'));
      final why = got.firstWhere((m) => m['t'] == 'reject')['why'] as String;
      expect(why, contains('incompatible network version'));
      expect(why, contains('Update'));
      expect(host.lobby!.seats.where((s) => s.kind == SeatKind.human), hasLength(1), reason: 'only the host sits down');
    });

    test('different rules are turned away, and the lobby still works for the next person', () async {
      final odd = client('Odd', rules: 'rules-2');
      await until(() => odd.closed != null);
      expect(odd.closed, contains('Different rules version'));
      expect(odd.closed, contains('Update'));
      expect(odd.mySeat, isNull);
      // The host is not stuck: someone on the right rules joins and the match starts.
      final ok = client('Ok');
      await until(() => ok.mySeat != null && ok.lobby != null);
      host.pickHero('alice');
      ok.pickHero('medusa');
      await until(() => host.lobby!.seats[ok.mySeat!].hero == 'medusa');
      ok.setReady(true);
      await until(() => host.notReady == null);
      host.start();
      await until(() => ok.match != null);
    });

    test('an older app (no features announced) with the same rules joins; mulligans are off for everybody; both copies end the same', () async {
      final old = client('Old', caps: const []);
      await until(() => old.mySeat != null && old.lobby != null);
      host.pickHero('alice');
      old.pickHero('medusa');
      await until(() => host.lobby!.seats[old.mySeat!].hero == 'medusa');
      old.setReady(true);
      await until(() => host.notReady == null);
      host.start();
      await until(() => old.match != null);
      expect(host.match!.mulligans, isFalse);
      expect(old.match!.mulligans, isFalse);
      final copies = [Copy(host.match!), Copy(old.match!)];
      await Future.wait([for (final x in copies) x.game.run()]).timeout(const Duration(minutes: 3));
      expect(copies[1].summary, copies[0].summary);
      expect(copies[1].log, copies[0].log);
      expect(copies[0].log.where((l) => l.contains('mulligan')), isEmpty);
    });

    test('a newer app announcing a feature this build has never heard of is still accepted (unknown features are ignored)', () async {
      final newer = client('Newer', caps: [...netCaps, 'some-future-feature']);
      await until(() => newer.mySeat != null && newer.lobby != null);
      host.pickHero('alice');
      newer.pickHero('medusa');
      await until(() => host.lobby!.seats[newer.mySeat!].hero == 'medusa');
      newer.setReady(true);
      await until(() => host.notReady == null);
      host.start();
      await until(() => newer.match != null);
      expect(host.match!.mulligans, isTrue, reason: 'both know mulligans');
      final copies = [Copy(host.match!), Copy(newer.match!)];
      await Future.wait([for (final x in copies) x.game.run()]).timeout(const Duration(minutes: 3));
      expect(copies[1].summary, copies[0].summary);
    });
  });

  group('over real sockets (LAN)', () {
    test('protocol and rules mismatches are turned away on a real connection, and a matching device then plays', () async {
      final host = HostSession(await LanHost.start(describe: () => {'name': 'Host'}), data, name: 'Host', dataVersion: 'rules-1');
      host.setMode(GameMode.duel, 2);
      host.setMap('blossom');
      final bad = ClientSession(await joinLan('127.0.0.1'), data, name: 'Bad', dataVersion: 'rules-9', address: '127.0.0.1');
      await until(() => bad.closed != null);
      expect(bad.closed, contains('Different rules version'));
      final good = ClientSession(await joinLan('127.0.0.1'), data, name: 'Good', dataVersion: 'rules-1', address: '127.0.0.1', caps: const []);
      await until(() => good.mySeat != null && good.lobby != null);
      host.pickHero('alice');
      good.pickHero('medusa');
      await until(() => host.lobby!.seats[good.mySeat!].hero == 'medusa');
      good.setReady(true);
      await until(() => host.notReady == null);
      host.start();
      await until(() => good.match != null);
      expect(good.match!.mulligans, isFalse, reason: 'an older build in the room switches the feature off for the table');
      final copies = [Copy(host.match!), Copy(good.match!)];
      await Future.wait([for (final x in copies) x.game.run()]).timeout(const Duration(minutes: 3));
      expect(copies[1].summary, copies[0].summary);
      await bad.leave();
      await good.leave();
      await host.leave();
    });
  });
}
