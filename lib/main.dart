import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/audio.dart';
import 'ui/invite_flow.dart';
import 'ui/screens/loading_screen.dart';
import 'ui/services.dart';
import 'ui/settings.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape only on phones and tablets. On the web the page handles orientation itself
  // (the JS rotate overlay and the Flutter RotatePrompt guide users to landscape; locking here
  // would prevent the overlay from ever appearing).
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations(OrientationGuard.landscapes);
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final settings = await Settings.load();
  runApp(UnmatchedApp(services: Services(settings: settings, audio: Audio(settings))));
}

class UnmatchedApp extends StatelessWidget {
  const UnmatchedApp({super.key, required this.services, this.home});
  final Services services;

  /// Overrides the first screen (tests).
  final Widget? home;

  @override
  Widget build(BuildContext context) => ServicesScope(
        services: services,
        child: MaterialApp(
          title: 'Unmatched',
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          builder: (context, child) => OrientationGuard(child: InviteListener(child: UiScale(child: child!))),
          home: home ?? const LoadingScreen(),
        ),
      );
}

/// Every screen is laid out for a landscape phone. On bigger screens the whole app is drawn at
/// that density and scaled up uniformly, like a console game's UI, instead of leaving small
/// controls floating in a large window.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.child});
  final Widget child;

  /// Scale for a screen whose shorter side is [shortest] logical pixels.
  static double factorFor(double shortest) => (shortest / 500).clamp(1.0, 1.6);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final k = factorFor(mq.size.shortestSide);
    // Always the same widget structure, so resizing a window across k == 1 keeps the app's state.
    final size = mq.size / k;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: MediaQuery(
          data: mq.copyWith(
            size: size,
            devicePixelRatio: mq.devicePixelRatio * k,
            padding: mq.padding / k,
            viewPadding: mq.viewPadding / k,
            viewInsets: mq.viewInsets / k,
          ),
          // Mobile browsers can't lock orientation: ask for landscape, keeping the app alive below.
          child: Stack(
            children: [
              child,
              if (mq.size.height > mq.size.width && mq.size.shortestSide < 600) const Positioned.fill(child: RotatePrompt()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when a phone is held upright: the game is landscape only.
class RotatePrompt extends StatelessWidget {
  const RotatePrompt({super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: Palette.bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.screen_rotation_rounded, color: Palette.bone, size: 64),
                const SizedBox(height: 20),
                Text('TURN YOUR PHONE', textAlign: TextAlign.center, style: titleStyle(30, spacing: 2)),
                const SizedBox(height: 8),
                Text('Unmatched is played in landscape.', textAlign: TextAlign.center, style: bodyStyle(16, color: Palette.boneDim)),
              ],
            ),
          ),
        ),
      );
}

/// Phones follow the sensor between landscape-left and landscape-right (flip the phone 180° and
/// the game turns with it) but never go upright. The lock itself is declared in the Android
/// manifest (`sensorLandscape`) and the iOS Info.plist; this re-asserts it, and the immersive
/// full-screen mode that Android drops on a rotation, each time the window changes shape or
/// insets, so the notch/gesture-bar padding follows the phone to its new side.
class OrientationGuard extends StatefulWidget {
  const OrientationGuard({super.key, required this.child});
  final Widget child;

  static const landscapes = [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];

  /// Phones and tablets only: desktops and browsers have no sensor to follow.
  static bool get applies => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<OrientationGuard> createState() => _OrientationGuardState();
}

class _OrientationGuardState extends State<OrientationGuard> with WidgetsBindingObserver {
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    if (OrientationGuard.applies) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _settle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // The metrics fire several times while the rotation animates; act once it has settled.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 250), _reassert);
  }

  void _reassert() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    // Leave the system bars alone while the keyboard is up.
    if (view != null && view.viewInsets.bottom > 0) return;
    SystemChrome.setPreferredOrientations(OrientationGuard.landscapes);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Padding (notch side) is read from MediaQuery by the screens; make sure they re-read it.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
