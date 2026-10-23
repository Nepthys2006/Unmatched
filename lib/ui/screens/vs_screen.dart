/// The VS intro: your side slams in from the left, the opposition from the right.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../audio.dart';
import '../match/match_config.dart';
import '../match/match_screen.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../../net/session.dart';

class VsScreen extends StatefulWidget {
  const VsScreen({super.key, required this.config, this.net});
  final MatchConfig config;
  final NetMatch? net;
  @override
  State<VsScreen> createState() => _VsScreenState();
}

class _VsScreenState extends State<VsScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2900));
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _a.forward();
    _a.addStatusListener((s) {
      if (s == AnimationStatus.completed) _go();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audio = context.services.audio;
    audio.stopMusic();
    Future<void>.delayed(const Duration(milliseconds: 120), () => audio.sfx(Sfx.whoosh));
    Future<void>.delayed(const Duration(milliseconds: 520), () => audio.sfx(Sfx.hit, volume: 0.8));
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    unawaited(
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, _, _) => MatchScreen(config: widget.config, net: widget.net),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final data = context.services.data;
    final heroes = [for (final id in c.heroIds) data.hero(id)];
    final teams = c.teams;
    final me = widget.net?.localSeat ?? 0;
    final mine = <int>[
      me,
      if (teams != null) ...[
        for (var i = 0; i < heroes.length; i++)
          if (i != me && teams[i] == teams[me]) i,
      ],
    ];
    final theirs = [
      for (var i = 0; i < heroes.length; i++)
        if (!mine.contains(i)) i,
    ];
    final username = context.services.settings.username;
    String who(int seat) => seat == me ? username : (widget.net?.names.value[seat] ?? 'AI ${c.ai.label}');

    final inL = CurvedAnimation(
      parent: _a,
      curve: const Interval(0, 0.18, curve: Curves.easeOutCubic),
    );
    final inR = CurvedAnimation(
      parent: _a,
      curve: const Interval(0.05, 0.23, curve: Curves.easeOutCubic),
    );
    final vs = CurvedAnimation(
      parent: _a,
      curve: const Interval(0.16, 0.3, curve: Curves.easeOutBack),
    );
    final out = CurvedAnimation(
      parent: _a,
      curve: const Interval(0.88, 1, curve: Curves.easeIn),
    );

    return Scaffold(
      backgroundColor: Palette.bgDeep,
      body: Semantics(
        button: true,
        label: 'Skip intro',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _go,
          child: AnimatedBuilder(
            animation: _a,
            builder: (context, _) {
              final size = MediaQuery.sizeOf(context);
              return Opacity(
                opacity: 1 - out.value,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.translate(
                      offset: Offset(-size.width * 0.6 * (1 - inL.value), 0),
                      child: ClipPath(
                        clipper: _HalfClipper(left: true),
                        child: _Side(heroes: [for (final i in mine) heroes[i]], labels: [for (final i in mine) who(i)], left: true),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(size.width * 0.6 * (1 - inR.value), 0),
                      child: ClipPath(
                        clipper: _HalfClipper(left: false),
                        child: _Side(heroes: [for (final i in theirs) heroes[i]], labels: [for (final i in theirs) who(i)], left: false),
                      ),
                    ),
                    // The seam between the halves.
                    IgnorePointer(child: CustomPaint(painter: _SeamPainter(inR.value))),
                    Center(
                      child: Transform.scale(
                        scale: vs.value.clamp(0, 1.2),
                        child: Container(
                          width: size.height * 0.3,
                          height: size.height * 0.26,
                          decoration: const ShapeDecoration(
                            color: Palette.bgDeep,
                            shape: HexBorder(side: BorderSide(color: Palette.bone, width: 2.5)),
                            shadows: [BoxShadow(color: Colors.black, blurRadius: 24)],
                          ),
                          alignment: Alignment.center,
                          child: Text('VS', style: titleStyle(size.height * 0.12, spacing: 2)),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: size.height * 0.05,
                      child: Opacity(
                        opacity: vs.value.clamp(0, 1),
                        child: Column(
                          children: [
                            Text(c.map.name.toUpperCase(), style: titleStyle(18, spacing: 3)),
                            Text('${c.mode.label} · AI ${c.ai.label}', style: bodyStyle(13, color: Palette.boneDim)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      top: 12,
                      child: SafeArea(
                        child: Text('TAP TO SKIP', style: titleStyle(12, color: Palette.muted, spacing: 1.6)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.heroes, required this.labels, required this.left});
  final List<HeroDef> heroes;
  final List<String> labels;
  final bool left;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final lead = hexColor(heroes.first.color);
    final n = heroes.length;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: [plateColor(lead), Color.lerp(plateColor(lead), Palette.bgDeep, 0.7)!],
        ),
      ),
      child: Align(
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        child: SizedBox(
          width: size.width * 0.5,
          child: Padding(
            padding: EdgeInsets.only(
              left: left ? 24 : size.width * 0.08,
              right: left ? size.width * 0.08 : 24,
              top: 20,
              bottom: size.height * 0.16,
            ),
            child: Row(
              mainAxisAlignment: left ? MainAxisAlignment.start : MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < n; i++)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Image.asset(heroes[i].mini, fit: BoxFit.contain, height: size.height * (n == 1 ? 0.62 : 0.5)),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(16, 3, 22, 3),
                              decoration: ShapeDecoration(
                                color: Palette.bgDeep.withValues(alpha: 0.85),
                                shape: PlateBorder(side: BorderSide(color: Palette.bone.withValues(alpha: 0.6))),
                              ),
                              child: Column(
                                children: [
                                  Text(heroes[i].name.toUpperCase(), style: titleStyle(n == 1 ? 30 : 18, spacing: 1)),
                                  Text(
                                    labels[i],
                                    style: bodyStyle(n == 1 ? 15 : 12, color: Palette.boneDim, weight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Each half is cut along a slanted line through the centre.
class _HalfClipper extends CustomClipper<Path> {
  _HalfClipper({required this.left});
  final bool left;
  @override
  Path getClip(Size s) {
    final top = s.width * 0.56, bottom = s.width * 0.44;
    return left
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(top, 0)
            ..lineTo(bottom, s.height)
            ..lineTo(0, s.height)
            ..close())
        : (Path()
            ..moveTo(top, 0)
            ..lineTo(s.width, 0)
            ..lineTo(s.width, s.height)
            ..lineTo(bottom, s.height)
            ..close());
  }

  @override
  bool shouldReclip(_HalfClipper old) => old.left != left;
}

class _SeamPainter extends CustomPainter {
  _SeamPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size s) {
    if (t <= 0) return;
    final a = Offset(s.width * 0.56, 0), b = Offset(s.width * 0.44, s.height);
    canvas.drawLine(
      a,
      Offset.lerp(a, b, t)!,
      Paint()
        ..color = Palette.bone
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SeamPainter old) => old.t != t;
}
