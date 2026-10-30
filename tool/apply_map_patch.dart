// Applies a map path patch (from the MAPDEBUG map editor's "Copy patch") to the game's map data.
// Run from the project folder:
//
//     dart tool/apply_map_patch.dart                            (reads the patch from the clipboard)
//     dart tool/apply_map_patch.dart patch.json [more.json...]
//     dart tool/apply_map_patch.dart --dry-run                  (show the changes, write nothing)
//
// A patch piped in also works (`Get-Clipboard | dart tool/apply_map_patch.dart`), in whatever
// encoding the shell sends it.
//
// A patch is {"map": id, "links": [[a,b],...], "oneway": [[from,to],...], "stairs": [[a,b],...]}
// (or a list of them), and replaces those three lists for that map in assets/data/maps.json and,
// for the game's own maps, in tool/maps_custom/<id>.json. Paths that are unchanged keep their
// place and direction in the file, so the git diff shows only what changed. If any patch is
// wrong, nothing is written.
//
// Then run `flutter test test/maps_test.dart`.
import 'dart:convert';
import 'dart:io';

const mapsFile = 'assets/data/maps.json';

typedef Pair = (int, int);

Pair norm(Pair p) => p.$1 < p.$2 ? p : (p.$2, p.$1);

List<Pair> pairs(Object? raw, String what) {
  if (raw == null) return [];
  if (raw is! List) throw FormatException('"$what" must be a list of [a, b] pairs');
  return [
    for (final e in raw)
      if (e is List && e.length == 2 && e[0] is int && e[1] is int)
        (e[0] as int, e[1] as int)
      else
        throw FormatException('"$what": bad entry $e'),
  ];
}

/// The new list for one key: entries already in the file that are still wanted keep their place
/// and direction; new ones are added at the end.
List<List<int>> merge(Object? old, List<Pair> want, {required bool directed}) {
  Pair key(Pair p) => directed ? p : norm(p);
  final wanted = {for (final p in want) key(p)};
  final out = <List<int>>[];
  final kept = <Pair>{};
  for (final p in pairs(old, 'existing')) {
    if (wanted.contains(key(p)) && kept.add(key(p))) out.add([p.$1, p.$2]);
  }
  for (final p in want) {
    if (kept.add(key(p))) out.add([p.$1, p.$2]);
  }
  return out;
}

/// Checks a patch against its map; returns the problems (empty = fine).
List<String> validate(Map<String, dynamic> map, List<Pair> links, List<Pair> oneway, List<Pair> stairs) {
  final errors = <String>[];
  final n = (map['spaces'] as List).length;
  final seen = <Pair>{};
  for (final p in links) {
    if (p.$1 == p.$2 || p.$1 < 0 || p.$2 < 0 || p.$1 >= n || p.$2 >= n) errors.add('link ${p.$1}-${p.$2} is not between two spaces (0..${n - 1})');
    if (!seen.add(norm(p))) errors.add('link ${p.$1}-${p.$2} is listed twice');
  }
  for (final p in oneway) {
    if (!seen.contains(norm(p))) errors.add('arrow ${p.$1}->${p.$2} is not a link');
  }
  if (oneway.any((p) => oneway.contains((p.$2, p.$1)))) errors.add('a path has arrows both ways');
  for (final p in stairs) {
    if (!seen.contains(norm(p))) errors.add('+1 path ${p.$1}-${p.$2} is not a link');
  }
  return errors;
}

/// Spaces that can't be reached from space 0, or can't be left (warnings only).
List<String> reachability(int n, List<Pair> links, List<Pair> oneway) {
  final steps = {for (var i = 0; i < n; i++) i: <int>{}};
  final arrows = oneway.toSet();
  for (final (a, b) in links) {
    if (!arrows.contains((b, a))) steps[a]!.add(b);
    if (!arrows.contains((a, b))) steps[b]!.add(a);
  }
  final reach = {0};
  final todo = [0];
  while (todo.isNotEmpty) {
    for (final j in steps[todo.removeLast()]!) {
      if (reach.add(j)) todo.add(j);
    }
  }
  return [
    for (var i = 0; i < n; i++)
      if (!reach.contains(i)) 'space $i cannot be reached from space 0' else if (steps[i]!.isEmpty) 'space $i is a dead end',
  ];
}

