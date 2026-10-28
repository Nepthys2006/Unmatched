/// The match HUD: name plates, the prompt bar, the turn banner, the hand fan, the combat view,
/// choice panels, the game log and the result screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../../engine/combat.dart';
import '../../engine/events.dart';
import '../../engine/game.dart';
import '../../engine/state.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'dials.dart';
import 'hero_items.dart';

// ------------------------------------------------------------------------------- name plates

/// A player's name plate. The big one sits bottom-left for you; compact ones top-right.
class PlayerPlate extends StatelessWidget {
  const PlayerPlate({
    super.key,
    required this.player,
    required this.color,
    required this.subtitle,
    this.big = false,
    this.active = false,
    this.actionsLeft,
    this.onTap,
    this.showHandBacks = false,
  });

  final Player player;
  final Color color;
  final String subtitle;
  final bool big;
  final bool active;

  /// Opponents: their hand as card backs (you can see how many, never which).
  final bool showHandBacks;

  /// Shown as pips while it is this player's turn.
  final int? actionsLeft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final out = player.eliminated;
    final hero = player.heroFighter;
    final avatar = big ? 58.0 : 40.0;
    final status = player.script.status();
    final plate = Container(
      padding: EdgeInsets.fromLTRB(big ? 16 : 12, big ? 4 : 3, big ? 26 : 20, big ? 5 : 3),
      decoration: ShapeDecoration(
        color: out ? Palette.panel : plateColor(hexColor(player.hero.color)),
        shape: PlateBorder(
          side: BorderSide(color: active ? Palette.gold : Palette.bone.withValues(alpha: 0.35), width: active ? 1.8 : 1),
        ),
        shadows: const [BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            player.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle(big ? 19 : 14, color: out ? Palette.muted : Colors.white, spacing: 0.8),
          ),
          Text(
            out ? 'Out of the game' : subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(big ? 12.5 : 11, color: Colors.white.withValues(alpha: 0.78), weight: FontWeight.w600),
          ),
        ],
      ),
    );
    final stats = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FighterDials(player: player, color: color, heroSize: big ? 46 : 38, sidekickSize: big ? 28 : 24),
        const SizedBox(width: 8),
        if (!showHandBacks) ...[
          _Count(icon: Icons.style_rounded, value: player.hand.length, tooltip: 'Cards in hand', small: !big),
          const SizedBox(width: 6),
        ],
        _Count(icon: Icons.layers_rounded, value: player.deck.length, tooltip: 'Cards left in deck', small: !big),
        if (actionsLeft != null) ...[
          const SizedBox(width: 10),
          // The prompt bar also says how many are left; the pips stay compact so the hand fits.
          Tooltip(
            message: '$actionsLeft action${actionsLeft == 1 ? '' : 's'} left',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 2; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      width: big ? 12 : 9,
                      height: big ? 12 : 9,
                      decoration: ShapeDecoration(
                        color: i < actionsLeft! ? Palette.bone : Colors.transparent,
                        shape: HexBorder(side: BorderSide(color: Palette.bone.withValues(alpha: 0.7))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
    return Semantics(
      button: onTap != null,
      label: '${player.name}, ${hero.hp} health, ${player.hand.length} cards in hand, ${player.deck.length} in deck. Show discard pile',
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: out ? 0.6 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Avatar(player.hero.avatar, size: avatar, ring: active ? Palette.bone : color, ringWidth: active ? 2.5 : 2, grey: out),
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  plate,
                  const SizedBox(height: 3),
                  stats,
                  if (showHandBacks && !out) ...[
                    const SizedBox(height: 4),
                    HandBacks(count: player.hand.length, back: player.hero.back, height: 28),
                  ],
                  // The hero's pieces (Alice's size card, Hellfire, the cauldron...), for every
                  // player: they are open information, like on the table.
                  if (status.isNotEmpty && !out) ...[
                    const SizedBox(height: 3),
                    HeroItemsRow(player: player, small: !big),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.value, required this.tooltip, this.small = false});
  final IconData icon;
  final int value;
  final String tooltip;
  final bool small;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Container(
      height: small ? 20 : 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: ShapeDecoration(
        color: const Color(0xCC0A0D13),
        shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.bone.withValues(alpha: 0.2))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: small ? 12 : 14, color: Palette.boneDim),
          const SizedBox(width: 3),
          Text('$value', style: titleStyle(small ? 12 : 14, weight: FontWeight.w700, spacing: 0)),
        ],
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: const ShapeDecoration(color: Palette.brass, shape: PlateBorder(slant: 0.3)),
    child: Text(text.toUpperCase(), style: titleStyle(11, color: Palette.bgDeep, spacing: 0.6)),
  );
}

// ------------------------------------------------------------------------------- prompt bar

/// The instruction strip at the top: always says what happens next.
class PromptBar extends StatelessWidget {
  const PromptBar({super.key, required this.text, this.mine = false, this.source, this.onSource});
  final String text;

  /// It's waiting on you (brighter).
  final bool mine;
  final String? source;
  final VoidCallback? onSource;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 6),
            decoration: ShapeDecoration(
              color: mine ? const Color(0xF20A0D13) : const Color(0xCC0A0D13),
              shape: _TrapezoidBorder(
                side: BorderSide(
                  color: mine ? Palette.select.withValues(alpha: 0.8) : Palette.bone.withValues(alpha: 0.25),
                  width: mine ? 1.5 : 1,
                ),
              ),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle(15, color: mine ? Palette.bone : Palette.boneDim, weight: FontWeight.w600),
            ),
          ),
        ),
        if (source != null) ...[
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Read the card this is about',
            child: GestureDetector(onTap: onSource, child: CardImage(source!, width: 34, radius: 3)),
          ),
        ],
      ],
    );
  }
}

