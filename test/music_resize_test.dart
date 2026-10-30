import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/main.dart' show UnmatchedApp;
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/screens/menu_screen.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';

import 'widget_test.dart' show loadFonts;

/// Counts the tracks the screens ask for.
class RecordingAudio extends Audio {
  RecordingAudio(super.settings) : super(enabled: false);
  final List<Music> requests = [];
  @override
  void music(Music m) => requests.add(m);
}

void main() {
  setUpAll(loadFonts);

  // Regression: minimizing the window (or resizing it, or turning a phone) re-ran the menu's
  // didChangeDependencies, which asked for the menu theme again - on top of the battle music when
  // a match was open above the menu.
  testWidgets('resizing or minimizing the window does not restart the menu music', (t) async {
    t.view.physicalSize = const Size(1830, 824);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final settings = Settings.memory()
      ..username = 'Tester'
      ..board3d = false;
    final audio = RecordingAudio(settings);
    final services = Services(settings: settings, audio: audio, preloadImages: false);
    await t.runAsync(() => services.loadData());
    await t.pumpWidget(UnmatchedApp(services: services, home: const MenuScreen()));
    expect(audio.requests, [Music.menu], reason: 'the menu asks for its theme once when it opens');

    // A "match" opens above the menu; the menu stays mounted underneath it.
    final nav = Navigator.of(t.element(find.byType(MenuScreen)));
    unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('match')))));
    await t.pumpAndSettle();
    audio.requests.clear();

    for (final size in const [Size(4, 4), Size(1830, 824), Size(900, 700), Size(1830, 824)]) {
      t.view.physicalSize = size;
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(audio.requests, isEmpty, reason: 'a window resize must not ask for any music');
  });
}
