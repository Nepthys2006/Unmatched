/// LAN play on phones and desktops: the host runs a WebSocket server and announces itself with
/// a UDP beacon so players on the same Wi-Fi or phone hotspot can find it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'link.dart';
import 'ws_client.dart';

const lanPort = 47400;
const beaconPort = 47401;

bool get canHostLan => true;
bool get canDiscoverLan => true;
String? get servedByLanHost => null;
bool get canJoinLan => true;

/// A game found on the network.
typedef LanGame = ({String ip, String name, int players, int open, String status});

class LanHost implements HostLink {
  LanHost._(this._server, this._addresses);

  /// Starts serving. [describe] is put in the beacon (host name, seats).
  static Future<LanHost> start({required Map<String, Object?> Function() describe}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, lanPort, shared: true);
    final addresses = await localAddresses();
    final h = LanHost._(server, addresses);
    server.listen(h._onRequest);
    await h._startBeacon(describe);
    return h;
  }

  final HttpServer _server;
  final List<InternetAddress> _addresses;
  final Map<String, WebSocket> _peers = {};
  final StreamController<LinkEvent> _events = StreamController.broadcast();
  RawDatagramSocket? _udp;
  Timer? _beacon;
  int _ids = 0;

  @override
  Stream<LinkEvent> get events => _events.stream;

  /// The address players type to join (the first Wi-Fi / hotspot address).
  @override
  String get address => _addresses.isEmpty ? 'unknown' : _addresses.map((a) => a.address).join('  or  ');

  Future<void> _onRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      await _serveWebApp(req);
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 5);
    final id = 'p${_ids++}';
    _peers[id] = ws;
    _events.add(PeerJoined(id));
    ws.listen(
      (data) {
        if (data is! String || data.length > 64 * 1024) return;
        try {
          final m = jsonDecode(data);
          if (m is Map) _events.add(PeerMessage(id, m.cast<String, Object?>()));
        } catch (_) {}
      },
      onDone: () => _gone(id),
      onError: (_) => _gone(id),
      cancelOnError: true,
    );
  }

  /// Browsers on the network open `http://<host>:47400` and get the game: its runtime from
  /// assets/webapp (tool/bundle_webapp.py) and its art and data from this app's own bundle. The
  /// page is plain http, so it may open the ws:// connection to this host (an https page may not).
  Future<void> _serveWebApp(HttpRequest req) async {
    final res = req.response;
    try {
      var path = Uri.decodeComponent(req.uri.path);
      if (path == '/' || path.isEmpty) path = '/index.html';
      if (req.method != 'GET' || path.contains('..')) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      // Game art and data: the web build asks for `/assets/<bundle key>`.
      final key = path.startsWith('/assets/assets/')
          ? path.substring('/assets/'.length)
          : (path.startsWith('/assets/maps/') ||
                  path.startsWith('/assets/heroes/') ||
                  path.startsWith('/assets/cards/') ||
                  path.startsWith('/assets/data/') ||
                  path.startsWith('/assets/audio/')
              ? path.substring(1)
              : 'assets/webapp$path');
      final data = await rootBundle.load(key);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      res.headers
        ..set(HttpHeaders.contentTypeHeader, _mime(path))
        ..set(HttpHeaders.cacheControlHeader, 'no-cache')
        ..contentLength = bytes.length;
      res.add(bytes);
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    } finally {
      await res.close();
    }
  }

  static String _mime(String path) => switch (path.split('.').last) {
    'html' => 'text/html; charset=utf-8',
    'js' => 'text/javascript; charset=utf-8',
    'mjs' => 'text/javascript; charset=utf-8',
    'wasm' => 'application/wasm',
    'json' => 'application/json',
    'webp' => 'image/webp',
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'wav' => 'audio/wav',
    'ttf' => 'font/ttf',
    'otf' => 'font/otf',
    'glb' => 'model/gltf-binary',
    _ => 'application/octet-stream',
  };

  /// The address browsers open to play (the game is served from this host).
  String get webAddress => _addresses.isEmpty ? '' : 'http://${_addresses.first.address}:$lanPort';

  void _gone(String id) {
    if (_peers.remove(id) != null) _events.add(PeerLeft(id));
  }

  @override
  void lobbyChanged(LobbyInfo info) {}

  @override
  Future<void> finished({String? winner, required List<String> players}) async {}

  @override
  void send(String peer, Msg m) => _peers[peer]?.add(jsonEncode(m));

  @override
  void broadcast(Msg m) {
    final s = jsonEncode(m);
    for (final ws in _peers.values) {
      ws.add(s);
    }
  }

  @override
  void drop(String peer) {
    final ws = _peers[peer];
    if (ws == null) return;
    // Let the last message (the reason) go out first.
    Future<void>.delayed(const Duration(milliseconds: 300), () => ws.close());
  }

  Future<void> _startBeacon(Map<String, Object?> Function() describe) async {
    try {
      final udp = _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)..broadcastEnabled = true;
      // The limited broadcast plus each network's own broadcast address (some hotspots only pass one).
      final targets = {InternetAddress('255.255.255.255'), for (final a in _addresses) _broadcastOf(a)};
      _beacon = Timer.periodic(const Duration(seconds: 1), (_) {
        final msg = utf8.encode(jsonEncode({'app': 'unmatched', 'port': lanPort, ...describe()}));
        for (final t in targets) {
          try {
            udp.send(msg, t, beaconPort);
          } catch (_) {}
        }
      });
    } catch (_) {
      // No beacon: players can still type the address.
    }
  }

  /// Assumes a /24 network, which is what phone hotspots and home routers use.
  static InternetAddress _broadcastOf(InternetAddress a) {
    final b = a.rawAddress;
    return InternetAddress.fromRawAddress(Uint8List.fromList([...b.sublist(0, 3), 255]));
  }

  @override
  Future<void> close() async {
    _beacon?.cancel();
    _udp?.close();
    final peers = List.of(_peers.values);
    _peers.clear();
    for (final ws in peers) {
      await ws.close();
    }
    await _server.close(force: true);
    await _events.close();
  }
}