void report(String id, Map<String, dynamic> map, List<Pair> links, List<Pair> oneway, List<Pair> stairs) {
  Set<Pair> set(Object? raw, {bool directed = false}) => {for (final p in pairs(raw, 'existing')) directed ? p : norm(p)};
  void diff(String what, Set<Pair> before, Set<Pair> after, String sep) {
    for (final p in after.difference(before).toList()..sort(_cmp)) {
      stdout.writeln('  + $what ${p.$1}$sep${p.$2}');
    }
    for (final p in before.difference(after).toList()..sort(_cmp)) {
      stdout.writeln('  - $what ${p.$1}$sep${p.$2}');
    }
  }

  stdout.writeln('$id (${map['name']}):');
  final before = [set(map['links']), set(map['oneway'], directed: true), set(map['stairs'])];
  final after = [{for (final p in links) norm(p)}, oneway.toSet(), {for (final p in stairs) norm(p)}];
  diff('path ', before[0], after[0], '-');
  diff('arrow', before[1], after[1], '->');
  diff('+1   ', before[2], after[2], '-');
  if ([0, 1, 2].every((i) => before[i].length == after[i].length && before[i].containsAll(after[i]))) {
    stdout.writeln('  no changes');
  }
}

int _cmp(Pair a, Pair b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2;

/// Text in any encoding a shell may send: UTF-8 with or without a BOM, or UTF-16 with or without
/// one (Windows PowerShell pipes UTF-16 with some settings, even behind a UTF-8 BOM).
String decodeText(List<int> b) {
  String utf16(List<int> b, {required bool little}) =>
      String.fromCharCodes([for (var i = 0; i + 1 < b.length; i += 2) little ? b[i] | b[i + 1] << 8 : b[i] << 8 | b[i + 1]]);
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = b.sublist(3);
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return utf16(b.sublist(2), little: true);
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return utf16(b.sublist(2), little: false);
  // UTF-16 without a BOM: every other byte of the (ASCII) JSON is 0.
  if (b.length >= 4 && b[1] == 0 && b[3] == 0) return utf16(b, little: true);
  if (b.length >= 4 && b[0] == 0 && b[2] == 0) return utf16(b, little: false);
  return utf8.decode(b, allowMalformed: true);
}

/// The clipboard's text, or null if it can't be read.
Future<String?> readClipboard() async {
  try {
    if (Platform.isWindows) {
      // Base64 so the console's code page can't change the text on the way.
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'$t = Get-Clipboard -Raw; if ($t) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($t)) }',
      ]);
      if (r.exitCode == 0) return utf8.decode(base64.decode((r.stdout as String).trim()));
    } else {
      for (final cmd in [
        ['pbpaste'],
        ['wl-paste', '--no-newline'],
        ['xclip', '-o', '-selection', 'clipboard'],
      ]) {
        try {
          final r = await Process.run(cmd.first, cmd.sublist(1));
          if (r.exitCode == 0) return r.stdout as String;
        } on ProcessException {
          continue;
        }
      }
    }
  } catch (_) {}
  return null;
}

/// The start of [s] with invisible characters shown, for error messages.
String preview(String s) {
  final t = s.length > 60 ? '${s.substring(0, 60)}...' : s;
  return t.runes.map((c) => c >= 0x20 && c < 0x7F ? String.fromCharCode(c) : '\\u{${c.toRadixString(16)}}').join();
}

/// Writes JSON the way tool/build_maps.py does (1-space indent), keeping the file's line endings.
void writeJson(File f, Object data, {required bool crlf}) {
  var text = const JsonEncoder.withIndent(' ').convert(data);
  if (crlf) text = text.replaceAll('\n', '\r\n');
  f.writeAsStringSync(text);
}

