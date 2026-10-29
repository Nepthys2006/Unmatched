import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';

import 'support.dart';

class _MockHostLink implements HostLink {
  final _events = StreamController<LinkEvent>.broadcast();
  final List<LobbyInfo> lobbyHistory = [];

  @override
  String get address => '127.0.0.1:47400';

  @override
  Stream<LinkEvent> get events => _events.stream;

  @override
  void send(String peer, Msg m) {}

  @override
  void broadcast(Msg m) {}

  @override
  void drop(String peer) {}

  @override
  void lobbyChanged(LobbyInfo info) {
    lobbyHistory.add(info);
  }

  @override
  Future<void> finished({String? winner, required List<String> players}) async {}

  @override
  Future<void> close() async => _events.close();
}

void main() {
  final data = loadData();

  group('Lobby Status Badges (MATCHING vs IN GAME)', () {
    test('HostSession initializes with matching status and transitions to inGame on match start', () async {
      final link = _MockHostLink();
      final host = HostSession(
        link,
        data,
        name: 'HostPlayer',
        dataVersion: '1',
        playerId: 'host_id',
        reconnectToken: 'host_token',
      );

      // Initial lobby info should be matching
      expect(host.info.status, 'matching');
      expect(host.info.playing, isFalse);

      // Pick a hero for seat 0 and make seat 1 AI
      host.pickHero(data.heroes.keys.first);
      host.toggleSeat(1);

      // Start match
      host.start();
      expect(host.match, isNotNull);

      // After starting, status transitions to inGame
      expect(host.info.status, 'inGame');
      expect(host.info.playing, isTrue);

      host.leave();
    });

    test('LobbyInfo supports matching and inGame status values', () {
      final LobbyInfo matchingInfo = (
        mode: 'duel',
        players: 2,
        open: 1,
        playing: false,
        status: 'matching',
      );
      expect(matchingInfo.status, 'matching');

      final LobbyInfo inGameInfo = (
        mode: 'duel',
        players: 2,
        open: 0,
        playing: true,
        status: 'inGame',
      );
      expect(inGameInfo.status, 'inGame');
    });
  });
}
