/// Online play through Supabase. Hosts create a named lobby (optionally with a password) that
/// appears in everyone's lobby list; joining checks the password on the server and hands out
/// the lobby's secret Realtime channel, over which the match runs exactly as on LAN (the host's
/// device is the authority, see session.dart). When a match ends the lobby is deleted and only
/// the winner and the players' names are kept.
///
/// The lobby's chat goes over the same channel; the host also keeps each message in the
/// `chat_messages` table (`chat_post`) while the lobby lives, keyed by the lobby's secret topic,
/// and deletes them all (`chat_clear`) when the match ends or the lobby closes. The server
/// deletes messages over 6 hours old too, for hosts that vanished mid-match. (The SQL for these,
/// supabase/chat.sql, is kept out of git with the rest of the database setup.)
///
/// Messages are batched (one broadcast per ~40 ms) to stay well inside Realtime's rate limits.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:supabase/supabase.dart';

import 'link.dart';

/// The game's Supabase project configuration (passed via --dart-define or environment).
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: '');

/// Whether online play credentials have been configured.
bool get isOnlineConfigured => _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty;

/// Created the first time online play is opened (not at app start, so the game starts fast and
/// works offline). No sign-in is needed.
SupabaseClient? _supabase;
SupabaseClient get _client {
  if (!isOnlineConfigured) {
    throw StateError('Online play is not configured (missing SUPABASE_URL / SUPABASE_KEY).');
  }
  return _supabase ??= newSupabaseClient();
}

/// A separate connection (tests use one per simulated device).
SupabaseClient newSupabaseClient([String? url, String? key]) {
  final targetUrl = url ?? _supabaseUrl;
  final targetKey = key ?? _supabaseKey;
  if (targetUrl.isEmpty || targetKey.isEmpty) {
    throw StateError('Online play is not configured (missing SUPABASE_URL / SUPABASE_KEY).');
  }
  return SupabaseClient(targetUrl, targetKey);
}

const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
String _id(math.Random r) => List.generate(12, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
String _channel(String topic) => 'unmatched-$topic';

/// A lobby as listed for players looking for a game.
typedef OnlineLobby = ({String id, String name, String host, String mode, int players, int open, bool locked, String status});

/// The lobbies waiting for players, newest first.
Future<List<OnlineLobby>> listLobbies({SupabaseClient? client}) async {
  if (client == null && !isOnlineConfigured) {
    return const [];
  }
  final rows = await _rpc(client ?? _client, 'list_lobbies', {}) as List;
  return [
    for (final r in rows.cast<Map>())
      (
        id: r['id'] as String,
        name: r['name'] as String,
        host: r['host_name'] as String,
        mode: r['mode'] as String,
        players: r['players'] as int,
        open: r['open_seats'] as int,
        locked: r['has_password'] == true,
        status: (r['status'] as String?) == 'playing' ? 'inGame' : 'matching',
      ),
  ];
}

/// Calls a lobby function; database errors come back as readable messages.
Future<Object?> _rpc(SupabaseClient c, String fn, Map<String, Object?> params) async {
  try {
    return await c.rpc(fn, params: params).timeout(const Duration(seconds: 12));
  } on PostgrestException catch (e) {
    if (e.code == 'PGRST202' || e.message.contains('Could not find the function')) {
      throw StateError('Online lobbies are not available on the server yet.');
    }
    throw StateError(e.message);
  } on TimeoutException {
    throw StateError('The online service didn\'t answer. Check your internet connection.');
  }
}

Future<RealtimeChannel> _join(SupabaseClient client, String topic, String key, {required void Function(RealtimeChannel) bind}) async {
  final ch = client.channel(topic, opts: RealtimeChannelConfig(key: key, enabled: true));
  bind(ch);
  final ready = Completer<void>();
  ch.subscribe((status, err) {
    if (ready.isCompleted) return;
    if (status == RealtimeSubscribeStatus.subscribed) {
      ready.complete();
    } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
      ready.completeError(StateError('Could not reach the online service ($status).'));
    }
  });
  await ready.future.timeout(const Duration(seconds: 12));
  return ch;
}

Msg _data(Map<String, dynamic> payload) {
  final inner = payload['payload'];
  return (inner is Map ? inner : payload).cast<String, Object?>();
}

/// Sends batched broadcasts on one event.
class _Outbox {
  _Outbox(this.ch, this.event, this.wrap);
  final RealtimeChannel ch;
  final String event;
  final Msg Function(List<Msg> items) wrap;
  final List<Msg> _items = [];
  Timer? _t;

