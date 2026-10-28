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

/// Bumped whenever the messages or the rules change in a way older copies can't follow.
const netProtocol = 1;

enum SeatKind { open, human, ai }

class LobbySeat {
  LobbySeat(this.kind, {this.name, this.hero, this.ready = false, this.peer});
  SeatKind kind;
  String? name;
  String? hero;
  bool ready;

  /// Host only: the connection this seat belongs to (null for the host and AI).
  String? peer;

  Msg toJson() => {'kind': kind.name, 'name': name, 'hero': hero, 'ready': ready};
  static LobbySeat fromJson(Msg m) => LobbySeat(
    SeatKind.values.byName(m['kind'] as String),
    name: m['name'] as String?,
    hero: m['hero'] as String?,
    ready: m['ready'] == true,
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
    required this.chat,
    required this._say,
  }) : names = ValueNotifier(names);

  final MatchConfig config;
  final int localSeat;
  final int seed;
  final bool isHost;
  final Set<int> aiSeats;

  /// Name per seat ("AI Hard" for AI seats and for players the AI took over).
  final ValueNotifier<List<String>> names;
  final Lockstep ls = Lockstep();
  final Map<int, RemoteSeatAgent> _remotes = {};

  /// Set when the connection is lost mid-match (the reason to show).
  final ValueNotifier<String?> lost = ValueNotifier(null);

  /// The lobby's chat, carried on into the match.
  final ChatLog chat;
  final void Function(String text) _say;

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
    final n = List.of(names.value);
    n[seat] = '${n[seat]} (AI)';
    names.value = n;
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
  LobbySession(this.data);
  final GameData data;

  Lobby? lobby;
  int? mySeat;
  bool get isHost;

  /// Why the session ended (shown, then back to the menu).
  String? closed;

  /// Table talk, in the lobby and through the match.
  final ChatLog chat = ChatLog();

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
      chat: chat,
      say: say,
    );
  }

  static String _label(AiLevel l) => l.name[0].toUpperCase() + l.name.substring(1);
}

// ============================================================================================ host

class HostSession extends LobbySession {
  HostSession(this.link, super.data, {required String name, required this.dataVersion}) {
    final duel = data.mapsFor('1v1');
    lobby = Lobby(
      mode: GameMode.duel,
      players: 2,
      mapId: duel.first.id,
      ai: AiLevel.medium,
      seats: [LobbySeat(SeatKind.human, name: name, ready: true), LobbySeat(SeatKind.open)],
    );
    mySeat = 0;
    _sub = link.events.listen(_onEvent);
  }

  final HostLink link;
  final String dataVersion;
  late final StreamSubscription<LinkEvent> _sub;

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
  );

  void _onEvent(LinkEvent e) {
    switch (e) {
      case PeerJoined():
        break;
      case PeerLeft(:final peer):
        final seat = _seatOf(peer);
        if (seat == null) return;
        if (match != null) {
          // Mid-match: the AI plays on for them.
          _l.seats[seat].peer = null;
          match!._takeOver(seat, AiLevel.hard);
          link.broadcast({'t': 'seatAi', 'seat': seat});
          return;
        }
        _l.seats[seat] = LobbySeat(SeatKind.open);
        _sync();
      case PeerMessage(:final peer, :final msg):
        _onMessage(peer, msg);
    }
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
        if (match != null) return _reject(peer, 'That match has already started.');
        final open = _l.seats.indexWhere((s) => s.kind == SeatKind.open);
        if (open < 0) return _reject(peer, 'The lobby is full.');
        final name = '${m['name'] ?? ''}'.trim();
        _l.seats[open] = LobbySeat(SeatKind.human, name: name.isEmpty ? 'Player ${open + 1}' : name, peer: peer);
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
    m.ls.publish = (seq, a) => link.broadcast({'t': 'ans', 'seq': seq, 'seat': a.seat, 'picks': a.picks});
    m._invalid = (seat) {
      final p = _l.seats[seat].peer;
      if (p != null) _reject(p, 'Your game sent an illegal move.');
      _l.seats[seat].peer = null;
      m._takeOver(seat, AiLevel.hard);
      link.broadcast({'t': 'seatAi', 'seat': seat});
    };
    m._leave = () => unawaited(leave());
    m._report = (winner, players) => link.finished(winner: winner, players: players);
    link.broadcast({'t': 'start', 'lobby': _l.toJson(), 'heroes': heroes, 'seed': seed});
    link.lobbyChanged(info);
    _changed();
  }

  bool _left = false;

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    match?.ls.fail(StateError('Left the match'));
    await _sub.cancel();
    await link.close();
  }
}

// ========================================================================================== player

class ClientSession extends LobbySession {
  ClientSession(this.link, super.data, {required String name, required String dataVersion, required this.address}) {
    _sub = link.messages.listen(_onMessage);
    link.send({'t': 'hello', 'v': netProtocol, 'data': dataVersion, 'name': name});
    unawaited(link.done.then(_onDone));
    _repair = Timer.periodic(const Duration(seconds: 2), (_) => _checkLost());
  }

  final ClientLink link;
  late final StreamSubscription<Msg> _sub;
  late final Timer _repair;

  /// Answers that came before the start message (messages can arrive out of order online).
  final List<Msg> _early = [];

  /// My own answers the host hasn't echoed back yet, by decision number.
  final Map<int, List<int>> _unacked = {};
  int? _lastWaiting;

  /// Online messages can get lost: ask again for answers we've waited on for a while, and send
  /// again our own answers the host hasn't confirmed.
  void _checkLost() {
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
      case 'start':
        final l = lobby = Lobby.fromJson((m['lobby'] as Map).cast<String, Object?>());
        final heroes = (m['heroes'] as List).cast<String>();
        final mm = match = _makeMatch(l, heroes, m['seed'] as int, mySeat!);
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
          final n = List.of(match!.names.value);
          n[seat] = '${n[seat]} (AI)';
          match!.names.value = n;
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

  void _onDone(String? reason) {
    final why = closed ?? reason ?? (match != null ? 'The host left the match.' : 'Lost the connection to the host.');
    closed = why;
    match?.ls.fail(StateError(why));
    match?.lost.value = why;
    _changed();
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
    _repair.cancel();
    match?.ls.fail(StateError('Left the match'));
    await _sub.cancel();
    await link.close();
  }
}
