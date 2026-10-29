/// Global online presence, active players directory, and direct match invites.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import 'online.dart';
import 'profile_stats.dart';

class OnlineUser {
  const OnlineUser({
    required this.id,
    required this.name,
    this.avatar,
    required this.status,
    this.lobbyId,
    this.stats,
  });

  final String id;
  final String name;
  final String? avatar;
  final String status; // 'idle', 'matching', 'inGame'
  final String? lobbyId;
  final Map<String, Object?>? stats;

  String get statusLabel => switch (status) {
    'matching' => 'Matching',
    'inGame' => 'In Game',
    _ => 'Online - Idle',
  };

  factory OnlineUser.fromJson(Map<String, Object?> json) => OnlineUser(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Player',
    avatar: json['avatar'] as String?,
    status: json['status'] as String? ?? 'idle',
    lobbyId: json['lobbyId'] as String?,
    stats: json['stats'] is Map ? (json['stats'] as Map).cast<String, Object?>() : null,
  );
}

class MatchInvite {
  const MatchInvite({
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.lobbyId,
    required this.lobbyName,
    required this.expiresAt,
  });

  final String fromId;
  final String fromName;
  final String toId;
  final String lobbyId;
  final String lobbyName;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class OnlinePresenceService extends ChangeNotifier {
  OnlinePresenceService._();
  static final OnlinePresenceService instance = OnlinePresenceService._();

  RealtimeChannel? _channel;
  bool _active = false;
  String _myId = '';
  String _myName = '';
  String _myStatus = 'idle';
  String? _myLobbyId;

  final Map<String, OnlineUser> _users = {};
  List<OnlineUser> get onlineUsers => _users.values.toList();
  List<OnlineUser> get users => onlineUsers;

  final StreamController<MatchInvite> _invites = StreamController.broadcast();
  Stream<MatchInvite> get invites => _invites.stream;

  Future<void> start({
    required String playerId,
    required String username,
    SupabaseClient? client,
  }) async {
    if (!isOnlineConfigured && client == null) return;
    _myId = playerId;
    _myName = username;
    _myStatus = 'idle';

    try {
      final sb = client ?? newSupabaseClient();
      final ch = _channel = sb.channel(
        'unmatched-presence',
        opts: const RealtimeChannelConfig(key: 'unmatched-global'),
      );

      ch.onPresenceSync((_) {
        final state = ch.presenceState();
        _users.clear();
        for (final presence in state) {
          for (final raw in presence.presences) {
            final payload = raw.payload;
            final u = OnlineUser.fromJson(payload);
            if (u.id.isNotEmpty && u.id != _myId) {
              _users[u.id] = u;
            }
          }
        }
        notifyListeners();
      });

      ch.onBroadcast(
        event: 'invite:send',
        callback: (payload) {
          final d = payload['payload'] is Map ? payload['payload'] as Map : payload;
          if (d['toId'] == _myId) {
            final exp = d['expiresAt'] != null
                ? (DateTime.tryParse(d['expiresAt'].toString()) ?? DateTime.now().add(const Duration(seconds: 60)))
                : DateTime.now().add(const Duration(seconds: 60));
            final inv = MatchInvite(
              fromId: '${d['fromId'] ?? ''}',
              fromName: '${d['fromName'] ?? 'Opponent'}',
              toId: _myId,
              lobbyId: '${d['lobbyId'] ?? ''}',
              lobbyName: '${d['lobbyName'] ?? 'Match'}',
              expiresAt: exp,
            );
            if (!inv.isExpired) {
              _invites.add(inv);
            }
          }
        },
      );

      ch.subscribe();
      _active = true;
      await updateStatus(status: 'idle');
    } catch (_) {}
  }

  Future<void> updateStatus({required String status, String? lobbyId}) async {
    _myStatus = status;
    _myLobbyId = lobbyId;
    final ch = _channel;
    if (ch == null || !_active) return;
    try {
      await ch.track({
        'id': _myId,
        'name': _myName,
        'status': _myStatus,
        if (_myLobbyId != null) 'lobbyId': _myLobbyId,
        'stats': ProfileStats.instance.toSummaryPayload(),
      });
    } catch (_) {}
  }

  Future<void> sendInvite({
    required String targetUserId,
    required String lobbyId,
    required String lobbyName,
  }) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(
        event: 'invite:send',
        payload: {
          'fromId': _myId,
          'fromName': _myName,
          'toId': targetUserId,
          'lobbyId': lobbyId,
          'lobbyName': lobbyName,
          'expiresAt': DateTime.now().add(const Duration(seconds: 60)).toIso8601String(),
        },
      );
    } catch (_) {}
  }

  Future<void> stop() async {
    _active = false;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.unsubscribe();
      } catch (_) {}
    }
  }
}
