/// Board geometry and painters. The static layer (background, paths, spaces) is painted once per
/// map and cached by a RepaintBoundary; tokens and highlights are separate, cheaper layers.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../theme.dart';

/// Maps engine coordinates (roughly -7..7 by -3.5..3.5) to board pixels.
class BoardGeometry {
  BoardGeometry(this.map, {this.unit = 100}) {
    final art = map.art;
    if (art != null) {
      // Printed-style maps: the board is the artwork; map units are art pixels / unitPx from
      // the image centre, so spaces land exactly on the painted circles.
      _minX = -art.w / 2 / art.unitPx;
      _minY = -art.h / 2 / art.unitPx;
      _pad = 0;
      size = Size(art.w / art.unitPx * unit, art.h / art.unitPx * unit);
      positions = {for (final s in map.spaces) s.id: _pos(s.x, s.y)};
      return;
    }
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final s in map.spaces) {
      minX = math.min(minX, s.x);
      maxX = math.max(maxX, s.x);
      minY = math.min(minY, s.y);
      maxY = math.max(maxY, s.y);
    }
    _minX = minX;
    _minY = minY;
    size = Size((maxX - minX + 2 * pad) * unit, (maxY - minY + 2 * pad) * unit);
    positions = {for (final s in map.spaces) s.id: _pos(s.x, s.y)};
  }

  final MapDef map;
  final double unit;
  static const pad = 0.9;
  double _pad = pad;
  late final double _minX, _minY;
  late final Size size;
  late final Map<int, Offset> positions;

  /// A space's radius on the board (the printed circles are about one unit across).
  double get radius => unit * (map.art != null ? 0.46 : 0.3);
  Offset _pos(double x, double y) => Offset((x - _minX + _pad) * unit, (y - _minY + _pad) * unit);
  Offset of(int space) => positions[space]!;

  /// Board pixels for a point in map coordinates (taps on the 3D board).
  Offset world(double x, double y) => _pos(x, y);

  /// The space under [p], if any (generous touch radius for fingers).
  int? spaceAt(Offset p, {double slack = 1.45}) {
    int? best;
    var bestD = radius * slack;
    for (final e in positions.entries) {
      final d = (e.value - p).distance;
      if (d < bestD) {
        bestD = d;
        best = e.key;
      }
    }
    return best;
  }

  /// The link (edge) nearest to [p] among [edges].
  (int, int)? edgeAt(Offset p, Iterable<(int, int)> edges) {
    (int, int)? best;
    var bestD = radius * 0.9;
    for (final e in edges) {
      final d = _segDist(p, of(e.$1), of(e.$2));
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  }

  static double _segDist(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// Ground colours per map theme: a printed board, lighter than the graphite table around it.
(Color, Color) themeColors(String theme) => switch (theme) {
  'garden' => (const Color(0xFF55664F), const Color(0xFF2E3A2C)),
  'forest' => (const Color(0xFF4A5E43), const Color(0xFF253222)),
  'winter' => (const Color(0xFF5D6E80), const Color(0xFF2E3A48)),
  'harbor' => (const Color(0xFF4F6370), const Color(0xFF283640)),
  'marsh' => (const Color(0xFF55604A), const Color(0xFF2B3226)),
  'desert' => (const Color(0xFF7A6146), const Color(0xFF3E2F22)),
  'ruins' => (const Color(0xFF5E5853), const Color(0xFF2E2A27)),
  'isle' => (const Color(0xFF4A6A6C), const Color(0xFF233638)),
  'keeps' => (const Color(0xFF55586A), const Color(0xFF2A2C36)),
  _ => (const Color(0xFF55585F), const Color(0xFF2A2C30)),
};

class BoardPainter extends CustomPainter {
  BoardPainter(this.geo, {this.showStarts = true, this.detailed = true});
  final BoardGeometry geo;
  final bool showStarts;

  /// Small previews skip text and texture.
  final bool detailed;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / geo.size.width;
    final sy = size.height / geo.size.height;
    final s = math.min(sx, sy);
    canvas.save();
    canvas.translate((size.width - geo.size.width * s) / 2, (size.height - geo.size.height * s) / 2);
    canvas.scale(s);
    _paint(canvas);
    canvas.restore();
  }

  void _paint(Canvas canvas) {
    final map = geo.map;
    // Maps with artwork are drawn from the image (see BoardArt); nothing to paint here.
    if (map.art != null) return;
    final rect = Offset.zero & geo.size;
    final (c1, c2) = themeColors(map.theme);
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(geo.unit * 0.25));
    if (detailed) {
      canvas.drawRRect(outer.shift(Offset(0, geo.unit * 0.12)), Paint()..color = const Color(0xAA000000));
    }
    canvas.drawRRect(outer, Paint()..shader = RadialGradient(colors: [c1, c2], radius: 0.95).createShader(rect));
    if (detailed) {
      canvas.save();
      canvas.clipRRect(outer);
      // Soft blotches give the ground some texture without an image.
      final rnd = math.Random(map.id.hashCode);
      final blot = Paint();
      for (var i = 0; i < 26; i++) {
        final o = Offset(rnd.nextDouble() * rect.width, rnd.nextDouble() * rect.height);
        final r = geo.unit * (0.6 + rnd.nextDouble() * 1.6);
        blot.color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(alpha: 0.025 + rnd.nextDouble() * 0.03);
        canvas.drawCircle(o, r, blot);
      }
      // Zone halos: a faint wash of each zone's colour around its spaces.
      final halo = Paint();
      for (final sp in map.spaces) {
        for (final z in sp.zones) {
          halo.color = hexColor(map.zones[z]?.color ?? '#888').withValues(alpha: 0.09);
          canvas.drawCircle(geo.of(sp.id), geo.unit * 0.7, halo);
        }
      }
      canvas.restore();
    }
    // The board's edge: a dark bevel and a thin bone inlay line, as on the printed boards.
    canvas.drawRRect(
      outer.deflate(geo.unit * 0.05),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = geo.unit * 0.1
        ..color = const Color(0xCC111214),
    );
    canvas.drawRRect(
      outer.deflate(geo.unit * 0.17),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Palette.bone.withValues(alpha: 0.35),
    );

    // Paths: black lines with a faint light edge so they read on dark ground too.
    final under = Paint()
      ..color = Palette.bone.withValues(alpha: 0.16)
      ..strokeWidth = geo.unit * 0.1
      ..strokeCap = StrokeCap.round;
    final over = Paint()
      ..color = const Color(0xFF0C0D0F)
      ..strokeWidth = geo.unit * 0.055
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in map.links) {
      canvas.drawLine(geo.of(a), geo.of(b), under);
    }
    for (final (a, b) in map.links) {
      canvas.drawLine(geo.of(a), geo.of(b), over);
    }

    final r = geo.radius;
    final shadow = Paint()..color = const Color(0x88000000);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.11
      ..color = const Color(0xFF0C0D0F);
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.04
      ..color = Colors.white.withValues(alpha: 0.35);
    for (final sp in map.spaces) {
      final c = geo.of(sp.id);
      canvas.drawCircle(c + Offset(0, r * 0.12), r * 1.06, shadow);
      final zones = sp.zones.toList()..sort();
      final colors = [for (final z in zones) hexColor(map.zones[z]?.color ?? '#999999')];
      final oval = Rect.fromCircle(center: c, radius: r);
      if (colors.length <= 1) {
        canvas.drawCircle(c, r, Paint()..color = colors.isEmpty ? Colors.grey : colors.first);
      } else {
        // Multi-zone spaces are split into wedges, one per zone.
        final sweep = 2 * math.pi / colors.length;
        for (var i = 0; i < colors.length; i++) {
          canvas.drawArc(oval, -math.pi / 2 + i * sweep, sweep, true, Paint()..color = colors[i]);
        }
        final div = Paint()
          ..color = const Color(0xFF0C0D0F)
          ..strokeWidth = r * 0.07;
        for (var i = 0; i < colors.length; i++) {
          final a = -math.pi / 2 + i * sweep;
          canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r, div);
        }
      }
      // A soft top highlight makes the spaces read as discs.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.5),
            colors: [Colors.white.withValues(alpha: 0.28), Colors.transparent],
          ).createShader(oval),
      );
      canvas.drawCircle(c, r * 0.84, inner);
      canvas.drawCircle(c, r, ring);
      if (showStarts && sp.start != null) _startBadge(canvas, c, sp.start!);
    }
  }

  void _startBadge(Canvas canvas, Offset c, int n) {
    final r = geo.radius;
    final o = c + Offset(r * 0.78, -r * 0.78);
    canvas.drawCircle(o, r * 0.42, Paint()..color = Palette.brass);
    canvas.drawCircle(
      o,
      r * 0.42,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Palette.bgDeep,
    );
    if (!detailed) return;
    final tp = TextPainter(
      text: TextSpan(
        text: '$n',
        style: titleStyle(r * 0.58, color: Palette.bgDeep, spacing: 0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(BoardPainter old) => old.geo.map != geo.map || old.detailed != detailed;
}

class MapPreview extends StatelessWidget {
  const MapPreview(this.map, {super.key, this.height = 120, this.fit = BoxFit.cover, this.cacheWidth = 960, this.quality = FilterQuality.high});
  final MapDef map;
  final double height;
  final BoxFit fit;

  /// Decode width: card thumbnails use less than the full-size previews.
  final int cacheWidth;
  final FilterQuality quality;

  @override
  Widget build(BuildContext context) {
    final art = map.art;
    if (art != null) {
      return AspectRatio(
        aspectRatio: art.w / art.h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(art.asset, fit: fit, cacheWidth: cacheWidth, filterQuality: quality, gaplessPlayback: true),
        ),
      );
    }
    final geo = BoardGeometry(map);
    return AspectRatio(
      aspectRatio: geo.size.width / geo.size.height,
      child: RepaintBoundary(child: CustomPaint(painter: BoardPainter(geo, detailed: true, showStarts: true))),
    );
  }
}
