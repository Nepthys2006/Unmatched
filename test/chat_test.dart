// The multiplayer chat: cleaning what people type, the message log (order, duplicates, unread,
// lost messages), and whole lobbies (over an in-memory network, so it never competes with the
// socket tests for the LAN port): messages relayed by the host to everyone
// with their seat and name, history for players who join later, a lost message fetched again,
// the flood limit, the chat carried on into the match, and every message handed to the server
// store (online) while the lobby lives.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/chat.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/match/match_config.dart';

import 'net_test.dart' show until;
import 'support.dart';

ChatMessage msg(int id, {int seat = 1, String text = 'hi'}) => ChatMessage(id: id, seat: seat, name: 'P$seat', text: text, at: DateTime(2026));

/// An in-memory network: the host's side. Every message goes through JSON and arrives a little
/// later, as on a real connection. It keeps chat messages like the online host does.
class MemoryHost implements HostLink, ChatKeeper {
  final kept = <Msg>[];
  final _events = StreamController<LinkEvent>.broadcast();
  final Map<String, MemoryClient> _peers = {};
  var _n = 0;

  /// A new player connecting; [lose] says which chat messages get lost on the way to them.
  MemoryClient connect({bool Function(Msg m)? lose}) {
    final c = MemoryClient(this, 'peer${++_n}', lose ?? (_) => false);
    _peers[c.id] = c;
    _deliver(() => _events.add(PeerJoined(c.id)));
    return c;
  }

  static Msg wire(Msg m) => (jsonDecode(jsonEncode(m)) as Map).cast<String, Object?>();
  static void _deliver(void Function() f) => Timer(const Duration(milliseconds: 2), f);

  void _fromPeer(String id, Msg m) => _deliver(() => _events.add(PeerMessage(id, wire(m))));

  @override
  Future<void> keepChat(Msg m) async => kept.add(m);
  @override
  Stream<LinkEvent> get events => _events.stream;
  @override
  void send(String peer, Msg m) => _peers[peer]?._receive(wire(m));
  @override
  void broadcast(Msg m) {
    for (final c in _peers.values) {
      c._receive(wire(m));
    }
  }

  @override
  void drop(String peer) => _peers.remove(peer)?._end('dropped');
  @override
  String get address => 'memory';
  @override
  void lobbyChanged(LobbyInfo info) {}
  @override
  Future<void> finished({String? winner, required List<String> players}) async {}
  @override
  Future<void> close() async {
    for (final c in _peers.values.toList()) {
      c._end('The host left.');
    }
    _peers.clear();
  }
}

/// A player's side of the in-memory network.
class MemoryClient implements ClientLink {
  MemoryClient(this.host, this.id, this.lose);
  final MemoryHost host;
  final String id;
  final bool Function(Msg m) lose;
  final lost = <Msg>[];
  final _messages = StreamController<Msg>.broadcast();
  final _done = Completer<String?>();

  void _receive(Msg m) {
    if (m['t'] == 'chat' && lose(m) && !lost.any((x) => (x['m'] as Map)['id'] == (m['m'] as Map)['id'])) {
      lost.add(m);
      return;
    }
    MemoryHost._deliver(() {
      if (!_messages.isClosed) _messages.add(m);
    });
  }

  void _end(String why) {
    if (!_done.isCompleted) _done.complete(why);
  }

  @override
  Stream<Msg> get messages => _messages.stream;
  @override
  Future<String?> get done => _done.future;
  @override
  void send(Msg m) {
    if (!_done.isCompleted) host._fromPeer(id, m);
  }

  @override
  Future<void> close() async {
    _end('');
    host._peers.remove(id);
    MemoryHost._deliver(() => host._events.add(PeerLeft(id)));
  }
}

List<String> texts(LobbySession s) => [for (final m in s.chat.messages) m.text];

