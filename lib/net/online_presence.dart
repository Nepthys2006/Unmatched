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
    this.seenAt,
  });

  final String id;
  final String name;
  final String? avatar;
  final String status; // 'idle', 'matching', 'inGame'
  final String? lobbyId;
  final Map<String, Object?>? stats;
  final DateTime? seenAt;

  String get statusLabel => switch (status) {
    'matching' => 'Matching',
    'inGame' => 'In Game',
    _ => 'Online - Idle',
  };

  factory OnlineUser.fromJson(Map<String, Object?> json) => OnlineUser(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? 'Player').toString(),
    avatar: json['avatar'] as String?,
    status: (json['status'] ?? 'idle').toString(),
    lobbyId: (json['lobby_id'] ?? json['lobbyId']) as String?,
    stats: json['stats'] is Map ? (json['stats'] as Map).cast<String, Object?>() : null,
    seenAt: json['seen_at'] != null ? DateTime.tryParse(json['seen_at'].toString()) : null,
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

  SupabaseClient? _sbClient;
  RealtimeChannel? _channel;
  Timer? _pingTimer;
  Timer? _fetchTimer;
  bool _active = false;
  bool _channelSubscribed = false;

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

    _sbClient = client ?? newSupabaseClient();
    final sb = _sbClient!;
    _active = true;

    // 1. Immediate database ping & fetch
    await _pingDatabase();
    await refresh();

    // 2. Start heartbeats: ping every 15 seconds, poll database every 10 seconds
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pingDatabase());

    _fetchTimer?.cancel();
    _fetchTimer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());

    // 3. Supabase Realtime channel for live invites and instant presence broadcast
    try {
      final ch = _channel = sb.channel(
        'unmatched-presence',
        opts: RealtimeChannelConfig(key: _myId),
      );

      ch.onPresenceSync((_) {
        final state = ch.presenceState();
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

      ch.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _channelSubscribed = true;
          _trackRealtime();
        }
      });
    } catch (_) {}
  }

  /// Sends a presence heartbeat to the database active_players table.
  Future<void> _pingDatabase() async {
    final sb = _sbClient;
    if (sb == null || !_active || _myId.isEmpty) return;
    try {
      await sb.rpc('ping_presence', params: {
        'p_id': _myId,
        'p_name': _myName,
        'p_status': _myStatus,
        if (_myLobbyId != null) 'p_lobby_id': _myLobbyId,
        'p_stats': ProfileStats.instance.toSummaryPayload(),
      }).timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  /// Refreshes the active players list from the database.
  Future<void> refresh() async {
    final sb = _sbClient;
    if (sb == null || !_active) return;
    try {
      final res = await sb.rpc('get_active_players').timeout(const Duration(seconds: 6));
      if (res is List) {
        final fetched = <String, OnlineUser>{};
        for (final row in res) {
          if (row is Map) {
            final u = OnlineUser.fromJson(row.cast<String, Object?>());
            if (u.id.isNotEmpty && u.id != _myId) {
              fetched[u.id] = u;
            }
          }
        }
        _users.clear();
        _users.addAll(fetched);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Tracks state in the Realtime channel if subscribed.
  void _trackRealtime() {
    final ch = _channel;
    if (ch == null || !_active || !_channelSubscribed) return;
    try {
      ch.track({
        'id': _myId,
        'name': _myName,
        'status': _myStatus,
        if (_myLobbyId != null) 'lobbyId': _myLobbyId,
        'stats': ProfileStats.instance.toSummaryPayload(),
      });
    } catch (_) {}
  }

  Future<void> updateStatus({required String status, String? lobbyId}) async {
    _myStatus = status;
    _myLobbyId = lobbyId;
    await _pingDatabase();
    _trackRealtime();
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
    _channelSubscribed = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _fetchTimer?.cancel();
    _fetchTimer = null;

    final sb = _sbClient;
    if (sb != null && _myId.isNotEmpty) {
      try {
        await sb.rpc('leave_presence', params: {'p_id': _myId}).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    _sbClient = null;

    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.unsubscribe();
      } catch (_) {}
    }
    _users.clear();
    notifyListeners();
  }
}
