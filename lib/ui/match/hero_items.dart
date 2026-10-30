/// A hero's public game pieces beside the identity card, as things you can see: Alice's BIG/SMALL
/// card, Jekyll or Hyde, Hamlet's TO BE / NOT TO BE, the Wayward Sisters' cauldron, Ghost Rider's
/// Hellfire, Tesla's coils, Sattler's insight... Shown for every player (everything here is open
/// information) on the player plates, beside the hero on the 2D board and on the 3D badge.
library;

import 'package:flutter/material.dart';

import '../../engine/state.dart';
import '../shapes.dart';
import '../theme.dart';

enum HeroItemKind {
  /// A two-sided card or a single state (Alice BIG/SMALL, Hamlet, Jekyll/Hyde, a gadget).
  card,

  /// A pile of tokens shown one by one (Hellfire, coils, rage, doubloons, insight).
  tokens,

  /// A number with a label (the cauldron's cards, Shakespeare's line).
  counter,
}

class HeroItem {
  const HeroItem(this.kind, this.label, {required this.icon, required this.emoji, this.count, this.max, this.color = Palette.bone});
  final HeroItemKind kind;
  final String label;
  final int? count;

  /// Tokens there can be at most (Tesla has 2 coils), drawn as empty slots.
  final int? max;
  final IconData icon;

  /// The same piece on the 3D board's badge (the web page has no icon font).
  final String emoji;
  final Color color;

  /// Short text for tight spots: the count, or the label.
  String get short => count != null ? (max != null ? '$count/$max' : '$count') : label;

  Map<String, Object?> toJson() => {
    'k': kind.name,
    't': label,
    if (count != null) 'n': count,
    if (max != null) 'm': max,
    'e': emoji,
    'c': '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
  };
}

int? _num(String s) => int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '');

const _flame = Color(0xFFFF8A3D), _gold = Color(0xFFF2C14E), _violet = Color(0xFFB98BE8), _steel = Color(0xFF9FB4C8);

