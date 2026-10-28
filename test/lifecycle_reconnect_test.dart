import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';

import 'support.dart';
import 'widget_test.dart' show boot, loadFonts, phone;

class _TestHostLink implements HostLink {
  final _events = StreamController<LinkEvent>.broadcast();
  final List<({String peer, Msg msg})> sent = [];
  final List<Msg> broadcasted = [];

  @override
  String get address => '127.0.0.1:47400';

  @override
  Stream<LinkEvent> get events => _events.stream;

  @override
  void send(String peer, Msg m) => sent.add((peer: peer, msg: m));

  @override
  void broadcast(Msg m) => broadcasted.add(m);

  @override
  void drop(String peer) {}

  @override
  void lobbyChanged(LobbyInfo info) {}

  @override
  Future<void> finished({String? winner, required List<String> players}) async {}

  @override
  Future<void> close() async => _events.close();

  void emit(LinkEvent e) => _events.add(e);
}

class _TestClientLink implements ClientLink {
  final _messages = StreamController<Msg>.broadcast();
  final _done = Completer<String?>();
  final List<Msg> sent = [];

  @override
  Stream<Msg> get messages => _messages.stream;

  @override
  Future<String?> get done => _done.future;

  @override
  void send(Msg m) => sent.add(m);

  void emitMessage(Msg m) => _messages.add(m);

  void triggerDone(String? reason) {
    if (!_done.isCompleted) _done.complete(reason);
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete(null);
    await _messages.close();
  }
}