class _TrapezoidBorder extends OutlinedBorder {
  const _TrapezoidBorder({super.side});
  Path _path(Rect r) {
    final s = r.height * 0.6;
    return Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right - s, r.bottom)
      ..lineTo(r.left + s, r.bottom)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(side.width));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  @override
  ShapeBorder scale(double t) => _TrapezoidBorder(side: side.scale(t));
  @override
  _TrapezoidBorder copyWith({BorderSide? side}) => _TrapezoidBorder(side: side ?? this.side);
}

// ------------------------------------------------------------------------------- turn banner

class TurnBanner extends StatelessWidget {
  const TurnBanner({super.key, required this.animation, required this.title, required this.sub, required this.color});
  final Animation<double> animation;
  final String title;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        if (t <= 0 || t >= 1) return const SizedBox.shrink();
        final inT = Curves.easeOutCubic.transform((t / 0.22).clamp(0, 1));
        final outT = Curves.easeInCubic.transform(((t - 0.78) / 0.22).clamp(0, 1));
        final w = MediaQuery.sizeOf(context).width;
        return Opacity(
          opacity: 1 - outT,
          child: Transform.translate(
            offset: Offset(-w * (1 - inT) + w * 0.5 * outT, 0),
            child: Center(
              child: Container(
                width: math.min(w * 0.72, 680),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: ShapeDecoration(
                  color: plateColor(color).withValues(alpha: 0.96),
                  shape: PlateBorder(slant: 0.5, point: true, side: const BorderSide(color: Palette.bone, width: 2)),
                  shadows: const [BoxShadow(color: Colors.black, blurRadius: 30, offset: Offset(0, 8))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title.toUpperCase(), style: titleStyle(40, color: Colors.white, spacing: 4)),
                    Text(
                      sub,
                      style: bodyStyle(14, color: Colors.white.withValues(alpha: 0.85), weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

// ------------------------------------------------------------------------------- hand fan

/// Your hand, fanned along the bottom edge. Playable cards glow green; tap to read a card.
class HandFan extends StatefulWidget {
  const HandFan({
    super.key,
    required this.cards,
    required this.playable,
    required this.dimOthers,
    required this.onTap,
    required this.cardWidth,
    this.onRead,
  });
  final List<Card> cards;
  final Set<Card> playable;

  /// While a card choice is open, cards that can't be chosen are dimmed.
  final bool dimOthers;
  final void Function(Card c) onTap;

  /// Long-press or right-click: read the card without playing it.
  final void Function(Card c)? onRead;
  final double cardWidth;

  @override
  State<HandFan> createState() => _HandFanState();
}

class _HandFanState extends State<HandFan> {
  Card? _hover;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final n = widget.cards.length;
      final w = widget.cardWidth;
      final h = w / cardAspect;
      if (n == 0) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text('NO CARDS IN HAND', style: titleStyle(13, color: Palette.muted, spacing: 1.6)),
          ),
        );
      }
      final spacing = n == 1 ? 0.0 : math.min(w * 0.86, (c.maxWidth - w) / (n - 1));
      final total = w + spacing * (n - 1);
      final left0 = (c.maxWidth - total) / 2;
      return Stack(
        clipBehavior: Clip.none,
        children: [for (var i = 0; i < n; i++) _card(i, n, widget.cards[i], left0 + spacing * i, w, h, c.maxHeight)],
      );
    },
  );

  Widget _card(int i, int n, Card card, double left, double w, double h, double maxH) {
    final mid = (n - 1) / 2;
    final rel = n == 1 ? 0.0 : (i - mid) / mid;
    final playable = widget.playable.contains(card);
    final raised = _hover == card;
    // The whole card shows, resting just above the bottom edge (the outer cards tilt a little,
    // so their low corner needs room too).
    final peek = h + 6 + w * 0.06;
    final top = maxH - peek + rel * rel * h * 0.06 - (raised ? h * 0.2 : (playable ? h * 0.06 : 0));
    return AnimatedPositioned(
      key: ValueKey(card.uid),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: w,
      height: h,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = card),
        onExit: (_) => setState(() => _hover = _hover == card ? null : _hover),
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: '${card.title}${playable ? ', playable' : ''}',
          child: GestureDetector(
            onTap: () => widget.onTap(card),
            onLongPress: widget.onRead == null ? null : () => widget.onRead!(card),
            onSecondaryTap: widget.onRead == null ? null : () => widget.onRead!(card),
            child: Transform.rotate(
              angle: rel * 0.07,
              alignment: Alignment.bottomCenter,
              child: CardImage(
                card.def.image,
                width: w,
                border: playable ? Palette.select : null,
                glow: playable ? Palette.select : null,
                dim: widget.dimOthers && !playable,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------- combat

/// Both combat cards side by side in the middle of the screen (defender left, attacker right),
/// with the order of play between them: reveal, IMMEDIATELY, DURING COMBAT, damage, AFTER COMBAT.
class CombatView extends StatelessWidget {
  const CombatView({
    super.key,
    required this.game,
    required this.combat,
    required this.me,
    required this.revealed,
    required this.resolved,
    required this.resolving,
    required this.effectText,
    required this.onZoom,
    required this.cardHeight,
  });

  final Game game;
  final Combat combat;
  final Player me;
  final bool revealed;
  final bool resolved;
  final Side? resolving;
  final String? effectText;
  final void Function(Card c) onZoom;
  final double cardHeight;

  static const _centerW = 176.0;

  @override
  Widget build(BuildContext context) {
    final c = combat;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _side(c.defender, left: true),
        const SizedBox(width: 10),
        // Small phones: the column shrinks to fit beside the cards.
        SizedBox(
          width: _centerW,
          height: cardHeight + 44,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(width: _centerW, child: _center()),
          ),
        ),
        const SizedBox(width: 10),
        _side(c.attacker, left: false),
      ],
    );
    return Stack(
      children: [
        Positioned(
          left: 8,
          right: 8,
          top: 50,
          height: cardHeight + 44,
          child: Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: row),
          ),
        ),
      ],
    );
  }

  /// VS, the step being resolved, the effect text, then who won.
  Widget _center() {
    final c = combat;
    final steps = [
      (Phase.reveal, 'REVEAL'),
      (Phase.immediately, 'IMMEDIATELY'),
      (Phase.during, 'DURING COMBAT'),
      (Phase.damage, 'DAMAGE'),
      (Phase.after, 'AFTER COMBAT'),
    ];
    final phase = resolved && c.phase.index < Phase.after.index ? Phase.damage : c.phase;
    Widget step(Phase ph, String label) {
      final now = ph == phase && revealed;
      final past = revealed && ph.index < phase.index;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: ShapeDecoration(
          color: now ? Palette.bone : const Color(0xCC0A0D13),
          shape: ChamferBorder(
            cut: 4,
            side: BorderSide(color: Palette.bone.withValues(alpha: now ? 1 : 0.25)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              past ? Icons.check_rounded : (now ? Icons.play_arrow_rounded : Icons.circle_outlined),
              size: 12,
              color: now ? Palette.bgDeep : (past ? Palette.good : Palette.muted),
            ),
            const SizedBox(width: 6),
            Text(label, style: titleStyle(12, color: now ? Palette.bgDeep : (past ? Palette.boneDim : Palette.muted), spacing: 1.1)),
          ],
        ),
      );
    }

    final won = c.attackerWon ? c.attacker : c.defender;
    final lost = c.attackerWon ? c.defender : c.attacker;
    final mineWon = won.player.team == me.team, mineLost = lost.player.team == me.team;
    // From your side: VICTORY or DEFEAT when you (or your team) fought; otherwise who won.
    final verdict = mineWon && !mineLost ? 'VICTORY' : (mineLost && !mineWon ? 'DEFEAT' : '${won.fighter.name.toUpperCase()} WINS');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('VS', textAlign: TextAlign.center, style: titleStyle(30, spacing: 4)),
        const SizedBox(height: 4),
        for (final (ph, label) in steps) step(ph, label),
        const SizedBox(height: 6),
        if (resolved)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            builder: (_, k, child) => Transform.scale(scale: k, child: child),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              decoration: ShapeDecoration(
                // Green when you won the combat, dark red when you lost; otherwise the winner's role colour.
                color: mineWon && !mineLost
                    ? const Color(0xFF2F7A3A)
                    : (mineLost && !mineWon ? const Color(0xFF8E1F1A) : (c.attackerWon ? Palette.attacker : Palette.defender)),
                shape: const ChamferBorder(cut: 8, side: BorderSide(color: Palette.bone, width: 1.6)),
                shadows: const [BoxShadow(color: Colors.black, blurRadius: 18)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${c.defenseValue}  VS  ${c.attackValue}', style: titleStyle(22, color: Colors.white, spacing: 1.5)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      verdict,
                      style: titleStyle(20, color: Colors.white, spacing: 1.6),
                    ),
                  ),
                  Text(
                    c.combatDamage > 0 ? '${c.combatDamage} DAMAGE TO ${c.defender.fighter.name.toUpperCase()}' : 'NO DAMAGE',
                    textAlign: TextAlign.center,
                    style: titleStyle(11, color: Colors.white.withValues(alpha: 0.9), spacing: 1),
                  ),
                ],
              ),
            ),
          )
        else if (effectText != null && resolving != null)
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            cut: 6,
            child: Text(effectText!, textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: bodyStyle(12.5)),
          ),
      ],
    );
  }

  Widget _side(Side s, {required bool left}) {
    final h = cardHeight;
    final w = h * cardAspect;
    final card = s.card;
    // Hidden information: an opponent's combat card stays face down until both are revealed.
    final faceUp = card != null && (revealed || s.faceUp || s.player == me || card.virtual);
    final role = left ? 'DEFENDER' : 'ATTACKER';
    final roleColor = left ? Palette.defender : Palette.attacker;
    final value = revealed ? game.valueOf(s) : null;
    final active = resolving == s;
    Widget cardW;
    if (card == null) {
      cardW = Container(
        width: w,
        height: h,
        decoration: ShapeDecoration(
          color: const Color(0x660A0D13),
          shape: ChamferBorder(cut: 8, side: BorderSide(color: Palette.bone.withValues(alpha: 0.3))),
        ),
        alignment: Alignment.center,
        child: Text(revealed ? 'NO CARD' : 'CHOOSING…', style: titleStyle(14, color: Palette.boneDim, spacing: 1.4)),
      );
    } else if (card.virtual) {
      cardW = Container(
        width: w,
        height: h,
        padding: const EdgeInsets.all(10),
        decoration: ShapeDecoration(
          color: Palette.panelHi,
          shape: ChamferBorder(cut: 8, side: BorderSide(color: Palette.attacker.withValues(alpha: 0.8), width: 2)),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('BONUS ATTACK', style: titleStyle(12, color: Palette.boneDim, spacing: 1.4)),
            const SizedBox(height: 6),
            Text(card.title.toUpperCase(), textAlign: TextAlign.center, style: titleStyle(18)),
            const SizedBox(height: 6),
            Text('${card.def.value ?? 0}', style: titleStyle(40)),
          ],
        ),
      );
    } else {
      cardW = GestureDetector(
        onTap: faceUp ? () => onZoom(card) : null,
        child: TweenAnimationBuilder<double>(
          key: ValueKey('${card.uid}-$faceUp'),
          tween: Tween(begin: faceUp ? 0 : 1, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY((1 - t) * math.pi / 2),
            child: child,
          ),
          child: CardImage(
            faceUp ? card.def.image : card.owner.hero.back,
            width: w,
            border: active ? Palette.bone : (s.canceled ? Palette.danger : null),
            glow: active ? Palette.bone : null,
          ),
        ),
      );
    }
    final plate = Container(
      width: w + 24,
      padding: const EdgeInsets.fromLTRB(14, 3, 14, 4),
      decoration: ShapeDecoration(
        color: roleColor,
        shape: PlateBorder(
          slant: 0.4,
          point: true,
          flip: !left,
          side: BorderSide(color: Palette.bone.withValues(alpha: 0.6)),
        ),
        shadows: const [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Text(role, style: titleStyle(16, color: Colors.white, spacing: 1.6)),
          Text(
            s.fighter.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(12, color: Colors.white.withValues(alpha: 0.85), weight: FontWeight.w600),
          ),
        ],
      ),
    );
    final breakdown = value == null || card == null
        ? null
        : Panel(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            cut: 6,
            child: SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (label, delta) in value.lines.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: bodyStyle(11.5, color: Palette.boneDim),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label == 'Card base value' ? '$delta' : (delta >= 0 ? '+$delta' : '$delta'),
                            style: titleStyle(13, color: delta < 0 ? Palette.danger : Palette.bone, spacing: 0),
                          ),
                        ],
                      ),
                    ),
                  Container(height: 1, color: Palette.bone.withValues(alpha: 0.25), margin: const EdgeInsets.symmetric(vertical: 3)),
                  Row(
                    children: [
                      Text('TOTAL', style: titleStyle(13, color: Palette.boneDim, spacing: 1.2)),
                      const Spacer(),
                      Text('${value.total}', style: titleStyle(24, spacing: 0)),
                    ],
                  ),
                  if (s.canceled) Text('EFFECTS CANCELED', style: titleStyle(11, color: Palette.danger, spacing: 1)),
                ],
              ),
            ),
          );
    final column = Column(
      crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [cardW, const SizedBox(height: 6), plate],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: left
          ? [
              if (breakdown != null) ...[breakdown, const SizedBox(width: 8)],
              column,
            ]
          : [
              column,
              if (breakdown != null) ...[const SizedBox(width: 8), breakdown],
            ],
    );
  }
}

