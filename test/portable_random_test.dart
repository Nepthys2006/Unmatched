// The multiplayer shuffle must give the same numbers on phones, desktops and browsers. These
// values are pinned: the web build (dart2js) must produce exactly the same ones.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/portable_random.dart';

void main() {
  test('PortableRandom gives the reference Mulberry32 sequence', () {
    final r = PortableRandom(1);
    // Reference: Mulberry32(1) in JavaScript gives these 32-bit outputs.
    final want = [2693262067, 11749833, 2265367787, 4213581821];
    expect([for (var i = 0; i < 4; i++) r.nextInt(0x100000000)], want);
  });

  test('nextInt stays in range and covers it', () {
    final r = PortableRandom(42);
    final seen = <int>{};
    for (var i = 0; i < 2000; i++) {
      final v = r.nextInt(7);
      expect(v, inInclusiveRange(0, 6));
      seen.add(v);
    }
    expect(seen.length, 7);
  });
}
