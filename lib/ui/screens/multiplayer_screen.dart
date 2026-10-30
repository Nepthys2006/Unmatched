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
import '../../net/transports.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'dart:math' as math;
import 'lobby_screen.dart';
import 'menu_screen.dart' show gameSnack;
import '../../net/online_presence.dart';
import '../dialogs/active_players_drawer.dart';

class MultiplayerScreen extends StatefulWidget {
  const MultiplayerScreen({super.key, required this.online, this.autoRejoin = false});
  final bool online;

  /// Opened from the main menu's "Rejoin match": go straight back into the match.
  final bool autoRejoin;

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

  String _randomToken() {
    final r = math.Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  bool get _online => widget.online;

  @override
  void initState() {
    super.initState();
    if (!_online && canDiscoverLan) {
      final d = _discovery = LanDiscovery();
      _sub = d.games.listen((g) => setState(() => _found = g));
      unawaited(d.start());
    }
    if (widget.autoRejoin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_rejoinActive());
      });
    }
    // A browser that was handed the game by a LAN host joins that host.
    final host = servedByLanHost;
    if (!_online && host != null) _address.text = host;
    if (_online) {
      unawaited(_loadLobbies());
      _refresh = Timer.periodic(const Duration(seconds: 4), (_) => _loadLobbies());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final s = context.services;
        OnlinePresenceService.instance.start(
          playerId: s.settings.playerId,
          username: s.settings.username,
        );
      });
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
      final token = _randomToken();
      final HostLink link = _online
          ? await OnlineHost.create(
              name: _lobbyName.text.trim().isEmpty ? '${s.settings.username}\'s lobby' : _lobbyName.text.trim(),
              hostName: s.settings.username,
              password: _password.text,
              info: (mode: 'duel', players: 2, open: 1, playing: false, status: 'matching'),
            )
          : await LanHost.start(
              describe: () {
                final l = session?.lobby;
                final isPlaying = session?.match != null;
                return {
                  'name': s.settings.username,
                  'players': l?.players ?? 2,
                  'open': l?.seats.where((x) => x.kind == SeatKind.open).length ?? 1,
                  'status': isPlaying ? 'inGame' : 'matching',
                };
              },
            );
      session = HostSession(
        link,
        s.data,
        name: s.settings.username,
        dataVersion: s.dataVersion,
        playerId: s.settings.playerId,
        reconnectToken: token,
      );
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
      final token = s.settings.reconnectToken ?? _randomToken();
      s.settings.saveReconnect(lobbyId: target, token: token);
      final link = await joinLan(target);
      final session = ClientSession(
        link,
        s.data,
        name: s.settings.username,
        dataVersion: s.dataVersion,
        address: target,
        playerId: s.settings.playerId,
        reconnectToken: token,
        transport: LanTransport(target, await firstLocalAddress(), hostName: s.settings.username),
      );
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
      final token = s.settings.reconnectToken ?? _randomToken();
      s.settings.saveReconnect(lobbyId: l.id, token: token);
      final link = await OnlineClient.join(l.id, password: password);
      s.settings.saveReconnect(lobbyId: l.id, token: token, topic: link.topic);
      final session = ClientSession(
        link,
        s.data,
        name: s.settings.username,
        dataVersion: s.dataVersion,
        address: l.name,
        playerId: s.settings.playerId,
        reconnectToken: token,
        transport: link.topic == null ? null : OnlineTransport(link.topic!, hostName: s.settings.username),
      );
      await _openLobby(session);
    } catch (e) {
      _error(e);
      unawaited(_loadLobbies());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejoinActive() async {
    final s = context.services;
    final lobbyId = s.settings.reconnectLobbyId;
    final token = s.settings.reconnectToken;
    final topic = s.settings.reconnectTopic;
    if (lobbyId == null || token == null) return;
    setState(() => _busy = true);
    try {
      if (_online) {
        final ClientLink link = (topic != null && topic.isNotEmpty)
            ? await OnlineClient.reconnect(topic: topic)
            : await OnlineClient.join(lobbyId);
        final session = ClientSession(
          link,
          s.data,
          name: s.settings.username,
          dataVersion: s.dataVersion,
          address: lobbyId,
          playerId: s.settings.playerId,
          reconnectToken: token,
          transport: (topic != null && topic.isNotEmpty) ? OnlineTransport(topic, hostName: s.settings.username) : null,
        );
        await _openLobby(session);
      } else {
        await _joinLan(lobbyId);
      }
    } catch (e) {
      _error(e);
      s.settings.clearReconnect();
      if (_online) unawaited(_loadLobbies());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openActivePlayers() => ActivePlayersDrawer.show(context);

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
              ScreenHeader(
                title: _online ? 'Online' : 'LAN',
                trailing: _online
                    ? PlateButton(
                        label: 'Active Players',
                        icon: Icons.people_alt_rounded,
                        height: 38,
                        fontSize: 14,
                        onPressed: _openActivePlayers,
                      )
                    : null,
              ),
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

  Widget _statusBadge(String status) {
    final isGame = status == 'inGame';
    final color = isGame ? const Color(0xFF10B981) : Palette.gold;
    final label = isGame ? 'IN GAME' : 'MATCHING';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isGame) ...[
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
            const SizedBox(width: 4),
          ],
          Text(label, style: titleStyle(10.5, color: color, weight: FontWeight.w800, spacing: 0.6)),
        ],
      ),
    );
  }

  Widget _rejoinBanner() {
    final s = context.services;
    if (!s.settings.hasActiveReconnect) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sync_rounded, color: Palette.gold, size: 20),
              const SizedBox(width: 8),
              Text('ACTIVE SESSION IN PROGRESS', style: titleStyle(13, color: Palette.gold, weight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text('You disconnected recently. Rejoin within the 2-minute grace window to keep your seat.', style: bodyStyle(12, color: Palette.boneDim)),
          const SizedBox(height: 10),
          PlateButton(
            label: 'REJOIN MATCH',
            icon: Icons.login_rounded,
            height: 46,
            fontSize: 15,
            onPressed: _busy ? null : _rejoinActive,
          ),
        ],
      ),
    );
  }
  Widget _joinPanel() => Panel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('JOIN A GAME', style: titleStyle(22, spacing: 1.2)),
        const SizedBox(height: 6),
        _rejoinBanner(),
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PlateButton(
                label: '${g.name}\'s game',
                subtitle: '${g.players} players · ${g.open} open · ${g.ip}',
                icon: Icons.login_rounded,
                style: PlateStyle.secondary,
                height: 58,
                fontSize: 17,
                onPressed: _busy ? null : () => _joinLan(g.ip),
              ),
              Positioned(
                top: -8,
                right: 18,
                child: _statusBadge(g.status),
              ),
            ],
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PlateButton(
                label: g.name,
                subtitle: '${g.host} · ${_modeLabel(g.mode, g.players)} · ${g.open} open seat${g.open == 1 ? '' : 's'}',
                icon: g.locked ? Icons.lock_rounded : Icons.login_rounded,
                style: PlateStyle.secondary,
                height: 58,
                fontSize: 17,
                onPressed: _busy || (g.open < 1 && context.services.settings.reconnectLobbyId != g.id) ? null : () => _joinOnline(g),
              ),
              Positioned(
                top: -8,
                right: 18,
                child: _statusBadge(g.status),
              ),
            ],
          ),
        ),
    ];
  }
}