// ------------------------------------------------------------------------------- choice panels

/// A centred panel for choices that aren't on the board or in the hand (options, yes/no...).
class ChoicePanel extends StatelessWidget {
  const ChoicePanel({
    super.key,
    required this.title,
    required this.labels,
    required this.onPick,
    this.source,
    this.onSource,
    this.skipLabel,
    this.onSkip,
  });
  final String title;
  final List<String> labels;
  final void Function(int i) onPick;
  final String? source;
  final VoidCallback? onSource;
  final String? skipLabel;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.min(620, size.width - 40), maxHeight: size.height * 0.7),
        child: Panel(
          padding: const EdgeInsets.all(18),
          cut: 14,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (source != null) ...[
                GestureDetector(
                  onTap: onSource,
                  child: CardImage(source!, width: math.min(130, size.height * 0.32)),
                ),
                const SizedBox(width: 16),
              ],
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: titleStyle(20, spacing: 0.6)),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < labels.length; i++)
                            PlateButton(
                              label: labels[i],
                              style: labels[i] == 'Yes' ? PlateStyle.confirm : PlateStyle.secondary,
                              height: 46,
                              fontSize: 16,
                              onPressed: () => onPick(i),
                            ),
                          if (onSkip != null)
                            PlateButton(
                              label: skipLabel ?? 'Skip',
                              style: PlateStyle.secondary,
                              height: 46,
                              fontSize: 16,
                              onPressed: onSkip,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick one or several cards that are not in your hand (discard pile, revealed cards), or
/// several from your hand (discard down to the hand limit).
class CardPicker extends StatefulWidget {
  const CardPicker({
    super.key,
    required this.title,
    required this.images,
    required this.min,
    required this.max,
    required this.onDone,
    required this.onZoom,
    this.onSkip,
    this.skipLabel,
  });
  final String title;
  final List<String> images;
  final int min;
  final int max;
  final void Function(List<int> picked) onDone;
  final void Function(int i) onZoom;
  final VoidCallback? onSkip;
  final String? skipLabel;

  @override
  State<CardPicker> createState() => _CardPickerState();
}

class _CardPickerState extends State<CardPicker> {
  final List<int> _picked = [];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = (size.height * 0.36 * cardAspect).clamp(70.0, 150.0);
    final single = widget.max == 1;
    final ok = _picked.length >= widget.min && _picked.length <= widget.max;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: size.width - 40),
        child: Panel(
          padding: const EdgeInsets.all(16),
          cut: 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, textAlign: TextAlign.center, style: titleStyle(19, spacing: 0.6)),
              if (!single)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.min == widget.max
                        ? 'Choose ${widget.min} · ${_picked.length} chosen'
                        : 'Choose ${widget.min}–${widget.max} · ${_picked.length} chosen',
                    style: bodyStyle(13, color: Palette.muted),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: w / cardAspect + 8,
                child: ListView.separated(
                  shrinkWrap: true,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final sel = _picked.contains(i);
                    return Semantics(
                      button: true,
                      selected: sel,
                      child: GestureDetector(
                        onTap: () {
                          if (single) {
                            widget.onDone([i]);
                            return;
                          }
                          setState(() {
                            if (sel) {
                              _picked.remove(i);
                            } else if (_picked.length < widget.max) {
                              _picked.add(i);
                            }
                          });
                        },
                        onLongPress: () => widget.onZoom(i),
                        onSecondaryTap: () => widget.onZoom(i),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: CardImage(
                            widget.images[i],
                            width: w,
                            border: sel ? Palette.select : null,
                            glow: sel ? Palette.select : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      single ? 'Tap a card to choose it · long-press to read' : 'Long-press a card to read it',
                      style: bodyStyle(12.5, color: Palette.muted),
                    ),
                  ),
                  if (widget.onSkip != null) ...[
                    PlateButton(
                      label: widget.skipLabel ?? 'Skip',
                      style: PlateStyle.secondary,
                      height: 44,
                      fontSize: 15,
                      onPressed: widget.onSkip,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (!single)
                    PlateButton(
                      label: 'Confirm',
                      icon: Icons.check_rounded,
                      style: PlateStyle.confirm,
                      height: 44,
                      fontSize: 15,
                      onPressed: ok ? () => widget.onDone(List.of(_picked)) : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------- piles, log

/// Every player's identity card and public cards, one tab per player: the identity card (tap to
/// read it full size), move, each fighter's health, the special ability, live status and set
/// rules, then the cards in play (Shakespeare's line), set aside (the cauldron), discarded and
/// removed. Hands and decks stay hidden.
Future<void> showHeroSheet(BuildContext context, {required List<Player> players, required Player initial, required Player me}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0xB3000000),
    pageBuilder: (ctx, _, _) => _HeroSheet(players: players, initial: initial, me: me),
  );
}

class _HeroSheet extends StatefulWidget {
  const _HeroSheet({required this.players, required this.initial, required this.me});
  final List<Player> players;
  final Player initial;
  final Player me;

  @override
  State<_HeroSheet> createState() => _HeroSheetState();
}

class _HeroSheetState extends State<_HeroSheet> {
  late Player _p = widget.initial;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final p = _p;
    final mine = p == widget.me;
    final idW = (size.height * 0.62 * cardAspect).clamp(110.0, 300.0);
    final cardW = (size.height * 0.26 * cardAspect).clamp(56.0, 110.0);
    final groups = <(String, List<Card>)>[
      (p.hero.id == 'shakespeare' ? 'His line (left to right)' : 'In play', p.inPlay),
      (p.hero.id == 'the-wayward-sisters' ? 'Cauldron' : 'Set aside', p.script.aside),
      ('Discard pile', p.discard.reversed.toList()),
      ('Removed from the game', p.removed),
    ];
    final ability = p.hero.ability.trim().split('\n');
    final abilityName = ability.length > 1 && ability.first.length <= 40 && !ability.first.endsWith('.') ? ability.first : null;
    final abilityText = (abilityName == null ? ability : ability.skip(1)).join(' ');
    final status = p.script.status();
    final reference = p.script.reference();

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.min(1000, size.width - 24), maxHeight: size.height - 24),
          child: Material(
            color: Colors.transparent,
            child: Panel(
              padding: const EdgeInsets.all(12),
              cut: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // One tab per player.
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final o in widget.players) ...[
                                _HeroTab(player: o, selected: o == p, you: o == widget.me, onTap: () => setState(() => _p = o)),
                                const SizedBox(width: 6),
                              ],
                            ],
                          ),
                        ),
                      ),
                      HexButton(icon: Icons.close_rounded, tooltip: 'Close', size: 36, onPressed: () => Navigator.of(context).pop()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                button: true,
                                label: "Read ${p.hero.name}'s identity card",
                                child: GestureDetector(
                                  onTap: () => showCardZoom<void>(context, p.hero.identity, caption: p.hero.description),
                                  child: CardImage(p.hero.identity, width: idW),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.hero.name.toUpperCase(), style: titleStyle(24)),
                                    Text(
                                      '${p.hero.set} · move ${p.hero.move} · ${p.hand.length} in hand · ${p.deck.length} in deck'
                                      '${p.eliminated ? ' · out of the game' : ''}',
                                      style: bodyStyle(13, color: Palette.muted),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final f in p.fighters.where((f) => !f.reserve || f.defeated)) _FighterChip(fighter: f),
                                        for (final d in p.hero.fighters)
                                          if (p.fighters.where((f) => f.def == d).every((f) => f.reserve && !f.defeated))
                                            _InfoChip('${d.name} ×${d.count} · ${d.attack.name} · ${d.hp} health · off the board'),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'SPECIAL ABILITY${abilityName == null ? '' : ' · ${abilityName.toUpperCase()}'}',
                                      style: titleStyle(14, color: Palette.brass, spacing: 1.2),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(abilityText, style: bodyStyle(14.5, color: Palette.bone)),
                                    if (status.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(spacing: 4, runSpacing: 4, children: [for (final t in status) _Chip(t)]),
                                    ],
                                    if (reference.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Text('RULES TO KNOW', style: titleStyle(14, color: Palette.brass, spacing: 1.2)),
                                      const SizedBox(height: 2),
                                      for (final r in reference)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 3),
                                          child: Text('• $r', style: bodyStyle(13.5, color: Palette.boneDim)),
                                        ),
                                    ],
                                    if (!mine) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Their hand and deck order stay hidden.',
                                        style: bodyStyle(12.5, color: Palette.muted, style: FontStyle.italic),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (final (title, cards) in groups)
                            if (cards.isNotEmpty) ...[
                              SectionLabel('$title · ${cards.length}'),
                              SizedBox(
                                height: cardW / cardAspect + 6,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: cards.length,
                                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                                  itemBuilder: (_, i) => GestureDetector(
                                    onTap: () => showCardZoom<void>(context, cards[i].def.image),
                                    child: CardImage(cards[i].def.image, width: cardW),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          if (groups.every((g) => g.$2.isEmpty)) Text('No cards played yet.', style: bodyStyle(14, color: Palette.muted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroTab extends StatelessWidget {
  const _HeroTab({required this.player, required this.selected, required this.you, required this.onTap});
  final Player player;
  final bool selected;
  final bool you;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${player.name}${you ? ' (you)' : ''}',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
        decoration: ShapeDecoration(
          color: selected ? plateColor(hexColor(player.hero.color)) : const Color(0xCC0A0D13),
          shape: ChamferBorder(cut: 6, side: BorderSide(color: selected ? Palette.gold : Palette.bone.withValues(alpha: 0.25))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(player.hero.avatar, size: 28, ringWidth: 1.5, grey: player.eliminated),
            const SizedBox(width: 6),
            Text(
              '${player.name.toUpperCase()}${you ? ' · YOU' : ''}',
              style: titleStyle(14, color: selected ? Colors.white : Palette.boneDim, spacing: 0.8),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One fighter's attack type and health, for the hero sheet.
class _FighterChip extends StatelessWidget {
  const _FighterChip({required this.fighter});
  final Fighter fighter;
  @override
  Widget build(BuildContext context) {
    final f = fighter;
    final state = f.defeated ? 'defeated' : '${f.hp}/${f.maxHp} health';
    return _InfoChip('${f.name} · ${f.isHero ? 'hero' : 'sidekick'} · ${f.attack.name} · $state', dim: f.defeated);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.text, {this.dim = false});
  final String text;
  final bool dim;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: ShapeDecoration(
      color: const Color(0xCC0A0D13),
      shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.bone.withValues(alpha: 0.2))),
    ),
    child: Text(text, style: bodyStyle(13, color: dim ? Palette.muted : Palette.bone, weight: FontWeight.w600)),
  );
}

/// One line of the game log.
class LogLine {
  LogLine(this.text, {this.turn = false, this.color});
  final String text;
  final bool turn;
  final Color? color;
}

class LogPanel extends StatelessWidget {
  const LogPanel({super.key, required this.lines, required this.onClose});
  final List<LogLine> lines;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    cut: 12,
    color: Palette.bgDeep,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('GAME LOG', style: titleStyle(18, spacing: 1.6))),
            HexButton(icon: Icons.close_rounded, tooltip: 'Close log', size: 36, onPressed: onClose),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final l = lines[lines.length - 1 - i];
              return Padding(
                padding: EdgeInsets.only(top: l.turn ? 10 : 2, bottom: 2, right: 6),
                child: l.turn
                    ? Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: ShapeDecoration(color: l.color ?? Palette.bone, shape: const HexBorder()),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(l.text.toUpperCase(), style: titleStyle(13, color: l.color ?? Palette.bone, spacing: 1)),
                          ),
                        ],
                      )
                    : Text(l.text, style: bodyStyle(13, color: Palette.boneDim)),
              );
            },
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------------------- result

class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.won,
    required this.winner,
    required this.reason,
    required this.turns,
    required this.onRematch,
    required this.onMenu,
  });
  final bool won;
  final Player? winner;
  final String reason;
  final int turns;
  /// Null in multiplayer (start a new lobby instead).
  final VoidCallback? onRematch;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final color = winner == null ? Palette.bone : hexColor(winner!.hero.color);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        color: const Color(0xE60A0D13),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: winner == null
                    ? const SizedBox()
                    : Padding(
                        padding: EdgeInsets.symmetric(vertical: size.height * 0.08),
                        child: DecoratedBox(
                          // A pool of the winner's colour behind the figure.
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, 0.35),
                              radius: 0.6,
                              colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
                            ),
                          ),
                          child: Image.asset(winner!.hero.mini, fit: BoxFit.contain),
                        ),
                      ),
              ),
              Expanded(
                flex: 6,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          won ? 'VICTORY' : 'DEFEAT',
                          style: titleStyle((size.height * 0.17).clamp(44, 110), color: won ? Palette.bone : Palette.danger, spacing: 6),
                        ),
                        DecoRule(width: 260, color: won ? Palette.bone : Palette.danger),
                        const SizedBox(height: 10),
                        if (winner != null) Text('${winner!.name} wins.', style: titleStyle(22, spacing: 0.6)),
                        if (reason.isNotEmpty) Text(reason, style: bodyStyle(14, color: Palette.boneDim)),
                        Text('$turns turns played', style: bodyStyle(14, color: Palette.muted)),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onRematch != null) ...[
                              PlateButton(label: 'Rematch', icon: Icons.replay_rounded, height: 52, fontSize: 19, onPressed: onRematch),
                              const SizedBox(width: 12),
                            ],
                            PlateButton(label: 'Menu', style: PlateStyle.secondary, height: 52, fontSize: 19, onPressed: onMenu),
                          ],
                        ),
                      ],
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
}

