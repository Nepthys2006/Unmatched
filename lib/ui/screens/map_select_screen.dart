/// A dedicated screen for choosing and inspecting battlefields in LAN, Online, and match setup.
/// Displays interactive 2D/3D board previews, space counts, starting positions, zones, and rules.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

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
      final i = widget.maps.indexOf(_selected);
      if (i > 0 && _scroll.hasClients) {
        _scroll.animateTo(
          (i * 300.0 - 40).clamp(0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
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
    final i = widget.maps.indexOf(pick);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        (i * 300.0 - 40).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
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
                          height: 38,
                          fontSize: 14,
                          onPressed: _random,
                        )
                      : null,
                ),
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
                  child: ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    itemCount: maps.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => MapCard(
                      map: maps[i],
                      selected: maps[i] == _selected,
                      onTap: () => setState(() => _selected = maps[i]),
                    ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
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
                    const SizedBox(height: 2),
                    Text(
                      _selected.blurb,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: bodyStyle(13, color: Palette.boneDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              if (widget.canSelect)
                PlateButton(
                  label: 'Select Battlefield',
                  icon: Icons.check_rounded,
                  style: PlateStyle.confirm,
                  height: 48,
                  fontSize: 17,
                  onPressed: _confirm,
                )
              else
                PlateButton(
                  label: 'Close',
                  style: PlateStyle.secondary,
                  height: 46,
                  fontSize: 16,
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card displaying a battlefield's preview, name, description, spaces, starts, and zones.
class MapCard extends StatelessWidget {
  const MapCard({super.key, required this.map, required this.selected, required this.onTap});
  final MapDef map;
  final bool selected;
  final VoidCallback onTap;

  /// The 3D map's screenshot when playing in 3D, else the 2D board.
  Widget _preview(BuildContext context) {
    final thumb = modelThumb(map);
    if (thumb == null || !context.services.settings.board3d || !board3dSupported) return MapPreview(map);
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 6)),
      child: Image.asset(thumb, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
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
        width: 290,
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