  void add(Msg m) {
    _items.add(m);
    _t ??= Timer(const Duration(milliseconds: 40), flush);
  }

  void flush() {
    _t = null;
    if (_items.isEmpty) return;
    final batch = List.of(_items);
    _items.clear();
    unawaited(ch.sendBroadcastMessage(event: event, payload: wrap(batch)).catchError((_) => ChannelResponse.error));
  }
}

class OnlineHost implements HostLink, ChatKeeper {
  OnlineHost._(this.name, this._sb, this._id, this._token, this._room);

  /// Creates a lobby called [name] (an empty [password] means anyone can join).
  static Future<OnlineHost> create({
    required String name,
    required String hostName,
    String password = '',
    required LobbyInfo info,
    SupabaseClient? client,
  }) async {
    final sb = client ?? _client;
    final rows = await _rpc(sb, 'create_lobby', {
      'p_name': name.trim().isEmpty ? '$hostName\'s lobby' : name.trim(),
      'p_host_name': hostName,
      'p_password': password,
      'p_mode': info.mode,
      'p_players': info.players,
      'p_open': info.open,
      'p_status': info.status == 'inGame' ? 'playing' : 'waiting',
    }) as List;
    final row = rows.first as Map;
    final h = OnlineHost._(name, sb, row['id'] as String, row['host_token'] as String, row['topic'] as String);
    try {
      h._ch = await _join(sb, _channel(h._room), 'host', bind: h._bind);
      await h._ch.track({'role': 'host', 'name': hostName});
    } catch (_) {
      await _rpc(sb, 'close_lobby', {'p_id': h._id, 'p_token': h._token});
      rethrow;
    }
    h._out = _Outbox(h._ch, 'h2c', (items) => {'items': items});
    h._info = info;
    // Heartbeat: a lobby whose host stops checking in disappears from the list.
    h._beat = Timer.periodic(const Duration(seconds: 30), (_) => h._push());
    return h;
  }

  final String name;
  final SupabaseClient _sb;
  final String _id;
  final String _token;

  String get id => _id;
  String get room => _room;

  /// The lobby's secret channel topic: only its players know it. The chat is kept under it.
  final String _room;
  late RealtimeChannel _ch;
  late _Outbox _out;
  late LobbyInfo _info;
  Timer? _beat;
  Timer? _debounce;
  bool _closed = false;
  final StreamController<LinkEvent> _events = StreamController.broadcast();
  final Set<String> _peers = {};

  void _bind(RealtimeChannel ch) {
    ch
      ..onPresenceJoin((p) {
        if (p.key == 'host' || !_peers.add(p.key)) return;
        _events.add(PeerJoined(p.key));
      })
      ..onPresenceLeave((p) {
        if (_peers.remove(p.key)) _events.add(PeerLeft(p.key));
      })
      ..onBroadcast(
        event: 'c2h',
        callback: (payload) {
          final d = _data(payload);
          final from = d['from'];
          final items = d['items'];
          if (from is! String || items is! List) return;
          if (_peers.add(from)) _events.add(PeerJoined(from));
          for (final m in items) {
            if (m is Map) _events.add(PeerMessage(from, m.cast<String, Object?>()));
          }
        },
      );
  }

  Future<void> _push() async {
    if (_closed) return;
    try {
      await _rpc(_sb, 'update_lobby', {
        'p_id': _id,
        'p_token': _token,
        'p_mode': _info.mode,
        'p_players': _info.players,
        'p_open': _info.open,
        'p_status': _info.status == 'inGame' || _info.playing ? 'playing' : 'waiting',
      });
    } catch (_) {
      // Next heartbeat tries again.
    }
  }

