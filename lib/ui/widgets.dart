/// Shared widgets: plates, hex buttons, panels, card images, zoom and confirmation dialogs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'audio.dart';
import 'services.dart';
import 'shapes.dart';
import 'theme.dart';

const cardAspect = 600 / 832;

enum PlateStyle { primary, secondary, confirm, danger, hero }

void _tapSound(BuildContext context, {double volume = 0.6}) {
  final s = context.services;
  s.audio.userGesture();
  s.audio.sfx(Sfx.click, volume: volume);
}

/// The main button: an angled plate with a bold condensed label.
class PlateButton extends StatelessWidget {
  const PlateButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.subtitle,
    this.badge,
    this.style = PlateStyle.primary,
    this.color,
    this.width,
    this.height = 52,
    this.fontSize = 20,
    this.point = false,
    this.align = MainAxisAlignment.center,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? subtitle;

  /// A small tag on the plate's corner ("Coming soon").
  final String? badge;
  final PlateStyle style;

  /// Fill for [PlateStyle.hero].
  final Color? color;
  final double? width;
  final double height;
  final double fontSize;
  final bool point;
  final MainAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final (Color fill, Color fg, Color edge) = !enabled
        ? (Palette.panelHi.withValues(alpha: 0.7), Palette.muted, Palette.line)
        : switch (style) {
            PlateStyle.primary => (Palette.bone, Palette.bgDeep, Palette.gold),
            PlateStyle.secondary => (Palette.panel, Palette.bone, Palette.gold.withValues(alpha: 0.55)),
            PlateStyle.confirm => (Palette.confirm, Colors.white, Palette.confirmHi),
            PlateStyle.danger => (Palette.attacker, Colors.white, const Color(0xFFF07A6E)),
            PlateStyle.hero => (plateColor(color ?? Palette.attacker), Colors.white, Palette.bone.withValues(alpha: 0.7)),
          };
    final shape = PlateBorder(
      side: BorderSide(color: edge, width: style == PlateStyle.primary && enabled ? 2 : 1.5),
      point: point,
    );
    Widget content(bool bounded) => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: align,
      children: [
        if (icon != null) ...[Icon(icon, color: fg, size: fontSize + 2), SizedBox(width: fontSize * 0.45)],
        _maybeFlexible(
          bounded,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: align == MainAxisAlignment.start ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle(fontSize, color: fg),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle(fontSize * 0.62, color: fg.withValues(alpha: 0.78), weight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: width,
        height: height,
        // Passthrough: a given width fills; without one the plate hugs its label.
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            Material(
              color: fill,
              shape: shape,
              elevation: enabled ? 3 : 0,
              shadowColor: Colors.black,
              child: InkWell(
                customBorder: shape,
                splashColor: fg.withValues(alpha: 0.15),
                highlightColor: fg.withValues(alpha: 0.08),
                onTap: enabled
                    ? () {
                        _tapSound(context);
                        onPressed!();
                      }
                    : null,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: height * 0.5),
                  // Ellipsize when the plate has a width to keep to; hug the label otherwise.
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: align == MainAxisAlignment.start ? Alignment.centerLeft : Alignment.center,
                      child: content(c.hasBoundedWidth),
                    ),
                  ),
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                right: height * 0.2,
                top: -9,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: const ShapeDecoration(color: Palette.brass, shape: PlateBorder(slant: 0.3)),
                  child: Text(badge!.toUpperCase(), style: titleStyle(10.5, color: Palette.bgDeep, spacing: 0.8)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Flexible only when the parent gives a bounded width (a Row offers unbounded width).
Widget _maybeFlexible(bool bounded, Widget child) => bounded ? Flexible(child: child) : child;

/// A hexagonal icon button (menu, log, zoom, back...).
class HexButton extends StatelessWidget {
  const HexButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 50,
    this.fill = Palette.panel,
    this.fg = Palette.bone,
    this.label,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color fill;
  final Color fg;

  /// Optional caption under the icon (Skip).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // Bone-on-navy hexes get the gold rim of the digital edition's buttons; coloured ones keep their own.
    final rim = fg == Palette.bone ? Palette.gold.withValues(alpha: 0.75) : fg.withValues(alpha: 0.8);
    final shape = HexBorder(side: BorderSide(color: enabled ? rim : Palette.line, width: 1.5));
    final w = size * 1.16;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox(
          width: w,
          height: size,
          child: Material(
            color: enabled ? fill : fill.withValues(alpha: 0.5),
            shape: shape,
            elevation: enabled ? 3 : 0,
            shadowColor: Colors.black,
            child: InkWell(
              customBorder: shape,
              splashColor: fg.withValues(alpha: 0.15),
              onTap: enabled
                  ? () {
                      _tapSound(context, volume: 0.5);
                      onPressed!();
                    }
                  : null,
              child: label == null
                  ? Icon(icon, color: enabled ? fg : Palette.muted, size: size * 0.46)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: enabled ? fg : Palette.muted, size: size * 0.34),
                        Text(label!.toUpperCase(), style: titleStyle(size * 0.2, color: enabled ? fg : Palette.muted, spacing: 0.6)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The big green hex that commits a choice.
class ConfirmHex extends StatelessWidget {
  const ConfirmHex({super.key, required this.onPressed, this.size = 84, this.tooltip = 'Confirm', this.pulse});
  final VoidCallback? onPressed;
  final double size;
  final String tooltip;

  /// 0..1 breathing glow while a choice is waiting to be confirmed.
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final hex = HexButton(
      icon: Icons.check_rounded,
      tooltip: tooltip,
      onPressed: onPressed,
      size: size,
      fill: onPressed == null ? Palette.panel : Palette.confirm,
      fg: onPressed == null ? Palette.muted : Colors.white,
    );
    if (pulse == null || onPressed == null) return hex;
    return AnimatedBuilder(
      animation: pulse!,
      builder: (_, child) => DecoratedBox(
        decoration: ShapeDecoration(
          shape: const HexBorder(),
          shadows: [BoxShadow(color: Palette.confirmHi.withValues(alpha: 0.25 + 0.35 * pulse!.value), blurRadius: 18, spreadRadius: 1)],
        ),
        child: child,
      ),
      child: hex,
    );
  }
}

/// A chamfered navy panel with a fine gold hairline (full gold when highlighted).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.highlight = false, this.color, this.cut = 10});
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  final Color? color;
  final double cut;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: ShapeDecoration(
      color: (color ?? Palette.panel).withValues(alpha: 0.95),
      shape: ChamferBorder(
        cut: cut,
        side: BorderSide(color: highlight ? Palette.gold : Palette.gold.withValues(alpha: 0.22), width: highlight ? 1.6 : 1),
      ),
      shadows: const [BoxShadow(color: Color(0x80000000), blurRadius: 14, offset: Offset(0, 5))],
    ),
    child: child,
  );
}

/// A small heading over a group of choices.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle(15, color: Palette.boneDim, spacing: 1.6),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Palette.gold.withValues(alpha: 0.45), Palette.gold.withValues(alpha: 0)]),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Flexible(child: trailing!),
        ],
      ],
    ),
  );
}

