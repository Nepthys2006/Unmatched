/// The live layer over the static board: highlights, tokens, fighters as their miniatures on
/// podiums (orbs until the pictures load), health hearts, the heroes' pieces and hit effects. Repaints on its own listenables only, never with the HUD.
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
import 'figure_art.dart';
import 'hero_items.dart';

/// Where [f] is drawn relative to its space's centre (small fighters sharing a space fan out).
Offset slotOffset(Game game, Fighter f, double radius) {
  final (x, y) = game.offsetInSpace(f);
  return Offset(x, y) * radius;
}

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
  static final Map<String, Shader> _shaders = {};

  static Shader _cachedShader(String key, Shader Function() create) {
    if (_shaders.length > 300 && !_shaders.containsKey(key)) _shaders.clear();
    return _shaders[key] ??= create();
  }

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
    return geo.of(f.space!) + slotOffset(game, f, geo.radius);
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
        // Invisible Man's fog: a cloud with a shadow and a dark outline, so it reads on light and
        // dark boards alike.
        final c = geo.of(t.space!);
        const puffs = [(Offset(-0.48, 0.12), 0.46), (Offset(0.44, 0.16), 0.44), (Offset(0, -0.22), 0.56), (Offset(0.02, 0.3), 0.5), (Offset(-0.26, -0.1), 0.42), (Offset(0.28, -0.08), 0.42)];
        final cloud = Path();
        for (final (o, s) in puffs) {
          cloud.addOval(Rect.fromCircle(center: c + o * r, radius: r * s));
        }
        canvas.drawShadow(cloud, const Color(0xFF000000), r * 0.18, false);
        canvas.drawPath(
          cloud,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.12
            ..color = const Color(0xFF39404E),
        );
        canvas.drawPath(
          cloud,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.4),
              colors: const [Color(0xFFFBFCFF), Color(0xFFCDD4E2), Color(0xFF8E98AE)],
              stops: const [0, 0.55, 1],
            ).createShader(Rect.fromCircle(center: c, radius: r)),
        );
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
        final alpha = t < 0.7 ? 1.0 : ((1.0 - t) / 0.3).clamp(0.0, 1.0);
        final tp = _label(e.text, r * 0.95, e.color.withValues(alpha: alpha));
        final rise = Curves.easeOutCubic.transform(t) * r * 1.4;
        final o = e.at - Offset(tp.width / 2, tp.height / 2 + r * 0.6 + rise);
        _label(e.text, r * 0.95, Colors.black.withValues(alpha: 0.75 * alpha)).paint(canvas, o + const Offset(2, 3));
        tp.paint(canvas, o);
      }
    }
  }

  /// A fighter as its miniature (or token) on a podium in its player's colour, or as an orb while
  /// the picture loads. Selection rings, the heart and the name tag are the same for both.
  void _orb(Canvas canvas, Fighter f, Offset c, double r, bool glow, double p) {
    final art = FigureArt.instance.of(f);
    if (art != null) {
      _figure(canvas, f, c, r, glow, p, art);
      return;
    }
    final color = colorOf(f.owner);
    final rad = r * (f.isHero ? 0.8 : (f.isSmall ? 0.4 : 0.58));
    final focused = focus.contains(f);
    if (glow) {
      // A radial gradient reads as the same soft glow as a blur at a fraction of the raster cost.
      final gr = rad * (focused ? 2.2 : 1.9);
      final keyGlow = 'orb_glow|${c.dx.toInt()}|${c.dy.toInt()}|${gr.toInt()}|${color.toARGB32()}|$focused';
      canvas.drawCircle(
        c,
        gr,
        Paint()
          ..shader = _cachedShader(
            keyGlow,
            () => RadialGradient(
              colors: [color.withValues(alpha: focused ? 0.85 : 0.65), color.withValues(alpha: focused ? 0.35 : 0.22), color.withValues(alpha: 0)],
              stops: const [0.35, 0.6, 1],
            ).createShader(Rect.fromCircle(center: c, radius: gr)),
          ),
      );
    } else {
      canvas.drawCircle(c, rad * 1.18, Paint()..color = color.withValues(alpha: 0.35));
    }
    canvas.drawCircle(c + Offset(0, rad * 0.18), rad, Paint()..color = const Color(0x99000000));
    final rect = Rect.fromCircle(center: c, radius: rad);
    final keyTop = 'orb_top|${c.dx.toInt()}|${c.dy.toInt()}|${rad.toInt()}|${color.toARGB32()}';
    canvas.drawCircle(
      c,
      rad,
      Paint()
        ..shader = _cachedShader(
          keyTop,
          () => RadialGradient(
            center: const Alignment(-0.35, -0.45),
            colors: [Color.lerp(color, Colors.white, 0.65)!, color, Color.lerp(color, Colors.black, 0.55)!],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
        ),
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

    _nameHeartMarks(canvas, f, c, r, rad, p, c + Offset(rad * 0.85, -rad * 0.8));
  }

  void _figure(Canvas canvas, Fighter f, Offset c, double r, bool glow, double p, FigureImage art) {
    final color = colorOf(f.owner);
    final rad = r * (f.isHero ? 0.62 : (f.isSmall ? 0.34 : 0.48));
    final focused = focus.contains(f);
    if (glow) {
      final gr = rad * (focused ? 2.1 : 1.7);
      final keyGlow = 'fig_glow|${c.dx.toInt()}|${c.dy.toInt()}|${gr.toInt()}|${color.toARGB32()}|$focused';
      canvas.drawCircle(
        c,
        gr,
        Paint()
          ..shader = _cachedShader(
            keyGlow,
            () => RadialGradient(
              colors: [color.withValues(alpha: focused ? 0.8 : 0.55), color.withValues(alpha: 0)],
            ).createShader(Rect.fromCircle(center: c, radius: gr)),
          ),
      );
    }
    // Podium: a short disc seen from above at a slant.
    final top = Rect.fromCenter(center: c, width: rad * 2, height: rad * 1.1);
    final side = top.shift(Offset(0, rad * 0.22));
    canvas.drawOval(side.shift(Offset(0, rad * 0.1)), Paint()..color = const Color(0x88000000));
    canvas.drawOval(side, Paint()..color = Color.lerp(color, Colors.black, 0.45)!);
    canvas.drawRect(Rect.fromLTRB(top.left, top.center.dy, top.right, side.center.dy), Paint()..color = Color.lerp(color, Colors.black, 0.45)!);
    final keyPod = 'fig_pod|${c.dx.toInt()}|${c.dy.toInt()}|${rad.toInt()}|${color.toARGB32()}';
    canvas.drawOval(
      top,
      Paint()
        ..shader = _cachedShader(
          keyPod,
          () => RadialGradient(
            center: const Alignment(-0.3, -0.5),
            colors: [Color.lerp(color, Colors.white, 0.35)!, color],
          ).createShader(top),
        ),
    );
    canvas.drawOval(top, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rad * 0.07
      ..color = Palette.bone.withValues(alpha: 0.8));

    // The figure stands on the podium: its printed base as wide as the podium (real proportions),
    // capped in height so it doesn't hide the spaces behind; a token stands a little wider.
    final img = art.image;
    var scale = art.token ? rad * 2.1 / img.width : rad * 2 * 0.98 / art.baseW;
    final maxH = r * (f.isHero ? 2.3 : 1.5);
    if (img.height * scale > maxH) scale = maxH / img.height;
    final w = img.width * scale, h = img.height * scale;
    final left = art.token ? c.dx - w / 2 : c.dx - art.baseX * scale;
    final dst = Rect.fromLTWH(left, c.dy + rad * 0.12 - h, w, h);
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst,
        Paint()..filterQuality = quality.filterQuality);

    // The hero's pieces (Alice's card, Hellfire...) float beside the main hero.
    if (f == f.owner.heroFighter) _items(canvas, f.owner, Offset(dst.left - r * 0.08, dst.top + r * 0.1), r);
    _nameHeartMarks(canvas, f, c, r, rad, p, Offset(math.min(dst.right, c.dx + rad * 1.1), dst.top + r * 0.22));
  }

  /// Small pieces stacked down the left of the figure: an icon and a count or name each.
  void _items(Canvas canvas, Player owner, Offset at, double r) {
    var y = at.dy;
    for (final i in heroItems(owner).take(2)) {
      final icon = TextPainter(
        text: TextSpan(text: String.fromCharCode(i.icon.codePoint), style: TextStyle(fontFamily: i.icon.fontFamily, package: i.icon.fontPackage, fontSize: r * 0.36, color: i.color)),
        textDirection: TextDirection.ltr,
      )..layout();
      final text = _label(i.kind == HeroItemKind.card ? i.label : i.short, r * 0.27, Colors.white);
      final w = icon.width + text.width + r * 0.22, h = math.max(icon.height, text.height) + r * 0.06;
      final box = Rect.fromLTWH(at.dx - w, y, w, h);
      final rr = RRect.fromRectAndRadius(box, Radius.circular(r * 0.08));
      canvas.drawRRect(rr, Paint()..color = const Color(0xE60E0F12));
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..color = i.color);
      icon.paint(canvas, Offset(box.left + r * 0.07, box.center.dy - icon.height / 2));
      text.paint(canvas, Offset(box.left + r * 0.1 + icon.width, box.center.dy - text.height / 2));
      y += h + r * 0.06;
    }
  }

  void _nameHeartMarks(Canvas canvas, Fighter f, Offset c, double r, double rad, double p, Offset heartAt) {
    // Name tag under the fighter.
    final name = _label(f.name.toUpperCase(), r * 0.34, Palette.bone);
    final tag = Rect.fromCenter(center: c + Offset(0, rad + r * 0.34), width: name.width + r * 0.24, height: name.height + r * 0.06);
    canvas.drawRRect(RRect.fromRectAndRadius(tag, Radius.circular(r * 0.06)), Paint()..color = const Color(0xCC0E0F12));
    name.paint(canvas, tag.topLeft + Offset(r * 0.12, r * 0.03));

    // Health heart.
    final hs = r * (f.isHero ? 0.66 : 0.54);
    final hRect = Rect.fromCenter(center: heartAt, width: hs, height: hs);
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
  SteppedPulse({this.period = const Duration(milliseconds: 900), this.step = const Duration(milliseconds: 33)});
  final Duration period;
  Duration step;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  double _value = 0;

  @override
  double get value => _value;
  @override
  AnimationStatus get status => _timer == null ? AnimationStatus.dismissed : AnimationStatus.forward;
  bool get running => _timer != null;

  void start([Duration? customStep]) {
    if (_timer != null) return;
    if (customStep != null) step = customStep;
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
