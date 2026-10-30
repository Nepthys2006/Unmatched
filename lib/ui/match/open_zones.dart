/// A hero's cards on the table outside the hand (Pandora's MISERIES, Titania's GLAMOURS, the
/// cauldron, Shakespeare's line...) as things you can see: a strip of small card chips under the
/// player's plate, and a tray that lays the same cards out full size. Everything here is open
/// information, except a card only its owner may look at (Pandora's HOPE), which the tray shows to
/// the owner alone.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../../engine/open_cards.dart';
import '../../engine/state.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

const _violet = Color(0xFFB98BE8), _mint = Color(0xFF8ED6A0), _teal = Color(0xFF7FD3C4);

/// The zones of [p] worth drawing right now.
List<OpenZone> visibleZones(Player p) => [
  for (final z in p.script.openZones())
    if (z.alwaysShow || z.total > 0) z,
];

/// The colour a zone's cards are edged in.
Color zoneAccent(OpenZone z, Player p) => switch (z.id) {
  'miseries' => Palette.gold,
  'glamour' || 'glamour-discard' => _violet,
  'cauldron' => _mint,
  'suit' => _violet,
  'inventions' || 'gadget' => _teal,
  _ => readable(hexColor(p.hero.color)),
};

// ------------------------------------------------------------------------------- card faces

/// A feather, drawn: MISERIES carry one to two of them.
class FeatherMark extends StatelessWidget {
  const FeatherMark({super.key, required this.size, required this.color, this.quill = Palette.bgDeep});
  final double size;
  final Color color;
  final Color quill;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _FeatherPainter(color, quill));
}

class _FeatherPainter extends CustomPainter {
  const _FeatherPainter(this.color, this.quill);
  final Color color;
  final Color quill;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final vane = Path()
      ..moveTo(w * 0.10, h * 0.96)
      ..cubicTo(w * -0.02, h * 0.48, w * 0.28, h * 0.06, w * 0.94, h * 0.04)
      ..cubicTo(w * 1.02, h * 0.56, w * 0.66, h * 0.90, w * 0.10, h * 0.96)
      ..close();
    canvas.drawPath(vane, Paint()..color = color);
    canvas.drawLine(
      Offset(w * 0.06, h * 1.0),
      Offset(w * 0.78, h * 0.20),
      Paint()
        ..color = quill
        ..strokeWidth = math.max(1, w * 0.09)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FeatherPainter o) => o.color != color || o.quill != quill;
}

/// A small stack of card outlines: the glyph for "a pile of cards" on the chips.
class StackGlyph extends StatelessWidget {
  const StackGlyph({super.key, required this.size, required this.color, this.filled = false});
  final double size;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _StackPainter(color, filled));
}

class _StackPainter extends CustomPainter {
  const _StackPainter(this.color, this.filled);
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size s) {
    final cw = s.width * 0.56, ch = cw / cardAspect.clamp(0.5, 1) * 0.86;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, s.width * 0.075);
    for (var i = 2; i >= 0; i--) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * s.width * 0.2, s.height - ch - (2 - i) * s.height * 0.1 - s.height * 0.04, cw, ch),
        Radius.circular(s.width * 0.08),
      );
      canvas.drawRRect(r, Paint()..color = Palette.bgDeep);
      canvas.drawRRect(r, line..color = color.withValues(alpha: i == 0 ? 1 : 0.55 + 0.15 * (2 - i)));
      if (filled && i == 0) canvas.drawRRect(r.deflate(s.width * 0.06), Paint()..color = color.withValues(alpha: 0.35));
    }
  }

  @override
  bool shouldRepaint(_StackPainter o) => o.color != color || o.filled != filled;
}

/// One open card as a face: its printed scan when it has one, otherwise a face drawn from the
/// title, feathers and text in the zone's colour. Text appears once the card is big enough to read.
class OpenCardFace extends StatelessWidget {
  const OpenCardFace({super.key, required this.card, required this.width, required this.accent, this.peek = false});
  final OpenCard card;
  final double width;
  final Color accent;

