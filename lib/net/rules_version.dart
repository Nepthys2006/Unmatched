/// The "rules version" two devices compare before playing together.
///
/// It fingerprints only what the rules depend on: each playable hero's stats, fighters and cards
/// (type, values, copies, who may play them) and each map's graph (spaces, zones, starts, paths).
/// Art, names, colours, card and ability text, line endings, whitespace and key order are left
/// out, so builds for different platforms (or with a typo fixed in a card's text) still pair,
/// while a changed attack value or a missing hero keeps two devices from playing a different game.
library;

import 'dart:convert';

/// Fingerprint of [heroes] (the heroes.json list), [maps] (the maps.json map) and which heroes
/// this build can [playable] play. Same on every platform, including the web, where ints are doubles.
String rulesFingerprint(List<dynamic> heroes, Map<String, dynamic> maps, {required Iterable<String> playable}) {
  final ids = playable.toSet();
  Map<String, dynamic> m(Object? o) => Map<String, dynamic>.from(o as Map);
  List<Map<String, dynamic>> ms(Object? l) => [for (final x in (l as List)) m(x)];
  Object? n(Object? v) => v; // numbers and strings are compared as they are
  List<Object?> sortedStrings(Object? l) => [for (final x in (l as List? ?? const [])) '$x']..sort();

  final heroPart = <Object?>[
    for (final h in (ms(heroes).where((h) => ids.contains(h['id'])).toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String))))
      [
        h['id'],
        n(h['move']),
        [
          for (final f in ms(h['fighters']))
            [f['id'], f['hero'], '${f['attack']}'.startsWith('r'), n(f['hp']), n(f['count'])],
        ],
        [
          for (final c in ms(h['cards']))
            [
              n(c['index']),
              c['title'],
              c['type'],
              n(c['value']),
              n(c['boost']),
              n(c['copies']),
              sortedStrings(c['fighters']),
              c['dieBoost'] == true,
              n(c['syllables']),
              c['ingredient'],
            ],
        ],
      ],
  ];

  List<Object?> pairs(Object? l) {
    final out = [
      for (final p in (l as List? ?? const [])) [(p as List)[0] as int, p[1] as int],
    ]..sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]));
    return out;
  }

  final mapKeys = maps.keys.toList()..sort();
  final mapPart = <Object?>[
    for (final k in mapKeys)
      () {
        final map = m(maps[k]);
        return [
          k,
          sortedStrings(map['modes'] ?? [map['mode']]),
          sortedStrings((map['zones'] as Map).keys.toList()),
          [
            for (final s in ms(map['spaces'])) [s['id'], sortedStrings(s['zones']), s['start']],
          ],
          pairs(map['links']),
          pairs(map['oneway']),
          pairs(map['stairs']),
          map['river'] == true,
        ];
      }(),
  ];

  final bytes = utf8.encode(jsonEncode([heroPart, mapPart]));
  // FNV-1a. The multiply by 0x01000193 (2^24 + 0x193) is split so no intermediate passes 2^53:
  // on the web ints are doubles, and a plain multiply loses bits there.
  var hash = 0x811c9dc5;
  for (final x in bytes) {
    final h = hash ^ x;
    hash = (h * 0x193 + (h & 0xFF) * 0x1000000) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16);
}
