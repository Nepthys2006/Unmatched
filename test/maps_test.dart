// Every battlefield: the data, the art, the rules for arrow and "+1" paths, and whole AI matches
// played on every map in every mode it offers.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

/// Reads a WebP's width and height from its header (VP8, VP8L or VP8X).
(int, int) webpSize(File f) {
  final b = f.readAsBytesSync();
  final kind = String.fromCharCodes(b.sublist(12, 16));
  int le(int i, int n) => [for (var k = 0; k < n; k++) b[i + k] << (8 * k)].reduce((a, c) => a | c);
  return switch (kind) {
    'VP8X' => (le(24, 3) + 1, le(27, 3) + 1),
    'VP8L' => ((le(21, 4) & 0x3FFF) + 1, ((le(21, 4) >> 14) & 0x3FFF) + 1),
    _ => (le(26, 2) & 0x3FFF, le(28, 2) & 0x3FFF),
  };
}

void main() {
  final data = loadData();
  final maps = data.maps.values.toList();

  test('47 maps: 1v1, 2v2, free-for-all and 3v3 all have maps', () {
    expect(maps, hasLength(47));
    for (final mode in ['1v1', '2v2', 'ffa', '3v3']) {
      expect(data.mapsFor(mode), isNotEmpty, reason: mode);
    }
    expect(data.mapsFor('3v3'), hasLength(5));
    expect(data.mapsFor('ffa').where((m) => m.startCount >= 5), isNotEmpty, reason: '5-player free-for-all');
  });

  for (final m in maps) {
    test('${m.id}: data and art', () {
      final n = m.spaces.length;
      expect([for (final s in m.spaces) s.id], List.generate(n, (i) => i), reason: 'space ids are 0..n-1');
      // Art: the file exists, its size matches, every space sits inside it.
      final art = m.art!;
      final f = File(art.asset);
      expect(f.existsSync(), isTrue, reason: art.asset);
      expect(webpSize(f), (art.w, art.h), reason: 'art size');
      for (final s in m.spaces) {
        final px = s.x * art.unitPx + art.w / 2, py = s.y * art.unitPx + art.h / 2;
        expect(px, inInclusiveRange(art.unitPx * 0.3, art.w - art.unitPx * 0.3), reason: 'space ${s.id} x');
        expect(py, inInclusiveRange(art.unitPx * 0.3, art.h - art.unitPx * 0.3), reason: 'space ${s.id} y');
        expect(s.zones, isNotEmpty, reason: 'space ${s.id} zone');
        expect(s.zones.every(m.zones.containsKey), isTrue, reason: 'space ${s.id} zone names');
      }
      // Spaces don't overlap.
      for (final a in m.spaces) {
        for (final b in m.spaces.where((b) => b.id > a.id)) {
          expect(math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)), greaterThan(0.85), reason: 'spaces ${a.id} and ${b.id} overlap');
        }
      }
      // Paths: valid, no duplicates, every space reachable from every other.
      final board = Board(m);
      final seen = <(int, int)>{};
      for (final (a, b) in m.links) {
        expect(a != b && a >= 0 && b >= 0 && a < n && b < n, isTrue, reason: 'link $a-$b');
        expect(seen.add(a < b ? (a, b) : (b, a)), isTrue, reason: 'duplicate link $a-$b');
      }
      for (final s in m.spaces) {
        expect(board.neighbours(s.id), isNotEmpty, reason: 'space ${s.id} has no path');
      }
      final reach = {0};
      final todo = [0];
      while (todo.isNotEmpty) {
        for (final j in board.stepsFrom(todo.removeLast())) {
          if (reach.add(j)) todo.add(j);
        }
      }
      expect(reach.length, n, reason: 'every space can be reached by moving (arrows included)');
      for (final (a, b) in [...m.oneWay, ...m.stairs]) {
        expect(board.adjacent(a, b), isTrue, reason: 'arrow/+1 path $a-$b is not a path');
      }
      // Starts: numbered 1..k, enough for every mode the map offers.
      final starts = [for (final s in m.spaces) ?s.start]..sort();
      expect(starts, List.generate(starts.length, (i) => i + 1));
      final need = m.modes.contains('3v3') ? 6 : (m.modes.contains('2v2') ? 4 : 2);
      expect(starts.length, greaterThanOrEqualTo(need), reason: 'start spaces');
      // Zones the map declares are used.
      for (final z in m.zones.keys) {
        expect(m.spaces.any((s) => s.zones.contains(z)), isTrue, reason: 'zone $z unused');
      }
    });
  }

  // Every printed path can be walked: a fighter on either end reaches the other with exactly the
  // movement the path costs (2 on "+1" paths), except backwards along an arrow.
  for (final m in maps) {
    test('${m.id}: every path can be walked', () {
      final g = Game(data: data, map: m, heroIds: ['medusa', 'bigfoot'], agents: [AiAgent(seed: 1), AiAgent(seed: 2)], seed: 1);
      final f = g.players[0].heroFighter;
      for (final p in g.players) {
        for (final o in p.fighters) {
          if (o != f) o.space = null;
        }
      }
      for (final (a, b) in m.links) {
        for (final (from, to) in [(a, b), (b, a)]) {
          f.space = from;
          final cost = g.board.stepCost(from, to);
          final back = m.oneWay.contains((to, from));
          expect(g.reachable(f, cost).keys.contains(to), !back, reason: '$from -> $to (${back ? 'against an arrow' : 'cost $cost'})');
          if (cost > 1) expect(g.reachable(f, cost - 1).keys.contains(to), isFalse, reason: '$from -> $to is a +1 path');
        }
      }
    });
  }

  group('arrow and "+1" paths', () {
    test('arrows: move only forwards, but the spaces stay adjacent', () async {
      final m = data.maps['raptor-paddock']!;
      final g = Game(data: data, map: m, heroIds: ['medusa', 'bigfoot'], agents: [AiAgent(seed: 1), AiAgent(seed: 2)], seed: 1);
      final medusa = g.players[0].heroFighter;
      medusa.space = 13;
      expect(g.board.adjacent(13, 4), isTrue);
      expect(g.reachable(medusa, 1).keys, isNot(contains(4)), reason: '4 -> 13 is one-way');
      medusa.space = 4;
      expect(g.reachable(medusa, 1).keys, contains(13));
    });

    test('"+1" paths cost 2 movement', () async {
      final m = data.maps['hanging-gardens']!;
      final g = Game(data: data, map: m, heroIds: ['medusa', 'bigfoot'], agents: [AiAgent(seed: 1), AiAgent(seed: 2)], seed: 1);
      final medusa = g.players[0].heroFighter;
      medusa.space = 1;
      expect(g.board.stepCost(1, 2), 2);
      expect(g.reachable(medusa, 1).keys, isNot(contains(2)), reason: '1-2 is a +1 path');
      expect(g.reachable(medusa, 2).keys, contains(2));
      expect(g.reachable(medusa, 1).keys, contains(0), reason: '0-1 is a normal path');
    });
  });

  // Whole AI matches on every map, in each of its modes.
  final rnd = math.Random(7);
  final heroes = data.heroes.keys.toList()..sort();
  for (final m in maps) {
    for (final mode in m.modes) {
      test('${m.id}: a full $mode match', () async {
        final n = switch (mode) { '2v2' => 4, '3v3' => 6, 'ffa' => math.min(m.startCount, 4), _ => 2 };
        final teams = switch (mode) { '2v2' => [0, 1, 0, 1], '3v3' => [0, 1, 0, 1, 0, 1], _ => null };
        final ids = (List.of(heroes)..shuffle(rnd)).take(n).toList();
        final g = Game(
          data: data,
          map: m,
          heroIds: ids,
          teams: teams,
          agents: [for (var i = 0; i < n; i++) AiAgent(level: AiLevel.hard, seed: i + 3)],
          seed: m.id.hashCode & 0xFFFF,
        );
        await g.setup();
        // Every fighter starts on a real, distinct space.
        final used = <int>{};
        for (final f in g.fighters.where((f) => f.onBoard && !f.isSmall)) {
          expect(used.add(f.space!), isTrue, reason: 'two fighters start on ${f.space}');
        }
        final g2 = Game(
          data: data,
          map: m,
          heroIds: ids,
          teams: teams,
          agents: [for (var i = 0; i < n; i++) AiAgent(level: AiLevel.hard, seed: i + 3)],
          seed: m.id.hashCode & 0xFFFF,
        );
        expect(await g2.run(), isNotNull);
        expect(g2.turnNumber, greaterThan(n), reason: 'a real match');
      });
    }
  }
}
