/// Multiplayer lobby and match sessions, the same for LAN and online: the host owns the lobby
/// (mode, map, AI level, who sits where), players pick heroes and get ready, then the host
/// starts the match and every device plays it in lockstep (see lockstep.dart).
///
/// Messages (JSON):
///   player -> host  hello {v, data, name} · hero {id} · ready {on} · seat {i} · ans {seq, picks}
///                   resend {from}  (a message got lost: send the answers from `from` again)
///                   chat {text} · chatResend {from}  (chat messages from number `from` again)
///   host -> player  welcome {seat} · lobby {lobby} · reject {why} · start {lobby, heroes, seed}
///                   ans {seq, seat, picks} · seatAi {seat} · chat {m} · chatLog {from, ms}
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/ai.dart';
import '../engine/defs.dart';
import '../engine/prompt.dart';
import '../ui/match/match_config.dart';
import 'chat.dart';
import 'link.dart';
import 'lockstep.dart';
import 'profile_stats.dart';

/// Bumped whenever the messages or the rules change in a way older copies can't follow.
const netProtocol = 1;

/// How long someone who drops out of a running match keeps their seat. Within it they can rejoin
/// the same match; when it runs out an AI takes their seat for good and the match goes on. The
/// same wait applies to the lobby host: if they do not come back, a remaining player takes over
/// as host (or plays on alone against the AI). A variable only so tests can shorten it.
Duration rejoinGrace = const Duration(minutes: 2);

/// How often a device retries reaching the host (or the new host) while waiting. Shortened by tests.
Duration rejoinRetry = const Duration(seconds: 3);

/// How a player's device reaches (and, if needed, replaces) the host. Supplied by the screen that
/// opened the session, which knows whether this is LAN or online.
abstract class MatchTransport {
  /// This device's address for others to reach it should it become the host (LAN); null if it
  /// can't host or the address doesn't matter (online).
  String? get localAddress => null;

  /// LAN: only players that announced an address can take over as host.
  bool get needsAddress => false;

  /// Whether this device could host in place of a lost host.
  bool get canHost => true;

  /// A fresh connection to the current host.
  Future<ClientLink> reconnect();

  /// Starts hosting in place of a lost host; null when this device can't.
  Future<HostLink?> hostNew() async => null;

  /// A connection to the player at [hostSeat] who has taken over as host; null when not possible.
  Future<ClientLink?> joinNew(Lobby lobby, int hostSeat) async => null;
}

enum SeatKind { open, human, ai, reservedDisconnected }

class LobbySeat {
  LobbySeat(
    this.kind, {
    this.name,
    this.hero,
    this.ready = false,
    this.peer,
    this.playerId,
    this.reconnectToken,
    this.reservedUntil,
    this.stats,
    this.host = false,
    this.addr,
  });

  SeatKind kind;
  String? name;
  String? hero;
  bool ready;

  /// Host only: the connection this seat belongs to (null for the host and AI).
  String? peer;

  /// Host and seat owner: identity and secret token for authenticated rejoin.
  String? playerId;
  String? reconnectToken;
  DateTime? reservedUntil;

  /// Public player stats payload
  Map<String, Object?>? stats;

  /// This seat belongs to the lobby host (everyone knows, so they can pick a new one).
  bool host;

  /// LAN: where this player's device can be reached if it has to become the host.
  String? addr;

  bool get isReserved =>
      kind == SeatKind.reservedDisconnected &&
      reservedUntil != null &&
      DateTime.now().isBefore(reservedUntil!);

  Msg toJson() => {
    'kind': kind.name,
    'name': name,
    'hero': hero,
    'ready': ready,
    if (stats != null) 'stats': stats,
    if (kind == SeatKind.reservedDisconnected) 'reserved': true,
    if (host) 'host': true,
    if (addr != null) 'addr': addr,
  };

  static LobbySeat fromJson(Msg m) => LobbySeat(
    SeatKind.values.byName(m['kind'] as String),
    name: m['name'] as String?,
    hero: m['hero'] as String?,
    ready: m['ready'] == true,
    stats: m['stats'] is Map ? (m['stats'] as Map).cast<String, Object?>() : null,
    host: m['host'] == true,
    addr: m['addr'] as String?,
  );
}

class Lobby {
  Lobby({required this.mode, required this.players, required this.mapId, required this.ai, required this.seats});
  GameMode mode;
  int players;
  String mapId;
  AiLevel ai;
  List<LobbySeat> seats;

  Msg toJson() => {
    'mode': mode.name,
    'players': players,
    'map': mapId,
    'ai': ai.name,
    'seats': [for (final s in seats) s.toJson()],
  };

  static Lobby fromJson(Msg m) => Lobby(
    mode: GameMode.values.byName(m['mode'] as String),
    players: m['players'] as int,
    mapId: m['map'] as String,
    ai: AiLevel.values.byName(m['ai'] as String),
    seats: [for (final s in m['seats'] as List) LobbySeat.fromJson((s as Map).cast<String, Object?>())],
  );

  /// Heroes already picked by seats other than [seat].
  Set<String> takenBy(int? seat) => {
    for (var i = 0; i < seats.length; i++)
      if (i != seat && seats[i].hero != null) seats[i].hero!,
  };
}