/// Whether an event's log line may be shown to [me] (an AI peeking at another AI's hand is
/// private between them).
bool logIsPublic(GameEvent e, Player me) {
  if (e is Revealed && e.viewer != null && e.viewer != me && e.player != me) return false;
  return e.log.trim().isNotEmpty;
}

// ------------------------------------------------------------------------------- reveals

/// Cards shown to you: a hand you look at, or cards revealed to everyone. Tap a card to read
/// it; OK (or tapping outside) closes the panel.
class RevealView extends StatelessWidget {
  const RevealView({super.key, required this.title, required this.images, required this.cardWidth, required this.onZoom, required this.onDone});
  final String title;
  final List<String> images;
  final double cardWidth;
  final void Function(int i) onZoom;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = images.length > 5 ? cardWidth * 0.8 : cardWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDone,
      child: ColoredBox(
        color: const Color(0x99000000),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size.width - 40),
            child: Panel(
              padding: const EdgeInsets.all(16),
              cut: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title.toUpperCase(), textAlign: TextAlign.center, style: titleStyle(19, spacing: 0.8)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: w / cardAspect + 4,
                    child: ListView.separated(
                      shrinkWrap: true,
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => GestureDetector(onTap: () => onZoom(i), child: CardImage(images[i], width: w)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tap a card to read it', style: bodyStyle(12.5, color: Palette.muted)),
                      const SizedBox(width: 14),
                      PlateButton(label: 'OK', icon: Icons.check_rounded, style: PlateStyle.confirm, height: 44, fontSize: 16, onPressed: onDone),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
