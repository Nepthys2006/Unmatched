/// Pieces of the player plates, after Unmatched: Digital Edition: the hero's diamond emblem with
/// its seat number, the stat cells on the plate (health, deck, move), and the companions row (the
/// hero's sidekicks, pets and fellow heroes, each with its health).
library;

import 'package:flutter/material.dart' hide Card;

import '../../engine/defs.dart' show HeroDef;
import '../../engine/state.dart';
import '../shapes.dart';
import '../theme.dart';

/// The hero's portrait in a diamond rimmed in the player's colour (gold on their turn), with the
/// seat number on a small bone diamond at the bottom point.
class HeroEmblem extends StatelessWidget {
  const HeroEmblem({
    super.key,
    required this.image,
    required this.color,
    required this.size,
    this.seat,
    this.active = false,
    this.grey = false,
  });

  final String image;
  final Color color;
  final double size;

  /// 1-based turn order; null hides the badge.
  final int? seat;
  final bool active;
  final bool grey;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final rim = active ? Palette.gold : color;
    Widget face = Image.asset(
      image,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      cacheWidth: (size * dpr) <= 128 ? 128 : 256,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const ColoredBox(color: Palette.panelHi),
    );
    if (grey) face = ColorFiltered(colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation), child: face);
    final badge = size * 0.36;
    final drop = seat == null ? 0.0 : badge * 0.3;
    return SizedBox(
      width: size,
      height: size + drop,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // rim and shadow (a gold halo while it is this player's turn)
          Positioned.fill(
            bottom: drop,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: Palette.bgDeep,
                shape: DiamondBorder(
                  side: BorderSide(color: rim, width: size * 0.055),
                ),
                shadows: [
                  const BoxShadow(color: Color(0xAA000000), blurRadius: 8, offset: Offset(0, 3)),
                  if (active) BoxShadow(color: Palette.gold.withValues(alpha: 0.55), blurRadius: 14, spreadRadius: 1),
                ],
              ),
            ),
          ),
          Positioned.fill(
            bottom: drop,
            child: Padding(
              padding: EdgeInsets.all(size * 0.075),
              child: ClipPath(
                clipper: const ShapeBorderClipper(shape: DiamondBorder()),
                child: face,
              ),
            ),
          ),
          if (seat != null)
            Positioned(
              left: (size - badge) / 2,
              bottom: 0,
              width: badge,
              height: badge,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: Palette.bone,
                  shape: DiamondBorder(
                    side: BorderSide(color: Palette.bgDeep, width: badge * 0.08),
                  ),
                ),
                child: Center(
                  child: Text('$seat', style: titleStyle(badge * 0.5, color: Palette.bgDeep, spacing: 0)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One square on the plate's right end: an icon over a number (deck, move), or a heart with the
/// health in it. Numbers pop when they change.
class StatCell extends StatelessWidget {
  const StatCell({
    super.key,
    required this.value,
    required this.size,
    required this.tooltip,
    this.icon,
    this.heart = false,
    this.low = false,
  });
  final int value;
  final double size;
  final String tooltip;
  final IconData? icon;

  /// Health: a red heart with the number in it.
  final bool heart;

  /// Nearly out (health): a darker heart.
  final bool low;

  @override
  Widget build(BuildContext context) {
    final Widget content = heart
        ? HeartBadge(value, size: size * 0.74, color: low ? const Color(0xFFA3141D) : Palette.heart)
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: size * 0.32, color: Palette.boneDim),
              Text('$value', style: titleStyle(size * 0.38, color: Colors.white, spacing: 0)),
            ],
          );
    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xE60A0D13),
          border: Border(left: BorderSide(color: Palette.gold.withValues(alpha: 0.35))),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, a) => ScaleTransition(
            scale: Tween(begin: 1.35, end: 1.0).animate(a),
            child: FadeTransition(opacity: a, child: child),
          ),
          child: KeyedSubtree(
            key: ValueKey(value),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

/// The player's other fighters: further heroes (the Raptors, Cloak & Dagger, the Wayward
/// Sisters), then sidekicks and pets, each as its token in a small diamond with its health. A big
/// pack of one-health sidekicks (Outlaws, Squirrels) is one chip with how many are left.
class CompanionsRow extends StatelessWidget {
  const CompanionsRow({super.key, required this.player, required this.color, this.size = 24});
  final Player player;
  final Color color;
  final double size;

  /// The fighters shown, grouped: one entry per fighter, or one per pack.
  static List<List<Fighter>> groups(Player player) {
    final heroes = player.heroes.toList();
    final others = [...heroes.skip(1), ...player.fighters.where((f) => f.isSidekick && (!f.reserve || f.defeated))];
    final out = <List<Fighter>>[];
    for (final f in others) {
      final pack = f.isSidekick && f.def.count > 2;
      final at = pack ? out.indexWhere((g) => g.first.def == f.def) : -1;
      if (at >= 0) {
        out[at].add(f);
      } else {
        out.add([f]);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final all = groups(player);
    if (all.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: [for (final g in all) CompanionChip(group: g, color: color, size: size)],
    );
  }
}

/// One companion (or a pack of them) with its health.
class CompanionChip extends StatelessWidget {
  const CompanionChip({super.key, required this.group, required this.color, required this.size});
  final List<Fighter> group;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final f = group.first;
    final pack = group.length > 1 || f.def.count > 2;
    final alive = group.where((x) => !x.defeated).length;
    final out = pack ? alive == 0 : f.defeated;
    final hero = f.owner.hero;
    final image = f.isHero ? hero.avatar : hero.token(f.def.id);
    final tip = pack ? '${f.kind}: $alive of ${group.length} left' : '${f.name}: ${f.defeated ? 'defeated' : '${f.hp} health'}';
    return Tooltip(
      message: tip,
      child: Opacity(
        opacity: out ? 0.5 : 1,
        child: Container(
          height: size,
          padding: EdgeInsets.only(right: size * 0.22),
          decoration: ShapeDecoration(
            color: const Color(0xD90A0D13),
            shape: PlateBorder(slant: 0.25, side: BorderSide(color: color.withValues(alpha: 0.55))),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HeroEmblem(image: image, color: color, size: size, grey: out),
              const SizedBox(width: 3),
              if (pack)
                Text('$alive/${group.length}', style: titleStyle(size * 0.5, spacing: 0))
              else if (f.defeated)
                Icon(Icons.close_rounded, size: size * 0.6, color: Palette.muted)
              else
                HeartBadge(f.hp, size: size * 0.82, color: f.hp <= 2 ? const Color(0xFFA3141D) : Palette.heart),
            ],
          ),
        ),
      ),
    );
  }
}

/// A hero's special ability split into its printed name, when it has one ("UNCONTAINABLE POWER"),
/// and its text.
(String?, String) abilityParts(HeroDef hero) {
  final lines = hero.ability.trim().split('\n');
  final name = lines.length > 1 && lines.first.length <= 40 && !lines.first.endsWith('.') ? lines.first : null;
  return (name, (name == null ? lines : lines.skip(1)).join(' '));
}

/// The hero's special ability on the plate: a gold star and the ability's name (or just the star
/// when [iconOnly]); a tap shows the whole text above it.
class AbilityChip extends StatelessWidget {
  const AbilityChip({super.key, required this.hero, required this.size, this.maxWidth = 140, this.iconOnly = false});
  final HeroDef hero;
  final double size;
  final double maxWidth;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final (name, text) = abilityParts(hero);
    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      preferBelow: false,
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(10),
      richMessage: TextSpan(
        children: [
          TextSpan(
            text: '${(name ?? 'Special ability').toUpperCase()}\n',
            style: titleStyle(14, color: Palette.gold, spacing: 0.8),
          ),
          TextSpan(text: text, style: bodyStyle(13)),
        ],
      ),
      child: Container(
        height: size,
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: EdgeInsets.symmetric(horizontal: size * 0.3),
        decoration: ShapeDecoration(
          color: const Color(0xD90A0D13),
          shape: PlateBorder(slant: 0.25, side: BorderSide(color: Palette.gold.withValues(alpha: 0.7))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: size * 0.6, color: Palette.gold),
            if (!iconOnly) ...[
              SizedBox(width: size * 0.15),
              Flexible(
                child: Text(
                  (name ?? 'Ability').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle(size * 0.46, color: Palette.bone, spacing: 0.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
