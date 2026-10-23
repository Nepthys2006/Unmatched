/// Health dials like the printed game's: a numbered wheel that turns so the current health sits
/// under the window at the top. Damage and healing turn it (animated). Also the fan of card
/// backs that shows how many cards an opponent holds.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../../engine/state.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

class HealthDial extends StatelessWidget {
  const HealthDial({super.key, required this.hp, required this.max, required this.color, this.size = 44, this.defeated = false});
  final int hp;

  /// The highest number printed on the wheel (the fighter's starting health, or more if healed
  /// above it).
  final int max;
  final Color color;
  final double size;
  final bool defeated;

  @override
  Widget build(BuildContext context) => Semantics(
    label: defeated ? 'Defeated' : '$hp health',
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: hp.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (_, v, _) => CustomPaint(
        size: Size.square(size),
        painter: _DialPainter(value: v, hp: hp, max: math.max(max, hp), color: color, defeated: defeated),
      ),
    ),
  );
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.value, required this.hp, required this.max, required this.color, required this.defeated});
  final double value;
  final int hp;
  final int max;
  final Color color;
  final bool defeated;

  static final Map<String, TextPainter> _cache = {};
  TextPainter _text(String s, double size, Color c, {FontWeight w = FontWeight.w700}) {
    final key = '$s|$size|${c.toARGB32()}|${w.value}';
    if (_cache.length > 400) _cache.clear();
    return _cache[key] ??= (TextPainter(
      text: TextSpan(text: s, style: titleStyle(size, color: c, weight: w, spacing: 0)),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final n = max + 1; // 0..max around the wheel
    final step = 2 * math.pi / n;

    // The wheel: hero colour rim, dark face, numbers around the edge.
    canvas.drawCircle(c + Offset(0, r * 0.06), r, Paint()..color = const Color(0x88000000));
    canvas.drawCircle(c, r, Paint()..color = defeated ? Palette.panel : Color.lerp(color, Colors.black, 0.35)!);
    canvas.drawCircle(c, r * 0.8, Paint()..color = const Color(0xFF15161A));
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(-value * step);
    final showNumbers = size.width >= 40;
    for (var i = 0; i < n; i++) {
      final a = i * step - math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      if (showNumbers) {
        final tp = _text('$i', r * 0.26, i == 0 ? Palette.danger : Palette.boneDim, w: FontWeight.w600);
        canvas
          ..save()
          ..translate(dir.dx * r * 0.9, dir.dy * r * 0.9)
          ..rotate(a + math.pi / 2);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      } else {
        canvas.drawLine(dir * r * 0.82, dir * r * 0.97, Paint()
          ..color = Palette.bone.withValues(alpha: 0.5)
          ..strokeWidth = 1);
      }
    }
    canvas.restore();

    // The window at the top and the current value in the middle.
    final win = Path()
      ..moveTo(c.dx - r * 0.2, 0)
      ..lineTo(c.dx + r * 0.2, 0)
      ..lineTo(c.dx, r * 0.24)
      ..close();
    canvas.drawPath(win, Paint()..color = Palette.bone);
    final low = !defeated && hp <= 3;
    final tp = _text(defeated ? '✕' : '$hp', r * 0.82, defeated ? Palette.muted : (low ? Palette.danger : Colors.white), w: FontWeight.w800);
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2 - r * 0.04));
    canvas.drawCircle(c, r - 0.75, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Palette.bone.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.value != value || old.hp != hp || old.color != color || old.defeated != defeated;
}

/// A player's hero dial plus a small dial per sidekick (marked with the sidekick's token).
class FighterDials extends StatelessWidget {
  const FighterDials({super.key, required this.player, required this.color, this.heroSize = 44, this.sidekickSize = 28});
  final Player player;
  final Color color;
  final double heroSize;
  final double sidekickSize;

  @override
  Widget build(BuildContext context) {
    final hero = player.heroFighter;
    final sidekicks = player.fighters.where((f) => f.isSidekick && !f.reserve || f.isSidekick && f.defeated).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Tooltip(
          message: '${hero.name}: ${hero.hp} health',
          child: HealthDial(hp: hero.hp, max: hero.maxHp, color: color, size: heroSize, defeated: hero.defeated),
        ),
        for (final f in sidekicks) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: '${f.name}: ${f.defeated ? 'defeated' : '${f.hp} health'}',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HealthDial(hp: f.hp, max: f.maxHp, color: color, size: sidekickSize, defeated: f.defeated),
                const SizedBox(height: 1),
                SizedBox(
                  width: sidekickSize + 6,
                  child: Text(
                    f.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: titleStyle(8.5, color: Palette.boneDim, spacing: 0.2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// An opponent's hand as fanned card backs with the count, so you can see how many they hold.
class HandBacks extends StatelessWidget {
  const HandBacks({super.key, required this.count, required this.back, this.height = 30});
  final int count;
  final String back;
  final double height;

  @override
  Widget build(BuildContext context) {
    final w = height * cardAspect;
    final shown = math.min(count, 8);
    final spacing = w * 0.42;
    final width = shown == 0 ? w : w + spacing * (shown - 1);
    return Tooltip(
      message: '$count card${count == 1 ? '' : 's'} in hand',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (shown == 0)
                  Container(
                    width: w,
                    height: height,
                    decoration: ShapeDecoration(shape: ChamferBorder(cut: 3, side: BorderSide(color: Palette.bone.withValues(alpha: 0.25)))),
                  ),
                for (var i = 0; i < shown; i++)
                  Positioned(
                    left: spacing * i,
                    top: 0,
                    child: Transform.rotate(
                      angle: shown == 1 ? 0 : (i / (shown - 1) - 0.5) * 0.35,
                      alignment: Alignment.bottomCenter,
                      child: CardImage(back, width: w),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text('$count', style: titleStyle(height * 0.55, spacing: 0)),
        ],
      ),
    );
  }
}