/// A running multiplayer match, handed to the match screen.
class NetMatch {
  NetMatch._({
    required this.config,
    required this.localSeat,
    required this.seed,
    required this.isHost,
    required List<String> names,
    required this.aiSeats,
    required this.humanSeats,
    required this.seatStats,
    required this.chat,
    required this._say,
  }) : names = ValueNotifier(names);

  final MatchConfig config;
  final int localSeat;
  final int seed;

  /// Whether this device is the authority. Becomes true when the lost host is replaced by this device.
  bool isHost;
  final Set<int> aiSeats;

  /// The seats that started the match held by real players (an AI may take one over later; it
  /// still counts as a match against a person for the rating).
  final Set<int> humanSeats;

  /// Each seat's public profile payload from the lobby (rating, main hero...), if it had one.
  final List<Map<String, Object?>?> seatStats;

  /// Name per seat ("AI Hard" for AI seats and for players the AI took over).
  final ValueNotifier<List<String>> names;
  final Lockstep ls = Lockstep();
  final Map<int, RemoteSeatAgent> _remotes = {};

  /// Set when the connection is lost mid-match (the reason to show).
  final ValueNotifier<String?> lost = ValueNotifier(null);

  /// Subtle non-intrusive banner message shown during network delays or opponent absence.
  final ValueNotifier<String?> waitingNotice = ValueNotifier(null);

  /// The lobby's chat, carried on into the match.
  final ChatLog chat;
  void Function(String text) _say;

  /// Sends a chat message to everyone in the match.
  void say(String text) => _say(text);
  void Function()? _leave;

  /// The agent for [seat]: [human] for the person on this device, [ai] for AI seats the host
  /// runs, and the network for everyone else.
  Agent agentFor(int seat, {required Agent human, required Agent ai}) {
    if (seat == localSeat) return LocalSeatAgent(ls, seat, human);
    if (isHost && aiSeats.contains(seat)) return LocalSeatAgent(ls, seat, ai);
    return _remotes[seat] = RemoteSeatAgent(ls, seat, host: isHost, onInvalid: _onInvalid);
  }

  void Function(int seat)? _invalid;
  void _onInvalid(int seat) => _invalid?.call(seat);

  void _takeOver(int seat, AiLevel level) {
    _remotes[seat]?.takeOver(AiAgent(level: level));
    _markAi(seat);
  }

  /// Shows [seat] as AI-run in the names.
  void _markAi(int seat) {
    final n = List.of(names.value);
    if (seat < n.length && !n[seat].endsWith('(AI)')) n[seat] = '${n[seat]} (AI)';
    names.value = n;
  }

  /// A short message shown over the match (who was replaced, who is hosting now).
  final ValueNotifier<String?> toast = ValueNotifier(null);
  Timer? _toastTimer;

  /// Shows [text] for a few seconds.
  void showToast(String text) {
    toast.value = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 7), () => toast.value = null);
  }

  /// Leaves the match (closes the connection).
  void leave() => _leave?.call();

  Future<void> Function(String? winner, List<String> players)? _report;

  /// Host only: the match is over. Online, the lobby is wiped and only the winner and the
  /// players' names are kept.
  Future<void> reportResult({String? winner, required List<String> players}) async => _report?.call(winner, players);
}

/// The lobby as either side sees it.
abstract class LobbySession extends ChangeNotifier {
  LobbySession(this.data, {ChatLog? chat}) : chat = chat ?? ChatLog();
  final GameData data;

  Lobby? lobby;
  int? mySeat;
  bool get isHost;

  /// Why the session ended (shown, then back to the menu).
  String? closed;

  /// Table talk, in the lobby and through the match.
  final ChatLog chat;

  /// Sends a chat message as this player.
  void say(String text);

  /// Set once the host starts the match.
  NetMatch? match;

  /// IP address or room code.
  String get address;

  void pickHero(String id);
  void setReady(bool on);
  void moveSeat(int i);
  void setMap(String id);
  void randomMap();
  Future<void> leave();

  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  NetMatch _makeMatch(Lobby l, List<String> heroes, int seed, int localSeat) {
    final map = data.maps[l.mapId]!;
    final config = MatchConfig(mode: l.mode, players: l.players, map: map, ai: l.ai, heroIds: heroes);
    return NetMatch._(
      config: config,
      localSeat: localSeat,
      seed: seed,
      isHost: isHost,
      names: [for (final s in l.seats) s.kind == SeatKind.ai ? 'AI ${_label(l.ai)}' : (s.name ?? 'Player')],
      aiSeats: {
        for (var i = 0; i < l.seats.length; i++)
          if (l.seats[i].kind == SeatKind.ai) i,
      },
      humanSeats: {
        for (var i = 0; i < l.seats.length; i++)
          if (l.seats[i].kind != SeatKind.ai && l.seats[i].kind != SeatKind.open) i,
      },
      seatStats: [for (final s in l.seats) s.stats],
      chat: chat,
      say: say,
    );
  }

  static String _label(AiLevel l) => l.name[0].toUpperCase() + l.name.substring(1);
}

// ============================================================================================ host

class HostSession extends LobbySession {
  HostSession(
    this.link,
    super.data, {
    required String name,
    required this.dataVersion,
    String? playerId,
    String? reconnectToken,
  }) {
    final duel = data.mapsFor('1v1');
    lobby = Lobby(
      mode: GameMode.duel,
      players: 2,
      mapId: duel.first.id,
      ai: AiLevel.medium,
      seats: [
        LobbySeat(
          SeatKind.human,
          name: name,
          ready: true,
          playerId: playerId,
          reconnectToken: reconnectToken,
          stats: ProfileStats.instance.toSummaryPayload(),
        ),
        LobbySeat(SeatKind.open),
      ],
    );
    mySeat = 0;
    _sub = link.events.listen(_onEvent);
  }


