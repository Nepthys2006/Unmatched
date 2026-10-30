/// LAN on the web: a browser can't open a server or listen for beacons, so it can only join a
/// host by typing its address (and only when the page itself was opened over http).
library;

import 'link.dart';
import 'ws_client.dart';

const lanPort = 47400;

bool get canHostLan => false;
bool get canDiscoverLan => false;

/// When this page was served by a LAN host (`http://<host>:47400`), that host's address: the
/// browser joins it directly. Null on any other page (an https page can't reach LAN hosts).
String? get servedByLanHost => Uri.base.scheme == 'http' && Uri.base.port == lanPort ? Uri.base.host : null;

/// Whether this page may open plain ws:// connections at all (browsers block them from https).
bool get canJoinLan => Uri.base.scheme == 'http';

/// Browsers can't host, so they have no address to offer.
Future<String?> firstLocalAddress() async => null;

typedef LanGame = ({String ip, String name, int players, int open, String status});

class LanHost implements HostLink {
  static Future<LanHost> start({required Map<String, Object?> Function() describe}) =>
      throw UnsupportedError('Hosting needs the Android, iPhone or Windows app.');

  @override
  Stream<LinkEvent> get events => const Stream.empty();
  @override
  String get address => '';
  String get webAddress => '';
  @override
  void send(String peer, Msg m) {}
  @override
  void broadcast(Msg m) {}
  @override
  void drop(String peer) {}
  @override
  void lobbyChanged(LobbyInfo info) {}
  @override
  Future<void> finished({String? winner, required List<String> players}) async {}
  @override
  Future<void> close() async {}
}

class LanDiscovery {
  Stream<List<LanGame>> get games => const Stream.empty();
  Future<void> start() async {}
  void stop() {}
}

Future<ClientLink> joinLan(String ip) => WsClientLink.connect(Uri.parse('ws://$ip:$lanPort'));