/// This device's IPv4 addresses on Wi-Fi / hotspot / Ethernet (not loopback).
Future<List<InternetAddress>> localAddresses() async {
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final all = [
      for (final i in ifs)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a,
    ];
    // Private ranges first: those are what a hotspot hands out.
    int rank(InternetAddress a) => a.address.startsWith('192.168.') ? 0 : (a.address.startsWith('10.') || a.address.startsWith('172.') ? 1 : 2);
    return all..sort((a, b) => rank(a).compareTo(rank(b)));
  } catch (_) {
    return const [];
  }
}

/// Listens for host beacons. [games] updates as hosts appear and disappear.
class LanDiscovery {
  final Map<String, (LanGame, DateTime)> _seen = {};
  final StreamController<List<LanGame>> _games = StreamController.broadcast();
  RawDatagramSocket? _udp;
  Timer? _sweep;

  Stream<List<LanGame>> get games => _games.stream;

  static const _lan = MethodChannel('unmatched/lan');

  Future<void> start() async {
    // Android only hands broadcast packets to apps holding a multicast lock.
    if (Platform.isAndroid) {
      try {
        await _lan.invokeMethod<bool>('acquire');
      } catch (_) {}
    }
    try {
      final udp = _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, beaconPort, reuseAddress: true);
      udp.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = udp.receive();
        if (d == null) return;
        try {
          final m = jsonDecode(utf8.decode(d.data));
          if (m is! Map || m['app'] != 'unmatched') return;
          final g = (
            ip: d.address.address,
            name: '${m['name'] ?? 'Host'}',
            players: (m['players'] as num?)?.toInt() ?? 2,
            open: (m['open'] as num?)?.toInt() ?? 0,
            status: '${m['status'] ?? 'matching'}',
          );
          _seen[g.ip] = (g, DateTime.now());
          _emit();
        } catch (_) {}
      });
    } catch (_) {
      // Port busy or blocked: typing the address still works.
    }
    _sweep = Timer.periodic(const Duration(seconds: 2), (_) {
      final before = _seen.length;
      _seen.removeWhere((_, v) => DateTime.now().difference(v.$2) > const Duration(seconds: 4));
      if (_seen.length != before) _emit();
    });
  }

  void _emit() => _games.add([for (final v in _seen.values) v.$1]);

  void stop() {
    _sweep?.cancel();
    _udp?.close();
    _games.close();
    if (Platform.isAndroid) unawaited(_lan.invokeMethod<bool>('release').catchError((_) => false));
  }
}

/// Connects to a LAN host at [ip].
Future<ClientLink> joinLan(String ip) => WsClientLink.connect(Uri.parse('ws://$ip:$lanPort'));