  /// A player's device takes over a running match whose host is lost for good. [link] is the new
  /// meeting point for the other players (or a [_NoLink] when playing on alone). The old host's
  /// seat, and every AI seat the old host was running, go to AI here; the other people get the
  /// grace period to join the new host, like anyone who drops out.
  HostSession._adopt(
    HostLink link,
    super.data, {
    required Lobby adoptedLobby,
    required int seat,
    required NetMatch running,
    required this.dataVersion,
    required super.chat,
  }) : link = link {
    lobby = adoptedLobby;
    mySeat = seat;
    match = running;
    _sub = link.events.listen(_onEvent);
    _chatSeq = chat.messages.isEmpty ? 0 : chat.messages.last.id;
    final level = adoptedLobby.ai;
    final solo = link is _NoLink;
    _wireMatch(running);
    for (var i = 0; i < _l.seats.length; i++) {
      final s = _l.seats[i];
      s.peer = null;
      if (i == seat) {
        s.kind = SeatKind.human;
        continue;
      }
      final wasHost = s.host;
      s.host = false;
      if (s.kind == SeatKind.open) continue;
      final agent = running._remotes[i];
      if (s.kind == SeatKind.ai || wasHost || solo) {
        // AI seats the old host ran, the lost host's own seat, and (alone) everyone else.
        s.kind = SeatKind.ai;
        agent?.takeOver(AiAgent(level: level));
        running._markAi(i);
      } else {
        // Another person: the match waits for them to join the new host, up to the grace period.
        agent?.becomeHost(running._invalid);
        _beginAway(i);
      }
    }
    _sync();
  }

  final HostLink link;
  final String dataVersion;
  late final StreamSubscription<LinkEvent> _sub;
  /// Seats whose player dropped out, with the timer that hands the seat to an AI.
  final Map<int, Timer> _awayTimers = {};
  /// Seconds each away seat has left (counted by [_ticker], not read from the clock).
  final Map<int, int> _awayLeft = {};
  Timer? _ticker;

  @override
  bool get isHost => true;
  @override
  String get address => link.address;

  Lobby get _l => lobby!;

  int? _seatOf(String peer) {
    final i = _l.seats.indexWhere((s) => s.peer == peer);
    return i < 0 ? null : i;
  }

  void _sync() {
    for (var i = 0; i < _l.seats.length; i++) {
      _l.seats[i].host = i == mySeat;
    }
    link.broadcast({'t': 'lobby', 'lobby': _l.toJson()});
    link.lobbyChanged(info);
    _changed();
  }

  /// What the lobby list / LAN beacon shows.
  LobbyInfo get info => (
    mode: _l.mode.name,
    players: _l.players,
    open: _l.seats.where((s) => s.kind == SeatKind.open).length,
    playing: match != null,
    status: match != null ? 'inGame' : 'matching',
  );

  void _onEvent(LinkEvent e) {
    switch (e) {
      case PeerJoined():
        break;
      case PeerLeft(:final peer):
        final seat = _seatOf(peer);
        if (seat == null) return;
        _beginAway(seat);
        _sync();
      case PeerMessage(:final peer, :final msg):
        _onMessage(peer, msg);
    }
  }

