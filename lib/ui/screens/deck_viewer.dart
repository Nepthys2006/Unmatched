/// The deck viewer: a read-only popup with every card of a hero's deck. Thumbnails on the left,
/// the chosen card's full info on the right, a filter by card type, and a way out (X, Esc or a
/// click outside). Everything shown comes from the hero's card data (`HeroDef.cards`).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';

import '../../engine/defs.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

/// Opens the viewer for [hero]. Resolves when it is closed.
Future<void> showDeckViewer(BuildContext context, HeroDef hero) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close deck',
    barrierColor: const Color(0xCC000000),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) => DeckViewer(hero: hero),
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(c), child: child),
      );
    },
  );
}

/// The label and colour a card type is shown with.
({String label, Color color}) cardTypeStyle(CardType t) => switch (t) {
  CardType.attack => (label: 'Attack', color: Palette.attacker),
  CardType.defense => (label: 'Defense', color: Palette.defender),
  CardType.versatile => (label: 'Versatile', color: const Color(0xFF9B7BFF)),
  CardType.scheme => (label: 'Scheme', color: const Color(0xFF3FA37A)),
};

/// Printed text by timing, in the order a card is read.
const _timings = <(String, String)>[
  ('effect', 'Effect'),
  ('immediately', 'Immediately'),
  ('during', 'During combat'),
  ('after', 'After combat'),
  ('ongoing', 'Ongoing'),
  ('boosted', 'If boosted'),
  ('completion', 'Completion'),
];

class DeckViewer extends StatefulWidget {
  const DeckViewer({super.key, required this.hero});
  final HeroDef hero;

  @override
  State<DeckViewer> createState() => _DeckViewerState();
}

class _DeckViewerState extends State<DeckViewer> {
  CardType? _filter;
  late CardDef _selected = widget.hero.cards.isEmpty ? throw StateError('${widget.hero.id} has no cards') : widget.hero.cards.first;

  List<CardDef> get _shown => [
    for (final c in widget.hero.cards)
      if (_filter == null || c.type == _filter) c,
  ];

  int _count(CardType? t) => widget.hero.cards.where((c) => t == null || c.type == t).fold(0, (n, c) => n + c.copies);

  void _setFilter(CardType? t) {
    setState(() {
      _filter = t;
      final shown = _shown;
      if (shown.isNotEmpty && !shown.contains(_selected)) _selected = shown.first;
    });
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hero = widget.hero;
    final color = readable(hexColor(hero.color));
    final shown = _shown;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: math.min(1120, size.width - 20), maxHeight: math.min(740, size.height - 20)),
                // Taps inside the panel must not reach the barrier behind it.
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
                          _header(hero, color),
                          const SizedBox(height: 8),
                          _filters(),
                          const SizedBox(height: 8),
                          Expanded(
                            child: shown.isEmpty
                                ? Center(child: Text('No ${cardTypeStyle(_filter!).label.toLowerCase()} cards in this deck', style: bodyStyle(15, color: Palette.muted)))
                                : LayoutBuilder(
                                    builder: (context, c) => c.maxWidth < 620 ? _stacked(shown, c) : _sideBySide(shown, c),
                                  ),
                          ),
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

  Widget _header(HeroDef hero, Color color) {
    final different = hero.cards.length;
    return Row(
      children: [
        Avatar(hero.avatar, size: 40, ring: color, ringWidth: 1.6),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${hero.name.toUpperCase()} · DECK', maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle(21, spacing: 1.2)),
              Text(
                '${hero.deckSize} cards',
                key: const ValueKey('deck-total'),
                style: bodyStyle(13.5, color: Palette.boneDim, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Text('$different different', style: bodyStyle(12.5, color: Palette.muted)),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          label: 'Close deck',
          child: InkResponse(
            key: const ValueKey('deck-close'),
            onTap: _close,
            radius: 24,
            child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, color: Palette.bone, size: 24)),
          ),
        ),
      ],
    );
  }

  Widget _filters() {
    Widget chip(CardType? t) {
      final n = _count(t);
      final sel = _filter == t;
      final style = t == null ? null : cardTypeStyle(t);
      final accent = style?.color ?? Palette.gold;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          button: true,
          selected: sel,
          enabled: n > 0,
          label: '${style?.label ?? 'All'} ($n)',
          child: GestureDetector(
            key: ValueKey('deck-filter-${t?.name ?? 'all'}'),
            onTap: n == 0 ? null : () => _setFilter(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: sel ? accent.withValues(alpha: 0.28) : Palette.bgDeep.withValues(alpha: 0.7),
                shape: ChamferBorder(cut: 6, side: BorderSide(color: sel ? accent : Palette.bone.withValues(alpha: n == 0 ? 0.08 : 0.22), width: sel ? 1.6 : 1)),
              ),
              child: Text(
                '${(style?.label ?? 'All').toUpperCase()}  $n',
                style: titleStyle(13, color: n == 0 ? Palette.muted.withValues(alpha: 0.5) : (sel ? Palette.bone : Palette.boneDim), spacing: 0.8),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(null),
          for (final t in const [CardType.attack, CardType.defense, CardType.scheme, CardType.versatile]) chip(t),
        ],
      ),
    );
  }

  Widget _sideBySide(List<CardDef> shown, BoxConstraints c) {
    final leftW = (c.maxWidth * 0.46).clamp(250.0, 520.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: leftW, child: _thumbs(shown, leftW)),
        const SizedBox(width: 14),
        Expanded(child: _detail()),
      ],
    );
  }

  Widget _stacked(List<CardDef> shown, BoxConstraints c) {
    return Column(
      children: [
        SizedBox(height: math.min(118.0, c.maxHeight * 0.34), child: _thumbs(shown, c.maxWidth, strip: true)),
        const SizedBox(height: 8),
        Expanded(child: _detail()),
      ],
    );
  }

  Widget _thumbs(List<CardDef> shown, double width, {bool strip = false}) => KeyedSubtree(key: const ValueKey('deck-thumbs'), child: _thumbList(shown, width, strip: strip));

  Widget _thumbList(List<CardDef> shown, double width, {bool strip = false}) {
    Widget tile(CardDef card, double w) {
      final sel = card == _selected;
      return Semantics(
        button: true,
        selected: sel,
        label: '${card.title}, ${card.copies} in deck',
        child: GestureDetector(
          key: ValueKey('deck-card-${card.index}'),
          onTap: () => setState(() => _selected = card),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 160),
            scale: sel ? 1.0 : 0.96,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CardImage(card.image, width: w, border: sel ? Palette.gold : null, glow: sel ? Palette.gold : null),
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    key: ValueKey('deck-qty-${card.index}'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: ShapeDecoration(
                      color: Palette.bgDeep,
                      shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.gold.withValues(alpha: 0.8))),
                    ),
                    child: Text('×${card.copies}', style: titleStyle(12.5, spacing: 0.2)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (strip) {
      final w = 104 * cardAspect;
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 6, right: 6),
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => tile(shown[i], w),
      );
    }
    // As many columns as fit at a readable thumbnail size.
    final cols = math.max(2, (width / 118).floor());
    final w = (width - 14 - (cols - 1) * 10) / cols;
    return Scrollbar(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cardAspect,
        ),
        itemCount: shown.length,
        itemBuilder: (_, i) => tile(shown[i], w),
      ),
    );
  }

  Widget _detail() {
    final card = _selected;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
      child: _CardDetail(key: ValueKey(card.key), card: card),
    );
  }
}

