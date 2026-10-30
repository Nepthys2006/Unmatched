/// A dedicated screen for choosing and inspecting battlefields in LAN, Online, and match setup.
/// Displays interactive 2D/3D board previews, space counts, starting positions, zones, and rules.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../engine/defs.dart';
import '../board/board_painter.dart';
import '../board3d/board3d.dart';
import '../dialogs/map_inspect_dialog.dart';
import '../match/match_config.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

/// A rich, interactive battlefield selection and inspection screen.
class MapSelectScreen extends StatefulWidget {
  const MapSelectScreen({
    super.key,
    required this.maps,
    required this.initial,
    this.canSelect = true,
    this.mode,
    this.players,
  });

  final List<MapDef> maps;
  final MapDef initial;
  final bool canSelect;
  final GameMode? mode;
  final int? players;

  @override
  State<MapSelectScreen> createState() => _MapSelectScreenState();
}

class _MapSelectScreenState extends State<MapSelectScreen> {
  late MapDef _selected = widget.initial;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MapStrip.scrollTo(_scroll, widget.maps.indexOf(_selected), const Duration(milliseconds: 350));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _random() {
    final others = widget.maps.where((m) => m != _selected).toList();
    final pick = (others.isEmpty ? widget.maps : others)[math.Random().nextInt(others.isEmpty ? widget.maps.length : others.length)];
    setState(() => _selected = pick);
    MapStrip.scrollTo(_scroll, widget.maps.indexOf(pick), const Duration(milliseconds: 400));
  }