/// The pieces [p]'s hero has out right now (empty for heroes without any). Heroes whose pieces are
/// open cards (Pandora's MISERIES, Titania's GLAMOURS) draw them as a card strip on the plate
/// ([OpenZoneStrip]), so with [onPlate] they have no items; the board badge still gets one.
List<HeroItem> heroItems(Player p, {bool onPlate = false}) {
  final zones = p.script.openZones();
  if (onPlate && zones.isNotEmpty) return const [];
  final s = p.script.status();
  final first = s.isEmpty ? '' : s.first;
  HeroItem card(IconData i, String e, [Color c = Palette.bone]) => HeroItem(HeroItemKind.card, first.toUpperCase(), icon: i, emoji: e, color: c);
  switch (p.hero.id) {
    case 'alice':
      return [card(Icons.unfold_more_rounded, first == 'BIG' ? '🍄' : '🫖', const Color(0xFF8EC5FF))];
    case 'jekyll-hyde':
      return [card(Icons.science_rounded, '🧪', first.contains('HYDE') ? const Color(0xFFE05A5A) : const Color(0xFF8ED6A0))];
    case 'hamlet':
      return [card(Icons.theater_comedy_rounded, '💀', first == 'TO BE' ? const Color(0xFFE6D6A8) : const Color(0xFF9C8FB8))];
    case 'muhammad-ali':
      return [card(Icons.sports_mma_rounded, first.startsWith('Float') ? '🦋' : '🐝', _gold)];
    case 'willow':
      return [if (first == 'DARK') const HeroItem(HeroItemKind.card, 'DARK WILLOW', icon: Icons.auto_fix_high_rounded, emoji: '🔮', color: _violet)];
    case 'dr-jill-trent':
      return [if (s.isNotEmpty) card(Icons.biotech_rounded, '🔬', const Color(0xFF7FD3C4))];
    case 'little-red':
      return [if (s.isNotEmpty) card(Icons.shopping_basket_rounded, '🧺', const Color(0xFFE0675F))];
    case 'titania':
      final glamour = zones.first.cards;
      return [if (glamour.isNotEmpty) HeroItem(HeroItemKind.card, glamour.first.title.toUpperCase(), icon: Icons.auto_awesome_rounded, emoji: '✨', color: _violet)];
    case 'pandora':
      final out = zones.first.cards.length;
      return [if (out > 0) HeroItem(HeroItemKind.counter, 'MISERIES', count: out, icon: Icons.inventory_2_rounded, emoji: '📦', color: _gold)];
    case 'invisible-man':
      return [if (s.isNotEmpty) card(Icons.cloud_rounded, '☁️', const Color(0xFFD6DCE4))];
    case 'elektra':
      return [if (s.isNotEmpty) card(Icons.replay_rounded, '☠️', const Color(0xFFE05A5A))];
    case 'achilles':
      return [if (s.isNotEmpty) card(Icons.heart_broken_rounded, '💔', const Color(0xFFE05A5A))];
    case 'ghost-rider':
      return [HeroItem(HeroItemKind.tokens, 'HELLFIRE', count: _num(first) ?? 0, icon: Icons.local_fire_department_rounded, emoji: '🔥', color: _flame)];
    case 'nikola-tesla':
      return [HeroItem(HeroItemKind.tokens, 'COILS', count: _num(first) ?? 0, max: 2, icon: Icons.bolt_rounded, emoji: '⚡', color: const Color(0xFF8EC5FF))];
    case 'beowulf':
      return [HeroItem(HeroItemKind.tokens, 'RAGE', count: _num(first) ?? 0, icon: Icons.whatshot_rounded, emoji: '💢', color: const Color(0xFFE05A5A))];
    case 'blackbeard':
      return [
        HeroItem(HeroItemKind.tokens, 'DOUBLOONS', count: _num(first) ?? 0, icon: Icons.paid_rounded, emoji: '🪙', color: _gold),
        if (s.length > 1) HeroItem(HeroItemKind.counter, 'TREASURY', count: _num(s[1]) ?? 0, icon: Icons.savings_rounded, emoji: '💰', color: _gold),
      ];
    case 'loki':
      return [HeroItem(HeroItemKind.counter, 'TRICKS OUT', count: _num(first) ?? 0, icon: Icons.style_rounded, emoji: '🃏', color: const Color(0xFF8ED6A0))];
    case 'dr-sattler':
      return [HeroItem(HeroItemKind.tokens, 'INSIGHT', count: _num(first) ?? 0, icon: Icons.diamond_rounded, emoji: '💎', color: _gold)];
    case 'robert-muldoon':
      return [HeroItem(HeroItemKind.tokens, 'TRAPS', count: _num(first) ?? 0, icon: Icons.warning_amber_rounded, emoji: '🪤', color: const Color(0xFFF08A3C))];
    case 'spike':
      return [HeroItem(HeroItemKind.tokens, 'SHADOWS', count: _num(first) ?? 0, icon: Icons.dark_mode_rounded, emoji: '🌑', color: _violet)];
    case 'the-wayward-sisters':
      return [HeroItem(HeroItemKind.counter, 'CAULDRON', count: p.script.aside.length, icon: Icons.soup_kitchen_rounded, emoji: '🍲', color: const Color(0xFF8ED6A0))];
    case 'shakespeare':
      return [HeroItem(HeroItemKind.counter, 'LINE', count: _num(first) ?? 0, max: 10, icon: Icons.edit_note_rounded, emoji: '🪶', color: Palette.bone)];
    case 'black-panther':
      return [if (s.isNotEmpty) HeroItem(HeroItemKind.counter, 'VIBRANIUM', count: _num(first) ?? 0, icon: Icons.shield_rounded, emoji: '🛡️', color: _violet)];
    case 'sinbad':
      return [if (s.isNotEmpty) HeroItem(HeroItemKind.counter, 'VOYAGE', count: _num(first) ?? 0, icon: Icons.sailing_rounded, emoji: '⛵', color: const Color(0xFF8EC5FF))];
  }
  // Anyone else with a status line: shown as cards with their text.
  return [for (final t in s) HeroItem(HeroItemKind.card, t.toUpperCase(), icon: Icons.label_rounded, emoji: '🔖', color: _steel)];
}