  /// A card only its owner sees: outlined in the selectable green with an eye.
  final bool peek;

  @override
  Widget build(BuildContext context) {
    final height = width / cardAspect;
    if (card.image != null) {
      return Stack(
        children: [
          CardImage(card.image!, width: width),
          if (card.tag != null) Positioned(left: 4, bottom: 4, child: _TagChip(card.tag!, accent, width)),
        ],
      );
    }
    final pad = width * 0.075;
    final readable = width >= 78;
    final feathers = card.feathers ?? 0;
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.fromLTRB(pad, pad * 1.1, pad, pad),
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(Palette.panelHi, accent, 0.22)!, Palette.bgDeep],
        ),
        shape: ChamferBorder(
          cut: width * 0.09,
          side: BorderSide(color: peek ? Palette.select : accent, width: peek ? 2 : 1.4),
        ),
        shadows: [
          const BoxShadow(color: Color(0x99000000), blurRadius: 5, offset: Offset(0, 3)),
          if (peek) BoxShadow(color: Palette.select.withValues(alpha: 0.35), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Text(
            card.title.toUpperCase(),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: titleStyle(width * 0.14, color: Palette.bone, spacing: 0.4),
          ),
          SizedBox(height: pad * 0.6),
          Container(height: 1, color: accent.withValues(alpha: 0.6)),
          SizedBox(height: pad * 0.7),
          if (card.feathers != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (feathers == 0)
                  Text('NO FEATHERS', style: titleStyle(width * 0.085, color: Palette.muted, spacing: 0.8))
                else
                  for (var i = 0; i < feathers; i++)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: width * 0.02),
                      child: FeatherMark(size: width * 0.2, color: accent),
                    ),
              ],
            ),
          if (readable && card.text.isNotEmpty)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: pad * 0.7),
                child: Center(
                  child: Text(
                    card.text,
                    textAlign: TextAlign.center,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle((width * 0.095).clamp(8.5, 14), color: Palette.boneDim, weight: FontWeight.w600),
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          if (peek) Icon(Icons.visibility_rounded, size: width * 0.16, color: Palette.select),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.text, this.color, this.cardWidth);
  final String text;
  final Color color;
  final double cardWidth;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: cardWidth * 0.06, vertical: 1),
    decoration: ShapeDecoration(
      color: const Color(0xE60A0D13),
      shape: ChamferBorder(cut: 3, side: BorderSide(color: color, width: 1)),
    ),
    child: Text(text.toUpperCase(), style: titleStyle((cardWidth * 0.11).clamp(8.5, 12), color: Palette.bone, spacing: 0.4)),
  );
}

// ------------------------------------------------------------------------------- plate strip

/// The player's open cards as chips under the plate: one header chip per zone (its name and how
/// many cards lie face down), then a chip for each face-up card, with its feathers. A tap opens the
/// tray with the cards full size.
class OpenZoneStrip extends StatelessWidget {
  const OpenZoneStrip({
    super.key,
    required this.player,
    required this.viewer,
    this.small = false,
    this.maxCards = 4,
    this.alignment = WrapAlignment.start,
  });
  final Player player;

  /// Whose screen this is (a card only its owner may see stays hidden from everyone else).
  final Player viewer;
  final bool small;

