// The chat on the match screen of a multiplayer match (you host; the other seat is an AI, so no
// network is needed): the chat button sits in the menu row clear of the prompt bar, a message
// from someone else pops up for a moment and counts on the button, the panel opens with it,
// typing and the quick phrases send, and when the match ends the host reports it (online that
// deletes the lobby's chat from the server).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/net/link.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';

import 'match_hud_test.dart' show shot;
import 'widget_test.dart' show loadFonts, makeServices, phone, smallPhone;

class _Host implements HostLink, ChatKeeper {
  final kept = <Msg>[];
  final sent = <Msg>[];
  var finishedCalls = 0;
  final _events = StreamController<LinkEvent>.broadcast();

  @override
  Future<void> keepChat(Msg m) async => kept.add(m);
  @override
  String get address => 'Test lobby';
  @override
  Stream<LinkEvent> get events => _events.stream;
  @override
  void broadcast(Msg m) => sent.add(m);
  @override
  void send(String peer, Msg m) {}
  @override
  void drop(String peer) {}
  @override
  void lobbyChanged(LobbyInfo info) {}
  @override
  Future<void> finished({String? winner, required List<String> players}) async => finishedCalls++;
  @override
  Future<void> close() async {}
}

/// Pumps [ms] of frames, so animations run.
Future<void> frames(WidgetTester t, [int ms = 400]) async {
  for (var i = 0; i < ms ~/ 16; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(loadFonts);

  for (final size in [phone, smallPhone]) {
    testWidgets('chat in a multiplayer match (${size.width.round()} wide)', (t) async {
      final s = makeServices(speed: 0.05);
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = size * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final link = _Host();
      final host = HostSession(link, s.data, name: 'Host', dataVersion: 'test');
      // Bob joins, picks his hero and gets ready.
      Future<void> bob(Msg m) async {
        link._events.add(PeerMessage('bob', m));
        await t.pump();
      }

      link._events.add(const PeerJoined('bob'));
      await bob({'t': 'hello', 'v': netProtocol, 'data': 'test', 'name': 'Bob'});
      await bob({'t': 'hero', 'id': 'sherlock-holmes'});
      await bob({'t': 'ready', 'on': true});
      host.pickHero('medusa');
      expect(host.notReady, isNull);
      host.start();
      final m = host.match!;
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('shot'),
          child: UnmatchedApp(services: s, home: MatchScreen(config: m.config, net: m, seed: 3)),
        ),
      );
      await t.pump(const Duration(seconds: 2));

      // The chat button is in the menu row, clear of the prompt bar.
      final button = find.byTooltip('Chat');
      expect(button, findsOneWidget);
      final bar = t.getRect(find.byType(PromptBar));
      expect(t.getRect(button).intersect(bar).width <= 1, isTrue, reason: 'chat button ${t.getRect(button)} under the prompt bar $bar');
      expect(find.byKey(const ValueKey('chat-unread')), findsNothing);

      // A message from Bob: it pops up and counts on the button.
      await bob({'t': 'chat', 'text': 'good luck!'});
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('chat-toast')), findsOneWidget);
      await shot(t, 'chat-toast-${size.width.round()}');
      expect(find.text('1'), findsWidgets);
      expect(find.byKey(const ValueKey('chat-unread')), findsOneWidget);
      // ...and goes away by itself.
      await t.pump(const Duration(seconds: 6));
      expect(find.byKey(const ValueKey('chat-toast')), findsNothing);

      // Open the chat: the message is there, nothing is unread any more.
      await t.tap(button);
      await frames(t);
      expect(find.byKey(const ValueKey('chat-panel')), findsOneWidget);
      expect(find.textContaining('good luck!', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-unread')), findsNothing);

      expect((Offset.zero & size).contains(t.getRect(find.byKey(const ValueKey('chat-send'))).center), isTrue, reason: 'the panel is on screen');
      // Type and send; then a quick phrase.
      await t.enterText(find.byKey(const ValueKey('chat-input')), '  thanks,\n you too ');
      await t.tap(find.byKey(const ValueKey('chat-send')));
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.text('Nice move'));
      await t.pump(const Duration(milliseconds: 200));
      expect([for (final c in host.chat.messages) c.text], ['good luck!', 'thanks, you too', 'Nice move']);
      expect(find.textContaining('thanks, you too', findRichText: true), findsOneWidget);
      await shot(t, 'chat-open-${size.width.round()}');
      expect(link.kept.map((k) => k['text']), ['good luck!', 'thanks, you too', 'Nice move'], reason: 'the host keeps what it numbers');
      expect(link.sent.where((x) => x['t'] == 'chat'), hasLength(3), reason: 'and passes it to everyone');
      expect((t.widget(find.byKey(const ValueKey('chat-input'))) as TextField).controller!.text, isEmpty);

      // Close it; a new message while it's closed counts again.
      await t.tap(find.byTooltip('Close chat'));
      await frames(t);
      expect(find.byKey(const ValueKey('chat-panel')), findsNothing);
      await bob({'t': 'chat', 'text': 'oof'});
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('chat-unread')), findsOneWidget);
      expect([for (final c in host.chat.messages) (c.id, c.seat, c.name)], [(1, 1, 'Bob'), (2, 0, 'Host'), (3, 0, 'Host'), (4, 1, 'Bob')]);
      // Bob leaves; the AI plays on for him.
      link._events.add(const PeerLeft('bob'));
      await t.pump();

      // Let the AI play your side to the end: the host reports the result (online, that deletes
      // the lobby and its chat).
      final state = t.state(find.byType(MatchScreen)) as dynamic;
      final ai = AiAgent(level: AiLevel.medium, seed: 1);
      for (var i = 0; i < 40000 && find.byType(ResultView).evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 20));
        final p = state.debugPrompt as Prompt?;
        if (p != null) state.debugAnswer(await ai.decide(state.game as Game, p));
        expect(state.debugError, isNull);
      }
      expect(find.byType(ResultView), findsOneWidget);
      await t.pump(const Duration(milliseconds: 100));
      expect(link.finishedCalls, 1);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
