import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';

import 'support.dart';

class _MockHostLink implements HostLink {
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

void main() {
  final data = loadData();

  group('Authenticated Rejoin & Anti-Hijack Seat Lock', () {
    test('reserves seat on disconnect and blocks stranger without matching token', () async {
      final link = _MockHostLink();
      final host = HostSession(
        link,
        data,
        name: 'HostPlayer',
        dataVersion: '1',
        playerId: 'host_id',
        reconnectToken: 'host_token',
      );

      // Player 1 sends hello with playerId and reconnect token
      link.emit(
        PeerMessage(
          'peer_1',
          {
            't': 'hello',
            'v': netProtocol,
            'data': '1',
            'name': 'Player1',
            'playerId': 'p1_id',
            'token': 'token_secret_123',
          },
        ),
      );
      await pumpEventQueue();

      final lobby = host.lobby!;
      expect(lobby.seats[1].kind, SeatKind.human);
      expect(lobby.seats[1].playerId, 'p1_id');
      expect(lobby.seats[1].reconnectToken, 'token_secret_123');

      // Player 1 disconnects (PeerLeft)
      link.emit(const PeerLeft('peer_1'));
      await pumpEventQueue();

      // Seat 1 is now marked as reservedDisconnected
      expect(lobby.seats[1].kind, SeatKind.reservedDisconnected);
      expect(lobby.seats[1].isReserved, isTrue);
      expect(lobby.seats[1].playerId, 'p1_id');
      expect(lobby.seats[1].reconnectToken, 'token_secret_123');

      // A stranger attempts to join while seat is reserved
      link.emit(
        PeerMessage(
          'stranger_peer',
          {
            't': 'hello',
            'v': netProtocol,
            'data': '1',
            'name': 'Stranger',
            'playerId': 'stranger_id',
            'token': 'wrong_token',
          },
        ),
      );
      await pumpEventQueue();

      // Stranger should be rejected with anti-hijack notice
      final rejections = link.sent.where((s) => s.peer == 'stranger_peer' && s.msg['t'] == 'reject').toList();
      expect(rejections, isNotEmpty);
      expect(
        rejections.first.msg['why'],
        'This match is already underway or holding a spot for a reconnecting player.',
      );

      // Stranger was NOT seated in seat 1
      expect(lobby.seats[1].kind, SeatKind.reservedDisconnected);
      expect(lobby.seats[1].playerId, 'p1_id');

      // Original player reconnects with matching token
      link.emit(
        PeerMessage(
          'reconnecting_peer',
          {
            't': 'hello',
            'v': netProtocol,
            'data': '1',
            'name': 'Player1',
            'playerId': 'p1_id',
            'token': 'token_secret_123',
          },
        ),
      );
      await pumpEventQueue();

      // Original player successfully reclaimed seat 1!
      expect(lobby.seats[1].kind, SeatKind.human);
      expect(lobby.seats[1].peer, 'reconnecting_peer');
      expect(lobby.seats[1].playerId, 'p1_id');

      host.leave();
    });
  });
}
