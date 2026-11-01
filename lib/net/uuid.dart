/// Match ids: a random UUID (v4), and a UUID worked out from some text so that two devices that
/// know the same facts about a match arrive at the same id without talking.
library;

import 'dart:math' as math;

String _hex(int v, int digits) => v.toRadixString(16).padLeft(digits, '0');

String _format(List<int> b) {
  final h = [for (final x in b) _hex(x, 2)].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// A random version-4 UUID (from the system's secure random).
String newUuid([math.Random? rng]) {
  final r = rng ?? math.Random.secure();
  final b = [for (var i = 0; i < 16; i++) r.nextInt(256)];
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  return _format(b);
}

/// A version-4-shaped UUID that is the same for the same [text] on every device and platform
/// (FNV-1a with 32-bit steps that stay exact on the web).
String uuidFromText(String text) {
  final bytes = <int>[];
  for (final unit in text.codeUnits) {
    bytes
      ..add(unit & 0xff)
      ..add((unit >> 8) & 0xff);
  }
  final out = <int>[];
  for (var lane = 0; lane < 4; lane++) {
    var hash = 0x811c9dc5 ^ (lane * 0x9e3779b1 & 0xFFFFFFFF);
    for (final x in bytes) {
      final h = hash ^ x;
      hash = (h * 0x193 + (h & 0xFF) * 0x1000000) & 0xFFFFFFFF;
    }
    out
      ..add((hash >> 24) & 0xff)
      ..add((hash >> 16) & 0xff)
      ..add((hash >> 8) & 0xff)
      ..add(hash & 0xff);
  }
  out[6] = (out[6] & 0x0f) | 0x40;
  out[8] = (out[8] & 0x3f) | 0x80;
  return _format(out);
}

final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