Future<void> main(List<String> args) async {
  final dry = args.contains('--dry-run');
  final files = args.where((a) => !a.startsWith('--')).toList();
  final List<String> inputs;
  if (files.isNotEmpty) {
    inputs = [for (final f in files) decodeText(File(f).readAsBytesSync())];
  } else {
    // Piped in, or else straight from the clipboard.
    var text = stdin.hasTerminal ? '' : decodeText([for (final chunk in await stdin.toList()) ...chunk]);
    if (text.trim().isEmpty) {
      text = await readClipboard() ?? '';
      if (text.trim().isEmpty) {
        stderr.writeln('The clipboard is empty: press "Copy patch" in the map editor first (or give a patch file).');
        exit(2);
      }
    }
    inputs = [text];
  }

  final mapsF = File(mapsFile);
  if (!mapsF.existsSync()) {
    stderr.writeln('Run this from the project folder (no $mapsFile here).');
    exit(2);
  }
  final mapsText = mapsF.readAsStringSync();
  final maps = jsonDecode(mapsText) as Map<String, dynamic>;
  final custom = <String, (File, Map<String, dynamic>, bool)>{};
  var failed = false;

  for (final input in inputs) {
    final Object? decoded;
    try {
      decoded = jsonDecode(input.trim());
    } on FormatException catch (e) {
      stderr.writeln('Not a patch (bad JSON): ${e.message}\nReceived: ${preview(input.trim())}\n'
          'Press "Copy patch" in the map editor, then run: dart tool/apply_map_patch.dart');
      exit(2);
    }
    final patches = decoded is List ? decoded : [decoded];
    for (final p in patches) {
      if (p is! Map<String, dynamic> || p['map'] is! String) {
        stderr.writeln('Not a patch: expected {"map": id, "links": [...], ...}');
        exit(2);
      }
      final id = p['map'] as String;
      final map = maps[id] as Map<String, dynamic>?;
      if (map == null) {
        stderr.writeln('No map "$id" in $mapsFile');
        failed = true;
        continue;
      }
      final List<Pair> links, oneway, stairs;
      try {
        links = pairs(p['links'], 'links');
        oneway = pairs(p['oneway'], 'oneway');
        stairs = pairs(p['stairs'], 'stairs');
      } on FormatException catch (e) {
        stderr.writeln('$id: ${e.message}');
        failed = true;
        continue;
      }
      final errors = validate(map, links, oneway, stairs);
      if (errors.isNotEmpty) {
        stderr.writeln('$id: not applied:\n  ${errors.join('\n  ')}');
        failed = true;
        continue;
      }
      report(id, map, links, oneway, stairs);
      for (final w in reachability((map['spaces'] as List).length, links, oneway)) {
        stdout.writeln('  warning: $w');
      }
      void apply(Map<String, dynamic> m) {
        m['links'] = merge(m['links'], links, directed: false);
        m['oneway'] = merge(m['oneway'], oneway, directed: true);
        m['stairs'] = merge(m['stairs'], stairs, directed: false);
      }

      apply(map);
      final cf = File('tool/maps_custom/$id.json');
      if (cf.existsSync()) {
        final (_, cm, _) = custom[id] ??= (() {
          final t = cf.readAsStringSync();
          return (cf, jsonDecode(t) as Map<String, dynamic>, t.contains('\r\n'));
        })();
        apply(cm);
      }
    }
  }

  if (failed) {
    stderr.writeln('Nothing written: fix the patch and run again.');
    exit(1);
  }
  if (dry) {
    stdout.writeln('Dry run: nothing written.');
  } else {
    writeJson(mapsF, maps, crlf: mapsText.contains('\r\n'));
    for (final (f, m, crlf) in custom.values) {
      writeJson(f, m, crlf: crlf);
    }
    stdout.writeln('Wrote $mapsFile${custom.isEmpty ? '' : ' and ${[for (final (f, _, _) in custom.values) f.path].join(', ')}'}. '
        'Now run: flutter test test/maps_test.dart');
  }
}