  void _confirm() {
    Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final maps = widget.maps;
    final modeLabel = widget.mode != null
        ? '${widget.mode!.label}${widget.players != null && widget.mode == GameMode.ffa ? ' · ${widget.players} players' : ''}'
        : null;

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: TableBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeader(
                  title: widget.canSelect ? 'Choose Battlefield' : 'Battlefield Details',
                  step: modeLabel ?? '${maps.length} maps',
                  onBack: () => Navigator.of(context).pop(),
                  trailing: widget.canSelect && maps.length > 1
                      ? PlateButton(
                          label: 'Random',
                          icon: Icons.shuffle_rounded,
                          style: PlateStyle.secondary,
                          height: compactHeight(context) ? 34 : 38,
                          fontSize: 14,
                          onPressed: _random,
                        )
                      : null,
                ),
                if (!compactHeight(context))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                    child: SectionLabel(
                      '${maps.length} available battlefield${maps.length == 1 ? '' : 's'}',
                      trailing: Text(
                        'Tap any battlefield to view map layout and special rules',
                        style: bodyStyle(12, color: Palette.muted),
                      ),
                    ),
                  ),
                Expanded(
                  child: MapStrip(
                    maps: maps,
                    controller: _scroll,
                    isSelected: (m) => m == _selected,
                    onTap: (m) => setState(() => _selected = m),
                  ),
                ),
                _bottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final starts = _selected.spaces.where((s) => s.start != null).length;
    final compact = compactHeight(context);
    return Container(
      padding: compact ? const EdgeInsets.fromLTRB(24, 6, 24, 8) : const EdgeInsets.fromLTRB(24, 10, 24, 14),
      decoration: const ShapeDecoration(
        color: Color(0xEB0A0D13),
        shape: Border(top: BorderSide(color: Palette.line, width: 1.5)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _selected.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle(21, color: Palette.brass, spacing: 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: const ShapeDecoration(
                            color: Color(0x33E8E2D4),
                            shape: ChamferBorder(cut: 4),
                          ),
                          child: Text(
                            '${_selected.spaces.length} SPACES · $starts STARTS',
                            style: titleStyle(12, color: Palette.bone, spacing: 0.8),
                          ),
                        ),
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        _selected.blurb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(13, color: Palette.boneDim),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 20),
              if (widget.canSelect)
                PlateButton(
                  label: 'Select Battlefield',
                  icon: Icons.check_rounded,
                  style: PlateStyle.confirm,
                  height: compact ? 38 : 48,
                  fontSize: compact ? 14 : 17,
                  onPressed: _confirm,
                )
              else
                PlateButton(
                  label: 'Close',
                  style: PlateStyle.secondary,
                  height: compact ? 38 : 46,
                  fontSize: compact ? 14 : 16,
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The scrolling row of battlefield cards, shared by match setup, the lobby and the picker.
///
/// Built to scroll smoothly: fixed-extent children (no per-frame measuring), every card in its own
/// repaint layer, a little pre-built overscroll so images decode before they slide in, and the
/// mouse wheel / touchpad mapped onto the sideways scroll (a plain horizontal list ignores the
/// vertical wheel on desktop and the web) with mouse dragging enabled.
class MapStrip extends StatefulWidget {
  const MapStrip({
    super.key,
    required this.maps,
    required this.controller,
    required this.isSelected,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(24, 4, 10, 8),
  });

  final List<MapDef> maps;
  final ScrollController controller;
  final bool Function(MapDef map) isSelected;
  final void Function(MapDef map) onTap;
  final EdgeInsets padding;

  /// One card plus the gap after it.
  static const extent = MapCard.width + 14.0;

  /// Scrolls so the card at [index] sits near the left edge.
  static void scrollTo(ScrollController c, int index, Duration duration) {
    if (index < 0 || !c.hasClients) return;
    c.animateTo(
      (index * extent - 40).clamp(0.0, c.position.maxScrollExtent),
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  State<MapStrip> createState() => _MapStripState();
}

class _MapStripState extends State<MapStrip> {
  double? _wheelTarget;

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final c = widget.controller;
    if (!c.hasClients) return;
    // Sideways gestures (shift+wheel, touchpad) already scroll the list; only turn vertical into sideways.
    final dx = event.scrollDelta.dx, dy = event.scrollDelta.dy;
    if (dx.abs() >= dy.abs()) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final p = c.position;
      // Fine deltas (touchpads) follow the fingers directly; wheel notches glide.
      if (dy.abs() < 40) {
        _wheelTarget = null;
        c.jumpTo((p.pixels + dy).clamp(0.0, p.maxScrollExtent));
        return;
      }
      final base = (_wheelTarget != null && p.isScrollingNotifier.value) ? _wheelTarget! : p.pixels;
      final target = (base + dy * 1.4).clamp(0.0, p.maxScrollExtent);
      _wheelTarget = target;
      c.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maps = widget.maps;
    return Listener(
      onPointerSignal: _onSignal,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
          scrollbars: false,
        ),
        child: ListView.builder(
          controller: widget.controller,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          itemCount: maps.length,
          itemExtent: MapStrip.extent,
          scrollCacheExtent: const ScrollCacheExtent.pixels(MapStrip.extent * 3),
          addAutomaticKeepAlives: false,
          itemBuilder: (_, i) {
            final m = maps[i];
            return RepaintBoundary(
              key: ValueKey(m.id),
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: MapCard(map: m, selected: widget.isSelected(m), onTap: () => widget.onTap(m)),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A card displaying a battlefield's preview, name, description, spaces, starts, and zones.
class MapCard extends StatelessWidget {
  const MapCard({super.key, required this.map, required this.selected, required this.onTap});

  static const width = 290.0;
  final MapDef map;
  final bool selected;
  final VoidCallback onTap;

  /// The 3D map's screenshot when playing in 3D, else the 2D board.
  Widget _preview(BuildContext context) {
    final thumb = modelThumb(map);
    if (thumb == null || !context.services.settings.board3d || !board3dSupported) return MapPreview(map, cacheWidth: 640, quality: FilterQuality.medium);
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 6)),
      child: Image.asset(thumb, fit: BoxFit.cover, width: double.infinity, height: double.infinity, cacheWidth: 640),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shape = ChamferBorder(
      cut: 10,
      side: BorderSide(color: selected ? Palette.gold : Palette.bone.withValues(alpha: 0.2), width: selected ? 2 : 1),
    );
    final starts = map.spaces.where((s) => s.start != null).length;
    return Semantics(
      button: true,
      selected: selected,
      label: '${map.name}. ${map.blurb}',
      child: SizedBox(
        width: width,
        child: Material(
          color: selected ? Palette.panelHi : Palette.panel,
          shape: shape,
          elevation: selected ? 8 : 1,
          shadowColor: Colors.black,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: Stack(
                        children: [
                          Positioned.fill(child: _preview(context)),
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Material(
                              color: const Color(0xB30A0D13),
                              shape: const ChamferBorder(cut: 4, side: BorderSide(color: Palette.line)),
                              child: InkWell(
                                customBorder: const ChamferBorder(cut: 4),
                                onTap: () => showMapInspectDialog(context, map),
                                child: const Tooltip(
                                  message: 'Inspect battlefield in full resolution',
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.zoom_in_rounded, size: 16, color: Palette.brass),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          map.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle(18, color: selected ? Palette.brass : Palette.bone, spacing: 0.8),
                        ),
                      ),
                      if (selected) const Icon(Icons.check_circle_rounded, color: Palette.confirmHi, size: 20),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    map.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(12.5, color: Palette.muted),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${map.spaces.length} SPACES · $starts STARTS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle(11, color: Palette.boneDim, weight: FontWeight.w600, spacing: 0.6),
                        ),
                      ),
                      const SizedBox(width: 4),
                      for (final z in map.zones.values.take(5))
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Tooltip(
                            message: z.name,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: hexColor(z.color),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black54),
                              ),
                            ),
                          ),
                        ),
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
