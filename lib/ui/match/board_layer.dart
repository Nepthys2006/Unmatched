/// The live layer over the static board: highlights, tokens, fighters as glowing orbs, health
/// hearts and hit effects. Repaints on its own listenables only, never with the HUD.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/game.dart';
import '../../engine/state.dart';
import '../board/board_painter.dart';
import '../settings.dart';
import '../shapes.dart';
import '../theme.dart';

/// What the board should point out right now.
class BoardMarks {
  /// Fighters the player may pick (green pulse).
  final Set<Fighter> select = {};

  /// Fighters that would be hurt: attack targets (red reticle).
  final Set<Fighter> targets = {};
  final Set<int> spaces = {};
  final Set<(int, int)> edges = {};

  /// The fighter a space/path choice is about.
  Fighter? subject;

  /// Picked but not yet confirmed: a Fighter, a space id or an edge.
  Object? pending;
  List<int>? previewPath;

  /// Spaces whose choice is harmful (placing an enemy): drawn red instead of green.
  bool harmful = false;

  void clear() {
    select.clear();
    targets.clear();
    spaces.clear();
    edges.clear();
    subject = null;
    pending = null;
    previewPath = null;
    harmful = false;
  }

  bool get any => select.isNotEmpty || targets.isNotEmpty || spaces.isNotEmpty || edges.isNotEmpty;
}

/// A fighter walking along a path.
class MoveAnim {
  MoveAnim(this.fighter, this.path);
  final Fighter fighter;
  final List<int> path;
  double t = 0;
}

/// A rising number or burst at a fighter.
class Fx {
  Fx(this.at, this.text, this.color, {this.sparks = false}) : seed = math.Random().nextInt(1 << 20);
  final Offset at;
  final String text;
  final Color color;
  final bool sparks;
  final int seed;
}

