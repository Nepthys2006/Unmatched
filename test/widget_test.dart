// UI tests: first launch, menus, setup for every mode, and whole matches played through the real
// match screen (an AI answers the player's prompts) at phone and desktop sizes. Any layout
// overflow or exception during these fails the test.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';
import 'package:unmatched_game/ui/screens/menu_screen.dart';
import 'package:unmatched_game/ui/screens/setup_screen.dart';
import 'package:unmatched_game/ui/screens/username_screen.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';

const phone = Size(915, 412);
const desktop = Size(1440, 900);

/// A small Android phone in landscape.
const smallPhone = Size(740, 360);
String sizeName(Size s) => s == phone ? 'phone' : (s == smallPhone ? 'small phone' : 'desktop');

Services makeServices({String username = 'Tester', double speed = 0}) {
  final s = Settings.memory()
    ..username = username
    ..speedOverride = speed
    // No web view in widget tests: the 3D board has its own browser checks.
    ..board3d = false;
  return Services(settings: s, audio: Audio(s, enabled: false), preloadImages: false);
}

Future<Services> boot(WidgetTester t, Size size, {String username = 'Tester', Widget? home}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final s = makeServices(username: username);
  await t.runAsync(() => s.loadData());
  await t.pumpWidget(UnmatchedApp(services: s, home: home));
  return s;
}

/// Pumps frames until [done] or the frame budget runs out.
Future<void> pumpUntil(WidgetTester t, bool Function() done, {int frames = 400, Duration step = const Duration(milliseconds: 100)}) async {
  for (var i = 0; i < frames && !done(); i++) {
    await t.pump(step);
  }
}

/// The bundled fonts, so overflow checks measure the real (condensed) lettering.
Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Saira', ['SairaCondensed-SemiBold.ttf', 'SairaCondensed-Bold.ttf', 'SairaCondensed-ExtraBold.ttf']);
  await family('Barlow', ['BarlowSemiCondensed-Medium.ttf', 'BarlowSemiCondensed-SemiBold.ttf', 'BarlowSemiCondensed-Bold.ttf']);
}

void main() {
  // Regression: over the hand limit by one card, the picker used to open a read-only zoom with no
  // way to confirm. One tap now picks the card.
  testWidgets('a one-card pick (hand limit) takes a single tap', (t) async {
    List<int>? picked;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardPicker(
            title: 'Hand limit is 7: discard 1 card',
            images: [for (var i = 1; i <= 8; i++) 'assets/cards/achilles/0$i.webp'],
            min: 1,
            max: 1,
            onDone: (p) => picked = p,
            onZoom: (_) {},
          ),
        ),
      ),
    );
    await t.tap(find.byType(GestureDetector).at(2));
    expect(picked, [2]);
  });

  setUpAll(loadFonts);
  test('player names are trimmed and limited', () {
    expect(nameError('   '), isNotNull);
    expect(nameError('A' * (maxNameLength + 1)), isNotNull);
    expect(nameError('  Daryl '), isNull);
  });

  for (final size in [phone, smallPhone, desktop]) {
    final tag = sizeName(size);

    testWidgets('first launch asks for a name, then shows the menu ($tag)', (t) async {
      final s = await boot(t, size, username: '');
      await pumpUntil(t, () => find.byType(UsernameScreen).evaluate().isNotEmpty);
      expect(find.byType(UsernameScreen), findsOneWidget);

      await t.tap(find.text('CONTINUE'));
      await t.pump();
      expect(find.text('Enter a name to continue.'), findsOneWidget);

      await t.enterText(find.byType(TextField), '  Daryl ');
      await t.tap(find.text('CONTINUE'));
      await pumpUntil(t, () => find.byType(MenuScreen).evaluate().isNotEmpty);
      expect(s.settings.username, 'Daryl');
      expect(find.text('PLAY VS AI'), findsOneWidget);
      // LAN and Online are live (no "Coming soon" badge any more).
      expect(find.text('LAN'), findsOneWidget);
      expect(find.text('ONLINE'), findsOneWidget);
      expect(find.text('COMING SOON'), findsNothing);
      await t.pump(const Duration(seconds: 1));
    });

    for (final mode in GameMode.values) {
      testWidgets('setup reaches the match for ${mode.label} ($tag)', (t) async {
        await boot(t, size, home: const SetupScreen());
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.text(mode.label.toUpperCase()));
        await t.pump();
        if (mode == GameMode.ffa) {
          await t.tap(find.text('5'));
          await t.pump();
        }
        await t.tap(find.text('CHOOSE MAP'));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('BATTLEFIELD'), findsOneWidget);
        await t.tap(find.text('RANDOM MAP'));
        await t.pump(const Duration(milliseconds: 500));
        await t.tap(find.text('CHOOSE HERO'));
        await pumpUntil(t, () => find.text('CHOOSE YOUR HERO').evaluate().isNotEmpty, frames: 20);
        await t.tap(find.text('RANDOM'));
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.textContaining('FIGHT AS'));
        await pumpUntil(t, () => find.byType(MatchScreen).evaluate().isNotEmpty, frames: 60);
        expect(find.byType(MatchScreen), findsOneWidget);
        // Leave the match screen waiting on the player; replace the tree to end the test.
        await t.pump(const Duration(seconds: 1));
        await t.pumpWidget(const SizedBox());
      });
    }
  }

  final matches = <(String, GameMode, int, String, List<String>)>[
    ('1v1', GameMode.duel, 2, 'blossom', ['medusa', 'king-arthur']),
    ('1v1 sidekick swarm', GameMode.duel, 2, 'glade', ['sun-wukong', 'the-genie']),
    ('2v2', GameMode.teams2, 4, 'harbor', ['alice', 'dracula', 'sherlock-holmes', 'bigfoot']),
    ('3v3', GameMode.teams3, 6, 'keeps', ['robin-hood', 'shredder', 'invisible-man', 'annie-christmas', 'philippa', 'geralt-of-rivia']),
    ('free-for-all 5', GameMode.ffa, 5, 'star', ['loki', 'titania', 'krang', 'moon-knight', 'yennenga']),
  ];
  for (final (name, mode, players, mapId, heroes) in matches) {
    for (final size in [phone, smallPhone, desktop]) {
      testWidgets('a whole $name match plays through the UI (${sizeName(size)})', (t) async {
        // A small non-zero speed so every banner, combat and panel is laid out on some frame.
        final s = makeServices(speed: 0.05);
        await t.runAsync(() => s.loadData());
        final config = MatchConfig(mode: mode, players: players, map: s.data.maps[mapId]!, ai: AiLevel.medium, heroIds: heroes);
        t.view.physicalSize = size * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: config, seed: heroes.length * 7, autoplay: true)));
        await pumpUntil(t, () => find.byType(ResultView).evaluate().isNotEmpty, frames: 40000, step: const Duration(milliseconds: 20));
        expect(find.byType(ResultView), findsOneWidget, reason: 'the match should finish');
        expect(find.text('SOMETHING WENT WRONG'), findsNothing);
        final turns = int.parse((t.widget<Text>(find.textContaining('turns played')).data!).split(' ').first);
        expect(turns, greaterThan(3), reason: 'a real match takes several turns');
        // ignore: avoid_print
        print('$name: $turns turns');
        await t.pump(const Duration(seconds: 1));
        await t.pumpWidget(const SizedBox());
      }, timeout: const Timeout(Duration(minutes: 6)));
    }
  }
}