  @override
  void lobbyChanged(LobbyInfo info) {
    _info = info;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _push);
  }

  /// Chat messages being stored, in order (the last one).
  Future<void> _chatWrites = Future.value();

  @override
  Future<void> keepChat(Msg m) {
    // Once the match is over nothing more is kept (the "gg" after it is only passed on).
    if (_closed) return Future.value();
    return _chatWrites = _chatWrites.then(
      (_) => _rpc(_sb, 'chat_post', {
        'p_room': _room,
        'p_seq': m['id'],
        'p_seat': m['seat'],
        'p_name': m['name'],
        'p_body': m['text'],
      }).then((_) {}, onError: (Object _) {}),
    );
  }

  /// Deletes the lobby's chat from the server, after the messages still being stored.
  Future<void> _clearChat() async {
    await _chatWrites;
    await _rpc(_sb, 'chat_clear', {'p_room': _room}).catchError((_) => null);
  }

  @override
  Future<void> finished({String? winner, required List<String> players}) async {
    if (_closed) return;
    _closed = true;
    _beat?.cancel();
    await _clearChat();
    await _rpc(_sb, 'finish_lobby', {'p_id': _id, 'p_token': _token, 'p_winner': winner, 'p_players': players}).catchError((_) => null);
  }

  @override
  Stream<LinkEvent> get events => _events.stream;
  @override
  String get address => name;

  @override
  void send(String peer, Msg m) => _out.add({'to': peer, 'm': m});
  @override
  void broadcast(Msg m) => _out.add({'m': m});

  @override
  void drop(String peer) {
    // The channel can't disconnect anyone; the reject message makes their game leave.
    if (_peers.remove(peer)) _events.add(PeerLeft(peer));
  }

  @override
  Future<void> close() async {
    _beat?.cancel();
    _debounce?.cancel();
    if (!_closed) {
      _closed = true;
      await _clearChat();
      await _rpc(_sb, 'close_lobby', {'p_id': _id, 'p_token': _token}).catchError((_) => null);
    }
    _out.flush();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _sb.removeChannel(_ch);
    await _events.close();
  }
}

class OnlineClient implements ClientLink {
  OnlineClient._(this._me, this._sb, {this.topic});
  final String? topic;

  /// Joins lobby [id]; the server checks [password] and that a seat is free.
  /// Reconnects to an active lobby by topic during grace period.
  static Future<OnlineClient> reconnect({required String topic, SupabaseClient? client}) async {
    final sb = client ?? _client;
    final c = OnlineClient._(_id(math.Random.secure()), sb, topic: topic);
    final ch = c._ch = await _join(sb, _channel(topic), c._me, bind: c._bind);
    await ch.track({'role': 'player'});
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (!ch.presenceState().any((p) => p.key == 'host')) {
      if (DateTime.now().isAfter(end)) {
        await sb.removeChannel(ch);
        throw StateError('The host isn\'t answering. The match may have ended.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    c._out = _Outbox(ch, 'c2h', (items) => {'from': c._me, 'items': items});
    return c;
  }

  static Future<OnlineClient> join(String id, {String password = '', SupabaseClient? client}) async {
    final sb = client ?? _client;
    final topic = await _rpc(sb, 'join_lobby', {'p_id': id, 'p_password': password}) as String;
    final c = OnlineClient._(_id(math.Random.secure()), sb, topic: topic);
    final ch = c._ch = await _join(sb, _channel(topic), c._me, bind: c._bind);
    await ch.track({'role': 'player'});
    // Wait for the host to show up in the channel's presence.
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (!ch.presenceState().any((p) => p.key == 'host')) {
      if (DateTime.now().isAfter(end)) {
        await sb.removeChannel(ch);
        throw StateError('The host isn\'t answering. The lobby may have just closed.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    c._out = _Outbox(ch, 'c2h', (items) => {'from': c._me, 'items': items});
    return c;
  }

  final String _me;
  final SupabaseClient _sb;
  late RealtimeChannel _ch;
  late _Outbox _out;
  final StreamController<Msg> _messages = StreamController.broadcast();
  final Completer<String?> _done = Completer();

  void _bind(RealtimeChannel ch) {
    ch
      ..onPresenceLeave((p) {
        if (p.key == 'host' && !_done.isCompleted) _done.complete('The host left.');
      })
      ..onBroadcast(
        event: 'h2c',
        callback: (payload) {
          final items = _data(payload)['items'];
          if (items is! List) return;
          for (final it in items) {
            if (it is! Map) continue;
            final to = it['to'];
            final m = it['m'];
            if ((to == null || to == _me) && m is Map) _messages.add(m.cast<String, Object?>());
          }
        },
      );
  }

  @override
  Stream<Msg> get messages => _messages.stream;
  @override
  Future<String?> get done => _done.future;
  @override
  void send(Msg m) {
    if (!_done.isCompleted) _out.add(m);
  }

  @override
  Future<void> close() async {
    _out.flush();
    if (!_done.isCompleted) _done.complete(null);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _sb.removeChannel(_ch);
  }
}