class BoardLayerPainter extends CustomPainter {
  BoardLayerPainter({
    required this.game,
    required this.geo,
    required this.marks,
    required this.colorOf,
    required this.quality,
    required this.move,
    required this.pulse,
    required this.fxT,
    required this.fx,
    required this.focus,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Game game;
  final BoardGeometry geo;
  final BoardMarks marks;
  final Color Function(Player p) colorOf;
  final Quality quality;
  final ValueNotifier<MoveAnim?> move;
  final Animation<double> pulse;
  final Animation<double> fxT;
  final List<Fx> fx;

  /// Fighters in the current combat (drawn with a stronger halo).
  final Set<Fighter> focus;

  static final Map<String, TextPainter> _text = {};

  TextPainter _label(String s, double size, Color color, {bool title = true}) {
    final key = '$s|$size|${color.toARGB32()}|$title';
    if (_text.length > 300 && !_text.containsKey(key)) _text.clear();
    return _text[key] ??= (TextPainter(
      text: TextSpan(
        text: s,
        style: title ? titleStyle(size, color: color, spacing: 0.4) : bodyStyle(size, color: color, weight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  Offset _posOf(Fighter f) {
    final m = move.value;
    if (m != null && m.fighter == f && m.path.length > 1) {
      final segs = m.path.length - 1;
      final x = (m.t * segs).clamp(0.0, segs.toDouble());
      final i = math.min(x.floor(), segs - 1);
      final local = Curves.easeInOut.transform(x - i);
      return Offset.lerp(geo.of(m.path[i]), geo.of(m.path[i + 1]), local)!;
    }
    return geo.of(f.space!);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = geo.radius;
    final p = pulse.value;
    final glow = quality.glow;

    // Destination spaces.
    final spaceColor = marks.harmful ? Palette.target : Palette.select;
    for (final s in marks.spaces) {
      final c = geo.of(s);
      canvas.drawCircle(c, r * 1.02, Paint()..color = spaceColor.withValues(alpha: 0.22 + 0.12 * p));
      canvas.drawCircle(
        c,
        r * (1.08 + 0.05 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12
          ..color = spaceColor.withValues(alpha: 0.85),
      );
    }
    // Path preview to the pending space.
    final path = marks.previewPath;
    if (path != null && path.length > 1) {
      final line = Paint()
        ..color = Palette.bone
        ..strokeWidth = r * 0.14
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final pp = Path()..moveTo(geo.of(path.first).dx, geo.of(path.first).dy);
      for (final s in path.skip(1)) {
        pp.lineTo(geo.of(s).dx, geo.of(s).dy);
      }
      canvas.drawPath(
        pp,
        Paint()
          ..color = Colors.black54
          ..strokeWidth = r * 0.26
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(pp, line..strokeJoin = StrokeJoin.round);
    }
    if (marks.pending is int) {
      final c = geo.of(marks.pending! as int);
      canvas.drawCircle(
        c,
        r * 1.14,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.2
          ..color = Palette.bone,
      );
    }
    // Paths (Foot soldiers).
    for (final e in marks.edges) {
      final pending = marks.pending == e;
      canvas.drawLine(
        geo.of(e.$1),
        geo.of(e.$2),
        Paint()
          ..color = (pending ? Palette.bone : Palette.select).withValues(alpha: pending ? 1 : 0.55 + 0.3 * p)
          ..strokeWidth = r * (pending ? 0.34 : 0.24)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Tokens.
    for (final t in game.board.tokens) {
      if (t.kind == 'fog' && t.space != null) {
        final c = geo.of(t.space!);
        final cloud = Paint()..color = const Color(0xB3D6DCE4);
        for (final o in const [Offset(-0.45, 0.1), Offset(0.4, 0.15), Offset(0, -0.2), Offset(0.05, 0.3)]) {
          canvas.drawCircle(c + o * r, r * 0.5, cloud);
        }
      } else if (t.kind == 'trap' && t.space != null) {
        // Muldoon's traps: a steel jaw (orange ring with teeth).
        final c = geo.of(t.space!) + Offset(r * 0.55, r * 0.55);
        final jaw = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08
          ..color = const Color(0xFFF08A3C);
        canvas.drawCircle(c, r * 0.32, Paint()..color = const Color(0xE6202020));
        canvas.drawCircle(c, r * 0.32, jaw);
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(c + d * r * 0.12, c + d * r * 0.3, jaw);
        }
      } else if (t.kind == 'insight' && t.space != null) {
        // Dr. Sattler's insight tokens: small amber gems (several can share a space).
        final c = geo.of(t.space!);
        final n = game.board.tokens.where((o) => o.kind == 'insight' && o.space == t.space).toList().indexOf(t);
        final o = c + Offset(-r * 0.6 + n * r * 0.28, -r * 0.62);
        canvas.drawCircle(o, r * 0.2, Paint()..color = const Color(0xFFF2C14E));
        canvas.drawCircle(
          o,
          r * 0.2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.05
            ..color = const Color(0xFF3A2A08),
        );
      } else if (t.kind == 'shadow' && t.space != null) {
        // Spike's shadow tokens: a dark smoky disc (several can share a space).
        final c = geo.of(t.space!);
        final n = game.board.tokens.where((o) => o.kind == 'shadow' && o.space == t.space).toList().indexOf(t);
        final o = c + Offset(-r * 0.55 + n * r * 0.3, r * 0.55);
        canvas.drawCircle(o, r * 0.36, Paint()..color = const Color(0xE61A0F24));
        canvas.drawCircle(
          o,
          r * 0.36,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.07
            ..color = const Color(0xFFB04BE0),
        );
      } else if (t.path != null) {
        final a = geo.of(t.path!.$1), b = geo.of(t.path!.$2);
        final m = Offset.lerp(a, b, 0.5)!;
        final d = r * 0.32;
        final diamond = Path()
          ..moveTo(m.dx, m.dy - d)
          ..lineTo(m.dx + d, m.dy)
          ..lineTo(m.dx, m.dy + d)
          ..lineTo(m.dx - d, m.dy)
          ..close();
        canvas.drawPath(diamond, Paint()..color = const Color(0xFF1C1C1C));
        canvas.drawPath(
          diamond,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.08
            ..color = Palette.attacker,
        );
      }
    }

    // Fighters. A large fighter in two spaces (T. Rex) shows the back of her base as a band to a
    // smaller orb on the second space.
    for (final f in game.fighters) {
      if (!f.onBoard || f.tail == null || move.value?.fighter == f) continue;
      final a = geo.of(f.space!), b = geo.of(f.tail!);
      final color = colorOf(f.owner);
      canvas.drawLine(a, b, Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = r * 0.9
        ..strokeCap = StrokeCap.round);
      canvas.drawCircle(b, r * 0.5, Paint()..color = Color.lerp(color, Colors.black, 0.3)!);
      canvas.drawCircle(b, r * 0.5, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = Palette.bone.withValues(alpha: 0.7));
    }
    for (final f in game.fighters) {
      if (!f.onBoard) continue;
      _orb(canvas, f, _posOf(f), r, glow, p);
    }

    // Hit effects.
    final t = fxT.value;
    if (fx.isNotEmpty && t > 0 && t < 1) {
      for (final e in fx) {
        if (e.sparks && quality.particles) {
          final rnd = math.Random(e.seed);
          final sp = Paint()..color = e.color.withValues(alpha: (1 - t).clamp(0, 1));
          for (var i = 0; i < 14; i++) {
            final a = rnd.nextDouble() * math.pi * 2;
            final dist = r * (0.4 + rnd.nextDouble() * 1.2) * Curves.easeOut.transform(t);
            canvas.drawCircle(e.at + Offset(math.cos(a), math.sin(a)) * dist, r * 0.06 * (1 - t) + 1, sp);
          }
        }
        final tp = _label(e.text, r * 0.95, e.color);
        final rise = Curves.easeOutCubic.transform(t) * r * 1.4;
        final o = e.at - Offset(tp.width / 2, tp.height / 2 + r * 0.6 + rise);
        canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: t < 0.7 ? 1 : (1 - t) / 0.3));
        _label(e.text, r * 0.95, Colors.black).paint(canvas, o + const Offset(2, 3));
        tp.paint(canvas, o);
        canvas.restore();
      }
    }
  }

  void _orb(Canvas canvas, Fighter f, Offset c, double r, bool glow, double p) {
    final color = colorOf(f.owner);
    final rad = r * (f.isHero ? 0.8 : 0.58);
    final focused = focus.contains(f);
    if (glow) {
      // A radial gradient reads as the same soft glow as a blur at a fraction of the raster cost.
      final gr = rad * (focused ? 2.2 : 1.9);
      canvas.drawCircle(
        c,
        gr,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: focused ? 0.85 : 0.65), color.withValues(alpha: focused ? 0.35 : 0.22), color.withValues(alpha: 0)],
            stops: const [0.35, 0.6, 1],
          ).createShader(Rect.fromCircle(center: c, radius: gr)),
      );
    } else {
      canvas.drawCircle(c, rad * 1.18, Paint()..color = color.withValues(alpha: 0.35));
    }
    canvas.drawCircle(c + Offset(0, rad * 0.18), rad, Paint()..color = const Color(0x99000000));
    final rect = Rect.fromCircle(center: c, radius: rad);
    canvas.drawCircle(
      c,
      rad,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [Color.lerp(color, Colors.white, 0.65)!, color, Color.lerp(color, Colors.black, 0.55)!],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      rad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.1
        ..color = Palette.bone.withValues(alpha: 0.9),
    );
    if (f.isHero) {
      // Heroes wear a crown notch: a second inner ring.
      canvas.drawCircle(
        c,
        rad * 0.72,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rad * 0.06
          ..color = Colors.white.withValues(alpha: 0.55),
      );
    }
    // Initial letter so fighters of one colour stay distinguishable.
    final initial = f.isHero
        ? f.name.characters.first.toUpperCase()
        : (f.def.count > 1 ? '${f.ordinal}' : f.kind.characters.first.toUpperCase());
    final it = _label(initial, rad * 0.95, Colors.white);
    it.paint(canvas, c - Offset(it.width / 2, it.height / 2 + rad * 0.04));

    // Name tag under the orb.
    final name = _label(f.name.toUpperCase(), r * 0.34, Palette.bone);
    final tag = Rect.fromCenter(center: c + Offset(0, rad + r * 0.34), width: name.width + r * 0.24, height: name.height + r * 0.06);
    canvas.drawRRect(RRect.fromRectAndRadius(tag, Radius.circular(r * 0.06)), Paint()..color = const Color(0xCC0E0F12));
    name.paint(canvas, tag.topLeft + Offset(r * 0.12, r * 0.03));

    // Health heart.
    final hs = r * (f.isHero ? 0.66 : 0.54);
    final hRect = Rect.fromCenter(center: c + Offset(rad * 0.85, -rad * 0.8), width: hs, height: hs);
    canvas
      ..save()
      ..translate(hRect.left, hRect.top);
    HeartPainter(Palette.heart, Palette.bone).paint(canvas, hRect.size);
    canvas.restore();
    final hp = _label('${f.hp}', hs * 0.48, Colors.white);
    hp.paint(canvas, hRect.center - Offset(hp.width / 2, hp.height / 2 + hs * 0.06));

    // Selection marks.
    if (marks.select.contains(f) || marks.pending == f) {
      final pend = marks.pending == f;
      canvas.drawCircle(
        c,
        rad * (1.32 + (pend ? 0 : 0.1 * p)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rad * (pend ? 0.2 : 0.13)
          ..color = pend ? Palette.bone : Palette.select.withValues(alpha: 0.7 + 0.3 * p),
      );
    }
    if (marks.targets.contains(f)) {
      final rr = rad * (1.42 + 0.08 * p);
      final red = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.12
        ..color = Palette.target.withValues(alpha: 0.75 + 0.25 * p);
      canvas.drawCircle(c, rr, red);
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + d * rr * 0.82, c + d * rr * 1.22, red);
      }
    }
    if (marks.subject == f) {
      canvas.drawCircle(
        c,
        rad * 1.3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rad * 0.1
          ..color = Palette.bone.withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(BoardLayerPainter old) => true;
}

/// A breathing 0..1 value for highlights, stepped by a timer at ~20 fps instead of every vsync.
/// On the web every frame re-rasterises the whole scene, so a 60 fps ticker running for as long
/// as a prompt is open would cost a full redraw per vsync for a subtle effect.
class SteppedPulse extends Animation<double>
    with AnimationEagerListenerMixin, AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  SteppedPulse({this.period = const Duration(milliseconds: 900), this.step = const Duration(milliseconds: 50)});
  final Duration period;
  final Duration step;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  double _value = 0;

  @override
  double get value => _value;
  @override
  AnimationStatus get status => _timer == null ? AnimationStatus.dismissed : AnimationStatus.forward;
  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(step, (_) {
      final t = _clock.elapsedMicroseconds / period.inMicroseconds;
      _value = 0.5 - 0.5 * math.cos(t * 2 * math.pi);
      notifyListeners();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    if (_value != 0) {
      _value = 0;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    clearListeners();
    clearStatusListeners();
    super.dispose();
  }
}