void main() {
  setUpAll(loadFonts);

  final data = loadData();
  final testMap = data.maps.values.first;

  group('HostSession 2-minute notice & 5-minute timeout', () {
    testWidgets('Host starts 2-minute notice and 5-minute redirect to lobby on peer disconnect', (tester) async {
      final link = _TestHostLink();
      final host = HostSession(link, data, name: 'HostPlayer', dataVersion: 'test');
      try {
        // Seat 0: Host, Seat 1: Guest
        host.lobby!.seats[1] = LobbySeat(SeatKind.human, name: 'GuestPlayer', hero: 'medusa', ready: true, peer: 'peer-1');
        host.lobby!.seats[0].hero = 'alice';
        host.start();

        final match = host.match!;
        expect(match.waitingNotice.value, isNull);
        expect(match.timeoutRedirect.value, isNull);

        // Guest disconnects mid-match
        link.emit(const PeerLeft('peer-1'));
        await tester.pump();

        // Immediately: silent grace period (no notice yet)
        expect(match.waitingNotice.value, isNull);
        expect(match.timeoutRedirect.value, isNull);

        // Elapse 1 minute: still silent
        await tester.pump(const Duration(minutes: 1));
        expect(match.waitingNotice.value, isNull);

        // Elapse to 2 minutes: waiting notice appears
        await tester.pump(const Duration(minutes: 1));
        expect(match.waitingNotice.value, contains('opponent stepped away'));
        expect(match.timeoutRedirect.value, isNull);

        // Elapse to 5 minutes: timeout redirect fires for Main Lobby
        await tester.pump(const Duration(minutes: 3));
        expect(match.waitingNotice.value, isNull);
        expect(match.timeoutRedirect.value, isNotNull);
        expect(match.timeoutRedirect.value!.redirect, 'lobby');
        expect(match.timeoutRedirect.value!.title, 'Opponent Away');
      } finally {
        host.dispose();
      }
    });

    testWidgets('Host cancels timers and clears notice when peer reconnects before 5 minutes', (tester) async {
      final link = _TestHostLink();
      final host = HostSession(link, data, name: 'HostPlayer', dataVersion: 'test');
      try {
        host.lobby!.seats[1] = LobbySeat(SeatKind.human, name: 'GuestPlayer', hero: 'medusa', ready: true, peer: 'peer-1');
        host.lobby!.seats[0].hero = 'alice';
        host.start();

        final match = host.match!;

        // Peer leaves
        link.emit(const PeerLeft('peer-1'));
        await tester.pump();

        // Advance 2 minutes to show notice
        await tester.pump(const Duration(minutes: 2));
        expect(match.waitingNotice.value, isNotNull);

        // Peer reconnects with hello message
        link.emit(const PeerMessage('peer-reconnected', {'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'GuestPlayer'}));
        await tester.pump();

        // Notice is cleared!
        expect(match.waitingNotice.value, isNull);
        expect(host.lobby!.seats[1].peer, 'peer-reconnected');

        // Advance 5 minutes: timeout redirect should NEVER fire
        await tester.pump(const Duration(minutes: 5));
        expect(match.timeoutRedirect.value, isNull);
      } finally {
        host.dispose();
      }
    });
  });

  group('ClientSession 2-minute notice & 5-minute timeout', () {
    testWidgets('Client starts 2-minute notice and 5-minute redirect to mode picking on host disconnect', (tester) async {
      final link = _TestClientLink();
      final client = ClientSession(link, data, name: 'GuestPlayer', dataVersion: 'test', address: '127.0.0.1:47400');
      try {
        // Simulate host welcome and match start
        link.emitMessage({'t': 'welcome', 'seat': 1});
        final lobbyJson = Lobby(
          mode: GameMode.duel,
          players: 2,
          mapId: testMap.id,
          ai: AiLevel.medium,
          seats: [
            LobbySeat(SeatKind.human, name: 'HostPlayer', hero: 'alice', ready: true),
            LobbySeat(SeatKind.human, name: 'GuestPlayer', hero: 'medusa', ready: true),
          ],
        ).toJson();
        link.emitMessage({'t': 'start', 'lobby': lobbyJson, 'heroes': ['alice', 'medusa'], 'seed': 12345});
        await tester.pump();

        final match = client.match!;
        expect(match.waitingNotice.value, isNull);
        expect(match.timeoutRedirect.value, isNull);

        // Host disconnects / connection lost
        link.triggerDone('Host connection dropped');
        await tester.pump();

        // Immediately: silent grace period
        expect(match.waitingNotice.value, isNull);
        expect(match.timeoutRedirect.value, isNull);

        // Elapse 2 minutes: waiting notice appears
        await tester.pump(const Duration(minutes: 2));
        expect(match.waitingNotice.value, contains('Waiting for the host to return'));
        expect(match.timeoutRedirect.value, isNull);

        // Elapse to 5 minutes: redirect fires for mode selection
        await tester.pump(const Duration(minutes: 3));
        expect(match.waitingNotice.value, isNull);
        expect(match.timeoutRedirect.value, isNotNull);
        expect(match.timeoutRedirect.value!.redirect, 'mode');
        expect(match.timeoutRedirect.value!.title, 'Host Away');
      } finally {
        client.dispose();
      }
    });

    testWidgets('Client cancels timers and clears notice if host message arrives before 5 minutes', (tester) async {
      final link = _TestClientLink();
      final client = ClientSession(link, data, name: 'GuestPlayer', dataVersion: 'test', address: '127.0.0.1:47400');
      try {
        link.emitMessage({'t': 'welcome', 'seat': 1});
        final lobbyJson = Lobby(
          mode: GameMode.duel,
          players: 2,
          mapId: testMap.id,
          ai: AiLevel.medium,
          seats: [
            LobbySeat(SeatKind.human, name: 'HostPlayer', hero: 'alice', ready: true),
            LobbySeat(SeatKind.human, name: 'GuestPlayer', hero: 'medusa', ready: true),
          ],
        ).toJson();
        link.emitMessage({'t': 'start', 'lobby': lobbyJson, 'heroes': ['alice', 'medusa'], 'seed': 12345});
        await tester.pump();

        final match = client.match!;

        // Connection dropped
        link.triggerDone('Host connection dropped');
        await tester.pump();

        // Advance 2 minutes: notice appears
        await tester.pump(const Duration(minutes: 2));
        expect(match.waitingNotice.value, isNotNull);

        // Host recovers / message arrives
        link.emitMessage({'t': 'ans', 'seq': 1, 'seat': 0, 'picks': [0]});
        await tester.pump();

        // Notice cleared
        expect(match.waitingNotice.value, isNull);

        // Advance 5 minutes: timeout redirect should NEVER fire
        await tester.pump(const Duration(minutes: 5));
        expect(match.timeoutRedirect.value, isNull);
      } finally {
        client.dispose();
      }
    });
  });

  group('MatchScreen Lifecycle Resilience', () {
    testWidgets('MatchScreen survives background, pause, and resume without closing or quitting', (tester) async {
      final config = MatchConfig(
        mode: GameMode.duel,
        players: 2,
        map: testMap,
        ai: AiLevel.easy,
        heroIds: ['alice', 'medusa'],
      );

      await boot(
        tester,
        phone,
        home: MatchScreen(config: config, seed: 42),
      );
      await tester.pump();

      expect(find.byType(MatchScreen), findsOneWidget);

      // Simulate App Lifecycle backgrounding (inactive -> hidden -> paused)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(MatchScreen), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(find.byType(MatchScreen), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byType(MatchScreen), findsOneWidget);

      // Simulate resume
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(MatchScreen), findsOneWidget);
    });
  });
}
