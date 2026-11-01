/// The Full Screen button used in the menu and the match HUD. What it does depends on the device
/// (see FullscreenController): the Fullscreen API on desktop and Android, the API and then the
/// Home Screen help on iPad, the help straight away on iPhone; hidden when the app already runs
/// from the Home Screen. The label follows the system entering and leaving full screen.
library;

import 'package:flutter/material.dart';

import '../../l10n/localization_setup.dart';
import '../dialogs/fullscreen_help_dialog.dart';
import '../services.dart';
import '../widgets.dart';

class FullscreenButton extends StatelessWidget {
  const FullscreenButton({super.key, this.size = 44, this.onChanged});
  final double size;

  /// Called after the press so the parent can rebuild (e.g. update layout).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.services.fullscreen;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (!c.buttonVisible) return const SizedBox.shrink();
        final l = AppLocalizations.of(context);
        final full = c.isFullscreen;
        return HexButton(
          key: const ValueKey('fullscreen-button'),
          icon: full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          tooltip: full ? l.fsButtonExit : l.fsButtonEnter,
          size: size,
          // The controller makes the Fullscreen API call synchronously from here: a user gesture.
          onPressed: () {
            FullscreenHelpDialog.handlePress(context, c);
            onChanged?.call();
          },
        );
      },
    );
  }
}

/// The Settings entry: a "Full screen" button (what it does depends on the device) and, on an iPad,
/// "Better full screen: install the app" which opens the Home Screen help even when it was
/// dismissed before. Hidden when the app already runs from the Home Screen.
class FullscreenSettingsRow extends StatelessWidget {
  const FullscreenSettingsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.services.fullscreen;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (!c.buttonVisible) return const SizedBox.shrink();
        final l = AppLocalizations.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Full screen'),
            PlateButton(
              key: const ValueKey('settings-fullscreen'),
              label: c.isFullscreen ? l.fsButtonExit : l.fsButtonEnter,
              icon: c.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              style: PlateStyle.secondary,
              height: 52,
              fontSize: 17,
              onPressed: () => FullscreenHelpDialog.handlePress(context, c),
            ),
            if (c.installOptionVisible) ...[
              const SizedBox(height: 8),
              PlateButton(
                key: const ValueKey('settings-install'),
                label: l.fsInstallApp,
                icon: Icons.add_box_outlined,
                style: PlateStyle.secondary,
                height: 52,
                fontSize: 15,
                onPressed: () => FullscreenHelpDialog.showFor(context, c),
              ),
            ],
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}
