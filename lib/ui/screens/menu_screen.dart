/// Main menu: three miniatures on a lit plinth, the wordmark and the menu plates.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../audio.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  List<HeroDef> _trio = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.services;
    s.audio.music(Music.menu);
    if (_trio.isEmpty && s.loaded) {
      final all = s.data.heroes.values.toList()..shuffle(math.Random());
      _trio = all.take(3).toList();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(gameSnack('$what is coming soon. For now, battle the AI.'));
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) {
      context.services.audio.music(Music.menu);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final s = context.services;
    final h = size.height;
    final plateH = (h * 0.12).clamp(48.0, 76.0);
    final font = (h * 0.026).clamp(18.0, 26.0);
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return Scaffold(
      body: TableBackground(
        child: SafeArea(
          child: Stack(
            children: [
              // Left: the trio of miniatures on a lit plinth.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: size.width * 0.55,
                child: FadeTransition(
                  opacity: fade,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(-0.04, 0), end: Offset.zero).animate(fade),
                    child: _Plinth(trio: _trio),
                  ),
                ),
              ),
              // Right: wordmark and menu.
              Positioned(
                right: size.width * 0.05,
                top: 0,
                bottom: 0,
                width: (size.width * 0.4).clamp(280.0, 540.0),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('UNMATCHED', style: titleStyle((h * 0.14).clamp(40, 84), spacing: 5)),
                        ),
                        Row(
                          children: [
                            const Expanded(child: DecoRule(width: 400, opacity: 0.45)),
                            const SizedBox(width: 10),
                            Text('FAN EDITION', style: titleStyle(12, color: Palette.brass, spacing: 2.4)),
                          ],
                        ),
                        SizedBox(height: h * 0.05),
                        PlateButton(
                          label: 'Play vs AI',
                          subtitle: '1v1 · teams · free-for-all',
                          icon: Icons.play_arrow_rounded,
                          height: plateH * 1.18,
                          fontSize: font + 4,
                          onPressed: () => _open(const SetupScreen()),
                        ),
                        SizedBox(height: h * 0.03),
                        PlateButton(
                          label: 'LAN',
                          subtitle: 'Same Wi-Fi or phone hotspot',
                          icon: Icons.wifi_tethering_rounded,
                          badge: 'Coming soon',
                          style: PlateStyle.secondary,
                          height: plateH,
                          fontSize: font,
                          onPressed: () => _soon('LAN play'),
                        ),
                        SizedBox(height: h * 0.03),
                        PlateButton(
                          label: 'Online',
                          subtitle: 'Play friends anywhere',
                          icon: Icons.public_rounded,
                          badge: 'Coming soon',
                          style: PlateStyle.secondary,
                          height: plateH,
                          fontSize: font,
                          onPressed: () => _soon('Online play'),
                        ),
                        SizedBox(height: h * 0.03),
                        PlateButton(
                          label: 'Settings',
                          icon: Icons.tune_rounded,
                          style: PlateStyle.secondary,
                          height: plateH,
                          fontSize: font,
                          onPressed: () => _open(const SettingsScreen()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom left: who is playing.
              Positioned(
                left: 16,
                bottom: 12,
                child: _NamePlate(name: s.settings.username, onTap: () => _open(const SettingsScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Plinth extends StatelessWidget {
  const _Plinth({required this.trio});
  final List<HeroDef> trio;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final h = c.maxHeight;
      final w = c.maxWidth;
      final mainH = h * 0.78;
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // The pool of light the figures stand in.
          Positioned(
            bottom: h * 0.05,
            child: Container(
              width: w * 0.86,
              height: h * 0.2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.elliptical(w * 0.43, h * 0.1)),
                gradient: RadialGradient(
                  colors: [Palette.bone.withValues(alpha: 0.2), Palette.bone.withValues(alpha: 0.04), Colors.transparent],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ),
          if (trio.length == 3) ...[
            _figure(trio[1], left: w * 0.02, height: mainH * 0.74, bottom: h * 0.1, opacity: 0.75),
            _figure(trio[2], left: w * 0.56, height: mainH * 0.74, bottom: h * 0.1, opacity: 0.75),
            _figure(trio[0], left: w * 0.24, height: mainH, bottom: h * 0.06, opacity: 1),
          ],
        ],
      );
    },
  );

  Widget _figure(HeroDef hero, {required double left, required double height, required double bottom, required double opacity}) =>
      Positioned(
        left: left,
        bottom: bottom,
        height: height,
        child: Semantics(
          label: hero.name,
          image: true,
          child: Opacity(
            opacity: opacity,
            child: Image.asset(hero.mini, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
      );
}

class _NamePlate extends StatelessWidget {
  const _NamePlate({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Player $name. Open settings',
    child: GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 40,
            decoration: ShapeDecoration(
              color: Palette.panel,
              shape: HexBorder(side: BorderSide(color: Palette.bone.withValues(alpha: 0.7), width: 1.5)),
            ),
            child: const Icon(Icons.person_rounded, color: Palette.bone, size: 22),
          ),
          Container(
            height: 30,
            padding: const EdgeInsets.only(left: 12, right: 22),
            decoration: ShapeDecoration(
              color: Palette.panel,
              shape: PlateBorder(side: BorderSide(color: Palette.bone.withValues(alpha: 0.3))),
            ),
            alignment: Alignment.center,
            child: Text(name.toUpperCase(), style: titleStyle(15, spacing: 1.2)),
          ),
        ],
      ),
    ),
  );
}

/// A snackbar in the game's style.
SnackBar gameSnack(String text) => SnackBar(
  behavior: SnackBarBehavior.floating,
  width: 460,
  backgroundColor: Palette.panelHi,
  shape: ChamferBorder(cut: 8, side: BorderSide(color: Palette.bone.withValues(alpha: 0.4))),
  duration: const Duration(seconds: 3),
  content: Text(text, style: bodyStyle(15)),
);