  /// A player's connection is gone. Their seat is held for [rejoinGrace]: they can come back to
  /// it (same match, same position) until then; after that an AI takes it for good.
  void _beginAway(int seat) {
    final s = _l.seats[seat];
    s.peer = null;
    s.kind = SeatKind.reservedDisconnected;
    s.reservedUntil = DateTime.now().add(rejoinGrace);
    _awayLeft[seat] = rejoinGrace.inSeconds;
    _awayTimers[seat]?.cancel();
    _awayTimers[seat] = Timer(rejoinGrace, () => _graceOver(seat));
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      for (final k in _awayLeft.keys.toList()) {
        _awayLeft[k] = (_awayLeft[k]! - 1).clamp(0, 86400);
      }
      _tick();
    });
    _tick();
  }

  /// The seat's player is back (or gone for good): forget the wait.
  void _endAway(int seat) {
    _awayTimers.remove(seat)?.cancel();
    _awayLeft.remove(seat);
    _tick();
  }

  void _graceOver(int seat) {
    _awayTimers.remove(seat);
    _awayLeft.remove(seat);
    if (seat >= _l.seats.length || _l.seats[seat].kind != SeatKind.reservedDisconnected) {
      _tick();
      return;
    }
    final s = _l.seats[seat];
    final m = match;
    if (m == null) {
      // Still in the lobby: the seat opens up again.
      _l.seats[seat] = LobbySeat(SeatKind.open);
    } else {
      // The match goes on without them: an AI plays the seat from the decision being waited on.
      // The token stays on the seat so a late return is told what happened.
      s.kind = SeatKind.ai;
      m._takeOver(seat, _l.ai);
      link.broadcast({'t': 'seatAi', 'seat': seat});
      _announce("${s.name ?? 'A player'} didn't come back in time. An AI plays their seat now.");
    }
    _tick();
    _sync();
  }

  void _announce(String text) => match?.showToast(text);

  /// Keeps the on-screen "waiting for ... to rejoin" line (with its countdown) up to date.
  void _tick() {
    final m = match;
    if (_awayLeft.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
      if (m != null) m.waitingNotice.value = null;
      return;
    }
    if (m == null) return;
    final first = _awayLeft.entries.reduce((a, b) => a.value <= b.value ? a : b);
    final secs = first.value;
    final clock = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final who = _l.seats[first.key].name ?? 'A player';
    m.waitingNotice.value = _awayLeft.length > 1
        ? 'Waiting for ${_awayLeft.length} players to rejoin ($clock), then AI takes over'
        : '$who disconnected. They can rejoin for $clock, then an AI takes over.';
  }

  void _reject(String peer, String why) {
    link.send(peer, {'t': 'reject', 'why': why});
    link.drop(peer);
  }

  void _onMessage(String peer, Msg m) {
    final seat = _seatOf(peer);
    switch (m['t']) {
      case 'hello':
        if (seat != null) return;
        if (m['v'] != netProtocol || m['data'] != dataVersion) {
          return _reject(peer, 'Different game version. Update both devices to the same build.');
        }
        final clientPlayerId = m['playerId'] as String?;
        final clientToken = m['token'] as String?;
        final clientStats = m['stats'] is Map ? (m['stats'] as Map).cast<String, Object?>() : null;
        final name = '${m['name'] ?? ''}'.trim();

        // 1. Authenticated rejoin: a player who dropped out gets their own seat back. The secret
        //    token proves who they are (a seat can also be reclaimed by name when neither side
        //    ever had a token, as after the host changed).
        int reconnectSeat = -1;
        for (var i = 0; i < _l.seats.length; i++) {
          final s = _l.seats[i];
          final tokenMatch = clientToken != null && s.reconnectToken != null && clientToken == s.reconnectToken;
          // A seat the AI has taken over is not given back; the player is told why.
          if (s.kind == SeatKind.ai && match != null && tokenMatch) {
            return _reject(peer, 'You were away for more than ${rejoinGrace.inMinutes} minutes, so an AI took your seat. The match goes on without you.');
          }
          final isAway = s.kind == SeatKind.reservedDisconnected || (s.kind == SeatKind.human && s.peer == null);
          // The old connection may not have been noticed as gone yet; the token still proves it's them.
          final stale = s.kind == SeatKind.human && s.peer != null && tokenMatch;
          if (isAway || stale) {
            final idMatch = clientPlayerId != null && s.playerId != null && clientPlayerId == s.playerId;
            final legacyMatch = s.reconnectToken == null && s.playerId == null && s.name != null && name.isNotEmpty && s.name == name;
            if (tokenMatch || (s.reconnectToken == null && idMatch) || legacyMatch) {
              reconnectSeat = i;
              break;
            }
          }
        }

        if (reconnectSeat >= 0) {
          final s = _l.seats[reconnectSeat];
          final old = s.peer;
          s.kind = SeatKind.human;
          s.peer = peer;
          s.reservedUntil = null;
          if (name.isNotEmpty) s.name = name;
          if (clientStats != null) s.stats = clientStats;
          if (m['addr'] is String) s.addr = m['addr'] as String;
          _endAway(reconnectSeat);
          if (old != null && old != peer) link.drop(old);
          if (match != null) {
            _reconnectSeat(reconnectSeat, peer);
          } else {
            link.send(peer, {'t': 'welcome', 'seat': reconnectSeat});
            _sendChat(peer, 1);
            _sync();
          }
          return;
        }

        // 2. Reject strangers attempting to join active match or reserved seat
        final anyReserved = _l.seats.any((s) => s.isReserved);
        if (match != null || anyReserved) {
          return _reject(peer, 'This match is already underway or holding a spot for a reconnecting player.');
        }

        // 3. Normal join for open seats
        final open = _l.seats.indexWhere((s) => s.kind == SeatKind.open);
        if (open < 0) return _reject(peer, 'The lobby is full.');
        _l.seats[open] = LobbySeat(
          SeatKind.human,
          name: name.isEmpty ? 'Player ${open + 1}' : name,
          peer: peer,
          playerId: clientPlayerId,
          reconnectToken: clientToken,
          stats: clientStats,
          addr: m['addr'] as String?,
        );
        link.send(peer, {'t': 'welcome', 'seat': open});
        _sendChat(peer, 1);
        _sync();
      case 'hero' when seat != null && match == null:
        final id = m['id'];
        if (id is String && data.heroes.containsKey(id) && !_l.takenBy(seat).contains(id)) {
          _l.seats[seat].hero = id;
          _sync();
        }
      case 'ready' when seat != null && match == null:
        _l.seats[seat].ready = m['on'] == true && _l.seats[seat].hero != null;
        _sync();
      case 'seat' when seat != null && match == null:
        _move(seat, m['i']);
      case 'map' when seat != null && match == null:
        final id = m['id'];
        if (id is String && maps.any((x) => x.id == id)) setMap(id);
      case 'ans' when seat != null && match != null:
        final seq = m['seq'], picks = m['picks'];
        if (seq is int && picks is List && picks.every((x) => x is int)) match!.ls.offer(seq, seat, picks.cast<int>());
      case 'have' when seat != null && match != null:
        // A player joining a new host reports the latest decisions it knows. One that only
        // reached some devices when the old host was lost is taken over here before this host's
        // AI decides it differently. (Decisions of the sender's own seat go the normal way.)
        final list = m['a'];
        if (list is! List) return;
        for (final e in list) {
          if (e is! List || e.length != 3 || e[0] is! int || e[1] is! int || e[2] is! List) continue;
          final seq = e[0] as int, who = e[1] as int, picks = (e[2] as List).whereType<int>().toList();
          if (who == seat || who < 0 || who >= _l.seats.length || seq != match!.ls.answered) continue;
          match!.ls.put(seq, (seat: who, picks: picks));
          match!.ls.publish?.call(seq, (seat: who, picks: picks));
        }
      case 'chat' when seat != null:
        final text = m['text'];
        if (text is String) _post(seat, text, peer: peer);
      case 'chatResend' when seat != null:
        final from = m['from'];
        if (from is int) _sendChat(peer, from);
      case 'resend' when seat != null && match != null:
        final from = m['from'];
        if (from is! int) return;
        for (final (seq, a) in match!.ls.since(from).take(200)) {
          link.send(peer, {'t': 'ans', 'seq': seq, 'seat': a.seat, 'picks': a.picks});
        }
    }
  }

  int _chatSeq = 0;
  final Map<String, List<DateTime>> _chatTimes = {};

  @override
  void say(String text) {
    if (mySeat != null) _post(mySeat!, text);
  }

  /// Numbers a message, shows it here and on every device, and keeps it on the server (online).
  void _post(int seat, String text, {String? peer}) {
    final clean = cleanChat(text);
    if (clean.isEmpty || seat >= _l.seats.length) return;
    // At most 5 messages in 5 seconds from anyone.
    final now = DateTime.now();
    final times = _chatTimes.putIfAbsent(peer ?? '', () => [])..removeWhere((t) => now.difference(t) > const Duration(seconds: 5));
    if (times.length >= 5) return;
    times.add(now);
    final m = ChatMessage(id: ++_chatSeq, seat: seat, name: _l.seats[seat].name ?? 'Player ${seat + 1}', text: clean, at: now);
    chat.add(m, mine: mySeat);
    link.broadcast({'t': 'chat', 'm': m.toJson()});
    if (link case final ChatKeeper k) unawaited(k.keepChat(m.toJson()));
  }

  /// The chat from message number [from] on (what a newcomer missed, or what got lost).
  void _sendChat(String peer, int from) {
    final ms = chat.messages;
    link.send(peer, {
      't': 'chatLog',
      'from': ms.isEmpty ? _chatSeq + 1 : ms.first.id,
      'ms': [
        for (final m in ms)
          if (m.id >= from) m.toJson(),
      ],
    });
  }

  void _move(int from, Object? to) {
    if (to is! int || to < 0 || to >= _l.seats.length || _l.seats[to].kind != SeatKind.open) return;
    _l.seats[to] = _l.seats[from];
    _l.seats[from] = LobbySeat(SeatKind.open);
    if (from == mySeat) mySeat = to;
    for (final s in _l.seats) {
      if (s.peer != null) link.send(s.peer!, {'t': 'welcome', 'seat': _l.seats.indexOf(s)});
    }
    _sync();
  }

  /// Maps that fit the current mode and number of players.
  List<MapDef> get maps => mapsFor(data, _l.mode, _l.players);

  /// Changes mode / number of players. Refused if more people are in the lobby than seats.
  bool setMode(GameMode mode, int players) {
    final humans = [
      for (final s in _l.seats)
        if (s.kind == SeatKind.human) s,
    ];
    if (humans.length > players) return false;
    final old = _l.seats;
    final seats = List<LobbySeat?>.filled(players, null);
    // People keep their seat where it still exists; the rest move to the first free one.
    final moved = <LobbySeat>[];
    for (var i = 0; i < old.length; i++) {
      final s = old[i];
      if (s.kind != SeatKind.human) continue;
      if (i < players) {
        seats[i] = s;
      } else {
        moved.add(s);
      }
    }
    for (final s in moved) {
      seats[seats.indexOf(null)] = s;
    }
    for (var i = 0; i < players; i++) {
      seats[i] ??= i < old.length && old[i].kind == SeatKind.ai ? LobbySeat(SeatKind.ai) : LobbySeat(SeatKind.open);
    }
    _l
      ..mode = mode
      ..players = players
      ..seats = seats.cast<LobbySeat>();
    mySeat = _l.seats.indexWhere((s) => s.kind == SeatKind.human && s.peer == null);
    if (!maps.any((m) => m.id == _l.mapId)) _l.mapId = maps.first.id;
    for (var i = 0; i < _l.seats.length; i++) {
      final p = _l.seats[i].peer;
      if (p != null) link.send(p, {'t': 'welcome', 'seat': i});
    }
    _sync();
    return true;
  }

  @override
  void setMap(String id) {
    if (!maps.any((m) => m.id == id)) return;
    _l.mapId = id;
    _sync();
  }

  @override
  void randomMap() {
    final ms = maps;
    if (ms.isEmpty) return;
    final others = ms.where((m) => m.id != _l.mapId).toList();
    final pick = (others.isEmpty ? ms : others)[math.Random().nextInt(others.isEmpty ? ms.length : others.length)];
    setMap(pick.id);
  }

  void setAi(AiLevel level) {
    _l.ai = level;
    _sync();
  }

  /// Cycles an empty seat between waiting for a player and an AI.
  void toggleSeat(int i) {
    final s = _l.seats[i];
    if (s.kind == SeatKind.human) return;
    _l.seats[i] = LobbySeat(s.kind == SeatKind.open ? SeatKind.ai : SeatKind.open);
    _sync();
  }

  /// Removes a player from the lobby.
  void kick(int i) {
    final p = _l.seats[i].peer;
    if (p == null) return;
    _reject(p, 'The host removed you from the lobby.');
    _l.seats[i] = LobbySeat(SeatKind.open);
    _sync();
  }

  @override
  void pickHero(String id) {
    if (match != null || _l.takenBy(mySeat).contains(id)) return;
    _l.seats[mySeat!].hero = id;
    _sync();
  }

  @override
  void setReady(bool on) {}

  @override
  void moveSeat(int i) => _move(mySeat!, i);

  /// Why the match can't start yet, or null when it can.
  String? get notReady {
    if (_l.seats.any((s) => s.kind == SeatKind.open)) return 'Fill or close every open seat (tap a seat to make it AI).';
    if (_l.seats[mySeat!].hero == null) return 'Choose your hero.';
    final waiting = _l.seats.where((s) => s.kind == SeatKind.human && s.peer != null && (!s.ready || s.hero == null));
    if (waiting.isNotEmpty) return 'Waiting for ${waiting.map((s) => s.name).join(', ')} to get ready.';
    return null;
  }

  void start() {
    if (notReady != null || match != null) return;
    final rng = math.Random.secure();
    final taken = <String>{for (final s in _l.seats) ?s.hero};
    final pool = data.heroes.keys.where((h) => !taken.contains(h)).toList()..shuffle(rng);
    final heroes = [for (final s in _l.seats) s.hero ?? pool.removeLast()];
    // The match seed: decks are shuffled from it on every device. Fresh and secure each match.
    final seed = rng.nextInt(0x7FFFFFFF);
    final m = match = _makeMatch(_l, heroes, seed, mySeat!);
    _wireMatch(m);
    link.broadcast({'t': 'start', 'lobby': _l.toJson(), 'heroes': heroes, 'seed': seed});
    link.lobbyChanged(info);
    _changed();
  }

  void takeOver(int seat, [AiLevel level = AiLevel.hard]) => match?._takeOver(seat, level);

  /// Connects a match to this host: answers are relayed, illegal moves hand the seat to an AI.
  void _wireMatch(NetMatch m) {
    m.isHost = true;
    m.ls.publish = (seq, a) => link.broadcast({'t': 'ans', 'seq': seq, 'seat': a.seat, 'picks': a.picks});
    m._invalid = (seat) {
      final p = _l.seats[seat].peer;
      if (p != null) _reject(p, 'Your game sent an illegal move.');
      _l.seats[seat].peer = null;
      _l.seats[seat].kind = SeatKind.ai;
      m._takeOver(seat, AiLevel.hard);
      link.broadcast({'t': 'seatAi', 'seat': seat});
    };
    m._leave = () => unawaited(leave());
    m._report = (winner, players) => link.finished(winner: winner, players: players);
    m._say = say;
  }

  void _reconnectSeat(int seat, String peer) {
    _l.seats[seat].peer = peer;
    link.send(peer, {'t': 'welcome', 'seat': seat});
    final m = match!;
    final heroes = [for (final s in _l.seats) s.hero!];
    final log = m.ls.since(0).toList();
    // `replay` tells the device how many decisions it has to play through quickly to catch up.
    link.send(peer, {'t': 'start', 'lobby': _l.toJson(), 'heroes': heroes, 'seed': m.seed, 'replay': log.length});
    _sendChat(peer, 1);
    // Seats that started with a person but are AI-run now (replaced after a grace period, or the
    // lost host's seat after a host change).
    for (var i = 0; i < _l.seats.length; i++) {
      if (_l.seats[i].kind == SeatKind.ai && m.humanSeats.contains(i)) link.send(peer, {'t': 'seatAi', 'seat': i, 'quiet': true});
    }
    for (final (seq, a) in log) {
      link.send(peer, {'t': 'ans', 'seq': seq, 'seat': a.seat, 'picks': a.picks});
    }
    _sync();
  }

  bool _left = false;

  void _stopTimers() {
    for (final t in _awayTimers.values) {
      t.cancel();
    }
    _awayTimers.clear();
    _awayLeft.clear();
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    _stopTimers();
    match?.ls.fail(StateError('Left the match'));
    await _sub.cancel();
    await link.close();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }
}