/// A selectable chamfered tile (modes, difficulty, quality...). Selected tiles turn bone, rimmed in gold.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.minWidth = 0,
    this.height = 48,
    this.accent,
  });
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback? onTap;
  final double minWidth;
  final double height;

  /// Colour of the small mark on the tile's left (difficulty colours).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Palette.bgDeep : (onTap == null ? Palette.muted : Palette.bone);
    final shape = ChamferBorder(
      cut: 7,
      side: BorderSide(color: selected ? Palette.gold : Palette.bone.withValues(alpha: 0.2), width: selected ? 2 : 1),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, minHeight: height),
        child: Material(
          color: selected ? Palette.bone : Palette.panel,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap == null
                ? null
                : () {
                    _tapSound(context, volume: 0.45);
                    onTap!();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (accent != null) ...[Container(width: 4, height: 22, color: accent), const SizedBox(width: 10)],
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: accent != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                      children: [
                        Text(label.toUpperCase(), style: titleStyle(16, color: fg, spacing: 0.8)),
                        if (sub != null)
                          Text(
                            sub!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: bodyStyle(12, color: selected ? const Color(0xFF3A3A36) : Palette.muted),
                          ),
                      ],
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

/// A card image (or its back). Decoded at the size it is shown to keep memory and jank down.
class CardImage extends StatelessWidget {
  const CardImage(this.asset, {super.key, required this.width, this.radius, this.border, this.dim = false, this.glow});
  final String asset;
  final double width;
  final double? radius;
  final Color? border;
  final bool dim;

  /// A soft coloured glow around the card (playable cards).
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final cache = (width * dpr).clamp(64, 600).round();
    final r = radius ?? width * 0.055;
    Widget img = Image.asset(
      asset,
      width: width,
      height: width / cardAspect,
      fit: BoxFit.cover,
      cacheWidth: _bucket(cache),
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        width: width,
        height: width / cardAspect,
        color: Palette.panelHi,
        alignment: Alignment.center,
        child: const Icon(Icons.style, color: Palette.muted),
      ),
    );
    if (dim) {
      img = ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x8C000000), BlendMode.srcATop), child: img);
    }
    return Container(
      width: width,
      height: width / cardAspect,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        border: border != null ? Border.all(color: border!, width: width > 120 ? 3 : 2) : null,
        boxShadow: [
          if (glow != null) BoxShadow(color: glow!.withValues(alpha: 0.7), blurRadius: 9, spreadRadius: 1),
          const BoxShadow(color: Color(0x99000000), blurRadius: 5, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(r - (border != null ? 2 : 0)), child: img),
    );
  }

  /// Few distinct decode sizes so the image cache can share them.
  static int _bucket(int w) => w <= 160 ? 160 : (w <= 300 ? 300 : 600);
}

