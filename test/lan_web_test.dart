// A LAN host serves the game to browsers on the network: the page and runtime from assets/webapp,
// the art and data from the app's own bundle, and still accepts players over WebSocket.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/lan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes HttpClient; this test needs the real one.
  HttpOverrides.global = null;

  test('browsers get the game from the host', () async {
    final host = await LanHost.start(describe: () => {'name': 'Test'});
    addTearDown(host.close);
    final client = HttpClient();
    Future<(int, String?, int)> get(String path) async {
      final r = await (await client.get('127.0.0.1', lanPort, path)).close();
      final n = await r.fold<int>(0, (a, b) => a + b.length);
      return (r.statusCode, r.headers.contentType?.mimeType, n);
    }

    final page = await get('/');
    expect((page.$1, page.$2), (200, 'text/html'));
    expect(page.$3, greaterThan(100));
    expect((await get('/main.dart.js')).$1, 200);
    expect((await get('/canvaskit/canvaskit.wasm')).$2, 'application/wasm');
    expect((await get('/assets/FontManifest.json')).$1, 200);
    final data = await get('/assets/assets/data/heroes.json');
    expect(data.$1, 200);
    expect(data.$3, greaterThan(100000), reason: 'game data comes from the app bundle');
    expect((await get('/assets/assets/heroes/alice/figure.webp')).$1, 200);
    expect((await get('/../pubspec.yaml')).$1, 404);
    expect(host.webAddress, startsWith('http://'));
    client.close(force: true);
  });
}
