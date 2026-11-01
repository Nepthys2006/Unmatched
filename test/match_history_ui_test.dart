// Match History screen, the sync indicator and the menu entry: every match with its sync status
// and rating result, "n matches waiting to sync" turning into "All synced", at phone, tablet and
// desktop sizes, without layout errors.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/net/match_record.dart';
import 'package:unmatched_game/net/match_store.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/screens/match_history_screen.dart';
import 'package:unmatched_game/ui/screens/menu_screen.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';
import 'package:unmatched_game/ui/sync_indicator.dart';
import 'package:unmatched_game/ui/widgets.dart';

import 'match_sync_test.dart' show FakeServer, rec;
import 'widget_test.dart' show loadFonts, phone, desktop, smallPhone;

const iphoneSe = Size(568, 320);
const narrow = Size(640, 820);
String nameOf(Size s) => s == phone ? 'phone' : (s == smallPhone ? 'small phone' : (s == desktop ? 'desktop' : (s == iphoneSe ? 'iphone se' : 'narrow')));

Future<void> settle(WidgetTester t, [int ms = 500]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

void main() {
  setUpAll(loadFonts);

  late FakeServer server;
  late MatchStore store;

  Future<Services> services(WidgetTester t, {bool signedIn = true}) async {
    server = FakeServer();
    store = MatchStore.memory();
    final settings = Settings.memory()
      ..username = 'Tester'
      ..board3d = false;
    if (signedIn) {
      settings
        ..accountToken = 'tok'
        ..accountId = 'acct-1';
    }
    final s = Services(settings: settings, audio: Audio(settings, enabled: false), preloadImages: false, matchStore: store, matchBackend: server);
    await t.runAsync(() => s.loadData());
    return s;
  }

  Future<void> open(WidgetTester t, Services s, Size size, Widget home) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(UnmatchedApp(services: s, home: home));
    await settle(t);
  }

  Future<void> seed() async {
    await store.add(rec(at: DateTime.utc(2026, 10, 30, 9), hero: 'alice'));
    await store.add(rec(at: DateTime.utc(2026, 10, 30, 10), mode: MatchMode.lan, opp: 'u-2', won: false, hero: 'medusa')
      ..syncStatus = SyncStatus.synced
      ..serverResult = 'counted'
      ..mmrBefore = 1000
      ..mmrAfter = 976
      ..mmrDelta = -24);
    await store.add(rec(at: DateTime.utc(2026, 10, 30, 11), mode: MatchMode.online, opp: 'u-3')
      ..syncStatus = SyncStatus.synced
      ..serverResult = 'awaiting_opponent');
    await store.add(rec(at: DateTime.utc(2026, 10, 30, 12))
      ..syncStatus = SyncStatus.failed
      ..lastError = 'Rejected by the server: bad_duration');
    await store.add(rec(at: DateTime.utc(2026, 10, 30, 13), mode: MatchMode.lan, opp: 'u-4')
      ..syncStatus = SyncStatus.synced
      ..serverResult = 'disputed');
  }

  for (final size in [smallPhone, phone, desktop, iphoneSe, narrow]) {
    testWidgets('lists every match with its sync status and rating result (${nameOf(size)})', (t) async {
      final s = await services(t);
      await seed();
      await open(t, s, size, const MatchHistoryScreen());
      expect(find.byType(MatchTile), findsWidgets);
      final list = find.byKey(const ValueKey('history-list'));
      expect(list, findsOneWidget);
      // Newest first; scroll through them all.
      final ids = [for (final r in store.all) r.matchId];
      for (final id in ids) {
        final tile = find.byKey(ValueKey('match-$id'));
        await t.scrollUntilVisible(tile, 120, scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first);
        expect(tile, findsOneWidget);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('each line says victory or defeat, the mode, the sync status and what the rating did', (t) async {
    final s = await services(t);
    await seed();
    await open(t, s, desktop, const MatchHistoryScreen());
    String text(String key) => (t.widget(find.byKey(ValueKey(key))) as Text).data!;
    final counted = store.all.firstWhere((r) => r.serverResult == 'counted');
    expect(text('rating-${counted.matchId}'), '-24 MMR');
    expect(text('sync-${counted.matchId}'), 'SYNCED');
    final waiting = store.all.firstWhere((r) => r.serverResult == 'awaiting_opponent');
    expect(text('rating-${waiting.matchId}'), 'AWAITING OPPONENT');
    final disputed = store.all.firstWhere((r) => r.serverResult == 'disputed');
    expect(text('rating-${disputed.matchId}'), 'DISPUTED');
    final pending = store.all.firstWhere((r) => r.syncStatus == SyncStatus.pending);
    expect(text('sync-${pending.matchId}'), 'PENDING');
    expect(text('rating-${pending.matchId}'), 'NOT RANKED');
    final failed = store.all.firstWhere((r) => r.syncStatus == SyncStatus.failed);
    expect(text('sync-${failed.matchId}'), 'FAILED');
    expect(find.textContaining('bad_duration'), findsOneWidget);
    expect(find.text('VICTORY'), findsWidgets);
    expect(find.text('DEFEAT'), findsWidgets);
    expect(find.text('LAN'), findsWidgets);
    expect(find.text('ONLINE'), findsWidgets);
    expect(find.text('AI'), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the indicator counts what is waiting, Sync now sends it, and it says All synced', (t) async {
    final s = await services(t);
    await store.add(rec());
    await store.add(rec());
    await store.add(rec());
    await open(t, s, phone, const MatchHistoryScreen());
    expect((t.widget(find.byKey(const ValueKey('sync-summary'))) as Text).data, '3 matches waiting to sync');
    await t.tap(find.byKey(const ValueKey('sync-now')));
    await settle(t, 300);
    await settle(t, 300);
    expect((t.widget(find.byKey(const ValueKey('sync-summary'))) as Text).data, 'All synced');
    expect(server.counted.length, 3);
    expect(store.pendingCount, 0);
    expect(find.text('PENDING'), findsNothing);
    expect(find.text('SYNCED'), findsNWidgets(3));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('offline: the indicator says so and the matches stay listed as pending', (t) async {
    final s = await services(t);
    await store.add(rec());
    server.down = true;
    await open(t, s, phone, const MatchHistoryScreen());
    await t.tap(find.byKey(const ValueKey('sync-now')));
    await settle(t, 300);
    await settle(t, 300);
    expect((t.widget(find.byKey(const ValueKey('sync-summary'))) as Text).data, 'Offline · 1 match waiting to sync');
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('offline'), findsOneWidget, reason: 'why it is still pending');
    // Back online: one more tap and it goes through.
    server.down = false;
    await t.tap(find.byKey(const ValueKey('sync-now')));
    await settle(t, 300);
    await settle(t, 300);
    expect((t.widget(find.byKey(const ValueKey('sync-summary'))) as Text).data, 'All synced');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 20));
  });

  testWidgets('signed out: it says to sign in, Sync now is off, nothing is sent', (t) async {
    final s = await services(t, signedIn: false);
    await store.add(rec());
    await open(t, s, phone, const MatchHistoryScreen());
    expect((t.widget(find.byKey(const ValueKey('sync-summary'))) as Text).data, 'Sign in to sync · 1 match waiting to sync');
    expect(t.widget<PlateButton>(find.byKey(const ValueKey('sync-now'))).onPressed, isNull);
    expect(server.calls, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('no matches yet: an empty state, no errors', (t) async {
    final s = await services(t);
    await open(t, s, smallPhone, const MatchHistoryScreen());
    expect(find.text('No matches yet'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final size in [smallPhone, phone, desktop, iphoneSe]) {
    testWidgets('the menu has the history button and the sync chip; the button opens the history (${nameOf(size)})', (t) async {
      final s = await services(t);
      await store.add(rec());
      await store.add(rec());
      await open(t, s, size, const MenuScreen());
      expect(find.byKey(const ValueKey('menu-history')), findsOneWidget);
      expect(find.byType(SyncIndicator), findsOneWidget);
      expect((t.widget(find.byKey(const ValueKey('sync-summary'))) as Text).data, '2 matches waiting to sync');
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('menu-history')));
      await settle(t, 600);
      expect(find.byType(MatchHistoryScreen), findsOneWidget);
      expect(find.byType(MatchTile), findsNWidgets(2));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  }
}
