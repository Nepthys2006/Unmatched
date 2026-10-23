/// The multiplayer lobby: the host sets mode, map and AI level and fills empty seats with AI;
/// everyone picks a hero and gets ready; the host starts. Teams alternate by seat (1 & 3 vs
/// 2 & 4...), so tapping an open seat moves you there to change sides.
library;

import 'package:flutter/material.dart';

import '../../engine/ai.dart';
import '../../net/session.dart';
import '../match/match_config.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'hero_select_screen.dart';
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

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
  }

  @override
  void dispose() {
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
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => HeroSelectScreen.pick(map: data.maps[l.mapId]!, initial: l.seats[s.mySeat!].hero, taken: l.takenBy(s.mySeat)),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: TableBackground(
          child: SafeArea(
            child: Column(
              children: [
                ScreenHeader(title: s.isHost ? 'Your lobby' : 'Lobby', onBack: _leave, trailing: _address()),
                Expanded(
                  child: l == null || s.mySeat == null
                      ? Center(child: Text('Joining…', style: titleStyle(22, color: Palette.boneDim)))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1080),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 5, child: _settings(l)),
                                  const SizedBox(width: 20),
                                  Expanded(flex: 6, child: _seats(l)),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
                if (l != null && s.mySeat != null) _bottomBar(l),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// LAN lobbies are joined by IP address; online ones are listed by name.
  bool get _lan => RegExp(r'^\d+\.\d+\.\d+\.\d+').hasMatch(s.address);

  Widget _address() => Container(
    padding: const EdgeInsets.fromLTRB(14, 6, 16, 6),
    decoration: const ShapeDecoration(color: Color(0xCC0E0F12), shape: ChamferBorder(cut: 6, side: BorderSide(color: Palette.line))),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_lan ? Icons.wifi_tethering_rounded : Icons.public_rounded, size: 18, color: Palette.boneDim),
        const SizedBox(width: 8),
        Text(_lan ? 'JOIN AT ' : 'LOBBY ', style: titleStyle(13, color: Palette.boneDim, spacing: 1.2)),
        SelectableText(s.address, style: titleStyle(20, color: Palette.brass, spacing: 1)),
      ],
    ),
  );

  Widget _settings(Lobby l) {
    final host = s is HostSession ? s as HostSession : null;
    final map = context.services.data.maps[l.mapId]!;
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
        if (host == null)
          Text(map.name.toUpperCase(), style: titleStyle(18))
        else
          row([
            for (final m in host.maps) ChoiceTile(label: m.name, selected: m.id == l.mapId, height: 40, onTap: () => host.setMap(m.id)),
            ChoiceTile(label: 'Random', selected: false, height: 40, onTap: host.randomMap),
          ]),
        const SizedBox(height: 14),
        const SectionLabel('AI seats'),
        row([
          for (final a in AiLevel.values)
            ChoiceTile(label: a.label, selected: l.ai == a, height: 40, minWidth: 74, onTap: host == null ? null : () => host.setAi(a)),
        ]),
      ],
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
