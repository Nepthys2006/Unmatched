/// "Full screen on iPhone / iPad": how to add the app to the Home Screen and run it there, since a
/// page in Safari can't go full screen on iPhone and only sometimes on iPad. Dark navy panel, gold
/// condensed capitals, gold numbered steps and the green parallelogram button. Read-only help: it
/// changes nothing but the "dismissed" flag.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/localization_setup.dart';
import '../platform/fullscreen_controller.dart';
import '../platform/platform_info.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

class FullscreenHelpDialog extends StatelessWidget {
  const FullscreenHelpDialog({super.key, required this.device, required this.browser});

  /// iPhone or iPad (anything else is shown as iPhone).
  final DeviceKind device;
  final BrowserKind browser;

  bool get _ipad => device == DeviceKind.ipad;

  /// Opens the dialog over everything. Resolves when it is closed, by GOT IT, Esc or a tap outside;
  /// then the dismissed flag is saved through [controller].
  static Future<void> show(
    BuildContext context, {
    required DeviceKind device,
    required BrowserKind browser,
    FullscreenController? controller,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppLocalizations.of(context).fsGotIt,
      barrierColor: const Color(0xB3000000),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) => FullscreenHelpDialog(device: device, browser: browser),
      transitionBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(c), child: child),
        );
      },
    );
    if (controller != null) await controller.markDismissed();
  }

  /// Opens it for the device [controller] describes.
  static Future<void> showFor(BuildContext context, FullscreenController controller) => show(
    context,
    device: controller.info.deviceKind,
    browser: controller.info.browser,
    controller: controller,
  );

  /// What a Full Screen button's onPressed does: call this straight from the tap handler. The
  /// controller makes its Fullscreen API call synchronously, then the dialog opens if the device
  /// needs it (iPhone, or an iPad that refused).
  static void handlePress(BuildContext context, FullscreenController controller) {
    final result = controller.press(); // synchronous start: inside the user gesture
    unawaited(
      result.then((r) {
        if (r == FullscreenPress.showHelp && context.mounted) return showFor(context, controller);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final title = (_ipad ? l.fsTitleIpad : l.fsTitleIphone).toUpperCase();
    final body = _ipad ? l.fsBodyIpad : l.fsBodyIphone;
    final share = switch (shareStepFor(device, browser)) {
      ShareStep.iphoneSafari => l.fsStepShareIphoneSafari,
      ShareStep.ipadSafari => l.fsStepShareIpadSafari,
      ShareStep.otherBrowser => l.fsStepShareOther,
    };
    // A phone on its side is wide and short: put the words on the left and the steps on the right
    // instead of making the player scroll.
    final twoColumns = size.width >= 600 && size.height < 520;
    final maxWidth = math.min(twoColumns ? 760.0 : 460.0, size.width - 24);

    Widget heading() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(title, key: const ValueKey('fs-title'), style: titleStyle(22, color: Palette.gold, spacing: 1.4)),
        ),
        const SizedBox(height: 6),
        const DecoRule(width: 160, opacity: 0.45),
        const SizedBox(height: 14),
        Text(body, key: const ValueKey('fs-body'), style: bodyStyle(14.5, color: Palette.boneDim)),
      ],
    );

    Widget steps() => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Step(number: 1, icon: Icons.ios_share, text: share, stepLabel: l.fsStepNumber(1)),
        _Step(number: 2, icon: Icons.add_box_outlined, text: l.fsStepAdd, stepLabel: l.fsStepNumber(2)),
        _Step(number: 3, icon: Icons.touch_app, text: l.fsStepOpen, stepLabel: l.fsStepNumber(3)),
      ],
    );

    Widget gotIt() => PlateButton(
      key: const ValueKey('fs-got-it'),
      label: l.fsGotIt,
      icon: Icons.check_rounded,
      style: PlateStyle.confirm,
      width: double.infinity,
      height: 52,
      fontSize: 18,
      onPressed: () => Navigator.of(context).pop(),
    );

    return CallbackShortcuts(
      // Esc (an iPad with a hardware keyboard) closes it.
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: FocusScope(
        autofocus: true,
        child: FocusTraversalGroup(
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: l.fsDialogLabel,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: math.max(120, size.height - 24)),
                    // Taps inside the panel must not reach the barrier behind it.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: Material(
                        type: MaterialType.transparency,
                        child: Panel(
                          key: const ValueKey('fs-panel'),
                          padding: const EdgeInsets.all(22),
                          cut: 14,
                          child: SingleChildScrollView(
                            child: twoColumns
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: heading()),
                                      const SizedBox(width: 26),
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [steps(), const SizedBox(height: 14), gotIt()],
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [heading(), const SizedBox(height: 14), steps(), const SizedBox(height: 18), gotIt()],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One numbered step: a gold number, an icon, the words. At least 48 high so it reads like a
/// touch target.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.icon, required this.text, required this.stepLabel});
  final int number;
  final IconData icon;
  final String text;
  final String stepLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$stepLabel: $text',
    excludeSemantics: true,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Palette.gold, width: 1.6)),
            child: Text('$number', style: titleStyle(15, color: Palette.gold, spacing: 0)),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: Palette.bone, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(text, key: ValueKey('fs-step-$number'), style: bodyStyle(15, color: Palette.bone, weight: FontWeight.w600))),
        ],
      ),
    ),
  );
}
