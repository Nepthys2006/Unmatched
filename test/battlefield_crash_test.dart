import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/screens/lobby_screen.dart';
import 'package:unmatched_game/ui/screens/map_select_screen.dart';
import 'package:unmatched_game/ui/screens/setup_screen.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';
import 'package:unmatched_game/ui/audio.dart';

class MockHostLink implements HostLink {
  @override
  String get address => '192.168.1.100';
  @override
  Stream<LinkEvent> get events => const Stream.empty();
  @override
  void broadcast(Msg msg) {}
  @override
  void drop(String peer) {}
  @override
  void lobbyChanged(LobbyInfo info) {}
  @override
  void send(String peer, Msg msg) {}
  @override
  Future<void> finished({String? winner, required List<String> players}) async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('every map renders in MapCard without exception', (t) async {
    final settings = Settings.memory()..board3d = false;
    final services = Services(settings: settings, audio: Audio(settings, enabled: false), preloadImages: false);
    await t.runAsync(() => services.loadData());

    for (final map in services.data.maps.values) {
      await t.pumpWidget(
        ServicesScope(
          services: services,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 400,
                child: MapCard(
                  map: map,
                  selected: false,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
    }
  });

  testWidgets('setup screen: selecting maps does not crash', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final settings = Settings.memory()..board3d = false;
    final services = Services(settings: settings, audio: Audio(settings, enabled: false), preloadImages: false);
    await t.runAsync(() => services.loadData());

    await t.pumpWidget(UnmatchedApp(services: services, home: const SetupScreen()));
    await t.pump(const Duration(milliseconds: 300));

    // Tap Choose map
    await t.tap(find.text('CHOOSE MAP'));
    await t.pumpAndSettle();

    expect(find.text('BATTLEFIELD'), findsOneWidget);

    // Tap Random map
    await t.tap(find.text('RANDOM MAP'));
    await t.pumpAndSettle();

    // Tap Choose hero
    await t.tap(find.text('CHOOSE HERO'));
    await t.pumpAndSettle();
  });

  testWidgets('lobby screen: change battlefield does not crash', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final settings = Settings.memory()..board3d = false;
    final services = Services(settings: settings, audio: Audio(settings, enabled: false), preloadImages: false);
    await t.runAsync(() => services.loadData());

    final session = HostSession(MockHostLink(), services.data, name: 'Tester', dataVersion: services.dataVersion);
    await t.pumpWidget(UnmatchedApp(services: services, home: LobbyScreen(session: session)));
    await t.pumpAndSettle();

    // Tap Change Battlefield
    expect(find.text('CHANGE BATTLEFIELD'), findsOneWidget);
    await t.tap(find.text('CHANGE BATTLEFIELD'));
    await t.pumpAndSettle();

    // Now in battlefield page
    expect(find.text('BATTLEFIELD'), findsOneWidget);

    // Tap Random map in battlefield page
    expect(find.text('RANDOM MAP'), findsOneWidget);
    await t.tap(find.text('RANDOM MAP'));
    await t.pumpAndSettle();

    // Tap Done
    expect(find.text('DONE'), findsOneWidget);
    await t.tap(find.text('DONE'));
    await t.pumpAndSettle();

    // Back in lobby overview
    expect(find.text('CHANGE BATTLEFIELD'), findsOneWidget);
  });

  testWidgets('lobby screen: tapping a map card selects it', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final settings = Settings.memory()..board3d = false;
    final services = Services(settings: settings, audio: Audio(settings, enabled: false), preloadImages: false);
    await t.runAsync(() => services.loadData());

    final session = HostSession(MockHostLink(), services.data, name: 'Tester', dataVersion: services.dataVersion);
    await t.pumpWidget(UnmatchedApp(services: services, home: LobbyScreen(session: session)));
    await t.pumpAndSettle();

    // Tap Change Battlefield
    await t.tap(find.text('CHANGE BATTLEFIELD'));
    await t.pumpAndSettle();

    // Find and tap a MapCard
    final mapCards = find.byType(MapCard);
    expect(mapCards, findsWidgets);
    await t.tap(mapCards.at(1));
    await t.pumpAndSettle();

    // Tap Done
    await t.tap(find.text('DONE'));
    await t.pumpAndSettle();
  });

  testWidgets('MapSelectScreen displays and picks map', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final settings = Settings.memory()..board3d = false;
    final services = Services(settings: settings, audio: Audio(settings, enabled: false), preloadImages: false);
    await t.runAsync(() => services.loadData());

    final maps = services.data.maps.values.toList();
    MapDef? picked;

    await t.pumpWidget(
      ServicesScope(
        services: services,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await Navigator.of(ctx).push<MapDef>(
                      MaterialPageRoute(
                        builder: (_) => MapSelectScreen(maps: maps, initial: maps.first),
                      ),
                    );
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.text('OPEN'));
    await t.pumpAndSettle();

    expect(find.text('CHOOSE BATTLEFIELD'), findsOneWidget);
    await t.tap(find.text('RANDOM'));
    await t.pumpAndSettle();

    await t.tap(find.text('SELECT BATTLEFIELD'));
    await t.pumpAndSettle();

    expect(picked, isNotNull);
  });
}
