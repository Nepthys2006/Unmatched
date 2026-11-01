/// When the window is the wrong shape for the game, and what to tell the player.
///
/// * A phone held upright gets "Turn your phone" (iOS ignores the manifest's orientation lock).
/// * An iPad never does: it works in both orientations, also when it is turned in the middle of a match.
/// * A window too small to play in (iPad Slide Over and the narrowest Split View, a tiny desktop
///   window) gets "Make this window larger" instead of a broken layout. Nothing is torn down: the
///   match underneath keeps its state and carries on when the window is big enough again.
library;

import 'package:flutter/material.dart';

import '../../l10n/localization_setup.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import 'platform_info.dart';

enum ViewportNotice { rotate, larger }

/// The smallest window the game lays out well in.
const minGameWidth = 520.0;
const minGameHeight = 300.0;

ViewportNotice? viewportNotice(Size size, PlatformInfo info) {
  final ipad = info.deviceKind == DeviceKind.ipad;
  final portrait = size.height > size.width;
  if (!ipad && portrait && size.shortestSide < 600) return ViewportNotice.rotate;
  final resizable = ipad || info.deviceKind == DeviceKind.mac || info.deviceKind == DeviceKind.windows || info.deviceKind == DeviceKind.linux;
  if (resizable && (size.width < minGameWidth || size.height < minGameHeight)) return ViewportNotice.larger;
  return null;
}

class ViewportNoticeView extends StatelessWidget {
  const ViewportNoticeView({super.key, required this.notice});
  final ViewportNotice notice;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rotate = notice == ViewportNotice.rotate;
    return Material(
      key: ValueKey(rotate ? 'notice-rotate' : 'notice-larger'),
      color: Palette.bg,
      child: Semantics(
        liveRegion: true,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(rotate ? Icons.screen_rotation_rounded : Icons.open_in_full_rounded, color: Palette.bone, size: 56),
                const SizedBox(height: 16),
                Text((rotate ? l.rotateTitle : l.largerTitle).toUpperCase(), textAlign: TextAlign.center, style: titleStyle(26, spacing: 2)),
                const SizedBox(height: 6),
                const DecoRule(width: 140, opacity: 0.4),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(rotate ? l.rotateBody : l.largerBody, textAlign: TextAlign.center, style: bodyStyle(15, color: Palette.boneDim)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the app at the window size the debug panel asks for ("Simulate portrait", "Simulate Split
/// View"), letterboxed in the real window. With nothing simulated it is just the child.
class SimulatedWindow extends StatelessWidget {
  const SimulatedWindow({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    return ValueListenableBuilder<Size?>(
      valueListenable: services.simulatedWindow,
      child: child,
      builder: (context, size, child) {
        if (size == null) return child!;
        final real = MediaQuery.of(context);
        final fit = Size(size.width.clamp(1, real.size.width), size.height.clamp(1, real.size.height));
        return ColoredBox(
          color: const Color(0xFF000000),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: fit.width,
              height: fit.height,
              child: ClipRect(child: MediaQuery(data: real.copyWith(size: fit), child: child!)),
            ),
          ),
        );
      },
    );
  }
}
