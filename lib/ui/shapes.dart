/// The digital edition's shape language: cut hexagons, angled plates, chamfered panels, and the
/// thin art-deco linework on the graphite table.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A hexagon with points on the left and right (flat top and bottom), like the game's buttons.
class HexBorder extends OutlinedBorder {
  const HexBorder({super.side});

  static Path pathFor(Rect r) {
    final inset = r.height * 0.29;
    return Path()
      ..moveTo(r.left + inset, r.top)
      ..lineTo(r.right - inset, r.top)
      ..lineTo(r.right, r.center.dy)
      ..lineTo(r.right - inset, r.bottom)
      ..lineTo(r.left + inset, r.bottom)
      ..lineTo(r.left, r.center.dy)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect.deflate(side.width));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(pathFor(rect.deflate(side.width / 2)), side.toPaint()..strokeJoin = StrokeJoin.miter);
  }

  @override
  ShapeBorder scale(double t) => HexBorder(side: side.scale(t));
  @override
  HexBorder copyWith({BorderSide? side}) => HexBorder(side: side ?? this.side);
}

/// A diamond (a square on its point): the hero emblems on the player plates.
class DiamondBorder extends OutlinedBorder {
  const DiamondBorder({super.side});

  static Path pathFor(Rect r) => Path()
    ..moveTo(r.center.dx, r.top)
    ..lineTo(r.right, r.center.dy)
    ..lineTo(r.center.dx, r.bottom)
    ..lineTo(r.left, r.center.dy)
    ..close();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect.deflate(side.width * 1.42));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(pathFor(rect.deflate(side.width * 0.71)), side.toPaint()..strokeJoin = StrokeJoin.miter);
  }

  @override
  ShapeBorder scale(double t) => DiamondBorder(side: side.scale(t));
  @override
  DiamondBorder copyWith({BorderSide? side}) => DiamondBorder(side: side ?? this.side);
}

/// An angled name plate: the left edge leans, the right edge can end in an arrow point
/// (the DEFENDER / ATTACKER banners) or lean the other way.
class PlateBorder extends OutlinedBorder {
  const PlateBorder({super.side, this.slant = 0.35, this.point = false, this.flip = false});

  /// Horizontal lean as a fraction of the height.
  final double slant;

  /// The far end comes to an arrow point instead of a lean.
  final bool point;

  /// Mirror horizontally (point on the left).
  final bool flip;

  Path pathFor(Rect r) {
    final s = r.height * slant;
    final p = Path();
    if (!flip) {
      p
        ..moveTo(r.left + s, r.top)
        ..lineTo(r.right - (point ? s : 0), r.top);
      if (point) {
        p.lineTo(r.right, r.center.dy);
        p.lineTo(r.right - s, r.bottom);
      } else {
        p.lineTo(r.right - s, r.bottom);
      }
      p
        ..lineTo(r.left, r.bottom)
        ..close();
    } else {
      p
        ..moveTo(r.left + (point ? s : 0), r.top)
        ..lineTo(r.right - s, r.top)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.left + s, r.bottom);
      if (point) {
        p.lineTo(r.left, r.center.dy);
        p.lineTo(r.left + s, r.top);
      } else {
        p.lineTo(r.left + s, r.top);
      }
      p.close();
    }
    return p;
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect.deflate(side.width));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(pathFor(rect.deflate(side.width / 2)), side.toPaint()..strokeJoin = StrokeJoin.miter);
  }

  @override
  ShapeBorder scale(double t) => PlateBorder(side: side.scale(t), slant: slant, point: point, flip: flip);
  @override
  PlateBorder copyWith({BorderSide? side}) => PlateBorder(side: side ?? this.side, slant: slant, point: point, flip: flip);
}

/// A rectangle with its corners cut at 45°: the panels.
class ChamferBorder extends OutlinedBorder {
  const ChamferBorder({super.side, this.cut = 10});
  final double cut;