/// The link of a host that has no one to talk to (a player playing on alone after the host was
/// lost): everything is accepted and goes nowhere.
class _NoLink implements HostLink {
  @override
  Stream<LinkEvent> get events => const Stream.empty();
  @override
  void send(String peer, Msg m) {}
  @override
  void broadcast(Msg m) {}
  @override
  void drop(String peer) {}
  @override
  String get address => 'offline';
  @override
  void lobbyChanged(LobbyInfo info) {}
  @override
  Future<void> finished({String? winner, required List<String> players}) async {}
  @override
  Future<void> close() async {}
}

// ========================================================================================== player

class ClientSession extends LobbySession {
  ClientSession(
    this.link,
    super.data, {
    required this._name,
    required this._dataVersion,
    required this.address,
    this.playerId,
    this.reconnectToken,
    this.transport,
  }) {
    _attach(link);
    _repair = Timer.periodic(const Duration(seconds: 2), (_) => _checkLost());
  }

  ClientLink link;
  final String? playerId;
  final String? reconnectToken;

  /// How to reconnect, and how to take over as host, during a match. Without it a lost host ends
  /// the wait after [rejoinGrace] and this device plays on alone against the AI.
  final MatchTransport? transport;
  final String _name;
  final String _dataVersion;
  StreamSubscription<Msg>? _sub;
  late final Timer _repair;
  Timer? _recoveryTicker;
  bool _recovering = false;

