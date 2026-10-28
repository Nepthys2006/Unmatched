/// Colours, text styles and the app theme, after Unmatched: Digital Edition: a deep navy table
/// under a warm lamp, gold trim and inlay, bone-white lettering, hero-coloured plates, a green
/// confirm hex, red attacker / blue defender.
library;

import 'package:flutter/material.dart';

abstract final class Palette {
  /// The table: deep navy slate, darker toward the rim.
  static const bg = Color(0xFF151A23);
  static const bgDeep = Color(0xFF0A0D13);

  /// The pool of lamplight in the middle of the table.
  static const bgLit = Color(0xFF263044);
  static const panel = Color(0xFF1C2330);
  static const panelHi = Color(0xFF283141);
  static const line = Color(0xFF434D60);

  /// Gold trim: frames, selected edges, inlay linework, the deco rules.
  static const gold = Color(0xFFD9B45E);
  static const goldDim = Color(0xFF8E7642);

  /// Bone: the off-white of the printed linework and lettering.
  static const bone = Color(0xFFECE6D8);
  static const boneDim = Color(0xFFB9B3A5);

  /// Brass, from the logo plate on the card backs (start numbers, badges): the gold trim.
  static const brass = gold;
  static const text = bone;
  static const muted = Color(0xFF99A0AB);

  static const confirm = Color(0xFF5DB443);
  static const confirmHi = Color(0xFF8BE05A);
  static const attacker = Color(0xFFC8352C);
  static const defender = Color(0xFF2D8FD2);
  static const danger = Color(0xFFE0574C);
  static const good = Color(0xFF6BD08A);
  static const heart = Color(0xFFD8323A);

  /// Selectable things glow this green, like the digital edition's playable cards.
  static const select = Color(0xFF9BEA5C);

  /// Destination spaces and targets.
  static const target = Color(0xFFFF5B4E);

  /// Seat colours for free-for-all orbs.
  static const seats = [Color(0xFF4FA3FF), Color(0xFFFF5A5A), Color(0xFF6BE38A), Color(0xFFFFB648), Color(0xFFC57BFF), Color(0xFF4FE3D4)];

  /// Team play: the player's team in blues, the other team in reds; one shade per player.
  static const teamA = [Color(0xFF4FA3FF), Color(0xFF59E0FF), Color(0xFF7C8CFF)];
  static const teamB = [Color(0xFFFF5A5A), Color(0xFFFF9248), Color(0xFFFF6FB5)];
}

Color hexColor(String hex, [Color fallback = Palette.brass]) {
  var h = hex.replaceAll('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// Hero colours that are too dark to read on graphite get lifted.
Color readable(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.lightness < 0.45 ? hsl.withLightness(0.6).toColor() : c;
}

/// A hero colour deepened so bone lettering stays legible on it (name plates).
Color plateColor(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness * 0.72).clamp(0.22, 0.42)).withSaturation((hsl.saturation * 0.95).clamp(0, 1)).toColor();
}

abstract final class Fonts {
  static const title = 'Saira';
  static const body = 'Barlow';
}

TextStyle titleStyle(double size, {Color color = Palette.text, FontWeight weight = FontWeight.w800, double spacing = 1.0}) =>
    TextStyle(fontFamily: Fonts.title, fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing, height: 1.05);

TextStyle bodyStyle(double size, {Color color = Palette.text, FontWeight weight = FontWeight.w500, FontStyle? style}) =>
    TextStyle(fontFamily: Fonts.body, fontSize: size, fontWeight: weight, color: color, fontStyle: style, height: 1.25);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: Fonts.body,
    colorScheme: const ColorScheme.dark(
      primary: Palette.bone,
      onPrimary: Palette.bgDeep,
      secondary: Palette.confirm,
      surface: Palette.panel,
      onSurface: Palette.text,
      tertiary: Palette.gold,
      error: Palette.danger,
    ),
    scaffoldBackgroundColor: Palette.bg,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Palette.bone,
      selectionColor: Color(0x55ECE6D8),
      selectionHandleColor: Palette.bone,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: Fonts.body, bodyColor: Palette.text, displayColor: Palette.text),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.bone,
      thumbColor: Palette.bone,
      inactiveTrackColor: Palette.line,
      overlayColor: Color(0x22D9B45E),
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.bgDeep : Palette.boneDim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.confirm : Palette.panelHi),
      trackOutlineColor: const WidgetStatePropertyAll(Palette.line),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: Palette.panelHi,
        borderRadius: BorderRadius.all(Radius.circular(3)),
        border: Border.fromBorderSide(BorderSide(color: Color(0x66D9B45E))),
      ),
      textStyle: TextStyle(color: Palette.text, fontSize: 13, fontFamily: Fonts.body),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Color(0x66ECE6D8)),
      thickness: WidgetStatePropertyAll(4),
      radius: Radius.circular(2),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
