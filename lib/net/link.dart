/// The connection under a multiplayer session. LAN uses a WebSocket server on the host's phone;
/// online play uses a Supabase Realtime channel. Sessions only see JSON maps.
library;

import 'dart:async';

typedef Msg = Map<String, Object?>;

sealed class LinkEvent {
  const LinkEvent(this.peer);
  final String peer;
}

class PeerJoined extends LinkEvent {
  const PeerJoined(super.peer);
}

class PeerLeft extends LinkEvent {
  const PeerLeft(super.peer);
}

class PeerMessage extends LinkEvent {
  const PeerMessage(super.peer, this.msg);
  final Msg msg;
}

/// What a lobby list shows about a lobby (online) or a beacon announces (LAN).
typedef LobbyInfo = ({String mode, int players, int open, bool playing});

/// The host's side: many peers.
abstract class HostLink {
  Stream<LinkEvent> get events;
  void send(String peer, Msg m);
  void broadcast(Msg m);

  /// Disconnects one peer (lobby full, wrong version, cheating).
  void drop(String peer);

  /// What others type or see to join: an IP address, or the lobby's name online.
  String get address;

  /// The lobby changed (mode, seats, started): online, the lobby list is updated.
  void lobbyChanged(LobbyInfo info);

  /// The match ended. Online, the lobby is deleted and only the result is kept.
  Future<void> finished({String? winner, required List<String> players});
  Future<void> close();
}

/// A player's side: one connection to the host.
abstract class ClientLink {
  Stream<Msg> get messages;

  /// Completes when the connection ends, with a reason when one is known.
  Future<String?> get done;
  void send(Msg m);
  Future<void> close();
}
