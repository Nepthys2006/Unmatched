/// Hero select: a grid of hex portraits; the chosen hero's identity card, miniature, sidekick
/// tokens, stats and special ability beside it. AI heroes are random.
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
import 'vs_screen.dart';

class HeroSelectScreen extends StatefulWidget {
  const HeroSelectScreen({super.key, required this.mode, required this.players, required this.map, required this.ai})
    : pickOnly = false,
      initial = null,
      taken = const {};

  /// Multiplayer lobby: choose a hero and return its id (Navigator.pop) instead of starting a
  /// match. Heroes in [taken] are already someone else's.
  const HeroSelectScreen.pick({super.key, required this.map, this.initial, this.taken = const {}})
    : pickOnly = true,
      mode = GameMode.duel,
      players = 2,
      ai = AiLevel.medium;

  final GameMode mode;
  final int players;
  final MapDef map;
  final AiLevel ai;
  final bool pickOnly;
  final String? initial;
  final Set<String> taken;
  @override
  State<HeroSelectScreen> createState() => _HeroSelectScreenState();
}

class _HeroSelectScreenState extends State<HeroSelectScreen> {
  late final List<HeroDef> _heroes = context.services.data.heroes.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  late HeroDef _hero = widget.initial != null && context.services.data.heroes.containsKey(widget.initial)
      ? context.services.data.hero(widget.initial!)
      : _free[math.Random().nextInt(_free.length)];
  List<HeroDef> get _free => _heroes.where((h) => !widget.taken.contains(h.id)).toList();
  final _grid = ScrollController();

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  void _random() {
    final others = _free.where((h) => h != _hero).toList();
    setState(() => _hero = others[math.Random().nextInt(others.length)]);
    final i = _heroes.indexOf(_hero);
    if (_grid.hasClients) {
      final perRow = _perRow;
      final row = i ~/ perRow;
      _grid.animateTo(
        (row * 92.0 - 60).clamp(0, _grid.position.maxScrollExtent),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  int _perRow = 4;

  void _fight() {
    if (widget.pickOnly) {
      Navigator.of(context).pop(_hero.id);
      return;
    }
    final data = context.services.data;
    final config = MatchConfig(
      mode: widget.mode,
      players: widget.players,
      map: widget.map,
      ai: widget.ai,
      heroIds: MatchConfig.randomLineup(data, _hero.id, widget.players),
    );
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => VsScreen(config: config),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = hexColor(_hero.color);
    return Scaffold(
      body: TableBackground(
        tint: color,
        child: SafeArea(
          child: Column(
            children: [
              ScreenHeader(title: 'Choose your hero', step: '3 / 3'),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 42, child: _gridView()),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 58,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                          child: _HeroDetail(key: ValueKey(_hero.id), hero: _hero),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
                child: Row(
                  children: [
                    const Icon(Icons.shuffle_rounded, color: Palette.muted, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.pickOnly
                            ? (widget.taken.contains(_hero.id) ? '${_hero.name} is already taken in this lobby' : 'Choose your hero · ${widget.map.name}')
                            : '${widget.players - 1} AI ${widget.players == 2 ? 'opponent is' : 'heroes are'} picked at random · ${widget.map.name} · AI ${widget.ai.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(14, color: Palette.muted),
                      ),
                    ),
                    PlateButton(
                      label: 'Random',
                      icon: Icons.casino_rounded,
                      style: PlateStyle.secondary,
                      height: 50,
                      fontSize: 17,
                      onPressed: _random,
                    ),
                    const SizedBox(width: 12),
                    PlateButton(
                      label: widget.pickOnly ? 'Choose ${_hero.name}' : 'Fight as ${_hero.name}',
                      icon: Icons.bolt_rounded,
                      style: PlateStyle.hero,
                      color: color,
                      point: true,
                      height: 50,
                      fontSize: 18,
                      onPressed: widget.pickOnly && widget.taken.contains(_hero.id) ? null : _fight,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridView() => LayoutBuilder(
    builder: (context, c) {
      const tile = 84.0;
      _perRow = math.max(3, (c.maxWidth / tile).floor());
      return Scrollbar(
        controller: _grid,
        child: GridView.builder(
          controller: _grid,
          padding: const EdgeInsets.only(right: 10, bottom: 8, top: 4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _perRow, mainAxisExtent: 92, crossAxisSpacing: 4),
          itemCount: _heroes.length,
          itemBuilder: (_, i) {
            final h = _heroes[i];
            final sel = h == _hero;
            return Semantics(
              button: true,
              selected: sel,
              label: h.name,
              child: InkWell(
                onTap: () => setState(() => _hero = h),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: ShapeDecoration(
                        shape: const HexBorder(),
                        shadows: sel ? [BoxShadow(color: readable(hexColor(h.color)).withValues(alpha: 0.75), blurRadius: 16)] : const [],
                      ),
                      child: Avatar(
                        h.avatar,
                        size: 58,
                        ring: sel ? Palette.bone : Palette.bone.withValues(alpha: 0.25),
                        ringWidth: sel ? 2.5 : 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      h.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: titleStyle(11.5, color: sel ? Palette.bone : Palette.boneDim, weight: FontWeight.w700, spacing: 0.4),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _HeroDetail extends StatelessWidget {
  const _HeroDetail({super.key, required this.hero});
  final HeroDef hero;

  @override
  Widget build(BuildContext context) {
    final color = hexColor(hero.color);
    return LayoutBuilder(
      builder: (context, c) {
        final cardH = math.min(c.maxHeight - 8, 330.0);
        final cardW = cardH * cardAspect;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The miniature stands behind the text, lit in the hero's colour.
            Positioned(
              right: -10,
              top: 0,
              bottom: 0,
              width: c.maxWidth * 0.42,
              child: IgnorePointer(
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, 0.75, 1],
                  ).createShader(r),
                  child: Opacity(
                    opacity: 0.32,
                    child: Image.asset(hero.mini, fit: BoxFit.contain, alignment: Alignment.bottomRight, gaplessPlayback: true),
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  button: true,
                  label: 'Read ${hero.name}\'s character card',
                  child: GestureDetector(
                    onTap: () => showCardZoom<void>(context, hero.identity, caption: hero.description),
                    child: Stack(
                      children: [
                        CardImage(hero.identity, width: cardW),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const ShapeDecoration(color: Color(0xCC0E0F12), shape: HexBorder()),
                            child: const Icon(Icons.zoom_in_rounded, color: Palette.bone, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 4, 30, 4),
                          decoration: ShapeDecoration(
                            color: plateColor(color),
                            shape: PlateBorder(side: BorderSide(color: Palette.bone.withValues(alpha: 0.5))),
                          ),
                          child: Text(
                            hero.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle(26, color: Colors.white, spacing: 1),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hero.set,
                          style: bodyStyle(13, color: Palette.muted, style: FontStyle.italic),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Stat(icon: HeartBadge(hero.hero.hp, size: 26), label: 'Health'),
                            _Stat(icon: _Num('${hero.move}'), label: 'Move'),
                            _Stat(
                              icon: Icon(
                                hero.hero.attack == AttackType.ranged ? Icons.my_location_rounded : Icons.sports_martial_arts_rounded,
                                color: Palette.bone,
                                size: 22,
                              ),
                              label: hero.hero.attack == AttackType.ranged ? 'Ranged' : 'Melee',
                            ),
                            _Stat(icon: _Num('${hero.deckSize}'), label: 'Cards'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('SPECIAL ABILITY', style: titleStyle(13, color: Palette.boneDim, spacing: 1.6)),
                        const SizedBox(height: 3),
                        Text(hero.ability, style: bodyStyle(14.5)),
                        if (hero.sidekicks.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            hero.sidekicks.length == 1 ? 'SIDEKICK' : 'SIDEKICKS',
                            style: titleStyle(13, color: Palette.boneDim, spacing: 1.6),
                          ),
                          const SizedBox(height: 6),
                          for (final s in hero.sidekicks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Avatar(hero.token(s.id), size: 40, hex: false, ring: Palette.bone.withValues(alpha: 0.5), ringWidth: 1.2),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: s.name.toUpperCase(), style: titleStyle(15)),
                                          TextSpan(
                                            text:
                                                '   ${s.count > 1 ? '×${s.count} · ' : ''}${s.hp} HP · ${s.attack == AttackType.ranged ? 'ranged' : 'melee'}',
                                            style: bodyStyle(13.5, color: Palette.boneDim),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});
  final Widget icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.only(left: 8, right: 12),
    decoration: ShapeDecoration(
      color: Palette.bgDeep.withValues(alpha: 0.8),
      shape: ChamferBorder(cut: 6, side: BorderSide(color: Palette.bone.withValues(alpha: 0.18))),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 7),
        Text(label.toUpperCase(), style: titleStyle(13, color: Palette.boneDim, spacing: 1)),
      ],
    ),
  );
}

class _Num extends StatelessWidget {
  const _Num(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: titleStyle(22));
}
