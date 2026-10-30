/// Match invites, in one place: inviting someone from the Active Players list (creates an online
/// lobby and sends the invite), accepting one (joins that lobby), and the single listener that
/// shows incoming invites on top of whatever screen is open.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../net/online.dart';
import '../net/online_presence.dart';
import '../net/transports.dart';
import '../net/session.dart';
import 'dialogs/invite_banner_dialog.dart';
import 'screens/lobby_screen.dart';
import 'screens/menu_screen.dart' show gameSnack;
import 'services.dart';

/// The app's navigator, so an invite can be shown (and a lobby opened) from outside any screen.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

String newReconnectToken() {
  final r = math.Random.secure();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
}

String _say(Object e) => e is StateError ? e.message : (e is TimeoutException ? 'Timed out. Check the connection and try again.' : '$e');

void _tell(ScaffoldMessengerState? m, String text) {
  m
    ?..hideCurrentSnackBar()
    ..showSnackBar(gameSnack(text));
}

bool _inviting = false;

/// Opens an online lobby for you and [user], and sends them the invite. Never throws: a problem
/// is told to the player instead.
Future<void> inviteToMatch(BuildContext context, OnlineUser user) async {
  // Everything that needs the context is taken before the first await.
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final s = context.services;
  if (_inviting) return;
  if (!isOnlineConfigured) {
    _tell(messenger, 'Online play isn\'t set up on this build.');
    return;
  }
  final presence = OnlinePresenceService.instance;
  if (!presence.canInvite) {
    _tell(messenger, 'Can\'t reach the online service yet. Try again in a moment.');
    return;
  }
  _inviting = true;
  try {
    final lobbyName = '${s.settings.username} vs ${user.name}';
    final token = newReconnectToken();
    final link = await OnlineHost.create(
      name: lobbyName,
      hostName: s.settings.username,
      info: (mode: 'duel', players: 2, open: 1, playing: false, status: 'matching'),
    );
    final sent = await presence.sendInvite(targetUserId: user.id, lobbyId: link.id, lobbyName: lobbyName);
    unawaited(presence.updateStatus(status: 'matching', lobbyId: link.id));
    final session = HostSession(
      link,
      s.data,
      name: s.settings.username,
      dataVersion: s.dataVersion,
      playerId: s.settings.playerId,
      reconnectToken: token,
    );
    _tell(messenger, sent ? 'Invite sent to ${user.name}. They have a minute to accept.' : 'Couldn\'t deliver the invite. The lobby is open if ${user.name} joins it from the list.');
    await nav.push(MaterialPageRoute<void>(builder: (_) => LobbyScreen(session: session)));
  } catch (e) {
    _tell(messenger, _say(e));
  } finally {
    _inviting = false;
  }
}

/// Joins the lobby an invite points to.
Future<void> acceptInvite(BuildContext context, MatchInvite inv) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final s = context.services;
  try {
    final token = newReconnectToken();
    final link = await OnlineClient.join(inv.lobbyId);
    s.settings.saveReconnect(lobbyId: inv.lobbyId, token: token, topic: link.topic);
    final session = ClientSession(
      link,
      s.data,
      name: s.settings.username,
      dataVersion: s.dataVersion,
      address: inv.lobbyName,
      playerId: s.settings.playerId,
      reconnectToken: token,
      transport: link.topic == null ? null : OnlineTransport(link.topic!, hostName: s.settings.username),
    );
    await nav.push(MaterialPageRoute<void>(builder: (_) => LobbyScreen(session: session)));
  } catch (e) {
    _tell(messenger, _say(e));
  }
}

/// Shows incoming invites over any screen. One of these sits above the navigator, so an invite
/// is never shown twice or lost when screens change. Invites are ignored mid-match.
class InviteListener extends StatefulWidget {
  const InviteListener({super.key, required this.child});
  final Widget child;

  @override
  State<InviteListener> createState() => _InviteListenerState();
}

class _InviteListenerState extends State<InviteListener> {
  StreamSubscription<MatchInvite>? _sub;
  StreamSubscription<({String name, String reason})>? _declineSub;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    final p = OnlinePresenceService.instance;
    _sub = p.invites.listen(_onInvite);
    _declineSub = p.declines.listen(_onDeclined);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _declineSub?.cancel();
    super.dispose();
  }

  void _onInvite(MatchInvite inv) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted || inv.isExpired) return;
    final presence = OnlinePresenceService.instance;
    // Mid-match (or already looking at another invite) there is nothing to show: the sender is told
    // straight away instead of waiting on an invite nobody will see.
    if (presence.myStatus == 'inGame' || _showing) {
      unawaited(presence.declineInvite(inv, reason: 'busy'));
      return;
    }
    _showing = true;
    InviteBannerDialog.show(
      ctx,
      invite: inv,
      onAccept: () {
        _showing = false;
        // Back to the first screen first: leaving a lobby you are in closes it, so it isn't left
        // open (and listed) while you join the other one.
        appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
        final c = appNavigatorKey.currentContext;
        if (c != null && c.mounted) unawaited(acceptInvite(c, inv));
      },
      onDecline: () {
        _showing = false;
        unawaited(presence.declineInvite(inv));
      },
    );
  }

  void _onDeclined(({String name, String reason}) d) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final text = switch (d.reason) {
      'busy' => '${d.name} is busy right now.',
      _ => '${d.name} declined your invite.',
    };
    _tell(ScaffoldMessenger.maybeOf(ctx), text);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
