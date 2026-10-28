/// The multiplayer lobby: the host sets mode, map and AI level and fills empty seats with AI;
/// everyone picks a hero and gets ready; the host starts. Teams alternate by seat (1 & 3 vs
/// 2 & 4...), so tapping an open seat moves you there to change sides.
library;

import 'package:flutter/material.dart';

import '../../engine/ai.dart';
import '../../engine/defs.dart';
import '../../net/lan.dart';
import '../../net/session.dart';
import '../board/board_painter.dart';
import '../dialogs/map_inspect_dialog.dart';
import '../match/match_config.dart';
import '../qr_dialog.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'hero_select_screen.dart';
import 'map_select_screen.dart';
import 'vs_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.session});
  final LobbySession session;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  LobbySession get s => widget.session;
  bool _started = false;
  bool _closedShown = false;
  int _view = 0; // 0 = Lobby Overview, 1 = Battlefield page (similar to VS AI)
  final _mapScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
  }

  @override
  void dispose() {
    _mapScroll.dispose();
    s.removeListener(_changed);
    if (!_started) s.leave();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final m = s.match;
    if (m != null && !_started) {
      _started = true;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, _, _) => VsScreen(config: m.config, net: m),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        ),
      );
      return;
    }
    if (s.closed != null && !_closedShown && m == null) {
      _closedShown = true;
      showConfirm(context, title: 'Left the lobby', message: s.closed, confirm: 'OK', cancel: 'Close').then((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    setState(() {});
  }

  Future<void> _pickHero() async {
    final l = s.lobby;
    if (l == null) return;
    final data = context.services.data;
    final map = data.maps[l.mapId] ?? data.maps.values.first;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => HeroSelectScreen.pick(map: map, initial: l.seats[s.mySeat!].hero, taken: l.takenBy(s.mySeat)),
      ),
    );
    if (id != null) s.pickHero(id);
  }

  Future<void> _leave() async {
    final ok = await showConfirm(context, title: 'Leave the lobby?', confirm: 'Leave', danger: true);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = s.lobby;
    final allMaps = l != null ? mapsFor(context.services.data, l.mode, l.players) : const <MapDef>[];
    final currentMap = l != null ? (context.services.data.maps[l.mapId] ?? (allMaps.isNotEmpty ? allMaps.first : null)) : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_view == 1) {
            setState(() => _view = 0);
          } else {
            _leave();
          }
        }
      },
      child: Scaffold(
        body: TableBackground(
          child: SafeArea(
            child: Column(
              children: [
                ScreenHeader(
                  title: _view == 1
                      ? 'Battlefield'
                      : (s.isHost ? 'Your lobby' : 'Lobby'),
                  step: _view == 1 && l != null ? '${allMaps.length} maps' : null,
                  onBack: _view == 1 ? () => setState(() => _view = 0) : _leave,
                  trailing: _address(),
                ),
                Expanded(
                  child: l == null || s.mySeat == null || currentMap == null
                      ? Center(child: Text('Joining…', style: titleStyle(22, color: Palette.boneDim)))
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          switchInCurve: Curves.easeOutCubic,
                          child: _view == 1
                              ? _battlefieldPage(l, allMaps, currentMap)
                              : SingleChildScrollView(
                                  key: const ValueKey('lobby_overview'),
                                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 1080),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final isNarrow = constraints.maxWidth < 740;
                                          if (isNarrow) {
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                _settings(l, currentMap),
                                                const SizedBox(height: 20),
                                                _seats(l),
                                              ],
                                            );
                                          }
                                          return Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(flex: 5, child: _settings(l, currentMap)),
                                              const SizedBox(width: 20),
                                              Expanded(flex: 6, child: _seats(l)),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                ),
                if (_view == 0 && l != null && s.mySeat != null) _bottomBar(l),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// LAN lobbies are joined by IP address; online ones are listed by name.
  bool get _lan => RegExp(r'^\d+\.\d+\.\d+\.\d+').hasMatch(s.address);

  String? get _qrUrl {
    if (_webAddress != null) return _webAddress;
    if (_lan) {
      final addr = s.address;
      return addr.startsWith('http://') || addr.startsWith('https://') ? addr : 'http://$addr';
    }
    return null;
  }

  Widget _address() {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 900;
    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: const ShapeDecoration(
          color: Color(0xCC0E0F12),
          shape: ChamferBorder(cut: 6, side: BorderSide(color: Palette.line)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_lan ? Icons.wifi_tethering_rounded : Icons.public_rounded, size: 16, color: Palette.boneDim),
            const SizedBox(width: 6),
            Flexible(child: SelectableText(s.address, style: titleStyle(14, color: Palette.brass, spacing: 0.5), maxLines: 1)),
            if (_qrUrl case final qrUrl?) ...[
              const SizedBox(width: 6),
              HexButton(
                icon: Icons.qr_code_2_rounded,
                size: 28,
                tooltip: 'Show QR Code',
                onPressed: () => showQrShareDialog(
                  context,
                  url: qrUrl,
                  title: 'SCAN TO JOIN ON iOS / MOBILE',
                  subtitle: 'Scan with your iPhone or iPad camera to open and play directly in Safari on the same Wi-Fi.',
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 16, 6),
      decoration: const ShapeDecoration(color: Color(0xCC0E0F12), shape: ChamferBorder(cut: 6, side: BorderSide(color: Palette.line))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_lan ? Icons.wifi_tethering_rounded : Icons.public_rounded, size: 18, color: Palette.boneDim),
          const SizedBox(width: 8),
          Text(_lan ? 'JOIN AT ' : 'LOBBY ', style: titleStyle(13, color: Palette.boneDim, spacing: 1.2)),
          SelectableText(s.address, style: titleStyle(20, color: Palette.brass, spacing: 1)),
          if (_webAddress case final web?) ...[
            const SizedBox(width: 14),
            Icon(Icons.language_rounded, size: 18, color: Palette.boneDim),
            const SizedBox(width: 6),
            Text('BROWSER ', style: titleStyle(13, color: Palette.boneDim, spacing: 1.2)),
            SelectableText(web, style: titleStyle(16, color: Palette.brass, spacing: 0.5)),
          ],
          if (_qrUrl case final qrUrl?) ...[
            const SizedBox(width: 12),
            PlateButton(
              label: 'QR Code',
              icon: Icons.qr_code_2_rounded,
              style: PlateStyle.primary,
              height: 32,
              fontSize: 13,
              onPressed: () => showQrShareDialog(
                context,
                url: qrUrl,
                title: 'SCAN TO JOIN ON iOS / MOBILE',
                subtitle: 'Scan with your iPhone or iPad camera to open and play directly in Safari on the same Wi-Fi.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? get _webAddress {
    final host = s is HostSession ? s as HostSession : null;
    final link = host?.link;
    if (link is! LanHost) return null;
    final w = link.webAddress;
    return w.isEmpty ? null : w;
  }

  Widget _settings(Lobby l, MapDef map) {
    final host = s is HostSession ? s as HostSession : null;
    Widget row(List<Widget> children) => Wrap(spacing: 8, runSpacing: 8, children: children);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Mode'),
        row([
          for (final (mode, n) in [
            (GameMode.duel, 2),
            (GameMode.teams2, 4),
            (GameMode.teams3, 6),
            (GameMode.ffa, 3),
            (GameMode.ffa, 4),
            (GameMode.ffa, 5),
          ])
            ChoiceTile(
              label: mode == GameMode.ffa ? 'FFA $n' : mode.label,
              selected: l.mode == mode && l.players == n,
              height: 42,
              minWidth: 74,
              onTap: host == null
                  ? null
                  : () {
                      if (!host.setMode(mode, n)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Too many people in the lobby for that mode.')));
                      }
                    },
            ),
        ]),
        const SizedBox(height: 14),
        const SectionLabel('Battlefield'),
        _battlefieldCard(l, map),
        const SizedBox(height: 14),
        const SectionLabel('AI seats'),
        row([
          for (final a in AiLevel.values)
            ChoiceTile(label: a.label, selected: l.ai == a, height: 40, minWidth: 74, onTap: host == null ? null : () => host.setAi(a)),
        ]),
      ],
    );
  }

  Widget _battlefieldCard(Lobby l, MapDef map) {
    final starts = map.spaces.where((s) => s.start != null).length;
    const shape = ChamferBorder(
      cut: 8,
      side: BorderSide(color: Palette.line, width: 1.2),
    );
    return Material(
      color: Palette.panel,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Prominent visual map display
          GestureDetector(
            onTap: () => showMapInspectDialog(context, map),
            child: Container(
              height: 148,
              decoration: const BoxDecoration(
                color: Color(0xFF090A0D),
                border: Border(bottom: BorderSide(color: Palette.line, width: 1)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        child: KeyedSubtree(
                          key: ValueKey(map.id),
                          child: MapPreview(map, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                  // Bottom gradient shading
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 38,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xDD0E0F12)],
                        ),
                      ),
                    ),
                  ),
                  // Battlefield badge top-left
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: const ShapeDecoration(
                        color: Color(0xEB0E0F12),
                        shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.line)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_rounded, size: 13, color: Palette.brass),
                          const SizedBox(width: 5),
                          Text('ACTIVE MAP', style: titleStyle(11, color: Palette.brass, spacing: 0.8)),
                        ],
                      ),
                    ),
                  ),
                  // Inspect indicator top-right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: const Color(0xEB0E0F12),
                      shape: const ChamferBorder(cut: 4, side: BorderSide(color: Palette.line)),
                      child: InkWell(
                        customBorder: const ChamferBorder(cut: 4),
                        onTap: () => showMapInspectDialog(context, map),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.zoom_in_rounded, size: 14, color: Palette.brass),
                              const SizedBox(width: 4),
                              Text('INSPECT', style: titleStyle(11, color: Palette.brass, spacing: 0.8)),
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
          // Details & action bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        map.name.toUpperCase(),
                        style: titleStyle(19, color: Palette.brass, spacing: 0.8),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${map.spaces.length} SPACES · $starts STARTS',
                      style: titleStyle(11.5, color: Palette.boneDim, spacing: 0.8),
                    ),
                  ],
                ),
                if (map.blurb.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    map.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(12, color: Palette.muted),
                  ),
                ],
                const SizedBox(height: 6),
                // Zone pills
                Row(
                  children: [
                    Text('ZONES: ', style: titleStyle(10.5, color: Palette.boneDim, spacing: 0.6)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final z in map.zones.values.take(6))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: hexColor(z.color).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: hexColor(z.color).withValues(alpha: 0.7)),
                              ),
                              child: Text(
                                z.name.toUpperCase(),
                                style: titleStyle(9.5, color: hexColor(z.color), spacing: 0.4),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (s.isHost) ...[
                      PlateButton(
                        label: 'Change Battlefield',
                        icon: Icons.map_rounded,
                        style: PlateStyle.primary,
                        height: 38,
                        fontSize: 13.5,
                        onPressed: () => setState(() => _view = 1),
                      ),
                      PlateButton(
                        label: 'Inspect',
                        icon: Icons.zoom_in_rounded,
                        style: PlateStyle.secondary,
                        height: 38,
                        fontSize: 13.5,
                        onPressed: () => showMapInspectDialog(context, map),
                      ),
                      PlateButton(
                        label: 'Random',
                        icon: Icons.shuffle_rounded,
                        style: PlateStyle.secondary,
                        height: 38,
                        fontSize: 13.5,
                        onPressed: s.randomMap,
                      ),
                    ] else ...[
                      PlateButton(
                        label: 'Inspect Battlefield',
                        icon: Icons.zoom_in_rounded,
                        style: PlateStyle.primary,
                        height: 38,
                        fontSize: 14,
                        onPressed: () => showMapInspectDialog(context, map),
                      ),
                      PlateButton(
                        label: 'Browse All Maps',
                        icon: Icons.map_rounded,
                        style: PlateStyle.secondary,
                        height: 38,
                        fontSize: 14,
                        onPressed: () => setState(() => _view = 1),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _battlefieldPage(Lobby l, List<MapDef> maps, MapDef currentMap) {
    return Column(
      key: const ValueKey('battlefield_page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: SectionLabel(
            s.isHost
                ? '${maps.length} maps for ${l.mode.label}${l.mode == GameMode.ffa ? ' · ${l.players} players' : ''}'
                : 'Current Battlefield: ${currentMap.name} · ${maps.length} maps available',
            trailing: Text(
              s.isHost ? 'Tap any map to pick for this lobby' : 'Tap any map to inspect spaces and artwork',
              style: bodyStyle(12, color: Palette.muted),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _mapScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            itemCount: maps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => MapCard(
              map: maps[i],
              selected: maps[i].id == l.mapId,
              onTap: s.isHost
                  ? () => s.setMap(maps[i].id)
                  : () => showMapInspectDialog(context, maps[i]),
            ),
          ),
        ),
        _battlefieldBottomBar(l, currentMap, maps),
      ],
    );
  }

  Widget _battlefieldBottomBar(Lobby l, MapDef map, List<MapDef> maps) {
    final starts = map.spaces.where((s) => s.start != null).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
      decoration: const ShapeDecoration(
        color: Color(0xEB0E0F12),
        shape: Border(top: BorderSide(color: Palette.line, width: 1.5)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 820;
              final buttons = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PlateButton(
                    label: 'Inspect',
                    icon: Icons.zoom_in_rounded,
                    style: PlateStyle.secondary,
                    height: 42,
                    fontSize: 14,
                    onPressed: () => showMapInspectDialog(context, map),
                  ),
                  if (s.isHost)
                    PlateButton(
                      label: 'Random map',
                      icon: Icons.shuffle_rounded,
                      style: PlateStyle.secondary,
                      height: 42,
                      fontSize: 14,
                      onPressed: () {
                        s.randomMap();
                        final updated = context.services.data.maps[l.mapId];
                        if (updated != null && _mapScroll.hasClients) {
                          final idx = maps.indexOf(updated);
                          if (idx >= 0) {
                            _mapScroll.animateTo(
                              (idx * 300.0 - 40).clamp(0, _mapScroll.position.maxScrollExtent),
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        }
                      },
                    ),
                  PlateButton(
                    label: s.isHost ? 'Done' : 'Back to Lobby',
                    icon: Icons.check_rounded,
                    style: PlateStyle.confirm,
                    height: 42,
                    fontSize: 15,
                    onPressed: () => setState(() => _view = 0),
                  ),
                ],
              );

              final textInfo = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        map.name.toUpperCase(),
                        style: titleStyle(19, color: Palette.brass, spacing: 0.8),
                      ),
                      Text(
                        '${map.spaces.length} SPACES · $starts STARTS',
                        style: titleStyle(12, color: Palette.boneDim, spacing: 0.8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    map.blurb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(13, color: Palette.boneDim),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    textInfo,
                    const SizedBox(height: 8),
                    buttons,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: textInfo),
                  const SizedBox(width: 12),
                  buttons,
                ],
              );
            },
          ),
        ),
      ),
    );
  }


  Widget _seats(Lobby l) {
    final teams = l.mode.isTeams;
    final host = s is HostSession ? s as HostSession : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(teams ? 'Seats · teams alternate' : 'Seats · turn order'),
        for (var i = 0; i < l.seats.length; i++) ...[
          _seat(i, l.seats[i], teams ? (i.isEven ? Palette.teamA.first : Palette.teamB.first) : Palette.seats[i % Palette.seats.length], host),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _seat(int i, LobbySeat seat, Color color, HostSession? host) {
    final me = i == s.mySeat;
    final hero = seat.hero == null ? null : context.services.data.hero(seat.hero!);
    final (title, status) = switch (seat.kind) {
      SeatKind.open => ('Open seat', host != null ? 'Tap to make it an AI' : 'Tap to sit here'),
      SeatKind.ai => ('AI ${s.lobby!.ai.label}', host != null ? 'Random hero · tap to open the seat' : 'Random hero'),
      SeatKind.human => (
        '${seat.name ?? 'Player'}${me ? ' (you)' : ''}',
        hero == null ? 'Choosing a hero…' : '${hero.name}${i == 0 || seat.ready ? ' · ready' : ' · not ready'}',
      ),
    };
    final tap = switch (seat.kind) {
      SeatKind.open when host != null => () => host.toggleSeat(i),
      SeatKind.open => () => s.moveSeat(i),
      SeatKind.ai when host != null => () => host.toggleSeat(i),
      _ => null,
    };
    return Material(
      color: me ? Palette.panelHi : Palette.panel,
      shape: ChamferBorder(cut: 8, side: BorderSide(color: me ? Palette.bone : color.withValues(alpha: 0.5), width: me ? 1.6 : 1)),
      child: InkWell(
        customBorder: const ChamferBorder(cut: 8),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text('${i + 1}', style: titleStyle(14, color: Colors.white, spacing: 0)),
              ),
              const SizedBox(width: 10),
              if (hero != null) ...[Avatar(hero.avatar, size: 38, ring: color, ringWidth: 1.6), const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle(17)),
                    Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(13, color: Palette.muted)),
                  ],
                ),
              ),
              if (seat.kind == SeatKind.human && (i == 0 || seat.ready) && hero != null)
                const Icon(Icons.check_circle_rounded, color: Palette.confirmHi, size: 22),
              if (host != null && seat.kind == SeatKind.human && !me)
                IconButton(
                  tooltip: 'Remove from lobby',
                  icon: const Icon(Icons.close_rounded, color: Palette.muted),
                  onPressed: () => host.kick(i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(Lobby l) {
    final mine = l.seats[s.mySeat!];
    final host = s is HostSession ? s as HostSession : null;
    final why = host?.notReady;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              host != null ? (why ?? 'Everyone is ready.') : (mine.ready ? 'Waiting for the host to start…' : 'Choose a hero, then tap Ready.'),
              style: bodyStyle(14, color: Palette.boneDim),
            ),
          ),
          PlateButton(
            label: mine.hero == null ? 'Choose hero' : 'Change hero',
            icon: Icons.person_search_rounded,
            style: PlateStyle.secondary,
            height: 50,
            fontSize: 17,
            onPressed: mine.ready && host == null ? null : _pickHero,
          ),
          const SizedBox(width: 12),
          if (host != null)
            PlateButton(label: 'Start match', icon: Icons.bolt_rounded, style: PlateStyle.confirm, height: 50, fontSize: 18, onPressed: why == null ? host.start : null)
          else
            PlateButton(
              label: mine.ready ? 'Not ready' : 'Ready',
              icon: mine.ready ? Icons.close_rounded : Icons.check_rounded,
              style: mine.ready ? PlateStyle.secondary : PlateStyle.confirm,
              height: 50,
              fontSize: 18,
              onPressed: mine.hero == null ? null : () => s.setReady(!mine.ready),
            ),
        ],
      ),
    );
  }
}