  /// Face-up cards drawn per zone before "+N".
  final int maxCards;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final zones = visibleZones(player);
    if (zones.isEmpty) return const SizedBox.shrink();
    final h = small ? 22.0 : 26.0;
    final children = <Widget>[];
    for (final z in zones) {
      final accent = zoneAccent(z, player);
      children.add(_ZoneChip(zone: z, accent: accent, height: h));
      for (final c in z.cards.take(maxCards)) {
        children.add(_CardChip(card: c, accent: accent, height: h));
      }
      if (z.cards.length > maxCards) children.add(_MoreChip(n: z.cards.length - maxCards, accent: accent, height: h));
    }
    final summary = [for (final z in zones) describe(z)].join('. ');
    return Semantics(
      button: true,
      label: '${player.name}: $summary. Open the card tray',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('open-zones-${player.seat}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showOpenZoneSheet(context, player: player, viewer: viewer),
        child: Wrap(spacing: 4, runSpacing: 3, alignment: alignment, crossAxisAlignment: WrapCrossAlignment.center, children: children),
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({required this.zone, required this.accent, required this.height});
  final OpenZone zone;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final small = height < 24;
    final count = zone.hidden > 0 ? '${zone.hidden}' : (zone.cards.isEmpty ? '0' : null);
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 6),
      decoration: ShapeDecoration(
        color: const Color(0xE60A0D13),
        shape: ChamferBorder(cut: 4, side: BorderSide(color: accent.withValues(alpha: 0.75))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StackGlyph(size: height * 0.72, color: accent, filled: zone.hidden > 0),
          const SizedBox(width: 4),
          Text(zone.chip, style: titleStyle(small ? 10 : 11.5, color: accent, spacing: 0.5)),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text(
              count,
              key: ValueKey('zone-count-${zone.id}'),
              style: titleStyle(small ? 12 : 14, color: Colors.white, spacing: 0),
            ),
          ],
        ],
      ),
    );
  }
}

/// One face-up card as a chip: its colour along the edge, its feathers, its name.
class _CardChip extends StatelessWidget {
  const _CardChip({required this.card, required this.accent, required this.height});
  final OpenCard card;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final small = height < 24;
    final feathers = card.feathers ?? 0;
    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 3, right: 6),
      decoration: ShapeDecoration(
        gradient: LinearGradient(colors: [accent.withValues(alpha: 0.95), accent.withValues(alpha: 0.55)], stops: const [0, 0.1]),
        shape: ChamferBorder(cut: 4, side: BorderSide(color: accent, width: 1.2)),
      ),
      child: Container(
        padding: const EdgeInsets.only(left: 4),
        color: const Color(0xE60A0D13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < feathers; i++)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: FeatherMark(size: height * 0.55, color: accent),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: small ? 104 : 124),
              child: Text(
                card.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle(small ? 10.5 : 12, color: Colors.white, spacing: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.n, required this.accent, required this.height});
  final int n;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: ShapeDecoration(
      color: const Color(0xE60A0D13),
      shape: ChamferBorder(cut: 4, side: BorderSide(color: accent.withValues(alpha: 0.5))),
    ),
    child: Text('+$n', style: titleStyle(height < 24 ? 11 : 12.5, color: Palette.bone, spacing: 0)),
  );
}

// ------------------------------------------------------------------------------- the tray

