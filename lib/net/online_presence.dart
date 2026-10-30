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

  /// The player's profile (rating, main hero, win rates) from the stats they publish.
  PlayerProfile get profile => PlayerProfile.fromPayload(stats);

  /// Reads a database row or a Realtime presence payload. Values of the wrong type from a peer on
  /// another build are ignored rather than thrown on.
  factory OnlineUser.fromJson(Map<String, Object?> json) {
    String? text(Object? v) => v?.toString();
    Map<String, Object?>? map(Object? v) {
      if (v is! Map) return null;
      try {
        return v.cast<String, Object?>();
      } catch (_) {
        return null;
      }
    }

    final name = (text(json['name']) ?? '').trim();
    return OnlineUser(
      id: text(json['id']) ?? '',
      name: name.isEmpty ? 'Player' : name,
      avatar: text(json['avatar']),
      status: text(json['status']) ?? 'idle',
      lobbyId: text(json['lobby_id'] ?? json['lobbyId']),
      stats: map(json['stats']),
      seenAt: DateTime.tryParse('${json['seen_at'] ?? ''}'),
    );
  }
}

class MatchInvite {
  const MatchInvite({
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.lobbyId,
    required this.lobbyName,
    required this.expiresAt,
    this.fromStats,
  });

  final String fromId;
  final String fromName;
  final String toId;
  final String lobbyId;
  final String lobbyName;
  final DateTime expiresAt;

  /// The challenger's rating badge payload (rating, main hero, win rates), if they sent it.
  final Map<String, Object?>? fromStats;

  PlayerProfile get fromProfile => PlayerProfile.fromPayload(fromStats);

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

  /// Delivers an invite as if it had arrived over the network (tests).
  @visibleForTesting
  void debugReceiveInvite(MatchInvite invite) => _invites.add(invite);

  /// Replaces the directory without a server (tests).
  @visibleForTesting
  void debugSetUsers(Iterable<OnlineUser> users) {
    _users
      ..clear()
      ..addEntries(users.map((u) => MapEntry(u.id, u)));
    notifyListeners();
  }

  final StreamController<MatchInvite> _invites = StreamController.broadcast();
  final Map<String, DateTime> _recentInvites = {};

  /// Someone answered one of our invites with "no" (or was busy): their name and why.
  final StreamController<({String name, String reason})> _declines = StreamController.broadcast();
  Stream<({String name, String reason})> get declines => _declines.stream;

  static Map<String, Object?>? _tryCast(Map m) {
    try {
      return m.cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }
  Stream<MatchInvite> get invites => _invites.stream;

  Future<void> start({
    required String playerId,
    required String username,
    SupabaseClient? client,
  }) async {
    if (!isOnlineConfigured && client == null) return;
    if (playerId.isEmpty) return;
    // Already running for this player (every screen asks): only pick up a changed name. Starting
    // again would leave the old Realtime channel subscribed, and invites would arrive twice.
    if (_active && _myId == playerId && client == null) {
      if (_myName != username) {
        _myName = username;
        _trackRealtime();
      }
      return;
    }
    if (_active) await stop();
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
          if (d['toId'] == _myId && d['fromId'] != _myId) {
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
              fromStats: d['fromStats'] is Map ? _tryCast(d['fromStats'] as Map) : null,
            );
            // The same invite can arrive twice (a retry, two sockets): show it once.
            final seen = _recentInvites[inv.lobbyId];
            _recentInvites[inv.lobbyId] = DateTime.now();
            if (seen != null && DateTime.now().difference(seen) < const Duration(seconds: 10)) return;
            if (!inv.isExpired && !_invites.isClosed) {
              _invites.add(inv);
            }
          }
        },
      );

      ch.onBroadcast(
        event: 'invite:decline',
        callback: (payload) {
          final d = payload['payload'] is Map ? payload['payload'] as Map : payload;
          if (d['toId'] == _myId && !_declines.isClosed) {
            _declines.add((name: '${d['fromName'] ?? 'Player'}', reason: '${d['reason'] ?? 'declined'}'));
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

  /// 'idle', 'matching' or 'inGame': what this device last told the others.
  String get myStatus => _myStatus;

  /// Whether the Realtime channel is up, so an invite can actually be delivered.
  bool get canInvite => _active && _channel != null && _channelSubscribed;

  /// Sends a match invite to [targetUserId]. False when it could not be sent.
  Future<bool> sendInvite({
    required String targetUserId,
    required String lobbyId,
    required String lobbyName,
  }) async {
    final ch = _channel;
    if (ch == null || !_channelSubscribed || targetUserId.isEmpty || targetUserId == _myId) return false;
    try {
      await ch.sendBroadcastMessage(
        event: 'invite:send',
        payload: {
          'fromId': _myId,
          'fromName': _myName,
          'fromStats': ProfileStats.instance.toBadgePayload(),
          'toId': targetUserId,
          'lobbyId': lobbyId,
          'lobbyName': lobbyName,
          'expiresAt': DateTime.now().add(const Duration(seconds: 60)).toIso8601String(),
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tells the sender of [invite] it was declined ([reason] 'declined', 'busy' or 'expired').
  Future<void> declineInvite(MatchInvite invite, {String reason = 'declined'}) async {
    final ch = _channel;
    if (ch == null || !_channelSubscribed || invite.fromId.isEmpty) return;
    try {
      await ch.sendBroadcastMessage(
        event: 'invite:decline',
        payload: {'toId': invite.fromId, 'fromId': _myId, 'fromName': _myName, 'lobbyId': invite.lobbyId, 'reason': reason},
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
