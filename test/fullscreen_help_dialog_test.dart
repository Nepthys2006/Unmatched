// The "Full screen on iPhone / iPad" dialog and everything around it, as a player meets it: what it
// says, how it closes, when it appears, what the Full Screen button does in Settings, and that the
// rotate screen is for phones only. All at the window sizes of phones, iPads and iPad Split View.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/l10n/localization_setup.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/dialogs/fullscreen_help_dialog.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';
import 'package:unmatched_game/ui/platform/fullscreen_help_storage.dart';
import 'package:unmatched_game/ui/platform/platform_info.dart';
import 'package:unmatched_game/ui/platform/platform_info_service.dart';
import 'package:unmatched_game/ui/platform/viewport_guard.dart';
import 'package:unmatched_game/ui/screens/menu_screen.dart';
import 'package:unmatched_game/ui/screens/settings_screen.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';
import 'package:unmatched_game/ui/theme.dart';

import 'fullscreen_logic_test.dart' show ipadDesktop, ipadMobile, iphoneSafari, uaIphoneChrome, uaIpadChrome, windows;
import 'widget_test.dart' show loadFonts;

const sizes = <(String, Size)>[
  ('small phone landscape 667x375', Size(667, 375)),
  ('large phone landscape 926x428', Size(926, 428)),
  ('iPad landscape 1024x768', Size(1024, 768)),
  ('iPad portrait 768x1024', Size(768, 1024)),
  ('iPad Pro 1366x1024', Size(1366, 1024)),
  ('Split View 507x768', Size(507, 768)),
  ('Slide Over 320x768', Size(320, 768)),
];

