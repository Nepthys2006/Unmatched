// Mulligans and AI-hero choice over the network (LAN and online share the same session code),
// and builds of different ages playing together. Runs over the in-memory network from chat_test.
//
// * a new host + a new player: mulligans on, both devices play the same match to the end
// * an older player (no capabilities in its hello): mulligans off, so nothing desyncs
// * a newer player joining an older host (no flag in `start`): mulligans off
// * only the host can choose the heroes of AI seats; nobody can take a hero already chosen
// * the rules fingerprint ignores line endings, art and text but not values or the hero roster
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/rules_version.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/match/match_config.dart';

import 'chat_test.dart' show MemoryHost;
import 'net_test.dart' show Copy, until;
import 'support.dart';

void main() {
  final data = loadData();
  late MemoryHost link;
  late HostSession host;
  final clients = <ClientSession>[];

  Future<ClientSession> join(String name) async {
    final c = ClientSession(link.connect(), data, name: name, dataVersion: 'test', address: 'memory');
    clients.add(c);
    await until(() => c.mySeat != null && c.lobby != null);
    return c;
  }

  setUp(() {
    clients.clear();
    link = MemoryHost();
    host = HostSession(link, data, name: 'Host', dataVersion: 'test');
    expect(host.setMode(GameMode.duel, 2), isTrue);
    host.setMap('blossom');
  });
  tearDown(() async {
    for (final c in clients) {
      await c.leave();
    }
    await host.leave();
  });

  group('mulligan in a LAN / online match', () {
    test('two current builds: switched on, and both devices play the same match to the end', () async {
      final c = await join('Ann');
      host.pickHero('alice');
      c.pickHero('medusa');
      await until(() => host.lobby!.seats[c.mySeat!].hero == 'medusa');
      c.setReady(true);
      await until(() => host.notReady == null);
      host.start();
      await until(() => c.match != null);
      expect(host.match!.mulligans, isTrue);
      expect(c.match!.mulligans, isTrue, reason: 'the start message carries it');

      final copies = [Copy(host.match!), Copy(c.match!)];
      await Future.wait([for (final x in copies) x.game.run()]).timeout(const Duration(minutes: 3));
      expect(copies[1].summary, copies[0].summary, reason: 'same match on both devices');
      expect(copies[1].log, copies[0].log);
      // Both players made the choice, and the second device saw the first one's answer.
      final choices = copies[0].log.where((l) => l.contains('keeps their hand') || l.contains('takes a mulligan')).toList();
      expect(choices, hasLength(2));
    });

    test('a mulligan taken on one device is the same hand on the other', () async {
      final c = await join('Ann');
      host.pickHero('alice');
      c.pickHero('medusa');
      await until(() => host.lobby!.seats[c.mySeat!].hero == 'medusa');
      c.setReady(true);
      await until(() => host.notReady == null);
      host.start();
      await until(() => c.match != null);
      // Both devices' AI "humans" decide for themselves; run it for several seeds' worth of
      // hands by reading what each copy ended up with after setup.
      final copies = [Copy(host.match!, humanSeed: 5), Copy(c.match!, humanSeed: 5)];
      await Future.wait([for (final x in copies) x.game.run()]).timeout(const Duration(minutes: 3));
      for (var i = 0; i < 2; i++) {
        expect(copies[1].game.players[i].mulliganUsed, isTrue);
        expect([for (final x in copies[0].game.players[i].hand) x.def.key], [for (final x in copies[1].game.players[i].hand) x.def.key]);
      }
    });

    test('an older build (no capabilities in its hello): mulligans stay off for the whole table', () async {
      final raw = link.connect();
      final got = <Msg>[];
      raw.messages.listen(got.add);
      raw.send({'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'Old'});
      await until(() => got.any((m) => m['t'] == 'welcome'));
      final seat = got.firstWhere((m) => m['t'] == 'welcome')['seat'] as int;
      raw.send({'t': 'hero', 'id': 'medusa'});
      await until(() => host.lobby!.seats[seat].hero == 'medusa');
      raw.send({'t': 'ready', 'on': true});
      host.pickHero('alice');
      await until(() => host.notReady == null);
      host.start();
      expect(host.match!.mulligans, isFalse);
      await until(() => got.any((m) => m['t'] == 'start'));
      expect(got.firstWhere((m) => m['t'] == 'start')['mulligan'], isFalse);
    });

    test('a current player joining an older host (no flag in start) plays without mulligans', () async {
      final c = await join('Ann');
      host.pickHero('alice');
      c.pickHero('medusa');
      await until(() => host.lobby!.seats[c.mySeat!].hero == 'medusa');
      // What an older host sends: no `mulligan` key.
      link.broadcast({
        't': 'start',
        'lobby': host.lobby!.toJson(),
        'heroes': ['alice', 'medusa'],
        'seed': 1234,
      });
      await until(() => c.match != null);
      expect(c.match!.mulligans, isFalse);
    });

    test('the protocol version did not change, so older and newer builds still meet', () {
      expect(netProtocol, 1);
      expect(netCaps, contains('mulligan'));
    });
  });

  group('choosing the AI opponent in a lobby', () {
    test('host picks, everyone sees it, it is used when the match starts', () async {
      expect(host.setMode(GameMode.ffa, 3), isTrue);
      host.toggleSeat(2);
      final c = await join('Ann');
      expect(c.mySeat, 1);
      const aiSeat = 2;
      expect(host.setAiHero(aiSeat, 'achilles'), isTrue);
      await until(() => c.lobby!.seats[aiSeat].hero == 'achilles');
      expect(c.lobby!.seats[aiSeat].kind, SeatKind.ai);

      // Ann can't take it, the host can't pick a hero a person already has, and only AI seats take one.
      // A person can't take a hero the host gave the AI (only the host has a way to set an AI seat).
      c.pickHero('achilles');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(host.lobby!.seats[c.mySeat!].hero, isNull);
      c.pickHero('medusa');
      await until(() => host.lobby!.seats[c.mySeat!].hero == 'medusa');
      expect(host.setAiHero(aiSeat, 'medusa'), isFalse);
      expect(host.setAiHero(c.mySeat!, 'alice'), isFalse, reason: 'a person chooses their own hero');
      expect(host.setAiHero(aiSeat, 'no-such-hero'), isFalse);
      expect(host.lobby!.seats[aiSeat].hero, 'achilles');

      host.pickHero('alice');
      c.setReady(true);
      await until(() => host.notReady == null);
      host.start();
      final ids = host.match!.config.heroIds;
      expect(ids[aiSeat], 'achilles');
      expect(ids.toSet(), hasLength(3), reason: 'nobody plays the same hero twice');
    });

    test('the AI seats without a chosen hero are random and differ from every chosen hero', () async {
      expect(host.setMode(GameMode.ffa, 4), isTrue);
      for (var i = 1; i < 4; i++) {
        host.toggleSeat(i);
      }
      host.pickHero('alice');
      expect(host.setAiHero(1, 'achilles'), isTrue);
      expect(host.setAiHero(2, 'medusa'), isTrue);
      host.start();
      final ids = host.match!.config.heroIds;
      expect(ids.sublist(0, 3), ['alice', 'achilles', 'medusa']);
      expect(ids.toSet(), hasLength(4));
      expect(data.heroes.containsKey(ids[3]), isTrue);
    });

    test('back to random clears the pick; the seat can be opened and made AI again', () async {
      host.toggleSeat(1);
      expect(host.setAiHero(1, 'achilles'), isTrue);
      expect(host.setAiHero(1, null), isTrue);
      expect(host.lobby!.seats[1].hero, isNull);
      expect(host.setAiHero(1, 'achilles'), isTrue);
      host.toggleSeat(1);
      host.toggleSeat(1);
      expect(host.lobby!.seats[1].hero, isNull, reason: 'a re-opened seat starts fresh');
    });

    test('not after the match has started', () async {
      host.toggleSeat(1);
      host.pickHero('alice');
      host.start();
      expect(host.setAiHero(1, 'achilles'), isFalse);
    });
  });

  group('lineup: random AI heroes are drawn at the start and never repeat', () {
    test('a chosen hero is kept, random seats avoid you and each other', () {
      for (var i = 0; i < 50; i++) {
        final ids = MatchConfig.lineup(data, 'alice', 4, chosen: ['achilles', null, null]);
        expect(ids.first, 'alice');
        expect(ids[1], 'achilles');
        expect(ids.toSet(), hasLength(4));
      }
    });
    test('a choice that repeats you or an earlier choice is ignored', () {
      final ids = MatchConfig.lineup(data, 'alice', 4, chosen: ['alice', 'medusa', 'medusa']);
      expect(ids[1], isNot('alice'));
      expect(ids[2], 'medusa');
      expect(ids[3], isNot('medusa'));
      expect(ids.toSet(), hasLength(4));
    });
    test('with nothing chosen it is the old random lineup', () {
      final ids = MatchConfig.lineup(data, 'alice', 2);
      expect(ids, hasLength(2));
      expect(ids[1], isNot('alice'));
    });
  });

  group('rules fingerprint', () {
    final heroesText = File('assets/data/heroes.json').readAsStringSync();
    final mapsText = File('assets/data/maps.json').readAsStringSync();
    List<dynamic> heroes() => jsonDecode(heroesText) as List;
    Map<String, dynamic> maps() => jsonDecode(mapsText) as Map<String, dynamic>;
    final playable = data.heroes.keys.toList();
    String fp(List<dynamic> h, Map<String, dynamic> m, [Iterable<String>? p]) => rulesFingerprint(h, m, playable: p ?? playable);
    final base = fp(heroes(), maps());

    test('is the same however the files are written: CRLF, indentation, key order', () {
      final crlf = jsonDecode(heroesText.replaceAll('\n', '\r\n')) as List;
      expect(fp(crlf, maps()), base);
      final pretty = jsonDecode(const JsonEncoder.withIndent('      ').convert(heroes())) as List;
      expect(fp(pretty, maps()), base);
      final reordered = [
        for (final h in heroes()) {for (final k in (h as Map).keys.toList().reversed) k: h[k]},
      ];
      expect(fp(reordered, maps()), base);
      final hs = heroes().reversed.toList();
      expect(fp(hs, maps()), base);
    });

    test('ignores card text, ability text, names, colours and art', () {
      final h = heroes();
      final first = h.first as Map<String, dynamic>;
      first['ability'] = 'A typo fixed.';
      first['description'] = 'Reworded';
      first['color'] = '#123456';
      first['name'] = 'Renamed';
      ((first['cards'] as List).first as Map<String, dynamic>)['text'] = {'after': 'Different words.'};
      expect(fp(h, maps()), base);
    });

    test('changes when a card value, boost or copy count changes', () {
      for (final key in ['value', 'boost', 'copies']) {
        final h = heroes();
        final c = (h.first['cards'] as List).first as Map<String, dynamic>;
        c[key] = ((c[key] as int?) ?? 0) + 1;
        expect(fp(h, maps()), isNot(base), reason: key);
      }
    });

    test('changes when a hero stat or a map path changes', () {
      final h = heroes();
      h.first['move'] = (h.first['move'] as int) + 1;
      expect(fp(h, maps()), isNot(base));
      final m = maps();
      final first = m.values.first as Map<String, dynamic>;
      (first['links'] as List).removeLast();
      expect(fp(heroes(), m), isNot(base));
    });

    test('changes when the playable roster differs (an older build would crash on the new hero)', () {
      expect(fp(heroes(), maps(), playable.skip(1)), isNot(base));
    });

    test('is stable and the same for every platform (plain integers, no big multiplies)', () {
      expect(fp(heroes(), maps()), base);
      expect(base, matches(RegExp(r'^[0-9a-f]{1,8}$')));
      expect(playable.every(isImplemented), isTrue);
    });
  });
}
