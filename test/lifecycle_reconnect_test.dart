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

/// Reconnects through test links: fails [failures] times, then succeeds.
class _TestTransport extends MatchTransport {
  int failures = 0;
  int attempts = 0;
  final List<_TestClientLink> links = [];

  @override
  Future<ClientLink> reconnect() async {
    attempts++;
    if (failures > 0) {
      failures--;
      throw StateError('host not reachable');
    }
    final l = _TestClientLink();
    links.add(l);
    return l;
  }
}

void main() {
  setUpAll(loadFonts);

  final data = loadData();
  final testMap = data.maps.values.first;

  Lobby duelLobby() => Lobby(
    mode: GameMode.duel,
    players: 2,
    mapId: testMap.id,
    ai: AiLevel.medium,
    seats: [
      LobbySeat(SeatKind.human, name: 'HostPlayer', hero: 'alice', ready: true, host: true),
      LobbySeat(SeatKind.human, name: 'GuestPlayer', hero: 'medusa', ready: true),
    ],
  );

  /// A host with a guest in seat 1, match running.
  (_TestHostLink, HostSession) startedHost() {
    final link = _TestHostLink();
    final host = HostSession(link, data, name: 'HostPlayer', dataVersion: 'test');
    host.lobby!.seats[1] = LobbySeat(SeatKind.human, name: 'GuestPlayer', hero: 'medusa', ready: true, peer: 'peer-1', reconnectToken: 'secret');
    host.lobby!.seats[0].hero = 'alice';
    host.start();
    return (link, host);
  }

  group('Host: a player who drops out keeps their seat for 2 minutes, then an AI takes it', () {
    testWidgets('the match waits with a countdown, then the AI takes over', (tester) async {
      final (link, host) = startedHost();
      try {
        final match = host.match!;
        link.emit(const PeerLeft('peer-1'));
        await tester.pump();
        // From the first second: who is away and for how long.
        expect(match.waitingNotice.value, contains('GuestPlayer disconnected'));
        expect(match.waitingNotice.value, contains('2:00'));
        expect(match.names.value[1], isNot(endsWith('(AI)')));

        await tester.pump(const Duration(seconds: 61));
        expect(match.waitingNotice.value, contains('0:5'), reason: 'the countdown ticks');
        expect(match.names.value[1], isNot(endsWith('(AI)')));
        expect(host.lobby!.seats[1].kind, SeatKind.reservedDisconnected);

        // The 2 minutes are up: an AI plays the seat, everyone is told, the notice goes.
        await tester.pump(const Duration(seconds: 60));
        expect(host.lobby!.seats[1].kind, SeatKind.ai);
        expect(match.names.value[1], endsWith('(AI)'));
        expect(match.waitingNotice.value, isNull);
        expect(match.toast.value, contains('An AI plays their seat'));
        expect(link.broadcasted.any((m) => m['t'] == 'seatAi' && m['seat'] == 1), isTrue);
        // And nothing else happens later (no redirect, no second takeover).
        await tester.pump(const Duration(minutes: 6));
        expect(match.toast.value, isNull);
      } finally {
        host.dispose();
      }
    });

    testWidgets('rejoining with the token inside the 2 minutes gets the same seat and the match so far', (tester) async {
      final (link, host) = startedHost();
      try {
        final match = host.match!;
        link.emit(const PeerLeft('peer-1'));
        await tester.pump(const Duration(seconds: 90));
        expect(match.waitingNotice.value, isNotNull);

        link.emit(const PeerMessage('peer-2', {'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'GuestPlayer', 'token': 'secret'}));
        await tester.pump();
        expect(host.lobby!.seats[1].kind, SeatKind.human);
        expect(host.lobby!.seats[1].peer, 'peer-2');
        expect(match.waitingNotice.value, isNull);
        // The device is told the seat, the lobby, the seed and how much to catch up on.
        final sent = link.sent.where((x) => x.peer == 'peer-2').map((x) => x.msg['t']).toList();
        expect(sent, containsAll(['welcome', 'start']));
        expect(link.sent.firstWhere((x) => x.msg['t'] == 'start').msg['replay'], isA<int>());

        // The grace period's end passes without a takeover.
        await tester.pump(const Duration(minutes: 3));
        expect(host.lobby!.seats[1].kind, SeatKind.human);
        expect(match.names.value[1], isNot(endsWith('(AI)')));
      } finally {
        host.dispose();
      }
    });

    testWidgets('a stranger cannot take the seat, and a player who is too late is told why', (tester) async {
      final (link, host) = startedHost();
      try {
        link.emit(const PeerLeft('peer-1'));
        await tester.pump(const Duration(seconds: 30));
        link.emit(const PeerMessage('thief', {'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'Thief', 'token': 'wrong'}));
        await tester.pump();
        expect(link.sent.any((x) => x.peer == 'thief' && x.msg['t'] == 'reject'), isTrue);
        expect(host.lobby!.seats[1].peer, isNull);

        await tester.pump(const Duration(minutes: 2));
        link.emit(const PeerMessage('late', {'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'GuestPlayer', 'token': 'secret'}));
        await tester.pump();
        final reject = link.sent.lastWhere((x) => x.peer == 'late' && x.msg['t'] == 'reject').msg['why'] as String;
        expect(reject, contains('AI took your seat'));
        expect(host.lobby!.seats[1].kind, SeatKind.ai);
      } finally {
        host.dispose();
      }
    });

    testWidgets('in the lobby (no match yet) the seat just opens up after the grace period', (tester) async {
      final link = _TestHostLink();
      final host = HostSession(link, data, name: 'HostPlayer', dataVersion: 'test');
      try {
        host.lobby!.seats[1] = LobbySeat(SeatKind.human, name: 'GuestPlayer', peer: 'peer-1');
        link.emit(const PeerLeft('peer-1'));
        await tester.pump(const Duration(minutes: 1));
        expect(host.lobby!.seats[1].kind, SeatKind.reservedDisconnected);
        await tester.pump(const Duration(minutes: 1, seconds: 1));
        expect(host.lobby!.seats[1].kind, SeatKind.open);
      } finally {
        host.dispose();
      }
    });
  });

  group('Client: the host drops out', () {
    Future<(_TestClientLink, ClientSession)> startedClient(WidgetTester tester, {MatchTransport? transport}) async {
      final link = _TestClientLink();
      final client = ClientSession(link, data, name: 'GuestPlayer', dataVersion: 'test', address: '127.0.0.1:47400', transport: transport);
      link.emitMessage({'t': 'welcome', 'seat': 1});
      link.emitMessage({'t': 'start', 'lobby': duelLobby().toJson(), 'heroes': ['alice', 'medusa'], 'seed': 12345});
      await tester.pump();
      return (link, client);
    }

    testWidgets('it reconnects to the same host within the 2 minutes and keeps its match', (tester) async {
      final transport = _TestTransport();
      final (link, client) = await startedClient(tester, transport: transport);
      try {
        final match = client.match!;
        // The first tries fail, then the host is reachable again.
        transport.failures = 2;
        link.triggerDone('Host connection dropped');
        await tester.pump();
        expect(match.waitingNotice.value, contains('Reconnecting'));
        expect(client.promoted, isNull);

        await tester.pump(const Duration(seconds: 10));
        expect(transport.attempts, greaterThanOrEqualTo(3));
        final fresh = transport.links.last;
        expect(fresh.sent.first['t'], 'hello');
        expect(match.waitingNotice.value, isNull);

        // The host answers with the match it is running: the same match carries on.
        fresh.emitMessage({'t': 'welcome', 'seat': 1});
        fresh.emitMessage({'t': 'start', 'lobby': duelLobby().toJson(), 'heroes': ['alice', 'medusa'], 'seed': 12345, 'replay': 0});
        await tester.pump();
        expect(identical(client.match, match), isTrue);
        expect(client.promoted, isNull);
        await tester.pump(const Duration(minutes: 5));
        expect(client.promoted, isNull, reason: 'no migration once reconnected');
      } finally {
        client.dispose();
      }
    });

    testWidgets('with nobody to reconnect to it takes over and plays on against the AI', (tester) async {
      final (link, client) = await startedClient(tester);
      try {
        final match = client.match!;
        expect(match.isHost, isFalse);
        link.triggerDone('Host connection dropped');
        await tester.pump(const Duration(seconds: 119));
        expect(client.promoted, isNull, reason: 'still inside the grace period');
        expect(match.waitingNotice.value, contains('Reconnecting'));

        await tester.pump(const Duration(seconds: 3));
        expect(client.promoted, isNotNull);
        expect(match.isHost, isTrue);
        expect(match.waitingNotice.value, isNull);
        expect(match.names.value[0], endsWith('(AI)'), reason: "the lost host's seat is the AI's now");
        expect(match.names.value[1], isNot(endsWith('(AI)')));
        expect(match.toast.value, contains('play on against the AI'));
        expect(client.closed, isNull);
        expect(match.lost.value, isNull);
        await tester.pump(const Duration(seconds: 8));
        expect(match.toast.value, isNull);
      } finally {
        unawaited(client.leave());
        await tester.pump();
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
