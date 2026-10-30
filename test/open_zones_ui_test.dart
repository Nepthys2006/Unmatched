// Heroes' open cards (Pandora's MISERIES and HOPE, Titania's GLAMOURS, the cauldron, the line),
// the hand-count cards on every plate, and the hero search. Engine data first, then the widgets,
// then the real match screen at phone and desktop sizes (nothing overflows or overlaps). Set
// CAPTURE=true to also write screenshots to build/hud_shots/.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/heroes/bol_more.dart';
import 'package:unmatched_game/engine/open_cards.dart';
import 'package:unmatched_game/engine/state.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/dials.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';
import 'package:unmatched_game/ui/match/open_zones.dart';
import 'package:unmatched_game/ui/match/plate_parts.dart';
import 'package:unmatched_game/ui/screens/hero_select_screen.dart';
import 'package:unmatched_game/ui/theme.dart';

import 'match_hud_test.dart' show shot;
import 'support.dart';
import 'widget_test.dart' show loadFonts, makeServices, phone, smallPhone, desktop, sizeName;

OpenZone zone(Player p, String id) => p.script.openZones().firstWhere((z) => z.id == id);

Future<void> showPlate(WidgetTester t, Size size, Player player, Player viewer, {bool big = false, bool mini = false}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          backgroundColor: Palette.bg,
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: PlayerPlate(
                player: player,
                color: Palette.defender,
                subtitle: 'AI Easy',
                big: big,
                showHandBacks: true,
                viewer: viewer,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadFonts);

  group('open zones: engine data', () {
    Pandora pan(Scenario s) => s.p1.script as Pandora;
    void stack(Scenario s, List<String> names) => pan(s).box
      ..clear()
      ..addAll([for (final n in names) miseries.firstWhere((m) => m.name == n)]);

    test("Pandora's Box: 7 face down at the start; revealed MISERIES lie face up with their feathers; HOPE shows the next one", () async {
      final s = Scenario('pandora', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      await s.p1.script.beforeDeck(); // the game does this when it builds the decks
      var z = zone(s.p1, 'miseries');
      expect(z.hidden, 7);
      expect(z.cards, isEmpty);
      expect(z.peek, isNull);
      expect(z.alwaysShow, isTrue, reason: 'the box is on the table before anything is revealed');

      stack(s, ['Hope', 'Pain', 'Toil', 'Misfortune']);
      OpenZone? atPrompt;
      s.a1
        ..then((p) {
          atPrompt = zone(s.p1, 'miseries'); // while deciding whether to reveal another
          return [0]; // Yes: reveal Pain
        })
        ..then('No');
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(atPrompt!.cards.map((c) => c.title), ['Hope']);
      expect(atPrompt!.peek?.title, 'Pain', reason: 'HOPE is face up: Pandora may look at the next card');
      z = zone(s.p1, 'miseries');
      expect(z.cards.map((c) => c.title), ['Hope', 'Pain']);
      expect(z.hidden, 2, reason: 'Toil and Misfortune are left in the box');
      expect(z.feathers, 1);
      expect(z.peek?.title, 'Toil');
      expect(z.cards.last.text, contains('adjacent'));
      expect(z.note, contains('1 of 3 feathers'));

      await s.p1.script.endOfTurn(s.game, s.p1);
      z = zone(s.p1, 'miseries');
      expect(z.cards, isEmpty);
      expect(z.hidden, 4, reason: 'the revealed MISERIES were shuffled back in');
      expect(z.peek, isNull);
    });

    test('without HOPE nobody, not even Pandora, gets to see the next card', () async {
      final s = Scenario('pandora', 'medusa');
      s.place(s.hero(s.p1), 4);
      stack(s, ['Toil', 'Greed', 'Misfortune']);
      s.a1.then('No');
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(zone(s.p1, 'miseries').peek, isNull);
    });

    test('Misfortune has two feathers and says it has no effect', () async {
      final s = Scenario('pandora', 'medusa');
      s.place(s.hero(s.p1), 4);
      stack(s, ['Misfortune', 'Toil']);
      s.a1.then('No');
      await s.p1.script.startOfTurn(s.game, s.p1);
      final c = zone(s.p1, 'miseries').cards.single;
      expect(c.feathers, 2);
      expect(c.text, contains('No effect'));
    });

    test("Titania: the glamour deck is face down, the flipped glamour face up, discarded ones lie face up", () async {
      final s = Scenario('titania', 'medusa');
      await s.p1.script.beforeDeck();
      var z = zone(s.p1, 'glamour');
      expect(z.cards, isEmpty);
      expect(z.hidden, 6);
      expect(
        s.p1.script.openZones().any((z) => z.id == 'glamour-discard'),
        isFalse,
        reason: 'no discard pile until a glamour is discarded',
      );
      final t = s.p1.script as dynamic;
      (t.glamourDeck as List<String>)
        ..clear()
        ..addAll(['SLEEP', 'LOVE']);
      await s.p1.script.startOfTurn(s.game, s.p1);
      z = zone(s.p1, 'glamour');
      expect(z.cards.single.title, 'Glamour of Sleep');
      expect(z.cards.single.text, contains('do not take damage'));
      expect(z.hidden, 1);
      (t.glamourDiscard as List<String>).add('GREED');
      final d = zone(s.p1, 'glamour-discard');
      expect(d.cards.single.title, 'Glamour of Greed');
      expect(visibleZones(s.p1).map((z) => z.id), ['glamour', 'glamour-discard']);
    });

    test("the Wayward Sisters' cauldron and heroes without open cards", () {
      final s = Scenario('the-wayward-sisters', 'medusa');
      expect(zone(s.p1, 'cauldron').cards, isEmpty);
      final c = s.make(s.p1, s.p1.hero.cards.first.title);
      s.p1.script.aside.add(c);
      expect(zone(s.p1, 'cauldron').cards.single.image, c.def.image);
      expect(s.p2.script.openZones(), isEmpty, reason: 'Medusa keeps nothing on the table');
    });
  });

  group('open zones: widgets', () {
    for (final size in [smallPhone, desktop]) {
      testWidgets("an opponent's plate shows Pandora's revealed MISERIES, how many are left, and the tray reads them (${sizeName(size)})", (
        t,
      ) async {
        final s = Scenario('pandora', 'medusa');
        s.place(s.hero(s.p1), 4);
        (s.p1.script as Pandora).box
          ..clear()
          ..addAll([
            for (final n in ['Hope', 'Pain', 'Toil', 'Woe', 'Greed', 'Confusion', 'Misfortune']) miseries.firstWhere((m) => m.name == n),
          ]);
        s.a1.then('No');
        await s.p1.script.startOfTurn(s.game, s.p1); // reveals HOPE, then stops
        await showPlate(t, size, s.p1, s.p2, big: size == desktop);
        await shot(t, 'open-pandora-plate-${sizeName(size).replaceAll(' ', '-')}');

        expect(find.text('MISERIES'), findsOneWidget);
        expect(find.text('HOPE'), findsOneWidget, reason: 'the revealed MISERY is named on the plate');
        expect(find.byKey(const ValueKey('zone-count-miseries')), findsOneWidget);
        expect(countText(t, 'zone-count-miseries'), '6', reason: '6 MISERIES still in the box');

        // The tray: the pile, HOPE face up, and no peek for the enemy.
        await t.tap(find.byKey(ValueKey('open-zones-${s.p1.seat}')));
        await t.pump(); // mounts the dialog; the next frames fade it in
        await t.pump(const Duration(milliseconds: 400));
        await shot(t, 'open-pandora-tray-enemy-${sizeName(size).replaceAll(' ', '-')}');
        expect(find.textContaining('CARDS ON THE TABLE'), findsOneWidget);
        expect(find.textContaining('6 in the box'), findsWidgets);
        expect(find.textContaining('may look at the top card first'), findsOneWidget);
        expect(find.text('Hope: the next MISERY'), findsNothing, reason: 'only Pandora sees it');

        // Read HOPE large.
        await t.tap(find.byKey(const ValueKey('open-card-miseries-0')));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('Look at the top card'), findsWidgets);
        await t.tapAt(const Offset(4, 4));
        await t.pump(const Duration(milliseconds: 300));
        expect(countText(t, 'zone-count-miseries'), '6');
      });
    }

    testWidgets("Pandora's own tray shows the card HOPE lets her look at, in the selectable green", (t) async {
      final s = Scenario('pandora', 'medusa');
      s.place(s.hero(s.p1), 4);
      (s.p1.script as Pandora).box
        ..clear()
        ..addAll([
          for (final n in ['Hope', 'Pain', 'Toil']) miseries.firstWhere((m) => m.name == n),
        ]);
      s.a1.then('No');
      await s.p1.script.startOfTurn(s.game, s.p1);
      await showPlate(t, smallPhone, s.p1, s.p1);
      await t.tap(find.byKey(ValueKey('open-zones-${s.p1.seat}')));
      await t.pump(); // mounts the dialog; the next frames fade it in
      await t.pump(const Duration(milliseconds: 400));
      await shot(t, 'open-pandora-tray-own');
      expect(find.text('Hope: the next MISERY'), findsOneWidget);
      expect(find.text('PAIN'), findsWidgets, reason: 'the peeked card is Pain');
      expect(find.textContaining('may look at the top card first'), findsNothing);
    });

    testWidgets("Titania's open card shows on her plate; the tray has the glamour deck and discard", (t) async {
      final s = Scenario('titania', 'medusa');
      final ti = s.p1.script as dynamic;
      (ti.glamourDeck as List<String>)
        ..clear()
        ..addAll(['RHYME', 'LOVE', 'SLEEP']);
      await s.p1.script.startOfTurn(s.game, s.p1);
      (ti.glamourDiscard as List<String>).add('GREED');
      await showPlate(t, smallPhone, s.p1, s.p2);
      await shot(t, 'open-titania-plate');
      expect(find.text('GLAMOUR'), findsOneWidget);
      expect(find.text('GLAMOUR OF RHYME'), findsOneWidget);
      expect(find.text('DISCARDED'), findsOneWidget);
      await t.tap(find.byKey(ValueKey('open-zones-${s.p1.seat}')));
      await t.pump(); // mounts the dialog; the next frames fade it in
      await t.pump(const Duration(milliseconds: 400));
      await shot(t, 'open-titania-tray');
      expect(find.textContaining('2 in the glamour deck'), findsWidgets);
      expect(find.text('Ongoing while face up.'), findsOneWidget);
    });

    testWidgets('every plate shows how many cards the player holds as a fan of their card backs', (t) async {
      for (final n in [0, 1, 2, 5, 9]) {
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: Center(
                child: HandCell(count: n, back: 'assets/heroes/pandora/back.webp', size: 30),
              ),
            ),
          ),
        );
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('$n'), findsOneWidget);
        expect(t.getSize(find.byKey(const ValueKey('hand-cell'))), Size(HandCell.widthFor(30), 30));
        expect(find.byType(Image), n == 0 ? findsNothing : findsNWidgets(n.clamp(0, 3)));
      }
    });
  });

  for (final size in [smallPhone, phone, desktop]) {
    testWidgets(
      'a real match, Pandora against Titania: the cards are on the plates, nothing overlaps, HOPE shows beside her question (${sizeName(size)})',
      (t) async {
        final s = makeServices(speed: 0.05);
        await t.runAsync(() => s.loadData());
        final config = MatchConfig(
          mode: GameMode.duel,
          players: 2,
          map: s.data.maps['blossom']!,
          ai: AiLevel.easy,
          heroIds: ['pandora', 'titania'],
        );
        t.view.physicalSize = size * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('shot'),
            child: UnmatchedApp(
              services: s,
              home: MatchScreen(config: config, seed: 5),
            ),
          ),
        );
        final state = t.state<MatchScreenState>(find.byType(MatchScreen));
        final pandora = state.game.players[0].script as Pandora;
        // Make HOPE the first MISERY (the first reveal is not a choice), so her next question has
        // something to look at.
        pandora.box
          ..clear()
          ..addAll([
            for (final n in ['Hope', 'Toil', 'Greed', 'Pain', 'Woe', 'Confusion', 'Misfortune']) miseries.firstWhere((m) => m.name == n),
          ]);

        final asked = find.textContaining('Reveal another MISERY');
        for (var i = 0; i < 9000 && asked.evaluate().isEmpty; i++) {
          await t.pump(const Duration(milliseconds: 20));
          for (final label in ['SKIP', 'NO DEFENSE']) {
            final skip = find.text(label);
            if (skip.evaluate().isNotEmpty) await t.tap(skip.first);
          }
        }
        final tag = sizeName(size).replaceAll(' ', '-');
        if (asked.evaluate().isEmpty) await shot(t, 'open-match-stuck-$tag');
        expect(asked, findsWidgets, reason: "Pandora's turn starts with the box");
        await t.pump(const Duration(milliseconds: 500));
        await shot(t, 'open-match-hope-$tag');
        expect(
          find.byKey(const ValueKey('peek-aside')),
          findsOneWidget,
          reason: 'HOPE is face up: the next MISERY shows beside the question',
        );
        expect(find.text('Hope: the next MISERY'), findsOneWidget);
        expect(find.text('TOIL'), findsWidgets);

        // Answer No: the plates and the tray stay whole.
        await t.tap(find.byKey(const ValueKey('choice-1')));
        await t.pump(const Duration(milliseconds: 600));
        expect(find.byKey(const ValueKey('peek-aside')), findsNothing);
        final gameOver = find.textContaining('choose an action');
        for (var i = 0; i < 3000 && gameOver.evaluate().isEmpty; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        await t.pump(const Duration(milliseconds: 300));
        await shot(t, 'open-match-turn-$tag');

        // Pieces stay on screen and clear of each other, hand cards included.
        Rect rect(Finder f) => t.getRect(f.first);
        final screen = Offset.zero & size;
        final pieces = <String, Rect>{
          'your plate': rect(find.byKey(const ValueKey('hud-me'))),
          'opponents': rect(find.byKey(const ValueKey('hud-opponents'))),
          'actions': rect(find.byKey(const ValueKey('hud-actions'))),
          'prompt bar': rect(find.byType(PromptBar)),
        };
        final cards = [
          for (final e in find.descendant(of: find.byType(HandFan), matching: find.byType(GestureDetector)).evaluate())
            t.getRect(find.byWidget(e.widget)),
        ];
        bool overlaps(Rect a, Rect b) {
          final i = a.intersect(b);
          return i.width > 1 && i.height > 1;
        }

        for (final MapEntry(key: name, value: r) in pieces.entries) {
          expect(
            screen.inflate(1).contains(r.topLeft) && screen.inflate(1).contains(r.bottomRight),
            isTrue,
            reason: '$name $r is off screen $size',
          );
          for (final MapEntry(key: other, value: r2) in pieces.entries) {
            if (name.compareTo(other) < 0) expect(overlaps(r, r2), isFalse, reason: '$name $r overlaps $other $r2');
          }
          for (final c in cards) {
            expect(overlaps(r, c), isFalse, reason: '$name $r covers a hand card $c');
          }
        }
        // The enemy's plate says how many cards they hold, with card icons.
        expect(find.byKey(const ValueKey('hand-cell')).evaluate().length + find.byType(HandBacks).evaluate().length, greaterThan(0));
        // Titania's glamour was flipped on her turn, or her glamour deck is waiting on her plate.
        expect(find.text('GLAMOUR'), findsWidgets);
        await t.pumpWidget(const SizedBox());
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }

  group('hero search', () {
    for (final size in [smallPhone, desktop]) {
      testWidgets(
        'typing narrows the grid, Enter picks the first hero, clearing brings everyone back; the keyboard may cover it (${sizeName(size)})',
        (t) async {
          final s = makeServices();
          await t.runAsync(() => s.loadData());
          final total = s.data.heroes.length;
          t.view.physicalSize = size * 2;
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('shot'),
              child: UnmatchedApp(
                services: s,
                home: HeroSelectScreen(mode: GameMode.duel, players: 2, map: s.data.maps['blossom']!, ai: AiLevel.easy),
              ),
            ),
          );
          await t.pump(const Duration(milliseconds: 500));
          final field = find.byKey(const ValueKey('hero-search'));
          final count = find.byKey(const ValueKey('hero-search-count'));
          expect(field, findsOneWidget);
          expect(count, findsNothing, reason: 'no count until something is typed');
          await shot(t, 'search-empty-${sizeName(size).replaceAll(' ', '-')}');

          // The phone's keyboard comes up over the lower half of the screen: no layout error.
          t.view.viewInsets = FakeViewPadding(bottom: size.height * 2 * 0.55);
          await t.enterText(field, 'tit');
          await t.pump(const Duration(milliseconds: 300));
          expect(t.takeException(), isNull);
          expect((t.widget(count) as Text).data, '1/$total');
          final grid = find.byType(GridView);
          expect(find.descendant(of: grid, matching: find.text('TITANIA')), findsOneWidget);
          expect(find.descendant(of: grid, matching: find.text('ALICE')), findsNothing);
          await shot(t, 'search-tit-keyboard-${sizeName(size).replaceAll(' ', '-')}');
          t.view.resetViewInsets();

          // Words are matched in any order, against the name and the set.
          await t.enterText(field, 'titania slings');
          await t.pump(const Duration(milliseconds: 200));
          expect((t.widget(count) as Text).data, '1/$total');
          await t.enterText(field, 'ARROWS');
          await t.pump(const Duration(milliseconds: 200));
          expect(
            find.descendant(of: find.byType(GridView), matching: find.text('HAMLET')),
            findsOneWidget,
            reason: 'Slings and Arrows has Hamlet',
          );

          // Nothing matches: it says so and offers the way back.
          await t.enterText(field, 'zzzz');
          await t.pump(const Duration(milliseconds: 200));
          expect(find.textContaining('No hero matches "zzzz"'), findsOneWidget);
          expect((t.widget(count) as Text).data, '0/$total');
          await shot(t, 'search-none-${sizeName(size).replaceAll(' ', '-')}');
          await t.tap(find.text('SHOW ALL HEROES'));
          await t.pump(const Duration(milliseconds: 200));
          expect(count, findsNothing);
          expect(find.textContaining('No hero matches'), findsNothing);
          expect(find.byKey(const ValueKey('hero-search-clear')), findsNothing);

          // Enter picks the first hero found; the clear button empties the field.
          await t.enterText(field, 'hamlet');
          await t.testTextInput.receiveAction(TextInputAction.search);
          await t.pump(const Duration(milliseconds: 400));
          expect(find.text('FIGHT AS HAMLET'), findsOneWidget);
          await t.tap(find.byKey(const ValueKey('hero-search-clear')));
          await t.pump(const Duration(milliseconds: 200));
          expect((t.widget(field) as TextField).controller!.text, isEmpty);
          expect(count, findsNothing);
          expect(find.text('FIGHT AS HAMLET'), findsOneWidget, reason: 'the pick survives clearing the search');
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  });
}

/// The text of the Text widget with [key].
String countText(WidgetTester t, String key) => (t.widget(find.byKey(ValueKey(key))) as Text).data!;
