import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/online_presence.dart';

void main() {
  group('OnlineUser', () {
    test('parses Postgres database response (snake_case)', () {
      final now = DateTime.now().toUtc();
      final json = <String, Object?>{
        'id': 'player-123',
        'name': 'Galahad',
        'avatar': 'avatar_1',
        'status': 'matching',
        'lobby_id': 'lobby-abc',
        'seen_at': now.toIso8601String(),
        'stats': <String, Object?>{
          'totalMatches': 10,
          'wins': 7,
          'losses': 3,
          'winRate': 70.0,
        },
      };

      final user = OnlineUser.fromJson(json);

      expect(user.id, 'player-123');
      expect(user.name, 'Galahad');
      expect(user.avatar, 'avatar_1');
      expect(user.status, 'matching');
      expect(user.lobbyId, 'lobby-abc');
      expect(user.seenAt, isNotNull);
      expect(user.stats?['totalMatches'], 10);
      expect(user.statusLabel, 'Matching');
    });

    test('parses Supabase Realtime broadcast payload (camelCase)', () {
      final json = <String, Object?>{
        'id': 'player-456',
        'name': 'RobinHood',
        'status': 'inGame',
        'lobbyId': 'lobby-xyz',
      };

      final user = OnlineUser.fromJson(json);

      expect(user.id, 'player-456');
      expect(user.name, 'RobinHood');
      expect(user.status, 'inGame');
      expect(user.lobbyId, 'lobby-xyz');
      expect(user.seenAt, isNull);
      expect(user.statusLabel, 'In Game');
    });

    test('statusLabel defaults to Online - Idle for unspecified or idle statuses', () {
      final idleUser = OnlineUser.fromJson({'id': 'p1', 'status': 'idle'});
      expect(idleUser.statusLabel, 'Online - Idle');

      final unknownUser = OnlineUser.fromJson({'id': 'p2', 'status': 'unknown_val'});
      expect(unknownUser.statusLabel, 'Online - Idle');
    });
  });

  group('MatchInvite', () {
    test('detects active vs expired invitations', () {
      final activeInvite = MatchInvite(
        fromId: 'p1',
        fromName: 'Alice',
        toId: 'p2',
        lobbyId: 'lobby-1',
        lobbyName: 'Duel Room',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );

      expect(activeInvite.isExpired, isFalse);

      final expiredInvite = MatchInvite(
        fromId: 'p1',
        fromName: 'Alice',
        toId: 'p2',
        lobbyId: 'lobby-1',
        lobbyName: 'Duel Room',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );

      expect(expiredInvite.isExpired, isTrue);
    });
  });
}

