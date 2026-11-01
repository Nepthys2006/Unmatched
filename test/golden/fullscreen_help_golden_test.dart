// Screenshots of the Home Screen help at every window size. Goldens are pixel exact and the text
// rendering differs between operating systems, so they are tagged `golden` and compared on ONE
// operating system (the CI job runs them on Windows, where the reference images were made).
//
//   flutter test --tags golden test/golden                    compare
//   flutter test --tags golden --update-goldens test/golden   rewrite the images
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/l10n/localization_setup.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/dialogs/fullscreen_help_dialog.dart';
import 'package:unmatched_game/ui/platform/fullscreen_help_storage.dart';
import 'package:unmatched_game/ui/platform/platform_info.dart';
import 'package:unmatched_game/ui/platform/platform_info_service.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';
import 'package:unmatched_game/ui/theme.dart';

import '../widget_test.dart' show loadFonts;

const sizes = <(String, Size)>[
  ('667x375', Size(667, 375)),
  ('926x428', Size(926, 428)),
  ('1024x768', Size(1024, 768)),
  ('768x1024', Size(768, 1024)),
  ('1366x1024', Size(1366, 1024)),
  ('507x768', Size(507, 768)),
  ('320x768', Size(320, 768)),
];

/// The Material icon font, so the golden shows the real icons instead of empty boxes.
Future<void> loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null) '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
      return;
    }
  }
}

void main() {
  setUpAll(() async {
    await loadFonts();
    await loadIcons();
  });

  for (final (label, size) in sizes) {
    for (final device in [DeviceKind.iphone, DeviceKind.ipad]) {
      testWidgets('help dialog, ${device.name}, $label', (t) async {
        final settings = Settings.memory();
        final s = Services(
          settings: settings,
          audio: Audio(settings, enabled: false),
          preloadImages: false,
          platformInfo: FakePlatformInfoService(const PlatformInfo()),
          helpStorage: MemoryFullscreenHelpStorage(),
        );
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('golden'),
            child: ServicesScope(
              services: s,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(),
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: appSupportedLocales,
                home: Scaffold(
                  backgroundColor: Palette.bg,
                  body: Builder(
                    builder: (ctx) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!t.any(find.byType(FullscreenHelpDialog))) {
                          FullscreenHelpDialog.show(ctx, device: device, browser: BrowserKind.safari);
                        }
                      });
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(t.takeException(), isNull);
        await expectLater(find.byKey(const ValueKey('golden')), matchesGoldenFile('goldens/fs_help_${device.name}_$label.png'));
        // Close it so no timer is left behind.
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump(const Duration(milliseconds: 400));
      });
    }
  }
}
