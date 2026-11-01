// The hidden debug panel: only for debug builds / ?debug=1, shows the live device facts, simulates other
// devices without touching real data, and its self-check passes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/debug/debug_panel.dart';
import 'package:unmatched_game/ui/debug/device_presets.dart';
import 'package:unmatched_game/ui/dialogs/fullscreen_help_dialog.dart';
import 'package:unmatched_game/ui/platform/fullscreen_help_storage.dart';
import 'package:unmatched_game/ui/platform/platform_info.dart';
import 'package:unmatched_game/ui/platform/platform_info_service.dart';
import 'package:unmatched_game/ui/screens/menu_screen.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';

import 'fullscreen_logic_test.dart' show ipadDesktop, iphoneSafari, windows;
import 'widget_test.dart' show loadFonts;

Future<void> settle(WidgetTester t, [int ms = 500]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

/// Presses a control of the panel, scrolling it into view first (the panel scrolls).
Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t, 300);
}

void main() {
  setUpAll(loadFonts);

  Future<(Services, MemoryFullscreenHelpStorage)> boot(WidgetTester t, {bool debug = true, Size size = const Size(1024, 768)}) async {
    final settings = Settings.memory()
      ..username = 'Tester'
      ..board3d = false;
    final real = MemoryFullscreenHelpStorage(dismissed: true);
    final s = Services(
      settings: settings,
      audio: Audio(settings, enabled: false),
      preloadImages: false,
      platformInfo: FakePlatformInfoService(windows()),
      helpStorage: real,
      debugPanel: debug,
    );
    await t.runAsync(() => s.loadData());
    await t.runAsync(() => s.fullscreen.load());
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(UnmatchedApp(services: s, home: const MenuScreen()));
    await settle(t);
    return (s, real);
  }

  testWidgets('the launcher is there only when the panel is switched on', (t) async {
    await boot(t, debug: false);
    expect(find.byKey(const ValueKey('debug-launcher')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await boot(t);
    expect(find.byKey(const ValueKey('debug-launcher')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the launcher is a small button for screen readers, not a screen-sized one that would block the app', (t) async {
    final handle = t.ensureSemantics();
    await boot(t);
    final node = t.getSemantics(find.byKey(const ValueKey('debug-launcher')));
    expect(node.label, 'DEBUG');
    expect(node.rect.width, lessThan(120));
    expect(node.rect.height, lessThan(60));
    await t.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('it shows the live values: device, browser, user agent, touch points, standalone, window size, would the dialog show', (t) async {
    await boot(t);
    await t.tap(find.byKey(const ValueKey('debug-launcher')));
    await settle(t);
    String v(String k) => (t.widget(find.byKey(ValueKey('debug-$k'))) as Text).data!;
    expect(v('device kind'), 'windows');
    expect(v('userAgent'), contains('Windows'));
    expect(v('maxTouchPoints'), '0');
    expect(v('isStandalone'), 'false');
    expect(v('fullscreen supported'), 'true');
    expect(v('dismissed flag'), 'true');
    expect(v('simulating'), contains('no, this is the real device'));
    expect(v('would the dialog show now?'), 'no');
    expect(find.byKey(const ValueKey('debug-window size')), findsOneWidget);
    expect(find.byKey(const ValueKey('debug-orientation')), findsOneWidget);
    expect(find.byKey(const ValueKey('debug-safe area (l t r b)')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const ValueKey('debug-close')));
    await settle(t);
  });

  testWidgets('pretending to be each device changes what the app does, and leaves the real flag alone', (t) async {
    final (s, real) = await boot(t);
    await t.tap(find.byKey(const ValueKey('debug-launcher')));
    await settle(t);
    String v(String k) => (t.widget(find.byKey(ValueKey('debug-$k'))) as Text).data!;
    for (final p in devicePresets) {
      await t.ensureVisible(find.byKey(ValueKey('preset-${p.name}')));
      await t.tap(find.byKey(ValueKey('preset-${p.name}')));
      await settle(t, 300);
      expect(v('device kind'), p.expectedDevice.name, reason: p.name);
      expect(v('simulating'), startsWith('yes'));
      expect(v('would the dialog show now?'), p.expectedHelp ? 'YES' : 'no', reason: '${p.name}: a simulated device has a fresh, not dismissed flag');
      expect(v('button action'), p.expectedAction.name, reason: p.name);
    }
    expect(real.dismissed, isTrue, reason: 'the real flag was never changed');
    expect(real.writes, 0);
    // Toggles.
    await tapKey(t, 'preset-iPad Safari (desktop mode)');
    await settle(t, 300);
    await t.ensureVisible(find.byKey(const ValueKey('toggle-standalone')));
    await tapKey(t, 'toggle-standalone');
    await settle(t, 300);
    expect(v('isStandalone'), 'true');
    expect(v('would the dialog show now?'), 'no');
    expect(v('button action'), 'hidden');
    await t.ensureVisible(find.byKey(const ValueKey('toggle-standalone')));
    await tapKey(t, 'toggle-standalone');
    await settle(t, 300);
    expect(v('isStandalone'), 'false');
    await t.ensureVisible(find.byKey(const ValueKey('toggle-fullscreen')));
    await tapKey(t, 'toggle-fullscreen');
    await settle(t, 300);
    expect(v('fullscreen supported'), 'false');
    expect(v('button action'), 'help', reason: 'an iPad without the API goes straight to the help');
    // Back to the real device.
    await t.ensureVisible(find.byKey(const ValueKey('use-real')));
    await tapKey(t, 'use-real');
    await settle(t, 300);
    expect(v('device kind'), 'windows');
    expect(v('simulating'), contains('no, this is the real device'));
    expect(s.fullscreen.simulated, isFalse);
    expect(real.writes, 0);
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const ValueKey('debug-close')));
    await settle(t);
  });

  testWidgets('Force show dialog, Clear dismissed flag, Simulate portrait / Split View, Run self-check', (t) async {
    final (s, real) = await boot(t);
    await t.tap(find.byKey(const ValueKey('debug-launcher')));
    await settle(t);
    String v(String k) => (t.widget(find.byKey(ValueKey('debug-$k'))) as Text).data!;
    await tapKey(t, 'preset-iPhone Safari');
    await settle(t, 300);
    // Clear dismissed flag (the simulated one).
    await t.ensureVisible(find.byKey(const ValueKey('clear-dismissed')));
    await tapKey(t, 'clear-dismissed');
    await settle(t, 300);
    expect(v('dismissed flag'), 'false');
    expect(real.dismissed, isTrue, reason: 'the real flag is untouched');
    // Force show dialog.
    await t.ensureVisible(find.byKey(const ValueKey('force-dialog')));
    await tapKey(t, 'force-dialog');
    await settle(t, 400);
    expect(find.byType(FullscreenHelpDialog), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('fs-got-it')));
    await settle(t, 400);
    // Simulate portrait: the window the app sees is turned; an iPhone then gets the rotate notice.
    await t.ensureVisible(find.byKey(const ValueKey('sim-portrait')));
    await tapKey(t, 'sim-portrait');
    await settle(t, 300);
    expect(s.simulatedWindow.value, const Size(768, 1024));
    expect(v('window size'), '768 x 1024');
    expect(v('screen notice'), 'none', reason: '768 wide is a tablet, not a phone');
    await tapKey(t, 'preset-iPad Safari (desktop mode)');
    await settle(t, 300);
    expect(v('screen notice'), 'none', reason: 'an iPad in portrait is fine');
    await t.ensureVisible(find.byKey(const ValueKey('sim-split')));
    await tapKey(t, 'sim-split');
    await settle(t, 300);
    expect(s.simulatedWindow.value!.width, 507);
    expect(v('screen notice'), 'larger');
    await t.ensureVisible(find.byKey(const ValueKey('sim-reset')));
    // The notice covers the panel at this size: the reset tab outside it still works.
    await t.tap(find.byKey(const ValueKey('debug-reset-window')));
    await settle(t, 300);
    await settle(t, 300);
    expect(s.simulatedWindow.value, isNull);
    // Self-check.
    await t.ensureVisible(find.byKey(const ValueKey('self-check')));
    await tapKey(t, 'self-check');
    await settle(t, 300);
    final summary = (t.widget(find.byKey(const ValueKey('self-check-summary'))) as Text).data!;
    expect(summary, endsWith('0 FAIL'));
    expect(find.textContaining('FAIL  '), findsNothing);
    expect(t.takeException(), isNull);
  });

  test('the self-check passes every rule on every preset, and catches a wrong rule', () {
    final results = runSelfCheck();
    expect(results.length, greaterThan(50));
    expect(results.where((r) => !r.passed), isEmpty, reason: results.where((r) => !r.passed).map((r) => '${r.name}: ${r.reason}').join('\n'));
    // A check that would fail reports why.
    final broken = SelfCheckResult('x', 'expected a but got b');
    expect(broken.passed, isFalse);
    expect(ipadDesktop().deviceKind, DeviceKind.ipad);
    expect(iphoneSafari().deviceKind, DeviceKind.iphone);
  });

  testWidgets('in a normal (release-like) session without the switch nothing of it is visible or reachable', (t) async {
    await boot(t, debug: false);
    expect(find.text('DEBUG'), findsNothing);
    expect(find.byType(DebugPanelDialog), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
