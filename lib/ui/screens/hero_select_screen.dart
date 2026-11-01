/// Hero select: a grid of hex portraits; the chosen hero's identity card, miniature, sidekick
/// tokens, stats and special ability beside it. The AI heroes are random unless you choose them.
/// Tapping the hero's card opens a read-only viewer of its whole deck.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/ai.dart';
import '../../engine/defs.dart';
import '../match/match_config.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'deck_viewer.dart';
import 'hero_grid.dart';
import 'vs_screen.dart';

class HeroSelectScreen extends StatefulWidget {
  const HeroSelectScreen({
    super.key,
    required this.mode,
    required this.players,
    required this.map,
    required this.ai,
    this.umccc = false,
  }) : pickOnly = false,
       initial = null,
       taken = const {},
       title = 'Choose your hero',
       choose = '';

  /// Multiplayer lobby: choose a hero and return its id (Navigator.pop) instead of starting a
  /// match. Heroes in [taken] are already someone else's. [title] and [choose] reword the screen
  /// when the host picks for an AI seat ("Choose Achilles for the AI").
  const HeroSelectScreen.pick({
    super.key,
    required this.map,
    this.initial,
    this.taken = const {},
    this.title = 'Choose your hero',
    this.choose = '',
  }) : pickOnly = true,
       mode = GameMode.duel,
       players = 2,
       ai = AiLevel.medium,
       umccc = false;

  final GameMode mode;
  final int players;
  final MapDef map;
  final AiLevel ai;
  final bool umccc;
  final bool pickOnly;
  final String? initial;
  final Set<String> taken;
  final String title;
  final String choose;
  @override
  State<HeroSelectScreen> createState() => _HeroSelectScreenState();
}

class _HeroSelectScreenState extends State<HeroSelectScreen> {
  late final List<HeroDef> _heroes =
      context.services.data.heroes.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  late HeroDef _hero =
      widget.initial != null &&
          context.services.data.heroes.containsKey(widget.initial)
      ? context.services.data.hero(widget.initial!)
      : _free[math.Random().nextInt(_free.length)];
  List<HeroDef> get _free =>
      _heroes.where((h) => !widget.taken.contains(h.id)).toList();
  final _gridKey = GlobalKey<HeroGridState>();

  /// The AI seats: "Random" draws them when the match starts; "Choose hero" lets you fill any of
  /// them (an empty one is still drawn at random).
  bool _aiChoose = false;
  late final List<String?> _aiPicks = List.filled(
    math.max(0, widget.players - 1),
    null,
  );