/// A hero portrait in a hexagonal frame (or a circle for tokens).
class Avatar extends StatelessWidget {
  const Avatar(
    this.asset, {
    super.key,
    required this.size,
    this.ring = Palette.bone,
    this.ringWidth = 2,
    this.grey = false,
    this.hex = true,
  });
  final String asset;
  final double size;
  final Color ring;
  final double ringWidth;
  final bool grey;
  final bool hex;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    Widget img = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * dpr) <= 128 ? 128 : 256,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(color: Palette.panelHi),
    );
    if (grey) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.3, 0.5, 0.1, 0, 0, //
          0.3, 0.5, 0.1, 0, 0,
          0.3, 0.5, 0.1, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    final ShapeBorder shape = hex
        ? HexBorder(
            side: BorderSide(color: ring, width: ringWidth),
          )
        : CircleBorder(
            side: BorderSide(color: ring, width: ringWidth),
          );
    return Container(
      width: hex ? size * 1.12 : size,
      height: size,
      decoration: ShapeDecoration(
        shape: shape,
        color: Palette.bgDeep,
        shadows: const [BoxShadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      foregroundDecoration: ShapeDecoration(shape: shape),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: img,
      ),
    );
  }
}

/// Shows a card (or identity card) large enough to read. Tap the card or outside to close.
/// [actions] sit beside it (e.g. "Attack with this card"); each closes the zoom when tapped.
Future<T?> showCardZoom<T>(BuildContext context, String asset, {String? caption, List<Widget> actions = const []}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0xD9000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) {
      final size = MediaQuery.sizeOf(ctx);
      final h = (size.height * 0.88).clamp(200.0, 832.0);
      final w = (h * cardAspect).clamp(100.0, size.width * 0.6);
      return SafeArea(
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: CardImage(asset, width: w),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: (size.width - w - 80).clamp(150, 300)),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (caption != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(caption, style: bodyStyle(16)),
                          ),
                        for (final a in actions) Padding(padding: const EdgeInsets.only(top: 12), child: a),
                        const SizedBox(height: 12),
                        PlateButton(
                          label: actions.isEmpty ? 'Close' : 'Back',
                          style: PlateStyle.secondary,
                          height: 46,
                          fontSize: 17,
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(c), child: child),
      );
    },
  );
}

