/// A seeded random generator that gives the same numbers on every platform (phones, desktops
/// and browsers), so multiplayer devices shuffle identically from a shared seed. Dart's own
/// Random(seed) isn't promised to match between the VM and JavaScript.
///
/// Mulberry32 with all arithmetic kept within 32 bits (multiplication split into 16-bit halves,
/// since JavaScript numbers lose precision past 2^53).
library;

import 'dart:math';

class PortableRandom implements Random {
  PortableRandom(int seed) : _s = seed & 0xFFFFFFFF;
  int _s;

  /// 32-bit multiply, low 32 bits of the product (like JavaScript's Math.imul, unsigned).
  static int _mul(int a, int b) {
    final lo = (a & 0xFFFF) * b;
    final hi = (((a >>> 16) & 0xFFFF) * b) & 0xFFFF;
    return (lo + (hi << 16)) & 0xFFFFFFFF;
  }

  int _next32() {
    _s = (_s + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _s;
    t = _mul(t ^ (t >>> 15), t | 1);
    t = (t ^ (t + _mul(t ^ (t >>> 7), t | 61))) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  @override
  int nextInt(int max) {
    if (max <= 0 || max > 0x100000000) throw RangeError.range(max, 1, 0x100000000, 'max');
    // Rejection sampling: no bias towards small values.
    final limit = 0x100000000 - (0x100000000 % max);
    for (;;) {
      final r = _next32();
      if (r < limit) return r % max;
    }
  }

  @override
  double nextDouble() => (_next32() * 0x200000 + (_next32() >>> 11)) / 9007199254740992.0;

  @override
  bool nextBool() => _next32() & 1 == 1;
}
