/// Main menu: three miniatures on a lit plinth, the wordmark and the menu plates.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../audio.dart';
import '../match/fullscreen_button.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_screen.dart';
import 'multiplayer_screen.dart';
import 'setup_screen.dart';
import '../dialogs/active_players_drawer.dart';
import '../dialogs/player_profile_modal.dart';
import 'dart:async';
import '../../net/online_presence.dart';
import '../../net/profile_stats.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  List<HeroDef> _trio = const [];
  bool _musicAsked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.services;
    // Once, when the menu opens. This runs again on every resize or minimize (build reads
    // MediaQuery), and the menu stays mounted under a match: asking again would put the menu
    // theme over the battle music. Coming back from another screen is handled in _open.
    if (!_musicAsked) {
      _musicAsked = true;
      s.audio.music(Music.menu);
    }
    if (_trio.isEmpty && s.loaded) {
      final all = s.data.heroes.values.toList()..shuffle(math.Random());
      _trio = all.take(3).toList();
    }
    unawaited(
      OnlinePresenceService.instance.start(
        playerId: s.settings.playerId,
        username: s.settings.username,
      ),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
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
                            Text('FAN MADE', style: titleStyle(12, color: Palette.brass, spacing: 2.4)),
                          ],
                        ),
                        SizedBox(height: h * 0.05),
                        if (s.settings.hasActiveReconnect) ...[
                          PlateButton(
                            label: 'Rejoin match',
                            subtitle: 'Your match is still running',
                            icon: Icons.login_rounded,
                            style: PlateStyle.confirm,
                            height: plateH,
                            fontSize: font,
                            onPressed: () => _open(
                              MultiplayerScreen(online: (s.settings.reconnectTopic ?? '').isNotEmpty, autoRejoin: true),
                            ),
                          ),
                          SizedBox(height: h * 0.03),
                        ],
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
                          style: PlateStyle.secondary,
                          height: plateH,
                          fontSize: font,
                          onPressed: () => _open(const MultiplayerScreen(online: false)),
                        ),
                        SizedBox(height: h * 0.03),
                        PlateButton(
                          label: 'Online',
                          subtitle: 'Play friends anywhere',
                          icon: Icons.public_rounded,
                          style: PlateStyle.secondary,
                          height: plateH,
                          fontSize: font,
                          onPressed: () => _open(const MultiplayerScreen(online: true)),
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
              // Web: full screen (and landscape on phones).
              const Positioned(
                left: 16,
                top: 12,
                child: FullscreenButton(size: 48),
              ),
              Positioned(
                right: 16,
                top: 12,
                child: HexButton(
                  icon: Icons.people_alt_rounded,
                  tooltip: 'Active Players',
                  size: 48,
                  onPressed: () => ActivePlayersDrawer.show(context),
                ),
              ),
              // Bottom left: who is playing.
              Positioned(
                left: 16,
                bottom: 12,
                child: _NamePlate(
                  name: s.settings.username,
                  onTap: () => PlayerProfileModal.show(
                    context,
                    name: s.settings.username,
                    statsPayload: ProfileStats.instance.toSummaryPayload(),
                    isSelf: true,
                  ),
                ),
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
