import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/dialogs/map_inspect_dialog.dart';
import 'package:unmatched_game/ui/qr_dialog.dart';
import 'package:unmatched_game/ui/screens/lobby_screen.dart';
import 'package:unmatched_game/ui/services.dart';
import 'package:unmatched_game/ui/settings.dart';
import 'package:unmatched_game/ui/widgets.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final data = loadData();
  final testMap = data.maps['sherwood-forest'] ?? data.maps.values.first;

  group('QrDialog responsiveness & overflow checks', () {
    const testSizes = [
      Size(360, 640), // portrait phone
      Size(740, 360), // small landscape phone
      Size(800, 480), // compact landscape
      Size(1280, 800), // tablet / desktop
    ];

    for (final size in testSizes) {
      testWidgets('QrDialog renders without overflow at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showQrShareDialog(
                        context,
                        url: 'http://192.168.1.11:47400',
                      );
                    },
                    child: const Text('Open QR'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open QR'));
        await tester.pumpAndSettle();

        expect(find.text('SCAN TO JOIN ON IOS / MOBILE'), findsOneWidget);
        expect(find.text('http://192.168.1.11:47400'), findsOneWidget);
        expect(find.text('DONE'), findsOneWidget);

        // Verify no overflow errors were thrown
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('MapInspectDialog checks', () {
    testWidgets('MapInspectDialog renders map title, stats, interactive board and zoom controls', (tester) async {
      tester.view.physicalSize = const Size(1280, 800) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showMapInspectDialog(context, testMap),
                  child: const Text('Inspect'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Inspect'));
      await tester.pumpAndSettle();

      expect(find.text(testMap.name.toUpperCase()), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
      expect(find.byIcon(Icons.center_focus_strong_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tap zoom in and zoom out
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.center_focus_strong_rounded));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('LobbyScreen visual battlefield card checks', () {
    testWidgets('Lobby overview renders prominent visual map preview and interactive buttons', (tester) async {
      tester.view.physicalSize = const Size(1280, 800) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final s = Services(settings: Settings.memory(), audio: Audio(Settings.memory(), enabled: false), preloadImages: false);
      await tester.runAsync(() => s.loadData());

      final session = HostSession(_FakeHostLink(), data, name: 'HostTester', dataVersion: 'test');
      addTearDown(session.dispose);

      await tester.pumpWidget(
        UnmatchedApp(
          services: s,
          home: LobbyScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the prominent visual map preview is rendered in the lobby overview
      expect(find.text('ACTIVE MAP'), findsOneWidget);
      expect(find.text(session.lobby!.mapId == testMap.id ? testMap.name.toUpperCase() : data.maps[session.lobby!.mapId]!.name.toUpperCase()), findsOneWidget);
      expect(find.text('CHANGE BATTLEFIELD'), findsOneWidget);

      // Tap inspect directly from the lobby overview
      final inspectFinder = find.widgetWithText(PlateButton, 'INSPECT');
      await tester.ensureVisible(inspectFinder);
      await tester.tap(inspectFinder);
      await tester.pumpAndSettle();

      // Verify MapInspectDialog opened
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);

      // Close inspect dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      final oldHandler = FlutterError.onError;
      FlutterErrorDetails? caughtDetails;
      FlutterError.onError = (details) {
        caughtDetails = details;
        // ignore: avoid_print
        print('CAPTURED ERROR:\n${details.toString()}');
      };

      // Open battlefield picker view
      final changeFinder = find.text('CHANGE BATTLEFIELD');
      await tester.ensureVisible(changeFinder);
      await tester.tap(changeFinder);
      await tester.pumpAndSettle();

      FlutterError.onError = oldHandler;
      expect(find.text('DONE'), findsOneWidget);
      expect(caughtDetails, isNull);
    });

    testWidgets('Guest player sees visual map, gets host map changes, and can browse all maps', (tester) async {
      final s = Services(settings: Settings.memory(), audio: Audio(Settings.memory(), enabled: false), preloadImages: false);
      await tester.runAsync(() => s.loadData());

      final clientLink = _FakeClientLink();
      final clientSession = ClientSession(clientLink, data, name: 'GuestTester', dataVersion: 'test', address: '192.168.1.10:47400');
      addTearDown(clientSession.dispose);

      final initialLobby = Lobby(
        mode: GameMode.duel,
        players: 2,
        mapId: 'sherwood-forest',
        ai: AiLevel.easy,
        seats: [
          LobbySeat(SeatKind.human, name: 'HostTester', hero: 'achilles', ready: true),
          LobbySeat(SeatKind.human, name: 'GuestTester'),
        ],
      );

      // Deliver welcome and initial lobby state
      clientLink.emitMessage({'t': 'welcome', 'seat': 1});
      clientLink.emitMessage({'t': 'lobby', 'lobby': initialLobby.toJson()});

      await tester.pumpWidget(
        UnmatchedApp(
          services: s,
          home: LobbyScreen(session: clientSession),
        ),
      );
      await tester.pumpAndSettle();

      // Verify guest sees visual active map card for Sherwood Forest
      expect(find.text('ACTIVE MAP'), findsOneWidget);
      expect(find.text('SHERWOOD FOREST'), findsOneWidget);
      expect(find.text('INSPECT BATTLEFIELD'), findsOneWidget);
      expect(find.text('BROWSE ALL MAPS'), findsOneWidget);

      // Verify host controls are NOT shown for guest
      expect(find.text('CHANGE BATTLEFIELD'), findsNothing);

      // Host changes map to Soho -> guest receives updated lobby
      final updatedLobby = Lobby(
        mode: initialLobby.mode,
        players: initialLobby.players,
        mapId: 'soho',
        ai: initialLobby.ai,
        seats: initialLobby.seats,
      );
      clientLink.emitMessage({'t': 'lobby', 'lobby': updatedLobby.toJson()});
      await tester.pumpAndSettle();

      // Verify guest now sees Soho visual card
      expect(find.text('SOHO'), findsOneWidget);

      // Guest opens "Browse All Maps"
      final browseBtn = find.text('BROWSE ALL MAPS');
      await tester.ensureVisible(browseBtn);
      await tester.tap(browseBtn);
      await tester.pumpAndSettle();

      expect(find.text('BACK TO LOBBY'), findsOneWidget);
      expect(find.text('INSPECT'), findsOneWidget);

      // Guest taps inspect
      await tester.tap(find.text('INSPECT'));
      await tester.pumpAndSettle();

      // Verify MapInspectDialog opens with zoom controls
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);

      // Close inspector
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Return to lobby
      await tester.tap(find.text('BACK TO LOBBY'));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE MAP'), findsOneWidget);
      expect(find.text('SOHO'), findsOneWidget);
    });
  });
}

class _FakeHostLink implements HostLink {
  @override
  String get address => '192.168.1.10:47400';
  final _events = StreamController<LinkEvent>.broadcast();
  @override
  Stream<LinkEvent> get events => _events.stream;
  @override
  void broadcast(Msg m) {}
  @override
  void send(String peer, Msg m) {}
  @override
  void drop(String peer) {}
  @override
  void lobbyChanged(LobbyInfo info) {}
  @override
  Future<void> finished({String? winner, required List<String> players}) async {}
  @override
  Future<void> close() async {}
}

class _FakeClientLink implements ClientLink {
  final _messages = StreamController<Msg>.broadcast();
  final _done = Completer<String?>();

  @override
  Stream<Msg> get messages => _messages.stream;

  @override
  Future<String?> get done => _done.future;

  @override
  void send(Msg m) {}

  void emitMessage(Msg m) => _messages.add(m);

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete(null);
    await _messages.close();
  }
}

