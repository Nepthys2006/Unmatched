// The whole Full Screen help flow in a real browser (Chrome), with the device simulated by an
// injected PlatformInfo service: iPhone, iPad (desktop-mode and mobile user agents), Android and
// desktop.  Storage is the browser's real localStorage, so "restart the app" really reloads the flag.
//
//   flutter test integration_test/fullscreen_help_test.dart -d chrome
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/dialogs/fullscreen_help_dialog.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';
import 'package:unmatched_game/ui/platform/fullscreen_help_storage.dart';
import 'package:unmatched_game/ui/platform/platform_info.dart';
import 'package:unmatched_game/ui/platform/platform_info_service.dart';
import 'package:unmatched_game/ui/screens/menu_screen.dart';
import 'package:unmatched_game/ui/screens/settings_screen.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';

const uaIphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const uaIpadDesktop = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
const uaIpadMobile = 'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const uaAndroid = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
const uaWindows = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const iphone = PlatformInfo(userAgent: uaIphone, platform: 'iPhone', maxTouchPoints: 5);
const ipadDesktop = PlatformInfo(userAgent: uaIpadDesktop, platform: 'MacIntel', maxTouchPoints: 5, fullscreenSupported: true);
const ipadMobile = PlatformInfo(userAgent: uaIpadMobile, platform: 'iPad', maxTouchPoints: 5, fullscreenSupported: true);
const android = PlatformInfo(userAgent: uaAndroid, platform: 'Linux armv81', maxTouchPoints: 5, fullscreenSupported: true);
const desktop = PlatformInfo(userAgent: uaWindows, platform: 'Win32', fullscreenSupported: true);

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Services newApp(FakePlatformInfoService fake) {
    final settings = Settings.memory()
      ..username = 'Tester'
      ..board3d = false;
    return Services(
      settings: settings,
      audio: Audio(settings, enabled: false),
      preloadImages: false,
      platformInfo: fake,
      // The browser's real localStorage, so a "restart" reads what the last run saved.
      helpStorage: const SharedPrefsFullscreenHelpStorage(),
    );
  }

  Future<void> launch(WidgetTester t, Services s, Widget home) async {
    await t.runAsync(() => s.loadData());
    await t.runAsync(() => s.fullscreen.load());
    await t.pumpWidget(UnmatchedApp(services: s, home: home));
    await settle(t);
  }

  setUp(() async {
    // A clean browser: nothing remembered.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  group('the flow on each device', () {
    for (final (name, info, title) in [
      ('iPhone', iphone, 'FULL SCREEN ON IPHONE'),
      ('iPad (desktop-mode user agent)', ipadDesktop, 'FULL SCREEN ON IPAD'),
      ('iPad (mobile user agent)', ipadMobile, 'FULL SCREEN ON IPAD'),
    ]) {
      testWidgets('$name: shown once, GOT IT, not after a restart, Settings opens it again', (t) async {
        final fake = FakePlatformInfoService(info, behavior: info.deviceKind == DeviceKind.ipad ? FakeFullscreen.refuses : FakeFullscreen.succeeds);
        await launch(t, newApp(fake), const MenuScreen());
        await t.pump(const Duration(seconds: 2));
        // 1. Loads and the dialog appears by itself, with the right title.
        expect(find.byType(FullscreenHelpDialog), findsOneWidget);
        expect((t.widget(find.byKey(const ValueKey('fs-title'))) as Text).data, title);
        // 2. GOT IT closes it.
        await t.tap(find.byKey(const ValueKey('fs-got-it')));
        await settle(t);
        expect(find.byType(FullscreenHelpDialog), findsNothing);
        // 3. Restart: a brand new app over the same browser storage.
        await t.pumpWidget(const SizedBox());
        final again = newApp(FakePlatformInfoService(info, behavior: fake.behavior));
        await launch(t, again, const MenuScreen());
        await t.pump(const Duration(seconds: 3));
        expect(find.byType(FullscreenHelpDialog), findsNothing, reason: 'remembered across the restart');
        // 4. Settings -> Full Screen behaves for the device.
        await t.pumpWidget(const SizedBox());
        final fake2 = FakePlatformInfoService(info, behavior: fake.behavior);
        await launch(t, newApp(fake2), const SettingsScreen());
        await t.ensureVisible(find.byKey(const ValueKey('settings-fullscreen')));
        await t.tap(find.byKey(const ValueKey('settings-fullscreen')));
        await settle(t);
        expect(find.byType(FullscreenHelpDialog), findsOneWidget, reason: 'iPhone: always the dialog; iPad: the API refused, so the dialog');
        expect(fake2.requests, info.deviceKind == DeviceKind.ipad ? 1 : 0, reason: 'only the iPad tries the Fullscreen API first');
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(t);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('iPad where the Fullscreen API works: enters full screen and no dialog opens', (t) async {
      final fake = FakePlatformInfoService(ipadDesktop);
      await launch(t, newApp(fake), const SettingsScreen());
      await t.ensureVisible(find.byKey(const ValueKey('settings-fullscreen')));
      await t.tap(find.byKey(const ValueKey('settings-fullscreen')));
      await settle(t);
      expect(fake.requests, 1);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      expect(find.text('EXIT FULL SCREEN'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    for (final (name, info) in [('Android', android), ('desktop', desktop)]) {
      testWidgets('$name: never shows the dialog, the button uses the Fullscreen API', (t) async {
        final fake = FakePlatformInfoService(info);
        await launch(t, newApp(fake), const MenuScreen());
        await t.pump(const Duration(seconds: 3));
        expect(find.byType(FullscreenHelpDialog), findsNothing);
        await t.tap(find.byKey(const ValueKey('fullscreen-button')));
        await settle(t);
        expect(fake.requests, 1);
        expect(find.byType(FullscreenHelpDialog), findsNothing);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('already on the Home Screen: no dialog, no button', (t) async {
      final fake = FakePlatformInfoService(ipadDesktop.copyWith(isStandalone: true));
      await launch(t, newApp(fake), const MenuScreen());
      await t.pump(const Duration(seconds: 3));
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      expect(find.byKey(const ValueKey('fullscreen-button')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('during a match', () {
    testWidgets('the help never appears, and turning or resizing an iPad mid-match keeps the match', (t) async {
      final fake = FakePlatformInfoService(ipadDesktop.copyWith(isStandalone: true));
      final s = newApp(fake);
      await t.runAsync(() => s.loadData());
      final config = MatchConfig(mode: GameMode.duel, players: 2, map: s.data.maps['blossom']!, ai: AiLevel.easy, heroIds: const ['alice', 'medusa']);
      t.view.physicalSize = const Size(1024, 768) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: config, seed: 5, autoplay: true)));
      // Let the match get going.
      for (var i = 0; i < 400; i++) {
        await t.pump(const Duration(milliseconds: 50));
        if (t.state<MatchScreenState>(find.byType(MatchScreen)).game.turnNumber >= 2) break;
      }
      final st = t.state<MatchScreenState>(find.byType(MatchScreen));
      final turn = st.game.turnNumber;
      final hands = [for (final p in st.game.players) p.hand.length + p.deck.length + p.discard.length];
      expect(turn, greaterThanOrEqualTo(1));
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      // Landscape -> portrait -> Split View width -> back.
      for (final size in const [Size(768, 1024), Size(678, 1024), Size(1024, 768)]) {
        t.view.physicalSize = size * 2;
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull, reason: '$size');
        expect(t.state<MatchScreenState>(find.byType(MatchScreen)), same(st), reason: 'the same match, not a new one');
        expect(find.byType(FullscreenHelpDialog), findsNothing);
      }
      // Narrower than the game can use: a notice instead of a broken layout, still the same match.
      t.view.physicalSize = const Size(320, 768) * 2;
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('notice-larger')), findsOneWidget);
      t.view.physicalSize = const Size(1024, 768) * 2;
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('notice-larger')), findsNothing);
      expect(t.state<MatchScreenState>(find.byType(MatchScreen)), same(st));
      expect(st.game.turnNumber, greaterThanOrEqualTo(turn), reason: 'the match carried on');
      expect([for (final p in st.game.players) p.hand.length + p.deck.length + p.discard.length].length, hands.length);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('an iPhone that has not dismissed the help still never gets it in a match', (t) async {
      final fake = FakePlatformInfoService(iphone);
      final s = newApp(fake);
      await t.runAsync(() => s.loadData());
      final config = MatchConfig(mode: GameMode.duel, players: 2, map: s.data.maps['blossom']!, ai: AiLevel.easy, heroIds: const ['alice', 'medusa']);
      t.view.physicalSize = const Size(844, 390) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: config, seed: 5)));
      await t.pump(const Duration(seconds: 5));
      expect(s.fullscreen.inMatch, isTrue);
      expect(find.byType(FullscreenHelpDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    });
  });
}
