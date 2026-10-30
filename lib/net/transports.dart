/// How a player's device reconnects to a match, and how it takes over as host when the host is
/// lost for good: one transport for LAN, one for online (see [MatchTransport]).
library;

import 'lan.dart';
import 'link.dart';
import 'online.dart';
import 'session.dart';

/// LAN: the host is a WebSocket server at [hostAddress]. A new host (the first remaining player
/// that announced an address) serves from its own address, which the others read from the lobby.
class LanTransport extends MatchTransport {
  LanTransport(this.hostAddress, this._me, {this.hostName = 'Host'});

  String hostAddress;
  final String? _me;
  final String hostName;

  @override
  String? get localAddress => canHostLan ? _me : null;
  @override
  bool get needsAddress => true;
  @override
  bool get canHost => canHostLan && _me != null;

  @override
  Future<ClientLink> reconnect() => joinLan(hostAddress);

  @override
  Future<HostLink?> hostNew() async {
    if (!canHost) return null;
    final h = await LanHost.start(describe: () => {'name': hostName, 'players': 2, 'open': 0, 'status': 'inGame'});
    if (_me != null) hostAddress = _me;
    return h;
  }

  @override
  Future<ClientLink?> joinNew(Lobby lobby, int hostSeat) async {
    final addr = lobby.seats[hostSeat].addr;
    if (addr == null) return null;
    final link = await joinLan(addr);
    hostAddress = addr;
    return link;
  }
}

/// Online: the match runs over a secret Realtime channel. When its host is lost, the new host
/// opens the same channel under the next "generation" name, which every player can work out, so
/// no one needs to be told where to go.
class OnlineTransport extends MatchTransport {
  OnlineTransport(this.topic, {this.hostName = 'Host'});

  String topic;
  final String hostName;

  String get _next => '$topic-m';

  @override
  Future<ClientLink> reconnect() => OnlineClient.reconnect(topic: topic);

  @override
  Future<HostLink?> hostNew() async {
    final next = _next;
    final h = await OnlineHost.adopt(topic: next, hostName: hostName);
    topic = next;
    return h;
  }

  @override
  Future<ClientLink?> joinNew(Lobby lobby, int hostSeat) async {
    final next = _next;
    final link = await OnlineClient.reconnect(topic: next);
    topic = next;
    return link;
  }
}