  Path pathFor(Rect r) {
    final c = math.min(cut, math.min(r.width, r.height) / 3);
    return Path()
      ..moveTo(r.left + c, r.top)
      ..lineTo(r.right - c, r.top)
      ..lineTo(r.right, r.top + c)
      ..lineTo(r.right, r.bottom - c)
      ..lineTo(r.right - c, r.bottom)
      ..lineTo(r.left + c, r.bottom)
      ..lineTo(r.left, r.bottom - c)
      ..lineTo(r.left, r.top + c)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect.deflate(side.width));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => pathFor(rect);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(pathFor(rect.deflate(side.width / 2)), side.toPaint()..strokeJoin = StrokeJoin.miter);
  }

  @override
  ShapeBorder scale(double t) => ChamferBorder(side: side.scale(t), cut: cut * t);
  @override
  ChamferBorder copyWith({BorderSide? side}) => ChamferBorder(side: side ?? this.side, cut: cut);
}

/// The navy table behind every screen, as in the digital edition: a pool of warm lamplight in
/// the middle falling off to a dark rim, a fine cloth grain, and gold deco inlay (stepped frames
/// and long diagonals) at the table's edge. Painted once into its own layer (it only repaints on
/// resize), so it costs nothing per frame.
class TableBackground extends StatelessWidget {
  const TableBackground({super.key, this.child, this.tint, this.ornament = true});
  final Widget? child;

  /// A hero colour washed faintly into the light pool (hero select, VS).
  final Color? tint;
  final bool ornament;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(child: CustomPaint(painter: _TablePainter(tint, ornament))),
      ?child,
    ],
  );
}

/// A small tile of cloth grain, made once and repeated across the table.
abstract final class _Grain {
  static const size = 128;
  static ui.Image? image;
  static final ValueNotifier<int> ready = ValueNotifier(0);
  static bool _started = false;

  static void ensure() {
    if (_started) return;
    _started = true;
    final rnd = math.Random(7);
    final px = Uint8List(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      // speckles, light and dark, faint; alpha carries the strength (premultiplied: a white
      // speck's colour equals its alpha)
      final light = rnd.nextBool();
      final a = (rnd.nextDouble() * rnd.nextDouble() * (light ? 22 : 34)).round();
      final v = light ? a : 0;
      px[i * 4] = v;
      px[i * 4 + 1] = v;
      px[i * 4 + 2] = v;
      px[i * 4 + 3] = a;
    }
    ui.decodeImageFromPixels(px, size, size, ui.PixelFormat.rgba8888, (img) {
      image = img;
      ready.value++;
    });
  }
}

class _TablePainter extends CustomPainter {
  _TablePainter(this.tint, this.ornament) : super(repaint: _Grain.ready) {
    _Grain.ensure();
  }
  final Color? tint;
  final bool ornament;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final light = tint == null ? Palette.bgLit : Color.lerp(Palette.bgLit, tint, 0.24)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.1,
          colors: [light, Palette.bg, Palette.bgDeep],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    // The lamp's warm core, high in the middle.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.55),
          radius: 0.7,
          colors: [const Color(0xFFFFD9A0).withValues(alpha: 0.07), const Color(0x00FFD9A0)],
        ).createShader(rect),
    );
    final grain = _Grain.image;
    if (grain != null) {
      canvas.drawRect(
        rect,
        Paint()..shader = ImageShader(grain, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage, filterQuality: FilterQuality.none),
      );
    }
    // A soft vignette pulls the eye to the middle.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: const [Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
          stops: const [0, 0.62, 1],
        ).createShader(rect),
    );
    if (!ornament) return;
    final c = rect.center;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Palette.gold.withValues(alpha: 0.11);
    // Long diagonals from the corners toward the centre, stopping short of it.
    for (final corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      for (final k in [0.0, 0.035]) {
        final d = (c - corner);
        final a = corner + d * (0.02 + k);
        final b = corner + d * 0.42;
        canvas.drawLine(a + Offset(0, k * size.height), b + Offset(0, k * size.height), line);
      }
    }
    // Two stepped frames: the table's inlay.
    final m = size.shortestSide * 0.035;
    _stepFrame(canvas, rect.deflate(m), m * 0.9, line);
    _stepFrame(canvas, rect.deflate(m * 1.6), m * 0.9, line..color = Palette.gold.withValues(alpha: 0.06));
  }

  void _stepFrame(Canvas canvas, Rect r, double step, Paint p) {
    final path = Path()
      ..moveTo(r.left + step * 2, r.top)
      ..lineTo(r.right - step * 2, r.top)
      ..lineTo(r.right - step * 2, r.top + step)
      ..lineTo(r.right - step, r.top + step)
      ..lineTo(r.right - step, r.top + step * 2)
      ..lineTo(r.right, r.top + step * 2)
      ..lineTo(r.right, r.bottom - step * 2)
      ..lineTo(r.right - step, r.bottom - step * 2)
      ..lineTo(r.right - step, r.bottom - step)
      ..lineTo(r.right - step * 2, r.bottom - step)
      ..lineTo(r.right - step * 2, r.bottom)
      ..lineTo(r.left + step * 2, r.bottom)
      ..lineTo(r.left + step * 2, r.bottom - step)
      ..lineTo(r.left + step, r.bottom - step)
      ..lineTo(r.left + step, r.bottom - step * 2)
      ..lineTo(r.left, r.bottom - step * 2)
      ..lineTo(r.left, r.top + step * 2)
      ..lineTo(r.left + step, r.top + step * 2)
      ..lineTo(r.left + step, r.top + step)
      ..lineTo(r.left + step * 2, r.top + step)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_TablePainter old) => old.tint != tint || old.ornament != ornament;
}

