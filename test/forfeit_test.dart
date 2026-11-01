// Leaving, going AFK or dropping out of a 1 v 1 against another person is a LOSS that counts.
//
// * the record says who left and why (forfeit_me / forfeit_opponent, leave / afk / disconnect)
// * the host tells every device; only a 1 v 1 between two people ends this way
// * a player who doesn't come back within the grace period lost; in a team match an AI takes over
// * a decision has a clock (90 s); the AI answers when it runs out; three misses in a row = AFK
// * the host's own watchdog catches a device that neither answers nor leaves
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/match_record.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/net/uuid.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';

import 'net_test.dart' show Copy;
import 'support.dart';
import 'widget_test.dart' show loadFonts, makeServices, phone, smallPhone, desktop;

class TestHostLink implements HostLink {
  final _events = StreamController<LinkEvent>.broadcast();
  final List<Msg> broadcasted = [];
  @override
  String get address => '127.0.0.1:47400';
  @override
  Stream<LinkEvent> get events => _events.stream;
  @override
  void send(String peer, Msg m) {}
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

  List<Msg> forfeits() => [
    for (final m in broadcasted)
      if (m['t'] == 'forfeit') m,
  ];
}

class TestClientLink implements ClientLink {
  final _messages = StreamController<Msg>.broadcast();
  final _done = Completer<String?>();
  final List<Msg> sent = [];
  @override
  Stream<Msg> get messages => _messages.stream;
  @override
  Future<String?> get done => _done.future;
  @override
  void send(Msg m) => sent.add(m);
  void emitMessage(Msg m) => _messages.add(m);
  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete(null);
    await _messages.close();
  }
}