/// The pieces as small graphics for a player plate: a tiny card, a row of tokens or a counter.
class HeroItemsRow extends StatelessWidget {
  const HeroItemsRow({super.key, required this.player, this.small = false});
  final Player player;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final items = heroItems(player, onPlate: true);
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 5, runSpacing: 4, children: [for (final i in items) HeroItemView(item: i, small: small)]);
  }
}

class HeroItemView extends StatelessWidget {
  const HeroItemView({super.key, required this.item, this.small = false});
  final HeroItem item;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final h = small ? 22.0 : 26.0;
    final i = item;
    final Widget body = switch (i.kind) {
      // A small card standing up: the piece's colour along its edge, icon and name.
      HeroItemKind.card => Container(
        height: h,
        padding: EdgeInsets.only(left: 3, right: small ? 6 : 8),
        decoration: ShapeDecoration(
          gradient: LinearGradient(colors: [i.color.withValues(alpha: 0.95), i.color.withValues(alpha: 0.55)], stops: const [0, 0.12]),
          shape: ChamferBorder(cut: 4, side: BorderSide(color: i.color, width: 1.2)),
        ),
        child: Container(
          padding: const EdgeInsets.only(left: 4),
          color: const Color(0xE60A0D13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(i.icon, size: h * 0.62, color: i.color),
              const SizedBox(width: 3),
              Text(i.label, style: titleStyle(small ? 11 : 12.5, color: Colors.white, spacing: 0.4)),
            ],
          ),
        ),
      ),
      // Tokens one by one (up to 6; then the icon and a count), empty slots up to the maximum.
      HeroItemKind.tokens => Container(
        height: h,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: ShapeDecoration(
          color: const Color(0xE60A0D13),
          shape: ChamferBorder(cut: 4, side: BorderSide(color: i.color.withValues(alpha: 0.6))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(i.label, style: titleStyle(small ? 10 : 11.5, color: i.color, spacing: 0.4)),
            const SizedBox(width: 4),
            if ((i.max ?? i.count ?? 0) <= 6)
              for (var k = 0; k < (i.max ?? i.count ?? 0); k++)
                _Token(icon: i.icon, color: i.color, size: h * 0.78, empty: k >= (i.count ?? 0))
            else ...[
              _Token(icon: i.icon, color: i.color, size: h * 0.78),
              Text(' ×${i.count}', style: titleStyle(small ? 12 : 14, color: Colors.white)),
            ],
            if ((i.count ?? 0) == 0 && i.max == null) Text('0', style: titleStyle(small ? 12 : 14, color: Palette.muted)),
          ],
        ),
      ),
      HeroItemKind.counter => Container(
        height: h,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: ShapeDecoration(
          color: const Color(0xE60A0D13),
          shape: ChamferBorder(cut: 4, side: BorderSide(color: i.color.withValues(alpha: 0.6))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(i.icon, size: h * 0.66, color: i.color),
            const SizedBox(width: 3),
            Text('${i.label} ', style: titleStyle(small ? 10 : 11.5, color: i.color, spacing: 0.4)),
            Text(i.short, style: titleStyle(small ? 12 : 14, color: Colors.white)),
          ],
        ),
      ),
    };
    return Tooltip(message: '${i.label}${i.count != null ? ': ${i.short}' : ''}', child: body);
  }
}

class _Token extends StatelessWidget {
  const _Token({required this.icon, required this.color, required this.size, this.empty = false});
  final IconData icon;
  final Color color;
  final double size;
  final bool empty;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    margin: const EdgeInsets.only(right: 2),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: empty ? Colors.transparent : Color.lerp(color, Colors.black, 0.55),
      border: Border.all(color: color.withValues(alpha: empty ? 0.35 : 1), width: 1.2),
    ),
    child: Icon(icon, size: size * 0.7, color: empty ? color.withValues(alpha: 0.3) : color),
  );
}
