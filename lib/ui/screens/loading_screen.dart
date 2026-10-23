/// First screen: loads the game data and warms the hero art while the miniatures parade past.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../../engine/ai.dart';
import '../match/match_config.dart';
import '../match/match_screen.dart';
import 'menu_screen.dart';
import 'username_screen.dart';

const _tips = [
  'Ranged fighters can attack anyone in a zone they share, not just adjacent fighters.',
  'Every maneuver draws a card first. Out of cards? Each of your fighters takes 2 damage instead.',
  'Discard a card while maneuvering to BOOST your movement by its boost value.',
  'The defender\'s effects resolve first. The attacker wins only if the attack dealt damage.',
  'You get two actions every turn, and you can repeat the same one.',
  'Your hand limit is 7. Extra cards are discarded at the end of your turn.',
  'Fighters move through friends but never through enemies.',
];

const _quickMatch = String.fromEnvironment('QUICKMATCH');

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});
  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
  final _tip = _tips[math.Random().nextInt(_tips.length)];
  double _progress = 0;
  String _status = 'Setting the table';
  String? _error;
  List<String> _minis = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_minis.isEmpty && _error == null) unawaited(_load());
  }

  Future<void> _load() async {
    final s = context.services;
    final started = DateTime.now();
    try {
      final data = await s.loadData();
      final heroes = data.heroes.values.toList();
      if (!mounted) return;
      setState(() {
        _minis = [for (final h in heroes) h.mini]..shuffle();
        _progress = 0.1;
        _status = 'Gathering ${heroes.length} heroes';
      });
      if (s.preloadImages) {
        var done = 0;
        for (final h in heroes) {
          if (!mounted) return;
          await Future.wait([precacheImage(AssetImage(h.mini), context), precacheImage(AssetImage(h.avatar), context)]);
          done++;
          if (mounted) setState(() => _progress = 0.1 + 0.9 * done / heroes.length);
        }
      } else {
        _progress = 1;
      }
      // Long enough to see the parade even on a fast machine.
      final wait = const Duration(milliseconds: 1400) - DateTime.now().difference(started);
      if (wait > Duration.zero && s.preloadImages) await Future<void>.delayed(wait);
      if (!mounted) return;
      final Widget next = _quickMatch.isNotEmpty
          ? _quick(s)
          : (s.settings.hasUsername ? const MenuScreen() : const UsernameScreen());
      unawaited(
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, _, _) => next,
            transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Dev only (`--dart-define=QUICKMATCH=<map id>[:<players>]`): straight into a match with
  /// random heroes, for screenshots and soak tests.
  Widget _quick(Services s) {
    final parts = _quickMatch.split(':');
    final map = s.data.maps[parts[0]]!;
    final players = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 2;
    final mode = switch (map.mode) {
      '2v2' => GameMode.teams2,
      '3v3' => GameMode.teams3,
      'ffa' => GameMode.ffa,
      _ => GameMode.duel,
    };
    if (!s.settings.hasUsername) s.settings.username = 'Tester';
    final hero = s.data.heroes.keys.elementAt(math.Random().nextInt(s.data.heroes.length));
    return MatchScreen(
      config: MatchConfig(mode: mode, players: players, map: map, ai: AiLevel.medium, heroIds: MatchConfig.randomLineup(s.data, hero, players)),
    );
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final miniH = (size.height * 0.36).clamp(110.0, 300.0);
    return Scaffold(
      body: TableBackground(
        child: Stack(
          children: [
            // The parade: hero miniatures drifting right to left on a lit band.
            if (_minis.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: size.height * 0.5 - miniH * 0.42,
                height: miniH,
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                    stops: [0, 0.18, 0.82, 1],
                  ).createShader(r),
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _drift,
                      builder: (_, child) {
                        final spacing = miniH * 0.62;
                        final total = spacing * _minis.length;
                        final shift = -_drift.value * total;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var i = 0; i < _minis.length; i++)
                              for (final copy in [0.0, total])
                                if (_visible(shift + i * spacing + copy, spacing, size.width))
                                  Positioned(
                                    left: shift + i * spacing + copy,
                                    bottom: (i.isEven ? 0 : miniH * 0.06),
                                    height: miniH * (i.isEven ? 1 : 0.86),
                                    child: Opacity(
                                      opacity: i.isEven ? 0.92 : 0.55,
                                      child: Image.asset(_minis[i], fit: BoxFit.contain, cacheHeight: 440, gaplessPlayback: true),
                                    ),
                                  ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: size.height * 0.1,
              child: Column(
                children: [
                  Text('UNMATCHED', style: titleStyle((size.height * 0.15).clamp(40, 96), spacing: 6)),
                  const SizedBox(height: 4),
                  DecoRule(width: (size.height * 0.7).clamp(180, 420)),
                ],
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: size.height * 0.07,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _error != null
                      ? Text(
                          'Could not load the game data.\n$_error',
                          textAlign: TextAlign.center,
                          style: bodyStyle(15, color: Palette.danger),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(_status.toUpperCase(), style: titleStyle(13, color: Palette.boneDim, spacing: 1.4)),
                                const Spacer(),
                                Text(
                                  '${(_progress * 100).round()}%',
                                  style: titleStyle(13, color: Palette.boneDim, weight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _ProgressBar(_progress),
                            const SizedBox(height: 12),
                            Text(
                              _tip,
                              textAlign: TextAlign.center,
                              style: bodyStyle(14, color: Palette.muted, style: FontStyle.italic),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _visible(double x, double w, double screen) => x > -w * 1.4 && x < screen + w * 0.2;
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar(this.value);
  final double value;
  @override
  Widget build(BuildContext context) => Container(
    height: 8,
    decoration: ShapeDecoration(
      shape: PlateBorder(slant: 1, side: BorderSide(color: Palette.bone.withValues(alpha: 0.5))),
      color: Palette.bgDeep,
    ),
    padding: const EdgeInsets.all(2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        widthFactor: value.clamp(0.02, 1),
        child: const SizedBox.expand(
          child: DecoratedBox(
            decoration: ShapeDecoration(color: Palette.bone, shape: PlateBorder(slant: 1)),
          ),
        ),
      ),
    ),
  );
}
