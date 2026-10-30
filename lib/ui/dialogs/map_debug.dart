/// Map connection editor for fixing a battlefield's paths against its art. Off in real builds:
/// run with `--dart-define=MAPDEBUG=true` and open any map's inspector (map select or lobby).
///
/// The inspector then draws every space's number and the path data over the art (plain paths,
/// arrows, "+1" paths), flags spaces that can't be reached or left, and lets you change paths:
/// tap a space, then another, to cycle the path between them
/// (none → path → arrow A→B → arrow B→A → +1 → none).
///
/// "Copy patch" puts the map's new `links` / `oneway` / `stairs` on the clipboard; apply it with
/// `dart tool/apply_map_patch.dart`, which reads the clipboard (see that file).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../board/board_painter.dart';
import '../theme.dart';

const mapDebug = bool.fromEnvironment('MAPDEBUG');

/// What joins two spaces, seen from the space tapped first.
enum PathKind {
  none('no path'),
  path('path'),
  forward('arrow →'),
  backward('arrow ←'),
  stairs('+1 path');

  const PathKind(this.label);
  final String label;
}

(int, int) _pair(int a, int b) => a < b ? (a, b) : (b, a);

class _Snapshot {
  _Snapshot(MapEdits e)
      : links = {...e.links},
        oneWay = {...e.oneWay},
        stairs = {...e.stairs};
  final Set<(int, int)> links, oneWay, stairs;
}

/// An editable copy of a map's paths. [links] and [stairs] hold sorted pairs; [oneWay] holds
/// (from, to): movement only goes from the first space to the second.
class MapEdits extends ChangeNotifier {
  MapEdits(this.map) {
    _origLinks = {for (final (a, b) in map.links) _pair(a, b)};
    _origOneWay = {...map.oneWay};
    _origStairs = {for (final (a, b) in map.stairs) _pair(a, b)};
    _restoreOriginal();
  }

  final MapDef map;
  late final Set<(int, int)> _origLinks, _origOneWay, _origStairs;
  final Set<(int, int)> links = {};
  final Set<(int, int)> oneWay = {};
  final Set<(int, int)> stairs = {};
  final List<_Snapshot> _undo = [];

  /// Paths that were in the map data but have been taken out.
  Iterable<(int, int)> get removed => _origLinks.difference(links);

  void _restore(_Snapshot s) => _set(s.links, s.oneWay, s.stairs);
  void _restoreOriginal() => _set(_origLinks, _origOneWay, _origStairs);

  void _set(Set<(int, int)> l, Set<(int, int)> o, Set<(int, int)> s) {
    links
      ..clear()
      ..addAll(l);
    oneWay
      ..clear()
      ..addAll(o);
    stairs
      ..clear()
      ..addAll(s);
  }

  PathKind kindOf(int from, int to) {
    final p = _pair(from, to);
    if (!links.contains(p)) return PathKind.none;
    if (stairs.contains(p)) return PathKind.stairs;
    if (oneWay.contains((from, to))) return PathKind.forward;
    if (oneWay.contains((to, from))) return PathKind.backward;
    return PathKind.path;
  }

  PathKind _origKindOf(int from, int to) {
    final p = _pair(from, to);
    if (!_origLinks.contains(p)) return PathKind.none;
    if (_origStairs.contains(p)) return PathKind.stairs;
    if (_origOneWay.contains((from, to))) return PathKind.forward;
    if (_origOneWay.contains((to, from))) return PathKind.backward;
    return PathKind.path;
  }

  /// Whether the path between [a] and [b] differs from the map data.
  bool changed(int a, int b) => kindOf(a, b) != _origKindOf(a, b);

  void setKind(int from, int to, PathKind k) {
    if (from == to || kindOf(from, to) == k) return;
    _undo.add(_Snapshot(this));
    final p = _pair(from, to);
    links.remove(p);
    stairs.remove(p);
    oneWay
      ..remove((from, to))
      ..remove((to, from));
    switch (k) {
      case PathKind.none:
        break;
      case PathKind.path:
        links.add(p);
      case PathKind.forward:
        links.add(p);
        oneWay.add((from, to));
      case PathKind.backward:
        links.add(p);
        oneWay.add((to, from));
      case PathKind.stairs:
        links.add(p);
        stairs.add(p);
    }
    notifyListeners();
  }

