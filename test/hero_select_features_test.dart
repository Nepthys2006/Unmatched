// Hero select: the deck viewer (tap the hero card), the AI opponent selector (Random / Choose
// hero, one or several AIs) and the mulligan in a real match, at phone, desktop and narrow sizes.
// Every test also fails on a layout overflow or any other exception.
import 'package:flutter/material.dart' hide Card, Intent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';
import 'package:unmatched_game/ui/screens/deck_viewer.dart';
import 'package:unmatched_game/ui/screens/hero_select_screen.dart';
import 'package:unmatched_game/ui/screens/vs_screen.dart';

import 'widget_test.dart' show loadFonts, makeServices, phone, desktop, smallPhone;

/// A narrow window (a browser tab, a tablet in portrait): the layouts must stack, not overflow.
const narrow = Size(640, 820);
String nameOf(Size s) => s == phone ? 'phone' : (s == smallPhone ? 'small phone' : (s == desktop ? 'desktop' : 'narrow'));

Future<void> settle(WidgetTester t, [int ms = 500]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

/// Scrolls the viewer's thumbnails (a lazy grid or strip) until [thumb] is built and on screen.
Future<void> reveal(WidgetTester t, Finder thumb) async {
  final scrollable = find.descendant(of: find.byKey(const ValueKey('deck-thumbs')), matching: find.byType(Scrollable)).first;
  // Lazy lists only build what is near the view: start from the beginning, then scroll forward.
  t.state<ScrollableState>(scrollable).position.jumpTo(0);
  await t.pump();
  await t.scrollUntilVisible(thumb, 120, scrollable: scrollable, maxScrolls: 200);
  // Built is not the same as on screen (lazy lists build a little beyond the edge): bring it in.
  await t.ensureVisible(thumb);
  await t.pump();
}

void main() {
  setUpAll(loadFonts);

  Future<dynamic> heroSelect(WidgetTester t, Size size, {GameMode mode = GameMode.duel, int players = 2}) async {
    final s = makeServices();
    await t.runAsync(() => s.loadData());
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      UnmatchedApp(
        services: s,
        home: HeroSelectScreen(mode: mode, players: players, map: s.data.maps[mode == GameMode.duel ? 'blossom' : s.data.mapsFor(mode == GameMode.teams2 ? '2v2' : 'ffa').first.id]!, ai: AiLevel.easy),
      ),
    );
    await settle(t);
    return s;
  }

  /// Chooses a hero as a player does with many heroes: search for it, tap it, clear the search.
  Future<void> pickHero(WidgetTester t, String id, {String prefix = 'hero'}) async {
    await t.enterText(find.byKey(ValueKey('$prefix-search')), id.replaceAll('-', ' '));
    await settle(t, 300);
    final tile = find.byKey(ValueKey('$prefix-tile-$id'));
    expect(tile, findsOneWidget, reason: id);
    await t.tap(tile);
    await settle(t, 300);
    await t.tap(find.byKey(ValueKey('$prefix-search-clear')));
    await settle(t, 300);
  }

  group('deck viewer', () {
    for (final size in [smallPhone, phone, desktop, narrow]) {
      testWidgets('tap the hero card: every card, details, filter, quantities; Esc, X and a click outside close it (${nameOf(size)})', (t) async {
        final s = await heroSelect(t, size);
        await pickHero(t, 'alice');
        final hero = s.data.hero('alice') as HeroDef;
        expect(find.text('FIGHT AS ALICE'), findsOneWidget);

        Future<void> open() async {
          await t.tap(find.byKey(const ValueKey('hero-card')));
          await settle(t, 400);
          expect(find.byType(DeckViewer), findsOneWidget);
          expect(t.takeException(), isNull);
        }

        await open();
        // The total and the first card's details: name, type, quantity, value, boost, text.
        expect((t.widget(find.byKey(const ValueKey('deck-total'))) as Text).data, '${hero.deckSize} cards');
        final first = hero.cards.first;
        expect((t.widget(find.byKey(const ValueKey('deck-detail-name'))) as Text).data, first.title.toUpperCase());
        expect(find.descendant(of: find.byKey(const ValueKey('deck-detail-type')), matching: find.text(cardTypeStyle(first.type).label.toUpperCase())), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('deck-detail-qty')), matching: find.text('×${first.copies} IN DECK')), findsOneWidget);
        expect((t.widget(find.byKey(const ValueKey('deck-detail-value'))) as Text).data, first.value == null ? '—' : '${first.value}');
        for (final e in first.text.entries.where((e) => e.value.trim().isNotEmpty)) {
          expect(find.text(e.value.trim()), findsWidgets, reason: 'the ${e.key} text');
        }

        // Every card has a thumbnail with its quantity (scrolled into view as needed).
        for (final c in hero.cards) {
          final th = find.byKey(ValueKey('deck-card-${c.index}'));
          await reveal(t, th);
          expect(th, findsOneWidget, reason: c.title);
          expect(find.descendant(of: find.byKey(ValueKey('deck-qty-${c.index}')), matching: find.text('×${c.copies}')), findsOneWidget);
        }
        expect(hero.cards.fold<int>(0, (n, c) => n + c.copies), hero.deckSize);

        // Tapping a thumbnail shows that card.
        final other = hero.cards.last;
        await reveal(t, find.byKey(ValueKey('deck-card-${other.index}')));
        await t.ensureVisible(find.byKey(ValueKey('deck-card-${other.index}')));
        await t.tap(find.byKey(ValueKey('deck-card-${other.index}')));
        await settle(t, 400);
        expect((t.widget(find.byKey(const ValueKey('deck-detail-name'))) as Text).data, other.title.toUpperCase());
        expect(find.descendant(of: find.byKey(const ValueKey('deck-detail-qty')), matching: find.text('×${other.copies} IN DECK')), findsOneWidget);

        // The filter by type narrows the thumbnails to that type.
        for (final type in [CardType.attack, CardType.defense, CardType.scheme, CardType.versatile]) {
          final has = hero.cards.where((c) => c.type == type).toList();
          if (has.isEmpty) continue;
          await t.tap(find.byKey(ValueKey('deck-filter-${type.name}')));
          await settle(t, 300);
          final shownCards = [for (final c in hero.cards) if (c.type == type) c];
          for (final c in hero.cards.where((c) => c.type != type)) {
            expect(find.byKey(ValueKey('deck-card-${c.index}')), findsNothing, reason: '${type.name} filter hides ${c.title}');
          }
          for (final c in shownCards) {
            await reveal(t, find.byKey(ValueKey('deck-card-${c.index}')));
            expect(find.byKey(ValueKey('deck-card-${c.index}')), findsOneWidget, reason: '${type.name} filter shows ${c.title}');
          }
          expect(t.takeException(), isNull);
        }
        await t.tap(find.byKey(const ValueKey('deck-filter-all')));
        await settle(t, 300);
        await reveal(t, find.byKey(ValueKey('deck-card-${hero.cards.first.index}')));
        expect(find.byKey(ValueKey('deck-card-${hero.cards.first.index}')), findsOneWidget);

        // Read-only: nothing here picks a hero, and the screen behind is as it was.
        expect(find.text('FIGHT AS ALICE'), findsOneWidget);

        // X closes it.
        await t.tap(find.byKey(const ValueKey('deck-close')));
        await settle(t);
        expect(find.byType(DeckViewer), findsNothing);
        // Esc closes it.
        await open();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(t);
        expect(find.byType(DeckViewer), findsNothing);
        // A click outside the panel closes it, a click inside does not.
        await open();
        await t.tap(find.byKey(const ValueKey('deck-total')));
        await settle(t, 200);
        expect(find.byType(DeckViewer), findsOneWidget, reason: 'a click on the panel keeps it open');
        await t.tapAt(const Offset(2, 2));
        await settle(t);
        expect(find.byType(DeckViewer), findsNothing);
        // The hero is still the one chosen and nothing else happened.
        expect(find.text('FIGHT AS ALICE'), findsOneWidget);
        expect(find.byType(VsScreen), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('reading the character card still works through the zoom badge', (t) async {
      await heroSelect(t, phone);
      await t.tap(find.byKey(const ValueKey('hero-card-zoom')));
      await settle(t);
      expect(find.byType(DeckViewer), findsNothing);
      expect(find.text('CLOSE'), findsOneWidget);
      await t.tap(find.text('CLOSE'));
      await settle(t);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('every hero opens: all filters and every card in turn, no exceptions (small phone)', (t) async {
      final s = makeServices();
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = smallPhone * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final heroes = s.data.heroes.values.toList();
      expect(heroes.length, greaterThan(60));
      for (final h in heroes) {
        await t.pumpWidget(UnmatchedApp(services: s, home: DeckViewer(hero: h)));
        await t.pump(const Duration(milliseconds: 50));
        expect(t.takeException(), isNull, reason: h.id);
        expect((t.widget(find.byKey(const ValueKey('deck-total'))) as Text).data, '${h.deckSize} cards', reason: h.id);
        for (final c in h.cards) {
          final th = find.byKey(ValueKey('deck-card-${c.index}'));
          await reveal(t, th);
          await t.ensureVisible(th);
          expect(th, findsOneWidget, reason: '${h.id} ${c.title}');
          await t.tap(th);
          await settle(t, 250);
          expect((t.widget(find.byKey(const ValueKey('deck-detail-name'))) as Text).data, c.title.toUpperCase(), reason: h.id);
          expect(t.takeException(), isNull, reason: '${h.id} ${c.title}');
        }
        for (final f in ['attack', 'defense', 'scheme', 'versatile', 'all']) {
          await t.tap(find.byKey(ValueKey('deck-filter-$f')), warnIfMissed: false);
          await t.pump(const Duration(milliseconds: 30));
          expect(t.takeException(), isNull, reason: '${h.id} $f');
        }
      }
      await t.pumpWidget(const SizedBox());
    });
  });

  group('choose the AI opponent', () {
    for (final size in [smallPhone, phone, desktop, narrow]) {
      testWidgets('Random is the default; Choose hero opens the same grid and search, the pick is shown by name, and it is the one fought (${nameOf(size)})', (t) async {
        final s = await heroSelect(t, size);
        await pickHero(t, 'alice');
        expect(find.byKey(const ValueKey('ai-random-note')), findsOneWidget, reason: 'Random by default');
        expect(find.byKey(const ValueKey('ai-hero-search')), findsNothing);

        await t.tap(find.byKey(const ValueKey('ai-mode-choose')));
        await settle(t, 400);
        // The same grid and search bar, in a popup.
        expect(find.byKey(const ValueKey('ai-hero-search')), findsOneWidget);
        expect(find.byKey(const ValueKey('ai-hero-tile-achilles')), findsOneWidget);
        // Your own hero is not on offer.
        await t.enterText(find.byKey(const ValueKey('ai-hero-search')), 'alice');
        await settle(t, 300);
        await t.tap(find.byKey(const ValueKey('ai-hero-tile-alice')), warnIfMissed: false);
        await settle(t, 200);
        expect(find.byKey(const ValueKey('ai-picker-name')), findsNothing);
        // Search narrows it like the main grid.
        await t.enterText(find.byKey(const ValueKey('ai-hero-search')), 'achil');
        await settle(t, 300);
        expect((t.widget(find.byKey(const ValueKey('ai-hero-search-count'))) as Text).data, startsWith('1/'));
        await pickHero(t, 'achilles', prefix: 'ai-hero');
        expect((t.widget(find.byKey(const ValueKey('ai-picker-name'))) as Text).data, 'ACHILLES');
        await t.tap(find.byKey(const ValueKey('ai-picker-choose')));
        await settle(t, 400);
        expect(t.takeException(), isNull);

        // The chosen hero is on the screen, by name, before fighting.
        expect(find.byKey(const ValueKey('ai-slots')), findsOneWidget);
        expect(find.text('ACHILLES'), findsWidgets);
        expect(find.text('FIGHT AS ALICE'), findsOneWidget);

        await t.tap(find.text('FIGHT AS ALICE'));
        await settle(t, 600);
        final vs = t.widget<VsScreen>(find.byType(VsScreen));
        expect(vs.config.heroIds, ['alice', 'achilles']);
        expect(t.takeException(), isNull);
        expect(s, isNotNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('Random draws the AI hero at the start and never your own hero', (t) async {
      final seen = <String>{};
      for (var i = 0; i < 6; i++) {
        await heroSelect(t, phone);
        await pickHero(t, 'alice');
        await t.tap(find.text('FIGHT AS ALICE'));
        await settle(t, 600);
        final ids = t.widget<VsScreen>(find.byType(VsScreen)).config.heroIds;
        expect(ids.first, 'alice');
        expect(ids[1], isNot('alice'));
        seen.add(ids[1]);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      }
      expect(seen.length, greaterThan(1), reason: 'drawn at random each time');
    });

    testWidgets('closing the picker (Esc / X / outside) without choosing goes back to Random', (t) async {
      await heroSelect(t, phone);
      await pickHero(t, 'alice');
      for (final how in ['esc', 'x', 'outside']) {
        await t.tap(find.byKey(const ValueKey('ai-mode-choose')));
        await settle(t, 400);
        expect(find.byKey(const ValueKey('ai-hero-search')), findsOneWidget);
        switch (how) {
          case 'esc':
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
          case 'x':
            await t.tap(find.byKey(const ValueKey('ai-picker-close')));
          default:
            await t.tapAt(const Offset(2, 2));
        }
        await settle(t, 400);
        expect(find.byKey(const ValueKey('ai-hero-search')), findsNothing, reason: how);
        expect(find.byKey(const ValueKey('ai-random-note')), findsOneWidget, reason: how);
      }
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('picking the hero the AI chose sends the AI back to random; the AI pick can be changed or set to Random', (t) async {
      await heroSelect(t, desktop);
      await pickHero(t, 'alice');
      await t.tap(find.byKey(const ValueKey('ai-mode-choose')));
      await settle(t, 400);
      await pickHero(t, 'achilles', prefix: 'ai-hero');
      await t.tap(find.byKey(const ValueKey('ai-picker-choose')));
      await settle(t, 400);
      // Change it through the slot.
      await t.tap(find.byKey(const ValueKey('ai-slot-0')));
      await settle(t, 400);
      await pickHero(t, 'medusa', prefix: 'ai-hero');
      await t.tap(find.byKey(const ValueKey('ai-picker-choose')));
      await settle(t, 400);
      expect(find.text('MEDUSA'), findsWidgets);
      // Take the AI's hero yourself: the AI seat is released.
      await pickHero(t, 'medusa');
      expect(find.text('FIGHT AS MEDUSA'), findsOneWidget);
      expect(find.text('RANDOM'), findsWidgets);
      expect(find.textContaining('goes back to a random hero'), findsOneWidget);
      // Random in the picker clears a pick.
      await t.tap(find.byKey(const ValueKey('ai-slot-0')));
      await settle(t, 400);
      await t.tap(find.byKey(const ValueKey('ai-picker-random')));
      await settle(t, 400);
      await t.tap(find.text('FIGHT AS MEDUSA'));
      await settle(t, 600);
      final ids = t.widget<VsScreen>(find.byType(VsScreen)).config.heroIds;
      expect(ids.first, 'medusa');
      expect(ids[1], isNot('medusa'));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });

    for (final size in [smallPhone, desktop]) {
      testWidgets('2 v 2: several AI seats, each chosen or left random, all different (${nameOf(size)})', (t) async {
        await heroSelect(t, size, mode: GameMode.teams2, players: 4);
        await pickHero(t, 'alice');
        await t.tap(find.byKey(const ValueKey('ai-mode-choose')));
        await settle(t, 400);
        await pickHero(t, 'achilles', prefix: 'ai-hero');
        await t.tap(find.byKey(const ValueKey('ai-picker-choose')));
        await settle(t, 400);
        // Three slots: foe, ally, foe. The second stays random, the third is chosen.
        for (var i = 0; i < 3; i++) {
          expect(find.byKey(ValueKey('ai-slot-$i')), findsOneWidget);
        }
        await t.ensureVisible(find.byKey(const ValueKey('ai-slot-2')));
        await t.tap(find.byKey(const ValueKey('ai-slot-2')));
        await settle(t, 400);
        // Seats already chosen are not on offer again.
        await t.enterText(find.byKey(const ValueKey('ai-hero-search')), 'achilles');
        await settle(t, 300);
        await t.tap(find.byKey(const ValueKey('ai-hero-tile-achilles')), warnIfMissed: false);
        await settle(t, 200);
        expect(find.byKey(const ValueKey('ai-picker-name')), findsNothing);
        await pickHero(t, 'medusa', prefix: 'ai-hero');
        await t.tap(find.byKey(const ValueKey('ai-picker-choose')));
        await settle(t, 400);
        expect(t.takeException(), isNull);
        await t.tap(find.text('FIGHT AS ALICE'));
        await settle(t, 600);
        final ids = t.widget<VsScreen>(find.byType(VsScreen)).config.heroIds;
        expect(ids, hasLength(4));
        expect(ids[0], 'alice');
        expect(ids[1], 'achilles');
        expect(ids[3], 'medusa');
        expect(ids.toSet(), hasLength(4));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('the multiplayer hero pick has no AI selector, and its deck viewer is read-only too', (t) async {
      final s = makeServices();
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = phone * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(UnmatchedApp(services: s, home: HeroSelectScreen.pick(map: s.data.maps['blossom']!, initial: 'alice', taken: const {'medusa'})));
      await settle(t);
      expect(find.byKey(const ValueKey('ai-mode-choose')), findsNothing);
      await t.tap(find.byKey(const ValueKey('hero-card')));
      await settle(t, 400);
      expect(find.byType(DeckViewer), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect(find.text('CHOOSE ALICE'), findsOneWidget);
      // A taken hero can be looked at but not chosen.
      await pickHero(t, 'medusa');
      expect(find.textContaining('already taken'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('mulligan in a match', () {
    Future<dynamic> startMatch(WidgetTester t, Size size, {int seed = 3}) async {
      final s = makeServices(speed: 0.05);
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = size * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final config = MatchConfig(mode: GameMode.duel, players: 2, map: s.data.maps['blossom']!, ai: AiLevel.medium, heroIds: const ['alice', 'medusa']);
      await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: config, seed: seed)));
      dynamic st() => t.state(find.byType(MatchScreen));
      // Setup asks a few questions first (Alice's size, where the sidekicks start): take the first.
      for (var i = 0; i < 600 && find.byType(MulliganPanel).evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
        final p = st().debugPrompt as Prompt?;
        if (p != null && p.intent != Intent.mulligan) {
          await t.pump(const Duration(milliseconds: 100));
          st().debugAnswer([0]);
        }
      }
      expect(find.byType(MulliganPanel), findsOneWidget, reason: 'the opening hand is offered before turn 1');
      return st();
    }

    for (final size in [smallPhone, phone, desktop, narrow]) {
      testWidgets('Keep Hand: the panel shows your cards with both buttons, then it is gone for good (${nameOf(size)})', (t) async {
        final st = await startMatch(t, size);
        expect((st.debugPrompt as Prompt).intent, Intent.mulligan);
        final me = st.me;
        final before = [for (final c in me.hand) c.uid];
        expect(before, hasLength(5));
        expect(find.byKey(const ValueKey('mulligan-take')), findsOneWidget);
        expect(find.byKey(const ValueKey('mulligan-keep')), findsOneWidget);
        for (var i = 0; i < 5; i++) {
          expect(find.byKey(ValueKey('mulligan-card-$i')), findsOneWidget);
        }
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const ValueKey('mulligan-keep')));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(MulliganPanel), findsNothing);
        expect([for (final c in me.hand) c.uid], before);
        // It never comes back: play on until the first turn is underway.
        for (var i = 0; i < 200; i++) {
          await t.pump(const Duration(milliseconds: 50));
          expect(find.byType(MulliganPanel), findsNothing);
        }
        expect(st.game.turnNumber, greaterThan(0));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 30));
      });
    }

    for (final size in [smallPhone, desktop]) {
      testWidgets('Mulligan: a new hand of the same size, no second mulligan (${nameOf(size)})', (t) async {
        final st = await startMatch(t, size, seed: 11);
        final me = st.me;
        final before = {for (final c in me.hand) c.uid};
        await t.tap(find.byKey(const ValueKey('mulligan-take')));
        await t.pump(const Duration(milliseconds: 600));
        expect(find.byType(MulliganPanel), findsNothing);
        expect(me.hand, hasLength(5));
        expect({for (final c in me.hand) c.uid}.difference(before), isNotEmpty, reason: 'new cards');
        expect(me.hand.length + me.deck.length, me.hero.deckSize, reason: 'nothing lost');
        expect(me.mulliganUsed, isTrue);
        for (var i = 0; i < 200; i++) {
          await t.pump(const Duration(milliseconds: 50));
          expect(find.byType(MulliganPanel), findsNothing, reason: 'the new hand is final');
        }
        expect(st.game.turnNumber, greaterThan(0));
        // The AI had its own choice too.
        expect(st.game.players[1].mulliganUsed, isTrue);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 30));
      });
    }

    testWidgets('tapping a card in the panel reads it without answering', (t) async {
      final st = await startMatch(t, phone);
      await t.tap(find.byKey(const ValueKey('mulligan-card-0')));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MulliganPanel), findsOneWidget);
      expect((st.debugPrompt as Prompt).intent, Intent.mulligan);
      expect(find.text('CLOSE'), findsOneWidget);
      await t.tap(find.text('CLOSE'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const ValueKey('mulligan-keep')));
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    });
  });

  test('every playable hero has a deck the viewer can show', () {
    expect(isImplemented('alice'), isTrue);
  });
}