void main() {
  group('cleanChat', () {
    test('one trimmed line, control and direction characters gone', () {
      expect(cleanChat('  hello \n\n there\t!  '), 'hello there !');
      expect(cleanChat('a\u0000b\u202Ec\u2066d'), 'a b c d');
      expect(cleanChat(' \n\t '), '');
    });
    test('at most $chatMaxLength characters, without cutting an emoji in half', () {
      expect(cleanChat('x' * 500).length, chatMaxLength);
      final s = cleanChat('${'x' * (chatMaxLength - 1)}😀 more');
      expect(s.length, chatMaxLength - 1);
      expect(s.codeUnits.last, 'x'.codeUnitAt(0));
    });
    test('messages from the network are cleaned and checked too', () {
      expect(ChatMessage.fromJson({'id': 1, 'seat': 0, 'name': 'A', 'text': '  a\nb '})!.text, 'a b');
      expect(ChatMessage.fromJson({'id': 1, 'seat': 0, 'name': 'A', 'text': '   '}), isNull);
      expect(ChatMessage.fromJson({'id': '1', 'seat': 0, 'name': 'A', 'text': 'x'}), isNull);
      expect(ChatMessage.fromJson('nope'), isNull);
      expect(ChatMessage.fromJson({'id': 1, 'seat': 0, 'name': 'N' * 90, 'text': 'x'})!.name.length, 40);
    });
  });

  group('ChatLog', () {
    test('keeps messages in order, once each; counts unread while closed, not your own', () {
      final log = ChatLog();
      log.addAll([msg(2), msg(1), msg(2)], mine: 0);
      log.add(msg(3, seat: 0), mine: 0);
      expect([for (final m in log.messages) m.id], [1, 2, 3]);
      expect(log.unread, 2);
      expect(log.latestIncoming!.id, 2);
      log.open = true;
      expect(log.unread, 0);
      log.add(msg(4), mine: 0);
      expect(log.unread, 0, reason: 'seen as it arrives');
      log.open = false;
      log.add(msg(5), mine: 0);
      expect(log.unread, 1);
    });
    test('finds the first message lost on the way', () {
      final log = ChatLog();
      expect(log.gap, isNull);
      log.addAll([msg(1), msg(2), msg(4), msg(6)]);
      expect(log.gap, 3);
      log.add(msg(3));
      expect(log.gap, 5);
      log.add(msg(5));
      expect(log.gap, isNull);
      // A newcomer's history starts where the host's does.
      final late = ChatLog()..addAll([msg(41), msg(42)], from: 41);
      expect(late.gap, isNull);
      expect((ChatLog()..addAll([msg(2)])).gap, 1, reason: 'message 1 never came');
    });
    test('keeps the last $chatKeep', () {
      final log = ChatLog()..addAll([for (var i = 1; i <= chatKeep + 30; i++) msg(i)]);
      expect(log.messages.length, chatKeep);
      expect(log.messages.first.id, 31);
      expect(log.gap, isNull);
    });
  });

  group('in a lobby', () {
    late MemoryHost link;
    late HostSession host;
    final clients = <ClientSession>[];
    final links = <MemoryClient>[];
    final data = loadData();

    Future<ClientSession> join(String name, {bool Function(Msg m)? lose}) async {
      final l = link.connect(lose: lose);
      final c = ClientSession(l, data, name: name, dataVersion: 'test', address: 'memory');
      links.add(l);
      clients.add(c);
      await until(() => c.mySeat != null && c.lobby != null);
      return c;
    }

    setUp(() async {
      clients.clear();
      links.clear();
      link = MemoryHost();
      host = HostSession(link, data, name: 'Host', dataVersion: 'test');
      expect(host.setMode(GameMode.ffa, 4), isTrue);
    });
    tearDown(() async {
      for (final c in clients) {
        await c.leave();
      }
      await host.leave();
    });

    test('everyone sees every message, numbered by the host, with who said it', () async {
      final a = await join('Ann');
      final b = await join('Bob');
      a.say('  hello\neveryone ');
      await until(() => [host, a, b].every((s) => s.chat.messages.length == 1));
      host.say('welcome');
      await until(() => [host, a, b].every((s) => s.chat.messages.length == 2));
      for (final s in [host, a, b]) {
        expect(texts(s), ['hello everyone', 'welcome']);
        expect([for (final m in s.chat.messages) m.id], [1, 2]);
        expect([for (final m in s.chat.messages) (m.seat, m.name)], [(a.mySeat, 'Ann'), (0, 'Host')]);
      }
      expect(a.chat.unread, 1, reason: "Ann's own message isn't unread");
      expect(host.chat.unread, 1);
      // Empty messages go nowhere.
      b.say('   ');
      host.say('');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(host.chat.messages.length, 2);
      // The host's store got each message once, as it was numbered.
      expect([for (final m in link.kept) (m['id'], m['text'])], [(1, 'hello everyone'), (2, 'welcome')]);
    });

    test('a player who joins later gets the chat so far', () async {
      final a = await join('Ann');
      a.say('first');
      await until(() => host.chat.messages.length == 1);
      host.say('second');
      await until(() => host.chat.messages.length == 2);
      final b = await join('Bob');
      await until(() => b.chat.messages.length == 2);
      expect(texts(b), ['first', 'second']);
      expect(b.chat.gap, isNull);
    });

    test('a message lost on the way is fetched again', () async {
      final a = await join('Ann', lose: (m) => (m['m'] as Map)['id'] == 2);
      final b = await join('Bob');
      b.say('one');
      b.say('two');
      b.say('three');
      await until(() => b.chat.messages.length == 3 && a.chat.messages.length >= 2);
      expect(links.first.lost, hasLength(1));
      // Ann noticed the hole and asked the host for it again (every 2 s).
      await until(() => a.chat.messages.length == 3, timeout: const Duration(seconds: 6));
      expect(texts(a), ['one', 'two', 'three']);
    });

    test('nobody can flood the chat: 5 messages in 5 seconds each', () async {
      final a = await join('Ann');
      for (var i = 0; i < 8; i++) {
        a.say('spam $i');
      }
      for (var i = 0; i < 3; i++) {
        host.say('host $i');
      }
      await until(() => a.chat.messages.length == 8);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // The host's numbering is the order everyone sees.
      expect(texts(a), texts(host));
      expect(texts(host).where((t) => t.startsWith('spam')), ['spam 0', 'spam 1', 'spam 2', 'spam 3', 'spam 4']);
      expect(texts(host).where((t) => t.startsWith('host')), ['host 0', 'host 1', 'host 2']);
    });

    test('the chat carries on into the match', () async {
      final a = await join('Ann');
      final b = await join('Bob');
      host.toggleSeat(3);
      a.say('glhf');
      await until(() => host.chat.messages.length == 1);
      final heroes = data.heroes.keys.toList();
      host.pickHero(heroes[0]);
      for (final (i, c) in [a, b].indexed) {
        c.pickHero(heroes[i + 1]);
        await until(() => host.lobby!.seats[c.mySeat!].hero != null);
        c.setReady(true);
      }
      await until(() => host.notReady == null);
      host.start();
      await until(() => a.match != null && b.match != null);
      expect(identical(a.match!.chat, a.chat), isTrue);
      b.match!.say('nice move');
      await until(() => host.chat.messages.length == 2);
      host.match!.say('thanks');
      await until(() => [host, a, b].every((s) => s.chat.messages.length == 3));
      for (final s in [host, a, b]) {
        expect(texts(s), ['glhf', 'nice move', 'thanks']);
      }
      expect(link.kept, hasLength(3));
    });
  });
}