  /// Steps the path between [from] and [to] to the next kind; returns the new kind.
  PathKind cycle(int from, int to) {
    final next = PathKind.values[(kindOf(from, to).index + 1) % PathKind.values.length];
    setKind(from, to, next);
    return next;
  }

  bool get canUndo => _undo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    _restore(_undo.removeLast());
    notifyListeners();
  }

  void reset() {
    if (changeCount == 0) return;
    _undo.add(_Snapshot(this));
    _restoreOriginal();
    notifyListeners();
  }

  /// Paths whose kind differs from the map data.
  int get changeCount => {...links, ..._origLinks}.where((p) => changed(p.$1, p.$2)).length;

  Set<int> neighbours(int s) => {
        for (final (a, b) in links)
          if (a == s) b else if (b == s) a,
      };

  /// Spaces a fighter may step to from [s] (arrows only forwards).
  Iterable<int> stepsFrom(int s) => neighbours(s).where((n) => !oneWay.contains((n, s)));

  /// Spaces with a problem, and what it is: no path at all, can't be reached from space 0, or a
  /// dead end that can't be left (mirrors the checks in test/maps_test.dart).
  Map<int, String> problems() {
    final out = <int, String>{};
    final ids = [for (final s in map.spaces) s.id];
    for (final s in ids) {
      if (neighbours(s).isEmpty) out[s] = 'no path';
    }
    if (ids.isEmpty) return out;
    final reach = {ids.first};
    final todo = [ids.first];
    while (todo.isNotEmpty) {
      for (final j in stepsFrom(todo.removeLast())) {
        if (reach.add(j)) todo.add(j);
      }
    }
    for (final s in ids) {
      if (out.containsKey(s)) continue;
      if (!reach.contains(s)) {
        out[s] = 'unreachable';
      } else if (stepsFrom(s).isEmpty) {
        out[s] = 'dead end';
      }
    }
    return out;
  }

  /// The map's paths as a patch for tool/apply_map_patch.dart.
  String patch() {
    List<List<int>> sorted(Iterable<(int, int)> s) =>
        ([for (final (a, b) in s) [a, b]]..sort((x, y) => x[0] != y[0] ? x[0] - y[0] : x[1] - y[1]));
    return jsonEncode({
      'map': map.id,
      'links': sorted(links),
      'oneway': sorted(oneWay),
      'stairs': sorted(stairs),
    });
  }
}

/// Draws the path data and space numbers over a map (in board pixels, like [BoardPainter]).
class MapDebugPainter extends CustomPainter {
  MapDebugPainter(this.geo, this.edits, {this.selected}) : super(repaint: edits);
  final BoardGeometry geo;
  final MapEdits edits;
  final int? selected;

  static const pathColor = Color(0xFF2BD2FF);
  static const arrowColor = Color(0xFFFF9F1C);
  static const stairsColor = Color(0xFFE45CFF);
  static const removedColor = Color(0xFFFF4D4D);
  static const selectColor = Color(0xFFFFE14D);

  @override
  void paint(Canvas canvas, Size size) {
    final r = geo.radius;
    final w = r * 0.13;

    // Paths taken out of the data: dashed red, so you can see what you removed.
    final gone = Paint()
      ..color = removedColor.withValues(alpha: 0.8)
      ..strokeWidth = w * 0.7
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in edits.removed) {
      _dashed(canvas, geo.of(a), geo.of(b), gone, r);
    }

