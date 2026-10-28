/// LAN and Online: host a game or join one. LAN finds hosts on the same Wi-Fi or phone hotspot
/// by itself (or takes an IP address); online hosts create a named lobby, optionally with a
/// password, and everyone else picks one from the lobby list.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../net/lan.dart';
import '../../net/link.dart';
import '../../net/online.dart';
import '../../net/session.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lobby_screen.dart';
import 'menu_screen.dart' show gameSnack;

class MultiplayerScreen extends StatefulWidget {
  const MultiplayerScreen({super.key, required this.online});
  final bool online;

  @override
  State<MultiplayerScreen> createState() => _MultiplayerScreenState();
}

class _MultiplayerScreenState extends State<MultiplayerScreen> {
  final _address = TextEditingController();
  final _lobbyName = TextEditingController();
  final _password = TextEditingController();
  LanDiscovery? _discovery;
  List<LanGame> _found = const [];
  StreamSubscription<List<LanGame>>? _sub;
  bool _busy = false;

  // Online lobby list, refreshed every few seconds while this screen is open.
  List<OnlineLobby>? _lobbies;
  String? _listError;
  Timer? _refresh;

  bool get _online => widget.online;

  @override
  void initState() {
    super.initState();
    if (!_online && canDiscoverLan) {
      final d = _discovery = LanDiscovery();
      _sub = d.games.listen((g) => setState(() => _found = g));
      unawaited(d.start());
    }
    // A browser that was handed the game by a LAN host joins that host.
    final host = servedByLanHost;
    if (!_online && host != null) _address.text = host;
    if (_online) {
      unawaited(_loadLobbies());
      _refresh = Timer.periodic(const Duration(seconds: 4), (_) => _loadLobbies());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _discovery?.stop();
    _refresh?.cancel();
    _address.dispose();
    _lobbyName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadLobbies() async {
    try {
      final l = await listLobbies();
      if (mounted) {
        setState(() {
          _lobbies = l;
          _listError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _listError = e is StateError ? e.message : 'Can\'t reach the online service.');
    }
  }

  void _error(Object e) {
    if (!mounted) return;
    final text = e is StateError ? e.message : (e is TimeoutException ? 'Timed out. Check the connection and try again.' : '$e');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(gameSnack(text));
  }

  Future<void> _host() async {
    final s = context.services;
    setState(() => _busy = true);
    try {
      HostSession? session;
      final HostLink link = _online
          ? await OnlineHost.create(
              name: _lobbyName.text.trim().isEmpty ? '${s.settings.username}\'s lobby' : _lobbyName.text.trim(),
              hostName: s.settings.username,
              password: _password.text,
              info: (mode: 'duel', players: 2, open: 1, playing: false),
            )
          : await LanHost.start(
              describe: () {
                final l = session?.lobby;
                return {
                  'name': s.settings.username,
                  'players': l?.players ?? 2,
                  'open': l?.seats.where((x) => x.kind == SeatKind.open).length ?? 1,
                };
              },
            );
      session = HostSession(link, s.data, name: s.settings.username, dataVersion: s.dataVersion);
      await _openLobby(session);
    } catch (e) {
      _error(_online ? e : 'Could not start hosting: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinLan(String where) async {
    final s = context.services;
    final target = where.trim();
    if (target.isEmpty) {
      _error('Type the host\'s address, like 192.168.43.1');
      return;
    }
    setState(() => _busy = true);
    try {
      final link = await joinLan(target);
      final session = ClientSession(link, s.data, name: s.settings.username, dataVersion: s.dataVersion, address: target);
      await _openLobby(session);
    } catch (e) {
      _error('Could not reach $target. Are you on the same Wi-Fi or hotspot?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinOnline(OnlineLobby l) async {
    final s = context.services;
    var password = '';
    if (l.locked) {
      final p = await _askPassword(l.name);
      if (p == null) return;
      password = p;
    }
    setState(() => _busy = true);
    try {
      final link = await OnlineClient.join(l.id, password: password);
      final session = ClientSession(link, s.data, name: s.settings.username, dataVersion: s.dataVersion, address: l.name);
      await _openLobby(session);
    } catch (e) {
      _error(e);
      unawaited(_loadLobbies());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword(String lobby) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.panel,
        title: Text('PASSWORD FOR ${lobby.toUpperCase()}', style: titleStyle(18)),
        content: TextField(
          controller: c,
          autofocus: !kIsWeb,
          obscureText: true,
          style: titleStyle(20, weight: FontWeight.w700),
          decoration: const InputDecoration(hintText: 'Password'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('CANCEL', style: titleStyle(15, color: Palette.boneDim))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: Text('JOIN', style: titleStyle(15, color: Palette.confirmHi))),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _openLobby(LobbySession session) async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LobbyScreen(session: session)));
    if (_online) unawaited(_loadLobbies());
  }

  @override
  Widget build(BuildContext context) {
    final canHost = _online || canHostLan;
    return Scaffold(
      body: TableBackground(
        child: SafeArea(
          child: Column(
            children: [
              ScreenHeader(title: _online ? 'Online' : 'LAN'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _hostPanel(canHost)),
                          const SizedBox(width: 20),
                          Expanded(child: _joinPanel()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hostPanel(bool canHost) => Panel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('HOST A GAME', style: titleStyle(22, spacing: 1.2)),
        const SizedBox(height: 6),
        Text(
          _online
              ? 'Your lobby shows up in everyone\'s lobby list. Add a password to keep it to friends; fill empty seats with AI.'
              : canHost
              ? 'Turn on your phone\'s hotspot (or use the same Wi-Fi), then host. Friends on it will see your game.'
              : 'Hosting needs the Android, iPhone or Windows app. In a browser you can join a game.',
          style: bodyStyle(14, color: Palette.boneDim),
        ),
        if (_online) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _lobbyName,
            maxLength: 32,
            style: titleStyle(18, weight: FontWeight.w700),
            decoration: InputDecoration(hintText: '${context.services.settings.username}\'s lobby', labelText: 'Lobby name'),
          ),
          TextField(
            controller: _password,
            maxLength: 24,
            obscureText: true,
            style: titleStyle(18, weight: FontWeight.w700),
            decoration: const InputDecoration(labelText: 'Password (optional)'),
          ),
        ],
        const SizedBox(height: 16),
        PlateButton(
          label: _online ? 'Create lobby' : 'Host on this device',
          icon: Icons.wifi_tethering_rounded,
          height: 52,
          fontSize: 18,
          onPressed: canHost && !_busy ? _host : null,
        ),
      ],
    ),
  );

  Widget _joinPanel() => Panel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('JOIN A GAME', style: titleStyle(22, spacing: 1.2)),
        const SizedBox(height: 6),
        if (_online) ..._lobbyList() else ..._lanJoin(),
      ],
    ),
  );

  List<Widget> _lanJoin() => [
    if (servedByLanHost case final host?) ...[
      PlateButton(
        label: 'Join the game on $host',
        subtitle: 'This page came from that host',
        icon: Icons.login_rounded,
        height: 58,
        fontSize: 17,
        onPressed: _busy ? null : () => _joinLan(host),
      ),
      const SizedBox(height: 12),
    ] else if (!canJoinLan) ...[
      Text(
        "Browsers can't reach LAN games from this page. On the same Wi-Fi, open the address the host "
        'shows under BROWSER (like http://192.168.1.5:47400), or play together with Online.',
        style: bodyStyle(14, color: Palette.boneDim),
      ),
      const SizedBox(height: 12),
    ],
    if (canDiscoverLan) ...[
      if (_found.isEmpty)
        Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.boneDim)),
            const SizedBox(width: 10),
            Expanded(child: Text('Looking for games on this network…', style: bodyStyle(14, color: Palette.boneDim))),
          ],
        ),
      for (final g in _found)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PlateButton(
            label: '${g.name}\'s game',
            subtitle: '${g.players} players · ${g.open} open · ${g.ip}',
            icon: Icons.login_rounded,
            style: PlateStyle.secondary,
            height: 58,
            fontSize: 17,
            onPressed: _busy ? null : () => _joinLan(g.ip),
          ),
        ),
      const SizedBox(height: 10),
      Text('Not listed? Type the address shown on the host\'s screen:', style: bodyStyle(13, color: Palette.muted)),
    ] else
      Text('Type the address shown on the host\'s screen.', style: bodyStyle(14, color: Palette.boneDim)),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: TextField(
            controller: _address,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: titleStyle(22, weight: FontWeight.w700, spacing: 1),
            decoration: const InputDecoration(hintText: '192.168.43.1'),
            onSubmitted: _busy ? null : _joinLan,
          ),
        ),
        const SizedBox(width: 10),
        ConfirmHex(size: 56, tooltip: 'Join', onPressed: _busy ? null : () => _joinLan(_address.text)),
      ],
    ),
  ];

  static String _modeLabel(String mode, int players) => switch (mode) {
    'teams2' => '2 v 2',
    'teams3' => '3 v 3',
    'ffa' => 'Free-for-all · $players',
    _ => '1 v 1',
  };

  List<Widget> _lobbyList() {
    final l = _lobbies;
    if (_listError != null) return [Text(_listError!, style: bodyStyle(14, color: Palette.danger))];
    if (l == null) {
      return [
        Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.boneDim)),
            const SizedBox(width: 10),
            Text('Loading lobbies…', style: bodyStyle(14, color: Palette.boneDim)),
          ],
        ),
      ];
    }
    if (l.isEmpty) return [Text('No open lobbies right now. Create one!', style: bodyStyle(14, color: Palette.boneDim))];
    return [
      for (final g in l)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PlateButton(
            label: g.name,
            subtitle: '${g.host} · ${_modeLabel(g.mode, g.players)} · ${g.open} open seat${g.open == 1 ? '' : 's'}',
            icon: g.locked ? Icons.lock_rounded : Icons.login_rounded,
            style: PlateStyle.secondary,
            height: 58,
            fontSize: 17,
            onPressed: _busy || g.open < 1 ? null : () => _joinOnline(g),
          ),
        ),
    ];
  }
}
