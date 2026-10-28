/// The fullscreen button used in the menu and match HUDs, aware of the platform it runs on:
///
///  • **iPhone Safari**: shows a one-time hint dialog explaining how to Add to Home Screen for
///    borderless gameplay. After dismissal the button hides.
///  • **iPhone standalone (home screen launch)**: hidden — already fullscreen.
///  • **iPad Safari / Android Chrome / desktop**: normal fullscreen toggle.
library;

import 'package:flutter/material.dart';

import '../platform/fullscreen.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

/// A fullscreen button that knows what to do on each platform.
///
/// On iPhone Safari it shows a one-time "Add to Home Screen" hint dialog; after dismissal
/// the button is hidden. On every other web platform it toggles element fullscreen.
///
/// Set [size] to match the surrounding HexButton row (44 in the match HUD, 48 on the menu).
class FullscreenButton extends StatefulWidget {
  const FullscreenButton({super.key, this.size = 44, this.onChanged});
  final double size;

  /// Called after fullscreen state changes so the parent can rebuild (e.g. update layout).
  final VoidCallback? onChanged;

  @override
  State<FullscreenButton> createState() => _FullscreenButtonState();
}

class _FullscreenButtonState extends State<FullscreenButton> {
  bool _hintDismissed = false;

  @override
  void initState() {
    super.initState();
    _hintDismissed = iosHintShown;
    addFullscreenChangeListener(_onFullscreenChange);
  }

  @override
  void dispose() {
    removeFullscreenChangeListener(_onFullscreenChange);
    super.dispose();
  }

  void _onFullscreenChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // iPhone Safari (not standalone): show the button until the hint has been shown, then hide.
    if (isIphoneSafari) {
      if (_hintDismissed) return const SizedBox.shrink();
      return HexButton(
        icon: Icons.fullscreen_rounded,
        tooltip: 'Full screen',
        size: widget.size,
        onPressed: () => _showIosHint(context),
      );
    }

    // Standalone / Home screen: no button needed, already fullscreen.
    if (isStandaloneApp) return const SizedBox.shrink();

    // Normal platforms: toggle fullscreen.
    if (!canToggleFullscreen) return const SizedBox.shrink();
    return HexButton(
      icon: isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      tooltip: isFullscreen ? 'Leave full screen' : 'Full screen',
      size: widget.size,
      onPressed: () async {
        await toggleFullscreen();
        widget.onChanged?.call();
        if (mounted) setState(() {});
      },
    );
  }

  /// Shows the "Full screen on iPhone" hint dialog, styled to match the game's UI exactly
  /// as shown in the design reference (screenshot).
  Future<void> _showIosHint(BuildContext context) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0xB3000000),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: Colors.transparent,
              child: Panel(
                padding: const EdgeInsets.all(24),
                cut: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title.
                    Text(
                      'FULL SCREEN ON IPHONE',
                      style: titleStyle(22, color: Palette.bone, spacing: 1.2),
                    ),
                    const SizedBox(height: 6),
                    const DecoRule(width: 160, opacity: 0.35),
                    const SizedBox(height: 14),
                    // Explanation.
                    Text(
                      "Safari can't show a web page full screen on iPhone. "
                      'Add Unmatched to your Home Screen and open it from there: '
                      "it runs without Safari's bars.",
                      style: bodyStyle(14.5, color: Palette.boneDim),
                    ),
                    const SizedBox(height: 18),
                    // Steps.
                    _step(1, Icons.ios_share_rounded, 'Tap Share in Safari'),
                    const SizedBox(height: 10),
                    _step(2, Icons.add_box_outlined, 'Choose Add to Home Screen'),
                    const SizedBox(height: 10),
                    _step(3, Icons.touch_app_rounded, 'Open Unmatched from your Home Screen'),
                    const SizedBox(height: 22),
                    // GOT IT button.
                    PlateButton(
                      label: 'Got it',
                      icon: Icons.check_rounded,
                      style: PlateStyle.confirm,
                      width: double.infinity,
                      height: 48,
                      fontSize: 18,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Remember the dismissal so the button hides and the hint doesn't come back.
    markIosHintShown();
    _hintDismissed = true;
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Widget _step(int n, IconData icon, String text) => Row(
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: ShapeDecoration(
          color: Palette.panelHi,
          shape: HexBorder(side: BorderSide(color: Palette.gold.withValues(alpha: 0.6))),
        ),
        alignment: Alignment.center,
        child: Text('$n', style: titleStyle(14, color: Palette.gold)),
      ),
      const SizedBox(width: 12),
      Icon(icon, color: Palette.boneDim, size: 22),
      const SizedBox(width: 10),
      Expanded(
        child: Text(text, style: bodyStyle(14.5, color: Palette.bone)),
      ),
    ],
  );
}