class _CardDetail extends StatelessWidget {
  const _CardDetail({super.key, required this.card});
  final CardDef card;

  @override
  Widget build(BuildContext context) {
    final type = cardTypeStyle(card.type);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 330;
        final art = math.min(wide ? c.maxWidth * 0.46 : c.maxWidth * 0.5, c.maxHeight * 0.95 * cardAspect).clamp(70.0, 300.0);
        final info = _info(type);
        final image = GestureDetector(
          onTap: () => showCardZoom<void>(context, card.image),
          child: CardImage(card.image, width: art),
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              image,
              const SizedBox(width: 14),
              Expanded(child: SingleChildScrollView(child: info)),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Center(child: image), const SizedBox(height: 10), info]),
        );
      },
    );
  }

  Widget _info(({String label, Color color}) type) {
    final value = card.value == null || (card.isScheme && card.value == 0) ? '—' : '${card.value}';
    final boost = card.dieBoost ? 'Die' : (card.boost == null ? '—' : '${card.boost}');
    final texts = [
      for (final (key, label) in _timings)
        if ((card.text[key] ?? '').trim().isNotEmpty) (label, card.text[key]!.trim()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(card.title.toUpperCase(), key: const ValueKey('deck-detail-name'), style: titleStyle(22, spacing: 0.8)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(key: const ValueKey('deck-detail-type'), text: type.label, color: type.color),
            _Pill(key: const ValueKey('deck-detail-qty'), text: '×${card.copies} in deck', color: Palette.gold),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Value', value: value, valueKey: const ValueKey('deck-detail-value'))),
            const SizedBox(width: 8),
            Expanded(child: _Stat(label: 'Boost', value: boost, valueKey: const ValueKey('deck-detail-boost'))),
          ],
        ),
        const SizedBox(height: 12),
        if (texts.isEmpty)
          Text('No card text.', style: bodyStyle(14, color: Palette.muted, style: FontStyle.italic))
        else
          for (final (label, text) in texts) ...[
            Text(label.toUpperCase(), style: titleStyle(12.5, color: Palette.boneDim, spacing: 1.5)),
            const SizedBox(height: 2),
            Text(text, key: ValueKey('deck-detail-text-$label'), style: bodyStyle(14.5)),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 2),
        Text(
          card.isAny ? 'Played by any fighter' : 'Played by ${card.usedBy}',
          style: bodyStyle(13, color: Palette.muted, style: FontStyle.italic),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 11),
    alignment: Alignment.center,
    decoration: ShapeDecoration(
      color: color.withValues(alpha: 0.22),
      shape: ChamferBorder(cut: 5, side: BorderSide(color: color.withValues(alpha: 0.9))),
    ),
    child: Text(text.toUpperCase(), style: titleStyle(13, spacing: 0.9)),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.valueKey});
  final String label;
  final String value;
  final Key valueKey;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: ShapeDecoration(
      color: Palette.bgDeep.withValues(alpha: 0.8),
      shape: ChamferBorder(cut: 6, side: BorderSide(color: Palette.bone.withValues(alpha: 0.18))),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label.toUpperCase(), style: titleStyle(12.5, color: Palette.boneDim, spacing: 1.2))),
        Text(value, key: valueKey, style: titleStyle(24)),
      ],
    ),
  );
}