void main() {
  setUpAll(loadFonts);
  final data = loadData();

  /// A host with a guest in seat 1 and the match running. [humans] seats start as people.
  (TestHostLink, HostSession) startHost({int humans = 2, GameMode mode = GameMode.duel}) {
    final link = TestHostLink();
    final host = HostSession(link, data, name: 'Host', dataVersion: 'test');
    if (mode != GameMode.duel) {
      expect(host.setMode(mode, humans), isTrue);
      host.setMap(mode == GameMode.ffa ? 'cross' : 'blossom');
    }
    host.lobby!.seats[0].hero = 'alice';
    for (var i = 1; i < humans; i++) {
      host.lobby!.seats[i] = LobbySeat(SeatKind.human, name: 'Guest$i', hero: ['medusa', 'achilles', 'dracula'][i - 1], ready: true, peer: 'peer-$i', reconnectToken: 'secret$i');
    }
    host.start();
    return (link, host);
  }

  group('what the record says', () {
    MatchRecord f({required EndedBy by, String? reason, bool won = false, int humans = 1}) => MatchRecord.finished(
      matchId: uuidFromText('f'),
      won: won,
      myHero: 'alice',
      opponentHero: 'medusa',
      opponentName: 'Bob',
      players: 2,
      humanOpponents: humans,
      online: false,
      mapId: 'blossom',
      playedAt: DateTime.now(),
      durationSeconds: 400,
      myUserId: 'u1',
      opponentUserId: 'u2',
      endedBy: by,
      forfeitReason: reason,
      turns: 9,
    );

    test('a forfeit is saved with who left, why and how long it lasted, and goes to the server that way', () {
      final mine = f(by: EndedBy.forfeitMe, reason: 'afk');
      expect(mine.endLabel, 'You were away too long');
      final sub = mine.toSubmission();
      expect(sub['ended_by'], 'forfeit_me');
      expect(sub['forfeit_reason'], 'afk');
      expect(sub['turns'], 9);
      expect(sub['winner'], 'opponent');
      final back = MatchRecord.fromJson(mine.toJson())!;
      expect(back.endedBy, EndedBy.forfeitMe);
      expect(back.forfeitReason, 'afk');
      expect(back.turns, 9);
      final theirs = f(by: EndedBy.forfeitOpponent, reason: 'leave', won: true);
      expect(theirs.endLabel, 'Opponent left the match');
      expect(theirs.toSubmission()['winner'], 'me');
      expect(f(by: EndedBy.forfeitMe, reason: 'disconnect').endLabel, 'You lost connection');
      expect(f(by: EndedBy.forfeitOpponent, reason: 'afk', won: true).endLabel, 'Opponent was away too long');
      expect(f(by: EndedBy.normal).endLabel, isNull);
    });

    test('a match against the AI is never a forfeit; older saves read as normal', () {
      final ai = f(by: EndedBy.forfeitMe, reason: 'leave', humans: 0);
      expect(ai.endedBy, EndedBy.normal);
      expect(ai.forfeitReason, isNull);
      final old = MatchRecord.fromJson({'match_id': 'a', 'played_at': '2026-10-30T12:00:00Z'})!;
      expect(old.endedBy, EndedBy.normal);
      expect(old.turns, isNull);
    });
  });

  group('the host decides and tells everyone', () {
    testWidgets('a player leaves a 1 v 1: they lost, and every device is told', (t) async {
      final (link, host) = startHost();
      addTearDown(host.dispose);
      final m = host.match!;
      expect(m.duelWithPerson, isTrue);
      link.emit(const PeerMessage('peer-1', {'t': 'forfeit', 'reason': 'leave'}));
      await t.pump();
      expect(m.forfeit.value, (seat: 1, reason: 'leave'));
      expect(link.forfeits(), [
        {'t': 'forfeit', 'seat': 1, 'reason': 'leave'},
      ]);
      // A second forfeit (or the same player again) changes nothing.
      link.emit(const PeerMessage('peer-1', {'t': 'forfeit', 'reason': 'afk'}));
      await t.pump();
      expect(m.forfeit.value, (seat: 1, reason: 'leave'));
      expect(link.forfeits(), hasLength(1));
    });

    testWidgets('an unknown reason is taken as leaving; a stranger\'s message does nothing', (t) async {
      final (link, host) = startHost();
      addTearDown(host.dispose);
      link.emit(const PeerMessage('stranger', {'t': 'forfeit', 'reason': 'leave'}));
      await t.pump();
      expect(host.match!.forfeit.value, isNull, reason: 'not a seat at the table');
      link.emit(const PeerMessage('peer-1', {'t': 'forfeit', 'reason': 'rm -rf'}));
      await t.pump();
      expect(host.match!.forfeit.value, (seat: 1, reason: 'leave'));
    });

    testWidgets('the host leaving or going AFK forfeits too', (t) async {
      final (link, host) = startHost();
      addTearDown(host.dispose);
      host.forfeitSelf('afk');
      expect(host.match!.forfeit.value, (seat: 0, reason: 'afk'));
      expect(link.forfeits().single['seat'], 0);
    });

    testWidgets('team and free-for-all matches never end this way: nobody forfeits a match for the others', (t) async {
      final (link, host) = startHost(humans: 3, mode: GameMode.ffa);
      addTearDown(host.dispose);
      expect(host.match!.duelWithPerson, isFalse);
      link.emit(const PeerMessage('peer-1', {'t': 'forfeit', 'reason': 'leave'}));
      await t.pump();
      expect(host.match!.forfeit.value, isNull);
      expect(link.forfeits(), isEmpty);
    });

    testWidgets('a 1 v 1 against the AI is not "a duel with a person"', (t) async {
      final link = TestHostLink();
      final host = HostSession(link, data, name: 'Host', dataVersion: 'test');
      addTearDown(host.dispose);
      host.toggleSeat(1);
      host.pickHero('alice');
      host.start();
      expect(host.match!.duelWithPerson, isFalse);
    });

    testWidgets('a guest\'s device learns of the forfeit from the host', (t) async {
      final link = TestClientLink();
      final s = ClientSession(link, data, name: 'Guest', dataVersion: 'test', address: 'x');
      addTearDown(s.dispose);
      final lobby = Lobby(
        mode: GameMode.duel,
        players: 2,
        mapId: 'blossom',
        ai: AiLevel.medium,
        seats: [
          LobbySeat(SeatKind.human, name: 'Host', hero: 'alice', ready: true, host: true),
          LobbySeat(SeatKind.human, name: 'Guest', hero: 'medusa', ready: true),
        ],
      );
      link.emitMessage({'t': 'welcome', 'seat': 1});
      link.emitMessage({'t': 'lobby', 'lobby': lobby.toJson()});
      link.emitMessage({'t': 'start', 'lobby': lobby.toJson(), 'heroes': ['alice', 'medusa'], 'seed': 5});
      await t.pump();
      final m = s.match!;
      expect(m.duelWithPerson, isTrue);
      link.emitMessage({'t': 'forfeit', 'seat': 7, 'reason': 'leave'});
      await t.pump();
      expect(m.forfeit.value, isNull, reason: 'a seat that is not in the match');
      link.emitMessage({'t': 'forfeit', 'seat': 0, 'reason': 'disconnect'});
      await t.pump();
      expect(m.forfeit.value, (seat: 0, reason: 'disconnect'));
      // And this player's own forfeit goes to the host.
      final link2 = TestClientLink();
      final s2 = ClientSession(link2, data, name: 'Guest', dataVersion: 'test', address: 'x');
      addTearDown(s2.dispose);
      link2.emitMessage({'t': 'welcome', 'seat': 1});
      link2.emitMessage({'t': 'lobby', 'lobby': lobby.toJson()});
      link2.emitMessage({'t': 'start', 'lobby': lobby.toJson(), 'heroes': ['alice', 'medusa'], 'seed': 5});
      await t.pump();
      s2.match!.announceForfeit('leave');
      expect(link2.sent.where((x) => x['t'] == 'forfeit').single['reason'], 'leave');
      unawaited(s.leave());
      unawaited(s2.leave());
      await t.pump();
    });
  });

  group('dropping out', () {
    testWidgets('a 1 v 1: not back within the grace period (2 minutes) = they lost', (t) async {
      final (link, host) = startHost();
      addTearDown(host.dispose);
      link.emit(const PeerLeft('peer-1'));
      await t.pump();
      expect(host.match!.forfeit.value, isNull, reason: 'they can still come back');
      await t.pump(const Duration(seconds: 119));
      expect(host.match!.forfeit.value, isNull);
      await t.pump(const Duration(seconds: 3));
      expect(host.match!.forfeit.value, (seat: 1, reason: 'disconnect'));
      expect(link.forfeits().single, {'t': 'forfeit', 'seat': 1, 'reason': 'disconnect'});
    });

    testWidgets('a 1 v 1: coming back in time means no forfeit', (t) async {
      final (link, host) = startHost();
      addTearDown(host.dispose);
      link.emit(const PeerLeft('peer-1'));
      await t.pump(const Duration(seconds: 60));
      link.emit(const PeerMessage('peer-2', {'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'Guest1', 'token': 'secret1'}));
      await t.pump();
      await t.pump(const Duration(minutes: 5));
      expect(host.match!.forfeit.value, isNull);
      expect(link.forfeits(), isEmpty);
    });

    testWidgets('a team match: the missing player is replaced by an AI, the match goes on', (t) async {
      final (link, host) = startHost(humans: 3, mode: GameMode.ffa);
      addTearDown(host.dispose);
      link.emit(const PeerLeft('peer-1'));
      await t.pump(const Duration(minutes: 3));
      expect(host.match!.forfeit.value, isNull);
      expect(host.lobby!.seats[1].kind, SeatKind.ai);
      expect(host.match!.names.value[1], endsWith('(AI)'));
    });
  });

  group('the host\'s AFK watchdog', () {
    setUp(() => afkLimit = const Duration(seconds: 5));
    tearDown(() => afkLimit = const Duration(minutes: 6));

    testWidgets('a player who never answers a 1 v 1 decision forfeits it', (t) async {
      final (link, host) = startHost();
      addTearDown(host.dispose);
      final copy = Copy(host.match!);
      unawaited(copy.game.run().then((_) {}, onError: (_) {}));
      await t.pump(const Duration(seconds: 3));
      expect(host.match!.forfeit.value, isNull);
      await t.pump(const Duration(seconds: 4));
      expect(host.match!.forfeit.value, (seat: 1, reason: 'afk'));
      expect(link.forfeits().single['reason'], 'afk');
    });

    testWidgets('in a team match the AI takes the silent seat instead', (t) async {
      final (link, host) = startHost(humans: 3, mode: GameMode.ffa);
      addTearDown(host.dispose);
      final copy = Copy(host.match!);
      unawaited(copy.game.run().then((_) {}, onError: (_) {}));
      await t.pump(const Duration(seconds: 12));
      expect(host.match!.forfeit.value, isNull);
      expect(host.match!.names.value.where((n) => n.endsWith('(AI)')), isNotEmpty);
      expect(link.broadcasted.where((m) => m['t'] == 'seatAi'), isNotEmpty);
      await t.pump(const Duration(seconds: 10)); // the notice on screen fades
    });
  });

  group('in the match screen', () {
    Future<(MatchScreenState, HostSession, TestHostLink, dynamic)> open(WidgetTester t, Size size, {Duration? limit, int humans = 2}) async {
      final (link, host) = startHost(humans: humans);
      addTearDown(host.dispose);
      final s = makeServices(speed: 0.05);
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = size * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final m = host.match!;
      await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: m.config, net: m, seed: 4, turnLimit: limit)));
      await t.pump();
      // The other player is covered by an AI so the match keeps moving, but the seat still counts as a person.
      host.takeOver(1);
      return (t.state<MatchScreenState>(find.byType(MatchScreen)), host, link, s);
    }

    Future<Prompt> nextPrompt(WidgetTester t, MatchScreenState st, {Prompt? after}) async {
      for (var i = 0; i < 4000; i++) {
        await t.pump(const Duration(milliseconds: 50));
        final p = st.debugPrompt;
        if (p != null && p != after) return p;
      }
      fail('no prompt came');
    }

    for (final size in [smallPhone, phone, desktop]) {
      testWidgets('three misses in a row: the AI answers each time, then you forfeit and lose (${size.width.round()}x${size.height.round()})', (t) async {
        final (st, host, link, s) = await open(t, size, limit: const Duration(seconds: 3));
        Prompt? last;
        for (var strike = 1; strike <= 2; strike++) {
          last = await nextPrompt(t, st, after: last);
          // The clock is on: the last 30 seconds show in the prompt bar (this one is only 3 seconds).
          await t.pump(const Duration(milliseconds: 1500));
          expect(find.textContaining('· '), findsWidgets);
          await t.pump(const Duration(seconds: 2));
          expect(st.debugLastPicks, isNotNull, reason: 'the AI answered for you');
          expect(find.textContaining('Time ran out'), findsWidgets);
          expect(find.byType(ResultView), findsNothing, reason: 'strike $strike of 3 is only a warning');
        }
        last = await nextPrompt(t, st, after: last);
        await t.pump(const Duration(seconds: 4));
        await t.pump(const Duration(milliseconds: 500));
        expect(find.byType(ResultView), findsOneWidget);
        expect(find.text('DEFEAT'), findsOneWidget);
        expect(find.textContaining('away too long'), findsWidgets);
        expect(host.match!.forfeit.value, (seat: 0, reason: 'afk'));
        expect(link.forfeits().single, {'t': 'forfeit', 'seat': 0, 'reason': 'afk'});
        // Saved like any other result, as a loss by forfeit.
        final saved = s.matches.all.single;
        expect(saved.won, isFalse);
        expect(saved.endedBy, EndedBy.forfeitMe);
        expect(saved.forfeitReason, 'afk');
        expect(saved.mode, MatchMode.lan);
        expect(saved.syncStatus, SyncStatus.pending);
        expect(saved.turns, isNotNull);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('answering yourself clears the misses: only three in a row forfeit', (t) async {
      final (st, host, link, s) = await open(t, phone, limit: const Duration(seconds: 3));
      var p = await nextPrompt(t, st);
      await t.pump(const Duration(seconds: 4)); // miss 1
      p = await nextPrompt(t, st, after: p);
      st.debugAnswer(const [0]); // an answer of your own: back to zero
      p = await nextPrompt(t, st, after: p);
      await t.pump(const Duration(seconds: 4)); // miss 1 again
      p = await nextPrompt(t, st, after: p);
      await t.pump(const Duration(seconds: 4)); // miss 2
      expect(find.byType(ResultView), findsNothing);
      expect(host.match!.forfeit.value, isNull);
      expect(s.matches.length, 0);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('the other player forfeits: you win, and it is saved as their forfeit', (t) async {
      final (st, host, link, s) = await open(t, phone);
      await nextPrompt(t, st);
      link.emit(const PeerMessage('peer-1', {'t': 'forfeit', 'reason': 'leave'}));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(ResultView), findsOneWidget);
      expect(find.text('VICTORY'), findsOneWidget);
      expect(find.textContaining('left the match'), findsWidgets);
      expect(st.debugPrompt, isNull, reason: 'the decision you were on is gone');
      final saved = s.matches.all.single;
      expect(saved.won, isTrue);
      expect(saved.endedBy, EndedBy.forfeitOpponent);
      expect(saved.forfeitReason, 'leave');
      expect(saved.toSubmission()['winner'], 'me');
      expect(find.text('SOMETHING WENT WRONG'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('leaving a 1 v 1 against a person asks first, then it is your loss and the other side is told', (t) async {
      final (st, host, link, s) = await open(t, phone);
      await nextPrompt(t, st);
      // The menu opens like the system back button does it.
      await t.binding.handlePopRoute();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('LEAVE MATCH'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Leaving counts as a loss'), findsOneWidget);
      // "Stay" (cancel) loses nothing.
      await t.tap(find.text('CANCEL'));
      await t.pump(const Duration(milliseconds: 400));
      expect(s.matches.length, 0);
      expect(link.forfeits(), isEmpty);
      // The menu opens like the system back button does it.
      await t.binding.handlePopRoute();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('LEAVE MATCH'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('LEAVE'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(link.forfeits().single, {'t': 'forfeit', 'seat': 0, 'reason': 'leave'});
      final saved = s.matches.all.single;
      expect(saved.won, isFalse);
      expect(saved.endedBy, EndedBy.forfeitMe);
      expect(saved.forfeitReason, 'leave');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('a match against the AI has no clock and leaving it loses nothing', (t) async {
      final s = makeServices(speed: 0.05);
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = phone * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final config = MatchConfig(mode: GameMode.duel, players: 2, map: s.data.maps['blossom']!, ai: AiLevel.medium, heroIds: const ['alice', 'medusa']);
      await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: config, seed: 3, turnLimit: const Duration(seconds: 2))));
      await t.pump();
      final st = t.state<MatchScreenState>(find.byType(MatchScreen));
      final p = await nextPrompt(t, st);
      await t.pump(const Duration(seconds: 6));
      expect(st.debugPrompt, p, reason: 'nobody answers for you against the AI, however long you take');
      // The menu opens like the system back button does it.
      await t.binding.handlePopRoute();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('LEAVE MATCH'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('counts as a loss'), findsNothing);
      await t.tap(find.text('LEAVE'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(s.matches.length, 0, reason: 'leaving a game against the computer is not a result');
    });
  });
}
