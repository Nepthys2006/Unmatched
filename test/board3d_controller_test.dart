// The 3D board's link to its page: a page that loads again (the host was rebuilt as the window grew
// or the device turned, or the web view reloaded) must be started over, not ignored - ignoring it
// left the board black until the player switched to 2D and back.
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/ui/board3d/board3d.dart';
import 'package:unmatched_game/ui/board3d/host_io.dart' as io;

import 'support.dart';

void main() {
  late Board3DController c;
  late List<Map<String, Object?>> sent;

  setUp(() {
    sent = [];
    c = Board3DController(map: lineMap(), graphics: const {'tier': 1}, homeSide: 1)
      ..bind((json) => sent.add(jsonDecode(json) as Map<String, Object?>));
  });
  tearDown(() => c.dispose());

  List<Object?> types() => [for (final m in sent) m['t']];

  test('a page that loads gets the map', () {
    c.receive('{"t":"loaded"}');
    expect(types(), ['init']);
    expect(c.status.value, Board3DStatus.loading);
    c.receive('{"t":"ready"}');
    expect(c.status.value, Board3DStatus.ready);
  });

  test('a second page (host rebuilt) is started over and the cover comes back until it is ready', () {
    c.send({'t': 'state', 'fighters': <Object>[]});
    c.receive('{"t":"loaded"}');
    c.receive('{"t":"progress","p":1}');
    c.receive('{"t":"ready"}');
    expect(c.status.value, Board3DStatus.ready);
    sent.clear();

    // The old web view is gone; a new, blank page announces itself.
    c.receive('{"t":"loaded"}');
    expect(types(), ['init', 'state'], reason: 'the new page gets the map and the board as it is now');
    expect(c.status.value, Board3DStatus.loading);
    expect(c.progress.value, 0);

    c.receive('{"t":"ready"}');
    expect(c.status.value, Board3DStatus.ready);
  });

  test('messages reach only the page that is bound now', () {
    final old = <String>[];
    c.bind(old.add);
    c.receive('{"t":"loaded"}');
    expect(old, hasLength(1));
    // The new host binds itself; the old one is not written to any more.
    c.bind((json) => sent.add(jsonDecode(json) as Map<String, Object?>));
    c.receive('{"t":"loaded"}');
    expect(old, hasLength(1));
    expect(types(), ['init']);
  });

  test('a failed board stays failed when a page loads', () {
    c.fail('WebGL is not available');
    c.receive('{"t":"loaded"}');
    expect(c.status.value, Board3DStatus.failed);
  });

  test('the web view is only given an area it can draw into', () {
    expect(io.webviewAreaUsable(Size.zero), isFalse);
    expect(io.webviewAreaUsable(const Size(7, 500)), isFalse);
    expect(io.webviewAreaUsable(const Size(500, 7)), isFalse);
    expect(io.webviewAreaUsable(const Size(8, 8)), isTrue);
    expect(io.webviewAreaUsable(const Size(1280, 720)), isTrue);
  });
}