/// A thin double rule with a diamond in the middle: the deco divider under titles.
class DecoRule extends StatelessWidget {
  const DecoRule({super.key, this.width = 220, this.color = Palette.gold, this.opacity = 0.7});
  final double width;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 12,
    child: CustomPaint(painter: _RulePainter(color.withValues(alpha: opacity))),
  );
}

class _RulePainter extends CustomPainter {
  _RulePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final y = size.height / 2;
    final cx = size.width / 2;
    const d = 5.0;
    canvas.drawLine(Offset(0, y - 2), Offset(cx - d - 4, y - 2), p);
    canvas.drawLine(Offset(size.width * 0.12, y + 2), Offset(cx - d - 4, y + 2), p);
    canvas.drawLine(Offset(cx + d + 4, y - 2), Offset(size.width, y - 2), p);
    canvas.drawLine(Offset(cx + d + 4, y + 2), Offset(size.width * 0.88, y + 2), p);
    canvas.drawPath(
      Path()
        ..moveTo(cx, y - d)
        ..lineTo(cx + d, y)
        ..lineTo(cx, y + d)
        ..lineTo(cx - d, y)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(_RulePainter old) => old.color != color;
}

/// A heart with a number in it: fighter health, as on the digital edition's board.
class HeartBadge extends StatelessWidget {
  const HeartBadge(this.value, {super.key, this.size = 30, this.color = Palette.heart, this.outline = Palette.bone});
  final int value;
  final double size;
  final Color color;
  final Color outline;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: HeartPainter(color, outline),
      child: Padding(
        padding: EdgeInsets.only(bottom: size * 0.12),
        child: Center(
          child: Text('$value', style: titleStyle(size * (value >= 10 ? 0.44 : 0.5), color: Colors.white, spacing: 0)),
        ),
      ),
    ),
  );
}

class HeartPainter extends CustomPainter {
  HeartPainter(this.color, this.outline);
  final Color color;
  final Color outline;

  static Path heart(Rect r) {
    final w = r.width, h = r.height;
    return Path()
      ..moveTo(r.left + w / 2, r.top + h * 0.95)
      ..cubicTo(r.left + w * 0.1, r.top + h * 0.62, r.left - w * 0.02, r.top + h * 0.32, r.left + w * 0.2, r.top + h * 0.14)
      ..cubicTo(r.left + w * 0.34, r.top + h * 0.03, r.left + w * 0.47, r.top + h * 0.1, r.left + w / 2, r.top + h * 0.24)
      ..cubicTo(r.left + w * 0.53, r.top + h * 0.1, r.left + w * 0.66, r.top + h * 0.03, r.left + w * 0.8, r.top + h * 0.14)
      ..cubicTo(r.left + w * 1.02, r.top + h * 0.32, r.left + w * 0.9, r.top + h * 0.62, r.left + w / 2, r.top + h * 0.95)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(size.width * 0.04);
    final path = heart(r);
    canvas.drawPath(path.shift(Offset(0, size.height * 0.05)), Paint()..color = const Color(0x99000000));
    canvas.drawPath(path, Paint()..color = outline);
    canvas.drawPath(heart(r.deflate(size.width * 0.08)), Paint()..color = color);
  }

  @override
  bool shouldRepaint(HeartPainter old) => old.color != color || old.outline != outline;
}
