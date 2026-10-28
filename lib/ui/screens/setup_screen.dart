/// Match setup in two steps: mode and AI level, then the battlefield. Hero select follows.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/ai.dart';
import '../../engine/defs.dart';
import '../match/match_config.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'hero_select_screen.dart';
import 'map_select_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 0;
  GameMode _mode = GameMode.duel;
  int _ffaPlayers = 3;
  AiLevel _ai = AiLevel.medium;
  MapDef? _map;
  final _mapScroll = ScrollController();

  int get _players => _mode == GameMode.ffa ? _ffaPlayers : _mode.fixedPlayers;

  List<MapDef> get _maps => mapsFor(context.services.data, _mode, _players);

  @override
  void dispose() {
    _mapScroll.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0) {
      final maps = _maps;
      setState(() {
        _step = 1;
        if (_map == null || !maps.contains(_map)) _map = maps.first;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HeroSelectScreen(mode: _mode, players: _players, map: _map!, ai: _ai),
      ),
    );
  }

  void _randomMap() {
    final maps = _maps;
    final others = maps.where((m) => m != _map).toList();
    final pick = (others.isEmpty ? maps : others)[math.Random().nextInt(others.isEmpty ? maps.length : others.length)];
    setState(() => _map = pick);
    final i = maps.indexOf(pick);
    if (_mapScroll.hasClients) {
      _mapScroll.animateTo(
        (i * 300.0 - 40).clamp(0, _mapScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = 0);
      },
      child: Scaffold(
        body: TableBackground(
          child: SafeArea(
            child: Column(
              children: [
                ScreenHeader(
                  title: _step == 0 ? 'Mode & opponents' : 'Battlefield',
                  step: '${_step + 1} / 3',
                  onBack: _step == 0 ? null : () => setState(() => _step = 0),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    child: _step == 0 ? _modeStep() : _mapStep(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _step == 0
                              ? '${_mode.label}${_mode == GameMode.ffa ? ' · $_players players' : ''} · AI ${_ai.label}'
                              : _map?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle(16, color: Palette.boneDim, weight: FontWeight.w600, spacing: 1),
                        ),
                      ),
                      if (_step == 1) ...[
                        PlateButton(
                          label: 'Random map',
                          icon: Icons.casino_rounded,
                          style: PlateStyle.secondary,
                          height: 50,
                          fontSize: 17,
                          onPressed: _randomMap,
                        ),
                        const SizedBox(width: 12),
                      ],
                      PlateButton(
                        label: _step == 0 ? 'Choose map' : 'Choose hero',
                        icon: Icons.arrow_forward_rounded,
                        height: 50,
                        fontSize: 18,
                        onPressed: _next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeStep() => LayoutBuilder(
    key: const ValueKey('mode'),
    builder: (context, c) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Mode'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: c.maxWidth > 900 ? 96 : 92,
                  children: [
                    for (final m in GameMode.values)
                      _ModeTile(
                        mode: m,
                        players: m == GameMode.ffa ? _ffaPlayers : m.fixedPlayers,
                        selected: _mode == m,
                        onTap: () => setState(() => _mode = m),
                      ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _mode != GameMode.ffa
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Text('PLAYERS', style: titleStyle(14, color: Palette.boneDim, spacing: 1.4)),
                              const SizedBox(width: 12),
                              for (final n in [2, 3, 4, 5]) ...[
                                ChoiceTile(
                                  label: '$n',
                                  minWidth: 56,
                                  selected: _ffaPlayers == n,
                                  onTap: () => setState(() => _ffaPlayers = n),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('AI difficulty'),
                for (final l in AiLevel.values) ...[
                  ChoiceTile(
                    label: l.label,
                    sub: l.blurb,
                    accent: l.color,
                    selected: _ai == l,
                    height: 50,
                    onTap: () => setState(() => _ai = l),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _mapStep() {
    final maps = _maps;
    return Column(
      key: const ValueKey('map'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: SectionLabel('${maps.length} maps for ${_mode.label}${_mode == GameMode.ffa ? ' · $_players players' : ''}'),
        ),
        Expanded(
          child: ListView.separated(
            controller: _mapScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            itemCount: maps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => MapCard(map: maps[i], selected: maps[i] == _map, onTap: () => setState(() => _map = maps[i])),
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.players, required this.selected, required this.onTap});
  final GameMode mode;
  final int players;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Palette.bgDeep : Palette.bone;
    final shape = ChamferBorder(
      cut: 9,
      side: BorderSide(color: selected ? Palette.gold : Palette.bone.withValues(alpha: 0.2), width: selected ? 2 : 1),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label}. ${mode.blurb}',
      child: Material(
        color: selected ? Palette.bone : Palette.panel,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
            child: Row(
              children: [
                SizedBox(width: 54, height: 40, child: CustomPaint(painter: _SeatsGlyph(mode, players, selected))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mode.label.toUpperCase(), style: titleStyle(19, color: fg)),
                      const SizedBox(height: 2),
                      Text(
                        mode.blurb,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(12.5, color: selected ? const Color(0xFF3A3A36) : Palette.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny diagram of the seats: blue dots for your side, red for the other, coloured for FFA.
class _SeatsGlyph extends CustomPainter {
  _SeatsGlyph(this.mode, this.players, this.selected);
  final GameMode mode;
  final int players;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.16;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = selected ? Palette.bgDeep : Palette.bone.withValues(alpha: 0.6);
    void dot(Offset o, Color c) {
      canvas.drawCircle(o, r, Paint()..color = c);
      canvas.drawCircle(o, r, rim);
    }

    if (mode == GameMode.ffa) {
      final c = size.center(Offset.zero);
      for (var i = 0; i < players; i++) {
        final a = -math.pi / 2 + i * 2 * math.pi / players;
        dot(c + Offset(math.cos(a), math.sin(a)) * size.height * 0.34, Palette.seats[i]);
      }
      return;
    }
    final side = players ~/ 2;
    for (var i = 0; i < side; i++) {
      final y = size.height * (side == 1 ? 0.5 : 0.2 + 0.6 * i / (side - 1));
      dot(Offset(size.width * 0.2, y), Palette.teamA[i]);
      dot(Offset(size.width * 0.8, y), Palette.teamB[i]);
    }
    final v = Paint()
      ..strokeWidth = 1.4
      ..color = selected ? Palette.bgDeep : Palette.bone.withValues(alpha: 0.5);
    canvas.drawLine(Offset(size.width / 2, size.height * 0.15), Offset(size.width / 2, size.height * 0.85), v);
  }

  @override
  bool shouldRepaint(_SeatsGlyph old) => old.mode != mode || old.players != players || old.selected != selected;
}