  /// Set once this device has become the host (see [_promote]).
  HostSession? promoted;

  Msg _hello() => {
    't': 'hello',
    'v': netProtocol,
    'data': _dataVersion,
    'name': _name,
    if (playerId != null) 'playerId': playerId,
    if (reconnectToken != null) 'token': reconnectToken,
    'stats': ProfileStats.instance.toSummaryPayload(),
    'addr': ?transport?.localAddress,
  };

  /// Starts using [l] as the connection to the host and introduces this player to it.
  void _attach(ClientLink l) {
    unawaited(_sub?.cancel());
    link = l;
    _sub = l.messages.listen(_onMessage);
    l.send(_hello());
    unawaited(l.done.then((reason) => _linkDone(l, reason)));
  }

  /// Answers that came before the start message (messages can arrive out of order online).
  final List<Msg> _early = [];

  /// My own answers the host hasn't echoed back yet, by decision number.
  final Map<int, List<int>> _unacked = {};
  int? _lastWaiting;

  /// Online messages can get lost: ask again for answers we've waited on for a while, and send
  /// again our own answers the host hasn't confirmed.
  void _checkLost() {
    if (_recovering) return;
    final gap = chat.gap;
    if (gap != null) link.send({'t': 'chatResend', 'from': gap});
    final m = match;
    if (m == null) return;
    final w = m.ls.oldestWaiting;
    if (w != null && w == _lastWaiting) link.send({'t': 'resend', 'from': w});
    _lastWaiting = w;
    for (final e in _unacked.entries) {
      link.send({'t': 'ans', 'seq': e.key, 'picks': e.value});
    }
  }