/// A zone laid out full size: the face-down pile, the face-up cards (tap one to read it large) and,
/// for the owner only, the card they may look at.
class OpenZoneBody extends StatelessWidget {
  const OpenZoneBody({super.key, required this.zone, required this.player, required this.viewer, required this.cardWidth});
  final OpenZone zone;
  final Player player;
  final Player viewer;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final accent = zoneAccent(zone, player);
    final mine = viewer == player;
    Widget captioned(Widget card, String caption, {Color? color}) => SizedBox(
      width: cardWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          card,
          const SizedBox(height: 4),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: bodyStyle(12, color: color ?? Palette.muted, weight: FontWeight.w600),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('${zone.label} · ${zone.cards.length} face up${zone.hidden > 0 ? ' · ${zone.hidden} ${zone.hiddenLabel}' : ''}'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            if (zone.hidden > 0)
              captioned(_FaceDownStack(count: zone.hidden, back: player.hero.back, width: cardWidth), '${zone.hidden} ${zone.hiddenLabel}'),
            for (var i = 0; i < zone.cards.length; i++)
              GestureDetector(
                key: ValueKey('open-card-${zone.id}-$i'),
                onTap: () => _read(context, zone.cards[i], accent),
                child: OpenCardFace(card: zone.cards[i], width: cardWidth, accent: accent),
              ),
            if (mine && zone.peek != null)
              captioned(
                OpenCardFace(card: zone.peek!, width: cardWidth, accent: accent, peek: true),
                zone.peekLabel,
                color: Palette.select,
              ),
            if (zone.cards.isEmpty && zone.hidden == 0)
              SizedBox(
                height: cardWidth / cardAspect,
                child: Center(
                  child: Text('Nothing here yet.', style: bodyStyle(14, color: Palette.muted)),
                ),
              ),
          ],
        ),
        if (zone.note.isNotEmpty || (!mine && zone.peek != null)) ...[
          const SizedBox(height: 6),
          Text(
            [
              if (zone.note.isNotEmpty) zone.note,
              if (!mine && zone.peek != null) '${player.name} may look at the top card first. You cannot see it.',
            ].join('  ·  '),
            style: bodyStyle(13, color: Palette.boneDim),
          ),
        ],
      ],
    );
  }

  void _read(BuildContext context, OpenCard c, Color accent) {
    if (c.image != null) {
      showCardZoom<void>(context, c.image!);
      return;
    }
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0xD9000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, _) {
        final size = MediaQuery.sizeOf(ctx);
        final w = (size.height * 0.8 * cardAspect).clamp(150.0, 320.0);
        return SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: OpenCardFace(card: c, width: w, accent: accent),
            ),
          ),
        );
      },
      transitionBuilder: (_, a, _, child) {
        final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curve), child: child),
        );
      },
    );
  }
}

/// Face-down cards: up to three backs offset, with the count.
class _FaceDownStack extends StatelessWidget {
  const _FaceDownStack({required this.count, required this.back, required this.width});
  final int count;
  final String back;
  final double width;

  @override
  Widget build(BuildContext context) {
    final shown = math.min(count, 3);
    final off = width * 0.07;
    return SizedBox(
      width: width,
      height: width / cardAspect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = shown - 1; i >= 0; i--)
            Positioned(
              left: i * off,
              top: -i * off,
              child: CardImage(back, width: width - off * 2),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: ShapeDecoration(
                color: const Color(0xF20A0D13),
                shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.bone.withValues(alpha: 0.5))),
              ),
              child: Text('$count', style: titleStyle(18, color: Colors.white, spacing: 0)),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showOpenZoneSheet(BuildContext context, {required Player player, required Player viewer}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0xB3000000),
    pageBuilder: (ctx, _, _) => OpenZoneSheet(player: player, viewer: viewer),
  );
}

/// The tray: one hero's open cards, full size.
class OpenZoneSheet extends StatelessWidget {
  const OpenZoneSheet({super.key, required this.player, required this.viewer});
  final Player player;
  final Player viewer;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardW = (size.height * 0.4 * cardAspect).clamp(84.0, 150.0);
    final zones = visibleZones(player);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.min(900, size.width - 24), maxHeight: size.height - 24),
          child: Material(
            color: Colors.transparent,
            child: Panel(
              padding: const EdgeInsets.all(12),
              cut: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${player.hero.name.toUpperCase()}  ·  CARDS ON THE TABLE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle(20, spacing: 0.8),
                        ),
                      ),
                      HexButton(icon: Icons.close_rounded, tooltip: 'Close', size: 36, onPressed: () => Navigator.of(context).pop()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final z in zones) ...[
                            OpenZoneBody(zone: z, player: player, viewer: viewer, cardWidth: cardW),
                            const SizedBox(height: 14),
                          ],
                          if (zones.isEmpty) Text('Nothing on the table.', style: bodyStyle(14, color: Palette.muted)),
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
