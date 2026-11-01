/// The hero grid with its search bar: hex portraits, a search that matches name, id and set, and
/// the "2/70" count. Shared by the hero select screen and the AI opponent picker.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

class HeroGrid extends StatefulWidget {
  const HeroGrid({
    super.key,
    required this.heroes,
    required this.selected,
    required this.onSelect,
    this.blocked = const {},
    this.keyPrefix = 'hero',
  });

  /// Every hero that can appear, in the order shown.
  final List<HeroDef> heroes;
  final HeroDef? selected;
  final ValueChanged<HeroDef> onSelect;

  /// Heroes that are taken: shown dimmed and not selectable.
  final Set<String> blocked;

  /// Prefix of the search field's keys (`hero-search`, `hero-search-count`, `hero-search-clear`).
  final String keyPrefix;

  @override
  State<HeroGrid> createState() => HeroGridState();
}

class HeroGridState extends State<HeroGrid> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _focus = FocusNode();
  int _perRow = 4;

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The heroes the search lets through: every word typed must appear in the hero's name, id or
  /// set (so "bol 3", "sis" and "slings titania" all work).
  List<HeroDef> get shown {
    final words = _search.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return widget.heroes;
    return [
      for (final h in widget.heroes)
        if (words.every((w) => '${h.name} ${h.id.replaceAll('-', ' ')} ${h.set}'.toLowerCase().contains(w))) h,
    ];
  }

  void _onSearch() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void clearSearch() {
    _search.clear();
    _onSearch();
  }

  /// Enter picks the first hero found.
  void _submit(String _) {
    final found = shown;
    final sel = widget.selected;
    if (found.isNotEmpty && (sel == null || !found.contains(sel)) && !widget.blocked.contains(found.first.id)) widget.onSelect(found.first);
    _focus.unfocus();
  }

  /// Scrolls [hero] into view, clearing a search that hides it.
  void reveal(HeroDef hero) {
    if (!shown.contains(hero)) clearSearch();
    final i = shown.indexOf(hero);
    if (i < 0) return;
    final row = i ~/ _perRow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        (row * 92.0 - 60).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final found = shown;
    return Column(
      children: [
        HeroSearchField(
          prefix: widget.keyPrefix,
          controller: _search,
          focus: _focus,
          onChanged: _onSearch,
          onClear: clearSearch,
          onSubmit: _submit,
          found: found.length,
          total: widget.heroes.length,
        ),
        const SizedBox(height: 6),
        Expanded(child: _list(found)),
      ],
    );
  }

  Widget _list(List<HeroDef> found) => LayoutBuilder(
    builder: (context, c) {
      const tile = 84.0;
      _perRow = math.max(3, (c.maxWidth / tile).floor());
      if (found.isEmpty) {
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_rounded, color: Palette.muted, size: 32),
                const SizedBox(height: 6),
                Text('No hero matches "${_search.text.trim()}"', textAlign: TextAlign.center, style: bodyStyle(15, color: Palette.boneDim)),
                const SizedBox(height: 10),
                PlateButton(label: 'Show all heroes', style: PlateStyle.secondary, height: 44, fontSize: 15, onPressed: clearSearch),
              ],
            ),
          ),
        );
      }
      return Scrollbar(
        controller: _scroll,
        child: GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(right: 10, bottom: 8, top: 4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _perRow, mainAxisExtent: 92, crossAxisSpacing: 4),
          itemCount: found.length,
          itemBuilder: (_, i) {
            final h = found[i];
            final sel = h == widget.selected;
            final blocked = widget.blocked.contains(h.id);
            return Semantics(
              button: true,
              selected: sel,
              enabled: !blocked,
              label: blocked ? '${h.name} (taken)' : h.name,
              child: Opacity(
                opacity: blocked ? 0.35 : 1,
                child: InkWell(
                  key: ValueKey('${widget.keyPrefix}-tile-${h.id}'),
                  onTap: blocked ? null : () => widget.onSelect(h),
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
                          ring: sel ? Palette.gold : Palette.bone.withValues(alpha: 0.25),
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
              ),
            );
          },
        ),
      );
    },
  );
}

/// The hero search: a chamfered field on the table's dark, with the count of heroes it leaves.
class HeroSearchField extends StatelessWidget {
  const HeroSearchField({
    super.key,
    required this.prefix,
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onClear,
    required this.onSubmit,
    required this.found,
    required this.total,
  });
  final String prefix;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onChanged;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmit;
  final int found;
  final int total;

  @override
  Widget build(BuildContext context) {
    final filtering = controller.text.trim().isNotEmpty;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 12),
      decoration: ShapeDecoration(
        color: Palette.bgDeep.withValues(alpha: 0.85),
        shape: ChamferBorder(cut: 8, side: BorderSide(color: Palette.gold.withValues(alpha: filtering ? 0.8 : 0.3), width: filtering ? 1.4 : 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Palette.boneDim, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: ValueKey('$prefix-search'),
              controller: controller,
              focusNode: focus,
              onChanged: (_) => onChanged(),
              onSubmitted: onSubmit,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              cursorColor: Palette.bone,
              style: bodyStyle(16, weight: FontWeight.w600),
              decoration: InputDecoration.collapsed(hintText: 'Search heroes or sets', hintStyle: bodyStyle(16, color: Palette.muted)),
            ),
          ),
          if (filtering) ...[
            Text('$found/$total', key: ValueKey('$prefix-search-count'), style: titleStyle(13, color: found == 0 ? Palette.danger : Palette.boneDim, spacing: 0.4)),
            Semantics(
              button: true,
              label: 'Clear search',
              child: InkResponse(
                key: ValueKey('$prefix-search-clear'),
                onTap: onClear,
                radius: 22,
                child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, color: Palette.bone, size: 20)),
              ),
            ),
          ] else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