  @override
  final String address;

  @override
  bool get isHost => false;

  void _onMessage(Msg m) {
    // Any word from the host means it is there.
    if (!_recovering) match?.waitingNotice.value = null;
    switch (m['t']) {
      case 'welcome':
        mySeat = m['seat'] as int?;
        _changed();
      case 'lobby':
        lobby = Lobby.fromJson((m['lobby'] as Map).cast<String, Object?>());
        _changed();
      case 'reject':
        closed = '${m['why']}';
        _changed();
        unawaited(leave());
      case 'start' when match != null && match!.seed == m['seed']:
        // Reconnected to the host of the match this device is already playing: carry on, the
        // answers that were missed follow.
        lobby = Lobby.fromJson((m['lobby'] as Map).cast<String, Object?>());
        _changed();
      case 'start':
        final l = lobby = Lobby.fromJson((m['lobby'] as Map).cast<String, Object?>());
        final heroes = (m['heroes'] as List).cast<String>();
        final mm = match = _makeMatch(l, heroes, m['seed'] as int, mySeat!);
        mm.ls.replayTarget = (m['replay'] as num?)?.toInt() ?? 0;
        mm.ls.publish = (seq, a) {
          if (a.seat != mySeat) return;
          _unacked[seq] = a.picks;
          link.send({'t': 'ans', 'seq': seq, 'picks': a.picks});
        };
        mm._leave = () => unawaited(leave());
        final early = List.of(_early);
        _early.clear();
        early.forEach(_onMessage);
        _changed();
      case 'ans' when match == null:
        _early.add(m);
      case 'ans':
        final seq = m['seq'], seat = m['seat'], picks = m['picks'];
        if (seq is int && seat is int && picks is List) {
          _unacked.remove(seq);
          match!.ls.put(seq, (seat: seat, picks: picks.cast<int>()));
        }
      case 'seatAi':
        final seat = m['seat'];
        if (seat is int && match != null) {
          final already = match!.names.value[seat].endsWith('(AI)');
          match!._markAi(seat);
          final name = match!.names.value[seat].replaceAll(' (AI)', '');
          if (!already && m['quiet'] != true) match!.showToast(seat == mySeat ? 'An AI is playing your seat now.' : "$name didn't come back in time. An AI plays their seat now.");
        }
      case 'chat':
        final c = ChatMessage.fromJson(m['m']);
        if (c != null) chat.add(c, mine: mySeat);
      case 'chatLog':
        final ms = m['ms'], from = m['from'];
        if (ms is List) chat.addAll(ms.map(ChatMessage.fromJson).whereType<ChatMessage>(), mine: mySeat, from: from is int ? from : null);
    }
  }

  @override
  void say(String text) {
    final clean = cleanChat(text);
    if (clean.isNotEmpty) link.send({'t': 'chat', 'text': clean});
  }

  /// The connection ended. In a match that starts the recovery: reconnect to the same host for
  /// [rejoinGrace], then (if it never came back) hand the host's job to a remaining player.
  void _linkDone(ClientLink l, String? reason) {
    if (!identical(l, link) || _left || promoted != null) return;
    if (match != null && !_recovering) {
      unawaited(_recover(reason));
      return;
    }
    if (match != null) return;
    final why = closed ?? reason ?? 'Lost the connection to the host.';
    closed = why;
    _changed();
  }