  void _select(HeroDef h) {
    setState(() => _hero = h);
    // An AI seat can't play the hero you just took: it goes back to random.
    final i = _aiPicks.indexOf(h.id);
    if (i >= 0) {
      setState(() => _aiPicks[i] = null);
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            // At the top, so it never covers the opponent bar or the Fight button.
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(20, 0, 20, math.max(0, MediaQuery.sizeOf(context).height - 130)),
            dismissDirection: DismissDirection.up,
            duration: const Duration(seconds: 3),
            content: Text(
              '${h.name} is yours now, so ${_aiSeatName(i)} goes back to a random hero.',
            ),
          ),
        );
    }
  }

  void _random() {
    final others = _free.where((h) => h != _hero).toList();
    if (others.isEmpty) return;
    _select(others[math.Random().nextInt(others.length)]);
    _gridKey.currentState?.reveal(_hero);
  }

  String _aiSeatName(int slot) =>
      widget.players == 2 ? 'the AI opponent' : 'AI seat ${slot + 1}';

  Future<void> _setAiMode(bool choose) async {
    if (choose == _aiChoose) return;
    setState(() => _aiChoose = choose);
    // Choosing opens the same hero grid and search to pick from.
    if (choose && _aiPicks.every((p) => p == null)) {
      await _pickAi(0);
      if (mounted && _aiPicks.every((p) => p == null)) setState(() => _aiChoose = false);
    }
  }

  Future<void> _pickAi(int slot) async {
    final data = context.services.data;
    final blocked = {
      _hero.id,
      for (var i = 0; i < _aiPicks.length; i++)
        if (i != slot && _aiPicks[i] != null) _aiPicks[i]!,
    };
    final r = await showAiHeroPicker(
      context,
      heroes: _heroes,
      initial: _aiPicks[slot] == null ? null : data.hero(_aiPicks[slot]!),
      blocked: blocked,
      seat: widget.players == 2 ? 'Your opponent' : _aiSeatLabel(slot),
    );
    if (r == null || !mounted) return;
    setState(() => _aiPicks[slot] = r.id);
  }

  /// "AI 2 · Foe", "AI 3 · Ally"... in team modes; "AI 2" otherwise.
  String _aiSeatLabel(int slot) {
    final seat = slot + 1;
    if (!widget.mode.isTeams) return 'AI ${slot + 1}';
    return 'AI ${slot + 1} · ${seat.isEven ? 'Ally' : 'Foe'}';
  }

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
      umccc: widget.umccc,
      // Random seats are drawn now, when the match starts, never the hero you play.
      heroIds: MatchConfig.lineup(
        data,
        _hero.id,
        widget.players,
        chosen: _aiChoose ? _aiPicks : const [],
      ),
    );
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => VsScreen(config: config),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = hexColor(_hero.color);
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 820;
    // A narrow window (a browser tab, a tablet in portrait): the grid above, the hero below.
    final stacked = width < 700 && MediaQuery.sizeOf(context).height > width;
    final subtitle =
        '${widget.map.name} · AI ${widget.umccc ? umcccLabel : widget.ai.label}';
    final info = widget.pickOnly
        ? Row(
            children: [
              const Icon(Icons.shuffle_rounded, color: Palette.muted, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.taken.contains(_hero.id)
                      ? '${_hero.name} is already taken in this lobby'
                      : '${widget.title} · ${widget.map.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle(14, color: Palette.muted),
                ),
              ),
            ],
          )
        : _OpponentBar(
            count: widget.players - 1,
            choose: _aiChoose,
            picks: [
              for (final id in _aiPicks)
                id == null ? null : context.services.data.hero(id),
            ],
            labelFor: (i) => widget.players == 2 ? 'Opponent' : _aiSeatLabel(i),
            onMode: _setAiMode,
            onSlot: _pickAi,
          );
    final buttons = <Widget>[
      if (narrow)
        HexButton(
          key: const ValueKey('hero-random'),
          icon: Icons.casino_rounded,
          tooltip: 'Random hero',
          size: 50,
          onPressed: _random,
        )
      else
        PlateButton(
          key: const ValueKey('hero-random'),
          label: 'Random',
          icon: Icons.casino_rounded,
          style: PlateStyle.secondary,
          height: 50,
          fontSize: 17,
          onPressed: _random,
        ),
      const SizedBox(width: 12),
      Flexible(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: stacked ? width : math.max(170, width * 0.34),
          ),
          child: PlateButton(
            label: widget.pickOnly
                ? 'Choose ${_hero.name}${widget.choose.isEmpty ? '' : ' ${widget.choose}'}'
                : 'Fight as ${_hero.name}',
            icon: Icons.bolt_rounded,
            style: PlateStyle.hero,
            color: color,
            point: true,
            height: 50,
            fontSize: 18,
            onPressed: widget.pickOnly && widget.taken.contains(_hero.id)
                ? null
                : _fight,
          ),
        ),
      ),
    ];
    final grid = HeroGrid(
      key: _gridKey,
      heroes: _heroes,
      selected: _hero,
      onSelect: _select,
    );
    final detail = AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
      child: _HeroDetail(key: ValueKey(_hero.id), hero: _hero),
    );
    return Scaffold(
      // The phone's keyboard may cover the heroes while typing; it must not squash the layout.
      resizeToAvoidBottomInset: false,
      body: TableBackground(
        tint: color,
        child: SafeArea(
          child: Column(
            children: [
              ScreenHeader(
                title: widget.title,
                step: widget.pickOnly ? null : '3 / 3',
                trailing: widget.pickOnly || narrow
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          subtitle,
                          style: bodyStyle(14, color: Palette.muted),
                        ),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 4, child: grid),
                            const SizedBox(height: 8),
                            Expanded(flex: 5, child: detail),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 42, child: grid),
                            const SizedBox(width: 18),
                            Expanded(flex: 58, child: detail),
                          ],
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          info,
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: buttons,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: info),
                          const SizedBox(width: 12),
                          ...buttons,
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------- AI opponent

/// "AI opponent: Random | Choose hero", and under Choose the heroes picked so far, each with its
/// portrait and name (tap one to change it).
class _OpponentBar extends StatelessWidget {
  const _OpponentBar({
    required this.count,
    required this.choose,
    required this.picks,
    required this.labelFor,
    required this.onMode,
    required this.onSlot,
  });
  final int count;
  final bool choose;
  final List<HeroDef?> picks;
  final String Function(int slot) labelFor;
  final ValueChanged<bool> onMode;
  final ValueChanged<int> onSlot;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 820;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: ShapeDecoration(
        color: Palette.bgDeep.withValues(alpha: 0.7),
        shape: ChamferBorder(
          cut: 8,
          side: BorderSide(color: Palette.bone.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          Tooltip(
            message: count == 1 ? 'AI opponent' : '$count AI heroes',
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Palette.boneDim,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _ModeToggle(
                choose: choose,
                onChanged: onMode,
                short: narrow,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: choose
                  ? SingleChildScrollView(
                      key: const ValueKey('ai-slots'),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < count; i++)
                            _AiSlot(
                              key: ValueKey('ai-slot-$i'),
                              label: labelFor(i),
                              hero: picks[i],
                              onTap: () => onSlot(i),
                              showLabel: count > 1,
                            ),
                        ],
                      ),
                    )
                  : Align(
                      key: const ValueKey('ai-random-note'),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        count == 1
                            ? 'Picked at random when the match starts'
                            : '$count heroes picked at random when the match starts',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(13.5, color: Palette.muted),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.choose,
    required this.onChanged,
    required this.short,
  });
  final bool choose;
  final ValueChanged<bool> onChanged;
  final bool short;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool value, Key key) {
      final sel = choose == value;
      return Semantics(
        button: true,
        selected: sel,
        label: label,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: sel
                  ? Palette.gold.withValues(alpha: 0.26)
                  : Colors.transparent,
              shape: ChamferBorder(
                cut: 6,
                side: BorderSide(
                  color: sel ? Palette.gold : Colors.transparent,
                  width: 1.4,
                ),
              ),
            ),
            child: Text(
              label.toUpperCase(),
              style: titleStyle(
                13.5,
                color: sel ? Palette.bone : Palette.boneDim,
                spacing: 0.8,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        seg('Random', false, const ValueKey('ai-mode-random')),
        seg(
          short ? 'Choose' : 'Choose hero',
          true,
          const ValueKey('ai-mode-choose'),
        ),
      ],
    );
  }
}

class _AiSlot extends StatelessWidget {
  const _AiSlot({
    super.key,
    required this.label,
    required this.hero,
    required this.onTap,
    required this.showLabel,
  });
  final String label;
  final HeroDef? hero;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final h = hero;
    return Semantics(
      button: true,
      label: h == null
          ? '$label: random hero, tap to choose'
          : '$label: ${h.name}, tap to change',
      child: InkWell(
        onTap: onTap,
        customBorder: const ChamferBorder(cut: 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (h != null)
                Avatar(h.avatar, size: 40, ring: Palette.gold, ringWidth: 1.8)
              else
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    shape: HexBorder(
                      side: BorderSide(
                        color: Palette.bone.withValues(alpha: 0.35),
                      ),
                    ),
                    color: Palette.panel,
                  ),
                  child: Text(
                    '?',
                    style: titleStyle(20, color: Palette.boneDim),
                  ),
                ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showLabel)
                    Text(
                      label.toUpperCase(),
                      style: titleStyle(
                        10.5,
                        color: Palette.muted,
                        spacing: 0.8,
                      ),
                    ),
                  Text(
                    h == null ? 'RANDOM' : h.name.toUpperCase(),
                    style: titleStyle(
                      15,
                      color: h == null ? Palette.boneDim : Palette.bone,
                      spacing: 0.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded, color: Palette.muted, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the AI picker returns: [id] is the hero chosen, or null for "random".
class AiHeroPick {
  const AiHeroPick(this.id);
  final String? id;
}

/// The hero grid and search in a popup, to choose the hero an AI plays. Null when it is closed
/// without choosing (Esc, a click outside or the X).
Future<AiHeroPick?> showAiHeroPicker(
  BuildContext context, {
  required List<HeroDef> heroes,
  required HeroDef? initial,
  required Set<String> blocked,
  required String seat,
}) {
  return showGeneralDialog<AiHeroPick>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0xCC000000),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) => _AiHeroPicker(
      heroes: heroes,
      initial: initial,
      blocked: blocked,
      seat: seat,
    ),
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(
        parent: a,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(c),
          child: child,
        ),
      );
    },
  );
}