    for (final (a, b) in edits.links) {
      final kind = edits.kindOf(a, b);
      final color = switch (kind) {
        PathKind.forward || PathKind.backward => arrowColor,
        PathKind.stairs => stairsColor,
        _ => pathColor,
      };
      final (p, q) = _trim(geo.of(a), geo.of(b), r * 0.5);
      final touchesSel = selected == a || selected == b;
      if (edits.changed(a, b)) {
        canvas.drawLine(p, q, Paint()
          ..color = Colors.white
          ..strokeWidth = w * 2.4
          ..strokeCap = StrokeCap.round);
      }
      canvas.drawLine(p, q, Paint()
        ..color = Colors.black.withValues(alpha: 0.75)
        ..strokeWidth = w * 1.7
        ..strokeCap = StrokeCap.round);
      canvas.drawLine(p, q, Paint()
        ..color = touchesSel ? selectColor : color
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round);
      if (kind == PathKind.forward) _arrowHead(canvas, p, q, color, r);
      if (kind == PathKind.backward) _arrowHead(canvas, q, p, color, r);
      if (kind == PathKind.stairs) _tag(canvas, (p + q) / 2, '+1', stairsColor, r);
    }

    final problems = edits.problems();
    final near = selected == null ? const <int>{} : edits.neighbours(selected!);
    for (final s in geo.map.spaces) {
      final c = geo.of(s.id);
      if (problems.containsKey(s.id)) {
        canvas.drawCircle(c, r * 0.98, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16
          ..color = removedColor);
      }
      if (s.id == selected) {
        canvas.drawCircle(c, r * 1.08, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.2
          ..color = selectColor);
      } else if (near.contains(s.id)) {
        canvas.drawCircle(c, r * 0.9, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08
          ..color = selectColor);
      }
      _label(canvas, c, '${s.id}', r);
    }
  }

  /// The segment between two space centres, shortened by [by] at each end.
  static (Offset, Offset) _trim(Offset a, Offset b, double by) {
    final d = b - a;
    final len = d.distance;
    if (len <= by * 2) return (a, b);
    final u = d / len;
    return (a + u * by, b - u * by);
  }

  void _arrowHead(Canvas canvas, Offset from, Offset to, Color color, double r) {
    final d = to - from;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    final n = Offset(-u.dy, u.dx);
    // At the middle of the path, pointing the way fighters may move.
    final tip = from + u * (len / 2 + r * 0.3);
    final back = tip - u * r * 0.55;
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((back + n * r * 0.32).dx, (back + n * r * 0.32).dy)
      ..lineTo((back - n * r * 0.32).dx, (back - n * r * 0.32).dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(head, Paint()..color = color);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double r) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    final dash = r * 0.3;
    for (var t = r * 0.5; t < len - r * 0.5; t += dash * 2) {
      canvas.drawLine(a + u * t, a + u * math.min(t + dash, len - r * 0.5), paint);
    }
  }

  void _tag(Canvas canvas, Offset c, String text, Color color, double r) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: titleStyle(r * 0.5, color: Colors.black, spacing: 0)),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: tp.width + r * 0.3, height: tp.height + r * 0.08),
      Radius.circular(r * 0.15),
    );
    canvas.drawRRect(box, Paint()..color = color);
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _label(Canvas canvas, Offset c, String text, double r) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: titleStyle(r * 0.62, color: Colors.white, spacing: 0)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawCircle(c, math.max(r * 0.42, tp.width / 2 + r * 0.1), Paint()..color = const Color(0xE6101114));
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(MapDebugPainter old) => old.selected != selected || old.edits != edits || old.geo != geo;
}

/// Colour key for the overlay, for the inspector's bottom bar.
class MapDebugLegend extends StatelessWidget {
  const MapDebugLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String label, {bool dashed = false}) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 18, height: dashed ? 2 : 4, color: c),
              const SizedBox(width: 5),
              Text(label, style: bodyStyle(12, color: Palette.bone)),
            ],
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item(MapDebugPainter.pathColor, 'Path'),
        item(MapDebugPainter.arrowColor, 'Arrow (one-way)'),
        item(MapDebugPainter.stairsColor, '+1 path'),
        item(MapDebugPainter.removedColor, 'Removed', dashed: true),
        item(Colors.white, 'Changed (white edge)'),
        item(MapDebugPainter.removedColor, 'Red ring: problem space'),
      ],
    );
  }
}