/// "Are you sure?" with an optional card preview. Resolves to true only on Confirm.
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirm = 'Confirm',
  String cancel = 'Cancel',
  String? cardAsset,
  bool danger = false,
}) async {
  final r = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancel,
    barrierColor: const Color(0xB3000000),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) {
      final size = MediaQuery.sizeOf(ctx);
      final cardW = (size.height * 0.5 * cardAspect).clamp(80.0, 210.0);
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 580, maxHeight: size.height - 24),
            child: Material(
              color: Colors.transparent,
              child: Panel(
                padding: const EdgeInsets.all(20),
                cut: 14,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cardAsset != null) ...[CardImage(cardAsset, width: cardW), const SizedBox(width: 20)],
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title.toUpperCase(), style: titleStyle(24, color: Palette.bone)),
                            const SizedBox(height: 4),
                            const DecoRule(width: 160, opacity: 0.35),
                            if (message != null) ...[
                              const SizedBox(height: 8),
                              Text(message, style: bodyStyle(16, color: Palette.boneDim)),
                            ],
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                PlateButton(
                                  label: cancel,
                                  style: PlateStyle.secondary,
                                  height: 48,
                                  fontSize: 17,
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                ),
                                PlateButton(
                                  label: confirm,
                                  style: danger ? PlateStyle.danger : PlateStyle.confirm,
                                  icon: danger ? null : Icons.check_rounded,
                                  height: 48,
                                  fontSize: 17,
                                  onPressed: () => Navigator.of(ctx).pop(true),
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
          ),
        ),
      );
    },
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(c), child: child),
      );
    },
  );
  return r ?? false;
}

/// A screen-wide header: a hex back button, the title in bone caps and a deco rule.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.onBack, this.trailing, this.step});
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// "2 / 4": where the player is in a multi-step flow.
  final String? step;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 16, 4),
    child: Row(
      children: [
        HexButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', size: 44, onPressed: onBack ?? () => Navigator.of(context).maybePop()),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle(28, color: Palette.bone, spacing: 1.6),
                    ),
                  ),
                  if (step != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      step!,
                      style: titleStyle(15, color: Palette.muted, weight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              const DecoRule(width: 180, opacity: 0.35),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Draws [child] [scale] times larger and takes up that larger size, so the whole of what is
/// drawn can be tapped. (Transform.scale keeps the unscaled size for layout and hit testing, which
/// left the outer part of enlarged HUD buttons dead on big screens.)
class ScaledBox extends SingleChildRenderObjectWidget {
  const ScaledBox({super.key, required this.scale, super.child});
  final double scale;

  @override
  RenderScaledBox createRenderObject(BuildContext context) => RenderScaledBox(scale);

  @override
  void updateRenderObject(BuildContext context, RenderScaledBox renderObject) => renderObject.scale = scale;
}

class RenderScaledBox extends RenderProxyBox {
  RenderScaledBox(this._scale);
  double _scale;
  set scale(double v) {
    if (v == _scale) return;
    _scale = v;
    markNeedsLayout();
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void performLayout() {
    final c = constraints;
    final kid = child;
    if (kid == null) {
      size = c.smallest;
      return;
    }
    kid.layout(
      BoxConstraints(
        minWidth: c.minWidth / _scale,
        maxWidth: c.maxWidth / _scale,
        minHeight: c.minHeight / _scale,
        maxHeight: c.maxHeight / _scale,
      ),
      parentUsesSize: true,
    );
    size = c.constrain(kid.size * _scale);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final kid = child;
    if (kid == null) return;
    layer = context.pushTransform(needsCompositing, offset, _transform, (c, o) => c.paintChild(kid, o),
        oldLayer: layer is TransformLayer ? layer as TransformLayer : null);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final kid = child;
    if (kid == null) return false;
    return result.addWithPaintTransform(transform: _transform, position: position, hitTest: (r, p) => kid.hitTest(r, position: p));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_transform);
}