class _AiHeroPicker extends StatefulWidget {
  const _AiHeroPicker({
    required this.heroes,
    required this.initial,
    required this.blocked,
    required this.seat,
  });
  final List<HeroDef> heroes;
  final HeroDef? initial;
  final Set<String> blocked;
  final String seat;
  @override
  State<_AiHeroPicker> createState() => _AiHeroPickerState();
}

class _AiHeroPickerState extends State<_AiHeroPicker> {
  late HeroDef? _sel = widget.initial;

  void _close([AiHeroPick? r]) => Navigator.of(context).pop(r);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final h = _sel;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(760, size.width - 20),
                  maxHeight: math.min(660, size.height - 20),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Material(
                    type: MaterialType.transparency,
                    child: Panel(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      cut: 14,
                      highlight: true,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${widget.seat.toUpperCase()} · CHOOSE A HERO',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle(19, spacing: 1.2),
                                ),
                              ),
                              Semantics(
                                button: true,
                                label: 'Close',
                                child: InkResponse(
                                  key: const ValueKey('ai-picker-close'),
                                  onTap: _close,
                                  radius: 24,
                                  child: const SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Palette.bone,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: HeroGrid(
                              keyPrefix: 'ai-hero',
                              heroes: widget.heroes,
                              selected: h,
                              blocked: widget.blocked,
                              onSelect: (x) => setState(() => _sel = x),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _summary(h),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(HeroDef? h) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final info = h == null
        ? Text(
            'Pick a hero for the AI to play, or leave it to chance.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(14, color: Palette.muted),
          )
        : Row(
            children: [
              Avatar(h.avatar, size: 44, ring: Palette.gold, ringWidth: 1.8),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      h.name.toUpperCase(),
                      key: const ValueKey('ai-picker-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle(18, spacing: 0.8),
                    ),
                    Text(
                      '${h.hero.hp} HP · move ${h.move} · ${h.hero.attack == AttackType.ranged ? 'ranged' : 'melee'} · ${h.set}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: bodyStyle(12.5, color: Palette.boneDim),
                    ),
                  ],
                ),
              ),
            ],
          );
    final random = PlateButton(
      key: const ValueKey('ai-picker-random'),
      label: 'Random',
      icon: Icons.casino_rounded,
      style: PlateStyle.secondary,
      height: 46,
      fontSize: 16,
      onPressed: () => _close(const AiHeroPick(null)),
    );
    final choose = PlateButton(
      key: const ValueKey('ai-picker-choose'),
      label: h == null ? 'Choose' : (narrow ? 'Choose' : 'Choose ${h.name}'),
      icon: Icons.check_rounded,
      style: PlateStyle.confirm,
      height: 46,
      fontSize: 16,
      onPressed: h == null ? null : () => _close(AiHeroPick(h.id)),
    );
    return Row(
      children: [
        Expanded(child: info),
        const SizedBox(width: 10),
        random,
        const SizedBox(width: 10),
        Flexible(child: choose),
      ],
    );
  }
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
                    child: Image.asset(
                      hero.mini,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomRight,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Semantics(
                      button: true,
                      label:
                          "See all ${hero.deckSize} cards in ${hero.name}'s deck",
                      child: GestureDetector(
                        key: const ValueKey('hero-card'),
                        onTap: () => showDeckViewer(context, hero),
                        child: CardImage(hero.identity, width: cardW),
                      ),
                    ),
                    // What tapping the card does: it opens the deck.
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: IgnorePointer(
                        child: Container(
                          height: 26,
                          padding: const EdgeInsets.only(left: 6, right: 9),
                          decoration: ShapeDecoration(
                            color: const Color(0xDD0A0D13),
                            shape: ChamferBorder(
                              cut: 5,
                              side: BorderSide(
                                color: Palette.gold.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.style_rounded,
                                color: Palette.gold,
                                size: 15,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'DECK · ${hero.deckSize}',
                                style: titleStyle(12, spacing: 0.6),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Semantics(
                        button: true,
                        label: "Read ${hero.name}'s character card",
                        child: GestureDetector(
                          key: const ValueKey('hero-card-zoom'),
                          onTap: () => showCardZoom<void>(
                            context,
                            hero.identity,
                            caption: hero.description,
                          ),
                          child: Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: const ShapeDecoration(
                              color: Color(0xCC0A0D13),
                              shape: HexBorder(),
                            ),
                            child: const Icon(
                              Icons.zoom_in_rounded,
                              color: Palette.bone,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                            shape: PlateBorder(
                              side: BorderSide(
                                color: Palette.bone.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: Text(
                            hero.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle(
                              26,
                              color: Colors.white,
                              spacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hero.set,
                          style: bodyStyle(
                            13,
                            color: Palette.muted,
                            style: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Stat(
                              icon: HeartBadge(hero.hero.hp, size: 26),
                              label: 'Health',
                            ),
                            _Stat(icon: _Num('${hero.move}'), label: 'Move'),
                            _Stat(
                              icon: Icon(
                                hero.hero.attack == AttackType.ranged
                                    ? Icons.my_location_rounded
                                    : Icons.sports_martial_arts_rounded,
                                color: Palette.bone,
                                size: 22,
                              ),
                              label: hero.hero.attack == AttackType.ranged
                                  ? 'Ranged'
                                  : 'Melee',
                            ),
                            _Stat(
                              icon: _Num('${hero.deckSize}'),
                              label: 'Cards',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'SPECIAL ABILITY',
                          style: titleStyle(
                            13,
                            color: Palette.boneDim,
                            spacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(hero.ability, style: bodyStyle(14.5)),
                        if (hero.sidekicks.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            hero.sidekicks.length == 1
                                ? 'SIDEKICK'
                                : 'SIDEKICKS',
                            style: titleStyle(
                              13,
                              color: Palette.boneDim,
                              spacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final s in hero.sidekicks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Avatar(
                                    hero.token(s.id),
                                    size: 40,
                                    hex: false,
                                    ring: Palette.bone.withValues(alpha: 0.5),
                                    ringWidth: 1.2,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: s.name.toUpperCase(),
                                            style: titleStyle(15),
                                          ),
                                          TextSpan(
                                            text:
                                                '   ${s.count > 1 ? '×${s.count} · ' : ''}${s.hp} HP · ${s.attack == AttackType.ranged ? 'ranged' : 'melee'}',
                                            style: bodyStyle(
                                              13.5,
                                              color: Palette.boneDim,
                                            ),
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
      shape: ChamferBorder(
        cut: 6,
        side: BorderSide(color: Palette.bone.withValues(alpha: 0.18)),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: titleStyle(13, color: Palette.boneDim, spacing: 1),
        ),
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