Future<void> settle(WidgetTester t, [int ms = 500]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

void main() {
  setUpAll(loadFonts);

  Services makeServices(PlatformInfo info, {FullscreenHelpStorage? storage, FakeFullscreen behavior = FakeFullscreen.succeeds, FakePlatformInfoService? fake}) {
    final settings = Settings.memory()
      ..username = 'Tester'
      ..board3d = false;
    return Services(
      settings: settings,
      audio: Audio(settings, enabled: false),
      preloadImages: false,
      platformInfo: fake ?? FakePlatformInfoService(info, behavior: behavior),
      helpStorage: storage ?? MemoryFullscreenHelpStorage(),
    );
  }

  Future<void> boot(WidgetTester t, Services s, Size size, Widget home) async {
    await t.runAsync(() => s.loadData());
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);
    await t.pumpWidget(UnmatchedApp(services: s, home: home));
    await settle(t);
  }

  /// The dialog in a plain MaterialApp at exactly [size] (no UI scaling, no "turn your phone" or
  /// "make this window larger" notice), to check every window size on its own.
  Future<void> bootBare(WidgetTester t, Services s, Size size, Widget home) async {
    await t.runAsync(() => s.loadData());
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);
    await t.pumpWidget(
      ServicesScope(
        services: s,
        child: MaterialApp(
          theme: buildTheme(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: appSupportedLocales,
          home: home,
        ),
      ),
    );
    await settle(t);
  }

  /// A page with one button that opens the dialog for [info], as the app does.
  Widget opener(Services s, PlatformInfo info) => Scaffold(
    body: Builder(
      builder: (ctx) => Center(
        child: TextButton(
          key: const ValueKey('open'),
          onPressed: () => FullscreenHelpDialog.show(ctx, device: info.deviceKind, browser: info.browser, controller: s.fullscreen),
          child: const Text('open'),
        ),
      ),
    ),
  );

  Future<void> openDialog(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('open')));
    await settle(t, 400);
  }

  String text(String key) => (find.byKey(ValueKey(key)).evaluate().single.widget as Text).data!;

  group('what it says', () {
    for (final (label, info, title, bodyStart, step1) in [
      ('iPhone Safari', iphoneSafari(), 'FULL SCREEN ON IPHONE', "Safari can't show a web page full screen on iPhone.", 'Tap Share in Safari'),
      ('iPad Safari (desktop mode)', ipadDesktop(), 'FULL SCREEN ON IPAD', 'Add Unmatched to your Home Screen and open it from there: it runs full screen', 'Tap Share in the top bar of Safari'),
      ('iPad Safari (mobile mode)', ipadMobile(), 'FULL SCREEN ON IPAD', 'Add Unmatched to your Home Screen', 'Tap Share in the top bar of Safari'),
      ('iPhone Chrome', PlatformInfo(userAgent: uaIphoneChrome, platform: 'iPhone', maxTouchPoints: 5), 'FULL SCREEN ON IPHONE', "Safari can't show", 'Tap Share (or the menu) in your browser'),
      ('iPad Chrome', ipadMobile(ua: uaIpadChrome), 'FULL SCREEN ON IPAD', 'Add Unmatched to your Home Screen', 'Tap Share (or the menu) in your browser'),
    ]) {
      testWidgets('$label: title, body, three steps with icons and GOT IT', (t) async {
        final s = makeServices(info);
        await boot(t, s, const Size(926, 428), opener(s, info));
        await openDialog(t);
        expect(find.byType(FullscreenHelpDialog), findsOneWidget);
        expect(text('fs-title'), title);
        expect(text('fs-body'), startsWith(bodyStart));
        expect(text('fs-step-1'), step1);
        expect(text('fs-step-2'), 'Choose Add to Home Screen');
        expect(text('fs-step-3'), 'Open Unmatched from your Home Screen');
        expect(find.byIcon(Icons.ios_share), findsOneWidget);
        expect(find.byIcon(Icons.add_box_outlined), findsOneWidget);
        expect(find.byIcon(Icons.touch_app), findsOneWidget);
        expect(find.byKey(const ValueKey('fs-got-it')), findsOneWidget);
        expect(find.text('GOT IT'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        // The numbers 1, 2, 3 in the gold rings.
        for (final n in ['1', '2', '3']) {
          expect(find.text(n), findsOneWidget);
        }
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const ValueKey('fs-got-it')));
        await settle(t);
      });
    }

    testWidgets('the iPhone body says Safari cannot do it; the iPad body does not', (t) async {
      for (final info in [iphoneSafari(), ipadDesktop()]) {
        final s = makeServices(info);
        await boot(t, s, const Size(926, 428), opener(s, info));
        await openDialog(t);
        final body = text('fs-body');
        expect(body.contains("can't show a web page full screen on iPhone"), info.deviceKind == DeviceKind.iphone);
        expect(body.contains("without Safari's bars"), isTrue);
        await t.tap(find.byKey(const ValueKey('fs-got-it')));
        await settle(t);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the text comes from AppLocalizations (Filipino, Bisaya, and English for anything else)', (t) async {
      final s = makeServices(iphoneSafari());
      await boot(t, s, const Size(926, 428), opener(s, iphoneSafari()));
      Future<String> gotIt(Locale l) async {
        t.platformDispatcher.localesTestValue = [l];
        await settle(t);
        await openDialog(t);
        final label = (t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('fs-got-it')), matching: find.byType(Text)).first)).data!;
        expect(t.takeException(), isNull, reason: 'no missing-localization crash for $l');
        await t.tap(find.byKey(const ValueKey('fs-got-it')));
        await settle(t);
        return label;
      }

      final en = await gotIt(const Locale('en'));
      expect(en, 'GOT IT');
      expect(await gotIt(const Locale('fil')), 'SIGE');
      expect(await gotIt(const Locale('ceb')), 'OKAY', reason: 'Flutter has no Bisaya: the built-in widgets fall back to English');
      expect(await gotIt(const Locale('de')), 'GOT IT', reason: 'a language the app lacks shows English');
      // The generated class has every string in every language.
      for (final l in appSupportedLocales) {
        final a = await AppLocalizations.delegate.load(l);
        expect(a.fsTitleIphone, isNotEmpty);
        expect(a.fsStepShareIpadSafari, isNotEmpty);
        expect(a.largerTitle, isNotEmpty);
      }
    });
  });

  group('closing it', () {
    testWidgets('GOT IT closes it and saves the dismissed flag', (t) async {
      SharedPreferences.setMockInitialValues({});
      final s = makeServices(iphoneSafari(), storage: const SharedPrefsFullscreenHelpStorage());
      await boot(t, s, const Size(926, 428), opener(s, iphoneSafari()));
      expect(s.fullscreen.dismissed, isFalse);
      await openDialog(t);
      await t.tap(find.byKey(const ValueKey('fs-got-it')));
      await settle(t);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      expect(s.fullscreen.dismissed, isTrue);
      final prefs = await t.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getBool(SharedPrefsFullscreenHelpStorage.key), isTrue, reason: 'saved to storage');
    });

    testWidgets('Esc closes it (an iPad with a keyboard)', (t) async {
      final s = makeServices(ipadDesktop());
      await boot(t, s, const Size(1024, 768), opener(s, ipadDesktop()));
      await openDialog(t);
      expect(find.byType(FullscreenHelpDialog), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      expect(s.fullscreen.dismissed, isTrue);
    });

    testWidgets('a tap outside closes it, a tap inside the panel does not', (t) async {
      final s = makeServices(iphoneSafari());
      await boot(t, s, const Size(926, 428), opener(s, iphoneSafari()));
      await openDialog(t);
      await t.tap(find.byKey(const ValueKey('fs-title')));
      await settle(t, 300);
      expect(find.byType(FullscreenHelpDialog), findsOneWidget, reason: 'inside the panel');
      await t.tap(find.byKey(const ValueKey('fs-body')));
      await settle(t, 300);
      expect(find.byType(FullscreenHelpDialog), findsOneWidget);
      await t.tapAt(const Offset(4, 4));
      await settle(t);
      expect(find.byType(FullscreenHelpDialog), findsNothing, reason: 'outside the panel, on the dimmed barrier');
    });

    testWidgets('it opens and closes with an animation, not a jump', (t) async {
      final s = makeServices(iphoneSafari());
      await boot(t, s, const Size(926, 428), opener(s, iphoneSafari()));
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(find.byType(FullscreenHelpDialog), findsOneWidget, reason: 'already coming in');
      final fading = t.widgetList<FadeTransition>(find.descendant(of: find.byType(Navigator), matching: find.byType(FadeTransition))).any((f) => f.opacity.value > 0 && f.opacity.value < 1);
      expect(fading, isTrue, reason: 'part way through the fade');
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const ValueKey('fs-got-it')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(find.byType(FullscreenHelpDialog), findsOneWidget, reason: 'still on its way out');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(FullscreenHelpDialog), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('the dialog has a name and role for screen readers, the steps read as steps, the button is 48+ high', (t) async {
      final handle = t.ensureSemantics();
      final s = makeServices(iphoneSafari());
      await boot(t, s, const Size(926, 428), opener(s, iphoneSafari()));
      await openDialog(t);
      expect(find.bySemanticsLabel('Add Unmatched to your Home Screen'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Step 1: Tap Share in Safari')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Step 2: Choose Add to Home Screen')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Step 3: Open Unmatched from your Home Screen')), findsOneWidget);
      final root = t.getSemantics(find.bySemanticsLabel('Add Unmatched to your Home Screen'));
      final flags = root.getSemanticsData().flagsCollection;
      expect(flags.scopesRoute && flags.namesRoute, isTrue, reason: 'announced as a dialog');
      expect(t.getSize(find.byKey(const ValueKey('fs-got-it'))).height, greaterThanOrEqualTo(48));
      for (final n in [1, 2, 3]) {
        expect(t.getSize(find.byKey(ValueKey('fs-step-$n'))).height, greaterThanOrEqualTo(16));
      }
      handle.dispose();
      await t.tap(find.byKey(const ValueKey('fs-got-it')));
      await settle(t);
    });

    testWidgets('focus stays inside the dialog however many times Tab is pressed', (t) async {
      final s = makeServices(ipadDesktop());
      await boot(t, s, const Size(1024, 768), opener(s, ipadDesktop()));
      await openDialog(t);
      for (var i = 0; i < 8; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        final focus = FocusManager.instance.primaryFocus;
        final inside = focus?.context?.findAncestorWidgetOfExactType<FullscreenHelpDialog>() != null;
        expect(inside, isTrue, reason: 'focus escaped to the page behind after $i Tabs');
      }
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
    });
  });

  group('every window size', () {
    for (final (label, size) in sizes) {
      for (final info in [iphoneSafari(), ipadDesktop()]) {
        testWidgets('$label, ${info.deviceKind.name}: no overflow, the panel fits, GOT IT can be reached', (t) async {
          final s = makeServices(info);
          await bootBare(t, s, size, opener(s, info));
          await openDialog(t);
          expect(t.takeException(), isNull);
          final panel = t.getRect(find.byKey(const ValueKey('fs-panel')));
          expect(panel.left, greaterThanOrEqualTo(-0.5));
          expect(panel.right, lessThanOrEqualTo(size.width + 0.5), reason: 'inside the window');
          expect(panel.top, greaterThanOrEqualTo(-0.5));
          expect(panel.bottom, lessThanOrEqualTo(size.height + 0.5));
          // Scrollable: bring GOT IT into view if the content doesn't fit, then press it.
          await t.ensureVisible(find.byKey(const ValueKey('fs-got-it')));
          await t.pump();
          await t.tap(find.byKey(const ValueKey('fs-got-it')));
          await settle(t);
          expect(find.byType(FullscreenHelpDialog), findsNothing);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('a very large system font still fits (scrolls) on a small phone', (t) async {
      final s = makeServices(iphoneSafari());
      await bootBare(t, s, const Size(667, 375), opener(s, iphoneSafari()));
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      await openDialog(t);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.byKey(const ValueKey('fs-got-it')));
      await t.tap(find.byKey(const ValueKey('fs-got-it')));
      await settle(t);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
    });
  });

  group('when it shows', () {
    testWidgets('on an iPhone the menu shows it by itself, once; after GOT IT a restart does not show it again', (t) async {
      final storage = MemoryFullscreenHelpStorage();
      var s = makeServices(iphoneSafari(), storage: storage);
      await boot(t, s, const Size(926, 428), const MenuScreen());
      await t.pump(const Duration(seconds: 2));
      expect(find.byType(FullscreenHelpDialog), findsOneWidget, reason: 'shortly after the menu loads');
      await t.tap(find.byKey(const ValueKey('fs-got-it')));
      await settle(t);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      expect(storage.dismissed, isTrue);
      await t.pumpWidget(const SizedBox());
      // "Restart the app": new services over the same storage.
      s = makeServices(iphoneSafari(), storage: storage);
      await boot(t, s, const Size(926, 428), const MenuScreen());
      await t.pump(const Duration(seconds: 3));
      expect(find.byType(FullscreenHelpDialog), findsNothing, reason: 'dismissed: not again');
      await t.pumpWidget(const SizedBox());
    });

    for (final (label, info) in [('iPad Safari desktop mode', ipadDesktop()), ('iPad mobile mode', ipadMobile())]) {
      testWidgets('$label: shown by itself too, with the iPad title', (t) async {
        final s = makeServices(info);
        await boot(t, s, const Size(1024, 768), const MenuScreen());
        await t.pump(const Duration(seconds: 2));
        expect(find.byType(FullscreenHelpDialog), findsOneWidget);
        expect(text('fs-title'), 'FULL SCREEN ON IPAD');
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(t);
        await t.pumpWidget(const SizedBox());
      });
    }

    for (final (label, info) in [
      ('a real Mac', const PlatformInfo(userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15', platform: 'MacIntel', fullscreenSupported: true)),
      ('Windows', windows()),
      ('an iPhone already on the Home Screen', iphoneSafari(standalone: true)),
      ('an iPad already on the Home Screen', ipadDesktop(standalone: true)),
    ]) {
      testWidgets('$label: never by itself', (t) async {
        final s = makeServices(info);
        await boot(t, s, const Size(1024, 768), const MenuScreen());
        await t.pump(const Duration(seconds: 3));
        expect(find.byType(FullscreenHelpDialog), findsNothing);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('never during a match, even before it is dismissed', (t) async {
      final s = makeServices(iphoneSafari());
      await t.runAsync(() => s.loadData());
      final config = MatchConfig(mode: GameMode.duel, players: 2, map: s.data.maps['blossom']!, ai: AiLevel.easy, heroIds: const ['alice', 'medusa']);
      await boot(t, s, const Size(926, 428), const MenuScreen());
      // The match opens over the menu before the menu's timer fires: the menu is no longer on top.
      final navigator = t.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => MatchScreen(config: config, seed: 2))));
      await t.pump(const Duration(milliseconds: 100));
      expect(s.fullscreen.inMatch, isTrue);
      expect(s.fullscreen.shouldAutoShowHelp, isFalse);
      await t.pump(const Duration(seconds: 5));
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      expect(s.fullscreen.inMatch, isFalse, reason: 'the flag is cleared when the match is gone');
    });
  });

  group('the Full Screen button in Settings and the menu', () {
    Future<void> settings(WidgetTester t, Services s, Size size) => boot(t, s, size, const SettingsScreen());

    testWidgets('iPhone: opens the dialog straight away, even after it was dismissed, and never calls the API', (t) async {
      final fake = FakePlatformInfoService(iphoneSafari().copyWith(fullscreenSupported: true));
      final s = makeServices(iphoneSafari(), storage: MemoryFullscreenHelpStorage(dismissed: true), fake: fake);
      await s.fullscreen.load();
      await settings(t, s, const Size(926, 428));
      await t.ensureVisible(find.byKey(const ValueKey('settings-fullscreen')));
      await t.tap(find.byKey(const ValueKey('settings-fullscreen')));
      await settle(t, 400);
      expect(find.byType(FullscreenHelpDialog), findsOneWidget);
      expect(fake.requests, 0);
      expect(find.byKey(const ValueKey('settings-install')), findsNothing, reason: 'the install option is an iPad thing');
      await t.tap(find.byKey(const ValueKey('fs-got-it')));
      await settle(t);
    });

    testWidgets('iPad where full screen works: enters it, no dialog, the label becomes Exit; pressing again leaves', (t) async {
      final fake = FakePlatformInfoService(ipadDesktop());
      final s = makeServices(ipadDesktop(), fake: fake);
      await settings(t, s, const Size(1024, 768));
      await t.ensureVisible(find.byKey(const ValueKey('settings-fullscreen')));
      expect(find.text('FULL SCREEN'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('settings-fullscreen')));
      await settle(t, 400);
      expect(fake.requests, 1);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      expect(find.text('EXIT FULL SCREEN'), findsOneWidget, reason: 'the label follows the state');
      await t.tap(find.byKey(const ValueKey('settings-fullscreen')));
      await settle(t, 400);
      expect(fake.exits, 1);
      expect(find.text('EXIT FULL SCREEN'), findsNothing);
      // The system leaves full screen by itself: the label follows that too.
      fake.setFullscreen(true);
      await settle(t, 300);
      expect(find.text('EXIT FULL SCREEN'), findsOneWidget);
      fake.setFullscreen(false);
      await settle(t, 300);
      expect(find.text('EXIT FULL SCREEN'), findsNothing);
    });

    for (final behavior in [FakeFullscreen.refuses, FakeFullscreen.throws]) {
      testWidgets('iPad where the API is blocked (${behavior.name}): the dialog opens instead', (t) async {
        final fake = FakePlatformInfoService(ipadDesktop(), behavior: behavior);
        final s = makeServices(ipadDesktop(), fake: fake);
        await settings(t, s, const Size(1024, 768));
        await t.ensureVisible(find.byKey(const ValueKey('settings-fullscreen')));
        await t.tap(find.byKey(const ValueKey('settings-fullscreen')));
        await settle(t, 400);
        expect(fake.requests, 1, reason: 'it tried first');
        expect(find.byType(FullscreenHelpDialog), findsOneWidget);
        expect(text('fs-title'), 'FULL SCREEN ON IPAD');
        await t.tap(find.byKey(const ValueKey('fs-got-it')));
        await settle(t);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('iPad also offers "Better full screen: install the app", which opens the dialog', (t) async {
      final fake = FakePlatformInfoService(ipadDesktop());
      final s = makeServices(ipadDesktop(), storage: MemoryFullscreenHelpStorage(dismissed: true), fake: fake);
      await s.fullscreen.load();
      await settings(t, s, const Size(1024, 768));
      await t.ensureVisible(find.byKey(const ValueKey('settings-install')));
      expect(find.text('BETTER FULL SCREEN: INSTALL THE APP'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('settings-install')));
      await settle(t, 400);
      expect(find.byType(FullscreenHelpDialog), findsOneWidget);
      expect(fake.requests, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
    });

    testWidgets('Windows / Android / Mac: the API, no dialog and no install option', (t) async {
      final fake = FakePlatformInfoService(windows());
      final s = makeServices(windows(), fake: fake);
      await settings(t, s, const Size(1024, 768));
      await t.ensureVisible(find.byKey(const ValueKey('settings-fullscreen')));
      await t.tap(find.byKey(const ValueKey('settings-fullscreen')));
      await settle(t, 400);
      expect(fake.requests, 1);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      expect(find.byKey(const ValueKey('settings-install')), findsNothing);
    });

    testWidgets('already on the Home Screen: the button is hidden', (t) async {
      for (final info in [iphoneSafari(standalone: true), ipadDesktop(standalone: true)]) {
        final s = makeServices(info);
        await settings(t, s, const Size(1024, 768));
        expect(find.byKey(const ValueKey('settings-fullscreen')), findsNothing);
        expect(find.byKey(const ValueKey('settings-install')), findsNothing);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the main menu button follows the same rules (iPhone: dialog; iPad: API first)', (t) async {
      final fake = FakePlatformInfoService(ipadDesktop());
      final s = makeServices(ipadDesktop(), storage: MemoryFullscreenHelpStorage(dismissed: true), fake: fake);
      await s.fullscreen.load();
      await boot(t, s, const Size(1024, 768), const MenuScreen());
      await t.tap(find.byKey(const ValueKey('fullscreen-button')));
      await settle(t, 400);
      expect(fake.requests, 1);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      final phone = makeServices(iphoneSafari(), storage: MemoryFullscreenHelpStorage(dismissed: true));
      await phone.fullscreen.load();
      await boot(t, phone, const Size(926, 428), const MenuScreen());
      await t.tap(find.byKey(const ValueKey('fullscreen-button')));
      await settle(t, 400);
      expect(find.byType(FullscreenHelpDialog), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('fs-got-it')));
      await settle(t);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('rotate and "make this window larger"', () {
    Future<void> app(WidgetTester t, PlatformInfo info, Size size) async {
      final s = makeServices(info);
      // A bare page: the notice is drawn over whatever the app shows, so the page doesn't matter.
      await boot(t, s, size, const Scaffold(body: SizedBox.expand()));
    }

    testWidgets('an iPhone held upright gets the rotate screen; on its side it does not', (t) async {
      await app(t, iphoneSafari(standalone: true), const Size(390, 844));
      expect(find.byKey(const ValueKey('notice-rotate')), findsOneWidget);
      expect(find.text('TURN YOUR PHONE'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await app(t, iphoneSafari(standalone: true), const Size(844, 390));
      expect(find.byKey(const ValueKey('notice-rotate')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('an iPad NEVER gets the rotate screen, in either orientation, in either mode', (t) async {
      for (final info in [ipadDesktop(standalone: true), ipadMobile(standalone: true)]) {
        for (final size in const [Size(768, 1024), Size(1024, 768), Size(834, 1194), Size(1366, 1024), Size(1024, 1366)]) {
          await app(t, info, size);
          expect(find.byKey(const ValueKey('notice-rotate')), findsNothing, reason: '${info.userAgent} $size');
          expect(find.byKey(const ValueKey('notice-larger')), findsNothing, reason: '$size is big enough');
          await t.pumpWidget(const SizedBox());
        }
      }
    });

    testWidgets('Split View / Slide Over widths too small for the game say "Make this window larger", not a broken layout', (t) async {
      for (final size in const [Size(320, 768), Size(438, 1024), Size(507, 768)]) {
        await app(t, ipadDesktop(standalone: true), size);
        expect(find.byKey(const ValueKey('notice-larger')), findsOneWidget, reason: '$size');
        expect(find.text('MAKE THIS WINDOW LARGER'), findsOneWidget);
        expect(find.byKey(const ValueKey('notice-rotate')), findsNothing, reason: 'not the phone message on an iPad');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
      await app(t, ipadDesktop(standalone: true), const Size(678, 768));
      expect(find.byKey(const ValueKey('notice-larger')), findsNothing, reason: 'a two-thirds Split View is playable');
      await t.pumpWidget(const SizedBox());
    });

    test('the rules as a function', () {
      expect(viewportNotice(const Size(390, 844), iphoneSafari()), ViewportNotice.rotate);
      expect(viewportNotice(const Size(844, 390), iphoneSafari()), isNull);
      expect(viewportNotice(const Size(768, 1024), ipadDesktop()), isNull);
      expect(viewportNotice(const Size(320, 768), ipadDesktop()), ViewportNotice.larger);
      expect(viewportNotice(const Size(1024, 250), ipadMobile()), ViewportNotice.larger);
      expect(viewportNotice(const Size(568, 320), const PlatformInfo(userAgent: 'Android', maxTouchPoints: 5)), isNull);
    });
  });
}
