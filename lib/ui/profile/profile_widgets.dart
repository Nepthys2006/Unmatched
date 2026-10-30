/// Pieces shared by the player profile, the Active Players list and the match invite: the MMR
/// badge, the PvP / PvE win rates, the main-hero showcase and the presence status.
library;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../../net/profile_stats.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

/// The colour a rating tier is drawn in. Always paired with the tier's name and the number, so
/// colour is never the only signal.
Color tierColor(MmrTier t) => switch (t) {
  MmrTier.rookie => Palette.muted,
  MmrTier.duelist => Palette.bone,
  MmrTier.veteran => Palette.gold,
  MmrTier.champion => Palette.confirmHi,
  MmrTier.legend => const Color(0xFF5BB6F5),
  MmrTier.immortal => const Color(0xFFFF6B5E),
};

/// How a presence status reads: colour and label. Unknown values count as idle.
({Color color, String label, String short}) presenceStyle(String status) => switch (status) {
  'matching' => (color: Palette.gold, label: 'Matching', short: 'MATCHING'),
  'inGame' => (color: const Color(0xFF10B981), label: 'In game', short: 'IN GAME'),
  _ => (color: Palette.boneDim, label: 'Online', short: 'ONLINE'),
};

/// A hero's portrait in a hex frame ringed in the hero's colour; a lettered hex when the player
/// has no main hero yet.
class HeroAvatar extends StatelessWidget {
  const HeroAvatar({super.key, required this.hero, required this.size, this.fallbackLetter = '?'});
  final HeroDef? hero;
  final double size;
  final String fallbackLetter;

  @override
  Widget build(BuildContext context) {
    final h = hero;
    if (h != null) return Avatar(h.avatar, size: size, ring: readable(hexColor(h.color)), ringWidth: size > 50 ? 2.4 : 1.8);
    return Container(
      width: size * 1.12,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: Palette.panelHi,
        shape: HexBorder(side: BorderSide(color: Palette.line, width: size > 50 ? 2.4 : 1.8)),
      ),
      child: Text(fallbackLetter.toUpperCase(), style: titleStyle(size * 0.46, color: Palette.boneDim)),
    );
  }
}

/// A small tag: matching / in game / online.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = presenceStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: ShapeDecoration(
        color: s.color.withValues(alpha: 0.14),
        shape: ChamferBorder(cut: 4, side: BorderSide(color: s.color.withValues(alpha: 0.6))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(s.short, style: titleStyle(10.5, color: s.color, spacing: 0.8)),
        ],
      ),
    );
  }
}

/// The rating as an angled plate: "MMR 1042" in the tier's colour with the tier name. For lists
/// and the invite; [MmrBadge] is the big hex for the profile.
class MmrChip extends StatelessWidget {
  const MmrChip(this.profile, {super.key});
  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = tierColor(profile.tier);
    return Semantics(
      label: profile.ranked ? 'Rating ${profile.mmr}, ${profile.tier.label}' : 'Unranked',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 3, 12, 3),
        decoration: ShapeDecoration(
          color: c.withValues(alpha: 0.13),
          shape: PlateBorder(slant: 0.3, side: BorderSide(color: c.withValues(alpha: 0.75))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('MMR', style: titleStyle(10.5, color: c.withValues(alpha: 0.85), spacing: 0.8)),
            const SizedBox(width: 5),
            Text(profile.ranked ? '${profile.mmr}' : '—', style: titleStyle(17, color: c, spacing: 0.4)),
            const SizedBox(width: 7),
            Text(profile.ranked ? profile.tier.label.toUpperCase() : 'UNRANKED', style: titleStyle(10.5, color: c.withValues(alpha: 0.85), spacing: 0.8)),
          ],
        ),
      ),
    );
  }
}

/// The rating as a hex badge: number large, tier beneath, and how far off the next tier is.
class MmrBadge extends StatelessWidget {
  const MmrBadge(this.profile, {super.key, this.size = 92});
  final PlayerProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = profile.tier;
    final c = profile.ranked ? tierColor(t) : Palette.muted;
    final next = t.next;
    final caption = !profile.ranked
        ? 'Play a PvP match to get ranked'
        : next == null
        ? 'Top tier'
        : '${next.floor - profile.mmr} to ${next.label}';
    return Semantics(
      label: profile.ranked ? 'Rating ${profile.mmr}, ${t.label}. $caption' : 'Unranked. $caption',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 1.16,
            height: size,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: c.withValues(alpha: 0.12),
              shape: HexBorder(side: BorderSide(color: c, width: 2.2)),
              shadows: const [BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('MMR', style: titleStyle(size * 0.13, color: c.withValues(alpha: 0.85), spacing: 1.2)),
                Text(profile.ranked ? '${profile.mmr}' : '—', style: titleStyle(size * 0.34, color: c, spacing: 0.3)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(profile.ranked ? t.label.toUpperCase() : 'UNRANKED', style: titleStyle(15, color: c, spacing: 1.4)),
          SizedBox(
            width: size * 1.5,
            child: Text(caption, textAlign: TextAlign.center, maxLines: 2, style: bodyStyle(11.5, color: Palette.muted)),
          ),
        ],
      ),
    );
  }
}

