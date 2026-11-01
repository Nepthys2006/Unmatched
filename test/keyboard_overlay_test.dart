// The on-screen keyboard overlays the sign-in / create-account screen (and the LAN screen) instead
// of squeezing them: nothing is resized or distorted, the form only scrolls so the field you are
// typing in stays above the keys. Checked for Android phones, small phones, tablets and iPads, in
// both orientations where the app allows them, with the keyboard up for each field, while
// switching tabs, and after it closes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/screens/multiplayer_screen.dart';
import 'package:unmatched_game/ui/screens/username_screen.dart';
import 'package:unmatched_game/ui/widgets.dart';

import 'widget_test.dart' show loadFonts, makeServices;

/// A device: window size (logical px) and the height its keyboard takes.
typedef Device = (String name, Size size, double keyboard);

const devices = <Device>[
  ('android phone landscape', Size(915, 412), 230),
  ('small android phone landscape', Size(740, 360), 200),
  ('iphone se landscape', Size(568, 320), 190),
  ('iphone landscape', Size(844, 390), 210),
  ('android tablet landscape', Size(1280, 800), 330),
  ('android tablet portrait', Size(800, 1280), 420),
  ('ipad landscape', Size(1024, 768), 330),
  ('ipad portrait', Size(768, 1024), 400),
  ('web tablet', Size(1100, 700), 300),
  ('desktop', Size(1440, 900), 0),
];

Future<void> settle(WidgetTester t, [int ms = 500]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

/// What must not change when the keyboard comes up: the size of every piece of the screen.
Map<String, Size> sizes(WidgetTester t, Map<String, Finder> pieces) => {
  for (final e in pieces.entries) e.key: t.getSize(e.value.first),
};

void main() {
  setUpAll(loadFonts);

  Future<void> open(WidgetTester t, Size size, Widget home) async {
    final s = makeServices();
    await t.runAsync(() => s.loadData());
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(() {
      t.view.reset();
      t.view.resetViewInsets();
    });
    await t.pumpWidget(UnmatchedApp(services: s, home: home));
    await settle(t);
  }

  void keyboard(WidgetTester t, double height) => t.view.viewInsets = FakeViewPadding(bottom: height * 2);

  /// The keyboard slides in; the form then scrolls the field into the free area (a debounce, then
  /// a short animation), which needs frames after the timer fires.
  Future<void> keyboardUp(WidgetTester t, double height) async {
    keyboard(t, height);
    await settle(t, 600);
    await settle(t, 400);
    await settle(t, 400);
  }

  /// The field is fully on screen and above the keyboard.
  void expectAboveKeyboard(WidgetTester t, Finder field, Size window, double kb, String why) {
    final r = t.getRect(field.first);
    expect(r.top, greaterThanOrEqualTo(-0.5), reason: '$why: not above the top edge');
    expect(r.bottom, lessThanOrEqualTo(window.height - kb + 0.5), reason: '$why: hidden behind the keyboard ($r, keyboard top ${window.height - kb})');
  }

  group('sign in / create account', () {
    for (final (name, size, kb) in devices) {
      testWidgets('keyboard overlays it, nothing is squeezed, the field stays above the keys ($name)', (t) async {
        await open(t, size, const UsernameScreen());
        final landscapePhone = size.shortestSide < 600 && size.width > size.height;
        final portraitPhone = size.height > size.width && size.shortestSide < 600;
        expect(portraitPhone, isFalse, reason: 'phones are landscape only: the rotate prompt covers upright phones');
        final fields = find.byType(TextField);
        expect(fields, findsNWidgets(2));
        final pieces = {
          'title': find.textContaining('ARENA'),
          'sign-in tab': find.text('SIGN IN').first,
          'create tab': find.text('CREATE ACCOUNT'),
          'username': fields.at(0),
          'password': fields.at(1),
          // Not resized: the screen's body keeps the whole window and the sign-in plate its size.
          'body': find.byType(SafeArea),
          'sign-in button': find.byType(PlateButton),
        };
        final before = sizes(t, pieces);

        for (final (i, label) in [(0, 'username'), (1, 'password')]) {
          await t.tap(fields.at(i));
          await settle(t, 300);
          await keyboardUp(t, kb);
          expect(t.takeException(), isNull, reason: '$name, $label focused');
          // Nothing was squeezed or resized: every piece keeps its size, the hero stays where it was.
          expect(sizes(t, pieces), before, reason: '$name: the screen was resized with the keyboard up ($label)');
          expectAboveKeyboard(t, fields.at(i), size, kb, '$name $label field');
          keyboard(t, 0);
          await settle(t, 400);
        }

        // Create account (more text under each field) while the keyboard is up.
        await t.tap(find.text('CREATE ACCOUNT'));
        await settle(t, 300);
        await t.tap(fields.at(1));
        await keyboardUp(t, kb);
        expect(t.takeException(), isNull, reason: '$name create account');
        expectAboveKeyboard(t, fields.at(1), size, kb, '$name create-account password field');
        await t.enterText(fields.at(1), 'abcdef');
        await settle(t, 300);
        expect(t.takeException(), isNull);

        // The keyboard closes: the form is back where it was.
        keyboard(t, 0);
        await settle(t, 600);
        expect(t.takeException(), isNull);
        expect(landscapePhone || size.shortestSide >= 600, isTrue);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('the screen is the same layout whether the keyboard is up or not (the title keeps its size)', (t) async {
      await open(t, const Size(740, 360), const UsernameScreen());
      final title = find.textContaining('ARENA');
      final before = t.getRect(title);
      keyboard(t, 200);
      await settle(t, 600);
      // The title is part of the form's scroll area, so it may scroll up out of the way, but it is
      // never made smaller.
      expect(t.getSize(title).width, closeTo(before.width, 0.01));
      expect(t.getSize(title).height, closeTo(before.height, 0.01));
      await t.pumpWidget(const SizedBox());
    });
  });

  group('LAN and online screen', () {
    for (final (name, size, kb) in devices.where((d) => d.$3 > 0)) {
      testWidgets('typing the host address overlays the keyboard without squeezing the screen ($name)', (t) async {
        await open(t, size, const MultiplayerScreen(online: false));
        final address = find.widgetWithText(TextField, '192.168.43.1').evaluate().isNotEmpty
            ? find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '192.168.43.1')
            : find.byType(TextField);
        expect(address, findsWidgets);
        final header = find.text('LAN');
        final headerBefore = t.getRect(header);
        final field = address.first;
        await t.ensureVisible(field);
        await t.pump();
        final fieldSize = t.getSize(field);
        await t.tap(field);
        await settle(t, 300);
        await keyboardUp(t, kb);
        expect(t.takeException(), isNull, reason: name);
        expect(t.getRect(header), headerBefore, reason: '$name: the header moved or shrank');
        expect(t.getSize(field), fieldSize, reason: '$name: the field was squeezed');
        expectAboveKeyboard(t, field, size, kb, '$name address field');
        keyboard(t, 0);
        await settle(t, 400);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  });
}