  void _fail(String? reason) {
    final why = closed ?? reason ?? 'The host left the match.';
    closed = why;
    match?.ls.fail(StateError(why));
    match?.lost.value = why;
    _changed();
  }

  static String _clock(int seconds) {
    final s = seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _recover(String? reason) async {
    final m = match!;
    _recovering = true;
    var left = rejoinGrace.inSeconds;
    var expired = false;
    final deadline = Timer(rejoinGrace, () => expired = true);
    void notice() {
      if (_left) return;
      m.waitingNotice.value = 'Lost the connection to the host. Reconnecting... ${_clock(left)}';
    }

    notice();
    _recoveryTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      left = (left - 1).clamp(0, 86400);
      notice();
    });
    final t = transport;
    while (!_left && !expired) {
      if (t != null) {
        try {
          final nl = await t.reconnect().timeout(const Duration(seconds: 10));
          if (_left) {
            unawaited(nl.close());
            return;
          }
          deadline.cancel();
          _recoveryTicker?.cancel();
          _recovering = false;
          m.waitingNotice.value = null;
          _attach(nl);
          return;
        } catch (_) {
          // The host isn't there yet; try again shortly.
        }
      }
      await Future<void>.delayed(rejoinRetry);
    }
    deadline.cancel();
    _recoveryTicker?.cancel();
    if (_left) return;
    await _migrate(reason);
  }

  /// The host did not come back in time. The first remaining person who can host takes over (the
  /// others join them); if there is nobody else, or the others can't be reached, this device plays
  /// on alone against the AI. Every device holds the whole match, so none of it is lost.
  Future<void> _migrate(String? reason) async {
    final m = match!;
    final l = lobby;
    final me = mySeat;
    final t = transport;
    if (l == null || me == null) return _fail(reason);
    final hostSeat = l.seats.indexWhere((s) => s.host);
    bool eligible(int i) {
      final s = l.seats[i];
      if (i == hostSeat || (s.kind != SeatKind.human && s.kind != SeatKind.reservedDisconnected)) return false;
      if (i == me) return t == null || t.canHost;
      return t != null && (!t.needsAddress || s.addr != null);
    }

    final order = [
      for (var i = 0; i < l.seats.length; i++)
        if (eligible(i)) i,
    ];
    final newHost = order.isEmpty ? me : order.first;
    if (newHost == me) {
      final hl = await t?.hostNew().timeout(const Duration(seconds: 20), onTimeout: () => null).catchError((Object _) => null);
      return _promote(hl ?? _NoLink(), hl == null);
    }
    // Someone else takes over: join them, or play on alone if they never appear.
    final name = l.seats[newHost].name ?? 'Another player';
    var expired = false;
    final deadline = Timer(rejoinGrace ~/ 2, () => expired = true);
    m.waitingNotice.value = 'The host is gone. Waiting for $name to take over...';
    while (!_left && !expired) {
      try {
        final nl = await t!.joinNew(l, newHost).timeout(const Duration(seconds: 10));
        if (nl != null) {
          if (_left) {
            unawaited(nl.close());
            return;
          }
          _recovering = false;
          m.waitingNotice.value = null;
          m.showToast("$name is hosting the match now. An AI plays the old host's seat.");
          deadline.cancel();
          _attach(nl);
          nl.send({
            't': 'have',
            'a': [
              for (final (seq, a) in m.ls.since(math.max(0, m.ls.answered - 40))) [seq, a.seat, a.picks],
            ],
          });
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(rejoinRetry);
    }
    deadline.cancel();
    if (!_left) await _promote(_NoLink(), true);
  }

  Future<void> _promote(HostLink hostLink, bool solo) async {
    final m = match!;
    _recovering = false;
    m.waitingNotice.value = null;
    _repair.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    final session = promoted = HostSession._adopt(
      hostLink,
      data,
      adoptedLobby: lobby!,
      seat: mySeat!,
      running: m,
      dataVersion: _dataVersion,
      chat: chat,
    );
    m.showToast(solo ? 'The host left. You play on against the AI.' : 'The host left. You are hosting the match now; an AI plays their seat.');
    // The old connection is of no use any more.
    try {
      await link.close();
    } catch (_) {}
    if (_left) await session.leave();
  }

  @override
  void pickHero(String id) => link.send({'t': 'hero', 'id': id});
  @override
  void setReady(bool on) => link.send({'t': 'ready', 'on': on});
  @override
  void moveSeat(int i) => link.send({'t': 'seat', 'i': i});
  @override
  void setMap(String id) => link.send({'t': 'map', 'id': id});
  @override
  void randomMap() {
    final l = lobby;
    if (l == null) return;
    final ms = mapsFor(data, l.mode, l.players);
    if (ms.isEmpty) return;
    final others = ms.where((m) => m.id != l.mapId).toList();
    final pick = (others.isEmpty ? ms : others)[math.Random().nextInt(others.isEmpty ? ms.length : others.length)];
    setMap(pick.id);
  }

  bool _left = false;

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    _recoveryTicker?.cancel();
    _repair.cancel();
    final p = promoted;
    if (p != null) return p.leave();
    match?.ls.fail(StateError('Left the match'));
    await _sub?.cancel();
    await link.close();
  }

  @override
  void dispose() {
    _repair.cancel();
    _recoveryTicker?.cancel();
    super.dispose();
  }
}