/// One win rate: who it is against, the percentage, the record and a bar.
class WinRateBlock extends StatelessWidget {
  const WinRateBlock({super.key, required this.label, required this.icon, required this.record, this.dense = false});
  final String label;
  final IconData icon;
  final Record record;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final played = record.matches > 0;
    final rate = record.winRate;
    final color = !played ? Palette.muted : (rate >= 50 ? Palette.good : Palette.danger);
    return Semantics(
      container: true,
      label: played ? '$label: ${rate.round()} percent wins, ${record.wins} won, ${record.losses} lost' : '$label: no games yet',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, dense ? 7 : 9, 12, dense ? 8 : 10),
        decoration: ShapeDecoration(
          color: Palette.bg.withValues(alpha: 0.55),
          shape: ChamferBorder(cut: 8, side: BorderSide(color: Palette.line.withValues(alpha: 0.7))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: Palette.boneDim),
                const SizedBox(width: 6),
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle(12.5, color: Palette.boneDim, spacing: 1.1))),
              ],
            ),
            const SizedBox(height: 2),
            Text(played ? '${rate.round()}%' : '—', style: titleStyle(dense ? 26 : 32, color: color, spacing: 0.2)),
            const SizedBox(height: 2),
            Text(played ? '${record.wins}W · ${record.losses}L · ${record.matches} games' : 'No games yet', maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(12, color: Palette.muted)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                height: 4,
                width: double.infinity,
                color: Palette.line.withValues(alpha: 0.6),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(widthFactor: (rate / 100).clamp(0.0, 1.0), child: Container(color: color)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The player's main hero (their most played): the miniature standing in a pool of the hero's
/// light, with the hero's name on a plate in the hero's colour.
class HeroShowcase extends StatelessWidget {
  const HeroShowcase({super.key, required this.hero, this.matches = 0, this.isSelf = false});
  final HeroDef? hero;

  /// The profile is the viewer's own (changes the empty-state wording).
  final bool isSelf;

  /// Matches played with the hero.
  final int matches;

  @override
  Widget build(BuildContext context) {
    final h = hero;
    if (h == null) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: Palette.bg.withValues(alpha: 0.45),
          shape: ChamferBorder(cut: 10, side: BorderSide(color: Palette.line.withValues(alpha: 0.6))),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HeroAvatar(hero: null, size: 56, fallbackLetter: '?'),
                const SizedBox(height: 10),
                Text('NO MAIN HERO YET', textAlign: TextAlign.center, style: titleStyle(15, color: Palette.boneDim, spacing: 1)),
                const SizedBox(height: 4),
                Text(isSelf ? 'The hero you play most shows up here.' : 'The hero they play most shows up here.', textAlign: TextAlign.center, style: bodyStyle(12, color: Palette.muted)),
              ],
            ),
          ),
        ),
      );
    }
    final color = hexColor(h.color);
    return Semantics(
      label: 'Main hero ${h.name}${matches > 0 ? ', $matches matches' : ''}',
      excludeSemantics: true,
      child: ClipPath(
        clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 10)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: readable(color).withValues(alpha: 0.5)),
            gradient: RadialGradient(
              center: const Alignment(0, 0.45),
              radius: 0.95,
              colors: [color.withValues(alpha: 0.5), color.withValues(alpha: 0.14), Palette.bg.withValues(alpha: 0.6)],
              stops: const [0, 0.55, 1],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // The pool of light under the figure.
                  Positioned(
                    bottom: c.maxHeight * 0.17,
                    child: Container(
                      width: c.maxWidth * 0.8,
                      height: c.maxHeight * 0.1,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.elliptical(c.maxWidth * 0.4, c.maxHeight * 0.05)),
                        gradient: RadialGradient(colors: [Palette.bone.withValues(alpha: 0.28), Colors.transparent]),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    bottom: c.maxHeight * 0.17,
                    top: 8,
                    child: Image.asset(
                      h.mini,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      cacheHeight: (c.maxHeight * dpr).clamp(200, 640).round(),
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                          decoration: ShapeDecoration(
                            color: plateColor(color),
                            shape: PlateBorder(side: BorderSide(color: Palette.bone.withValues(alpha: 0.7), width: 1.2)),
                            shadows: const [BoxShadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 3))],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.star_rounded, size: 15, color: Palette.gold),
                              const SizedBox(width: 6),
                              Flexible(child: Text(h.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle(16, color: Colors.white, spacing: 1))),
                            ],
                          ),
                        ),
                        if (matches > 0) ...[
                          const SizedBox(height: 4),
                          Text('MAIN HERO · $matches ${matches == 1 ? 'MATCH' : 'MATCHES'}', style: titleStyle(10.5, color: Palette.boneDim, spacing: 1)),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
