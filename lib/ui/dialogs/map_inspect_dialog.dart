/// Fullscreen interactive battlefield map inspection dialog.
/// Allows players in the lobby (hosts and waiting guests) to inspect map art,
/// spaces, starting positions, and zone topologies in high resolution.
library;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../board/board_painter.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

/// Opens an interactive high-resolution battlefield inspection dialog.
Future<void> showMapInspectDialog(BuildContext context, MapDef map) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close battlefield inspector',
    barrierColor: const Color(0xD90A0D13),
    pageBuilder: (ctx, _, _) => _MapInspectView(map: map),
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(c), child: child),
      );
    },
    transitionDuration: const Duration(milliseconds: 240),
  );
}

class _MapInspectView extends StatefulWidget {
  const _MapInspectView({required this.map});
  final MapDef map;

  @override
  State<_MapInspectView> createState() => _MapInspectViewState();
}

class _MapInspectViewState extends State<_MapInspectView> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = widget.map;
    final geo = BoardGeometry(map);
    final starts = map.spaces.where((s) => s.start != null).length;
    final mq = MediaQuery.of(context);
    final isCompact = mq.size.width < 700 || mq.size.height < 520;

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: EdgeInsets.all(isCompact ? 8 : 20),
            decoration: const ShapeDecoration(
              color: Palette.bgDeep,
              shape: ChamferBorder(
                cut: 12,
                side: BorderSide(color: Palette.brass, width: 1.6),
              ),
              shadows: [
                BoxShadow(color: Color(0xDD000000), blurRadius: 36, offset: Offset(0, 10)),
              ],
            ),
            child: ClipPath(
              clipper: const ShapeBorderClipper(shape: ChamferBorder(cut: 12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20, vertical: isCompact ? 10 : 14),
                    decoration: const ShapeDecoration(
                      color: Palette.panel,
                      shape: Border(bottom: BorderSide(color: Palette.line, width: 1.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.map_rounded, color: Palette.brass, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                map.name.toUpperCase(),
                                style: titleStyle(isCompact ? 17 : 21, color: Palette.brass, spacing: 0.8),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${map.spaces.length} SPACES · $starts STARTING POSITIONS · ${map.set.isNotEmpty ? map.set : map.theme.toUpperCase()}',
                                style: titleStyle(isCompact ? 11 : 12, color: Palette.boneDim, spacing: 0.6),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        HexButton(
                          icon: Icons.close_rounded,
                          size: 34,
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Interactive Map Canvas
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, constraints) {
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: InteractiveViewer(
                                transformationController: _controller,
                                minScale: 0.5,
                                maxScale: 4.0,
                                clipBehavior: Clip.hardEdge,
                                boundaryMargin: const EdgeInsets.all(300),
                                child: Center(
                                  child: SizedBox(
                                    width: geo.size.width,
                                    height: geo.size.height,
                                    child: map.art != null
                                        ? Stack(
                                            children: [
                                              Positioned.fill(
                                                child: Image.asset(
                                                  map.art!.asset,
                                                  fit: BoxFit.fill,
                                                  filterQuality: FilterQuality.high,
                                                ),
                                              ),
                                              Positioned.fill(
                                                child: CustomPaint(
                                                  painter: BoardPainter(geo, detailed: true, showStarts: true),
                                                ),
                                              ),
                                            ],
                                          )
                                        : CustomPaint(
                                            painter: BoardPainter(geo, detailed: true, showStarts: true),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            // Zoom controls overlay
                            Positioned(
                              right: 14,
                              bottom: 14,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ZoomButton(
                                    icon: Icons.add_rounded,
                                    tooltip: 'Zoom in',
                                    onPressed: () {
                                      _controller.value = _controller.value * Matrix4.diagonal3Values(1.3, 1.3, 1.0);
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  _ZoomButton(
                                    icon: Icons.remove_rounded,
                                    tooltip: 'Zoom out',
                                    onPressed: () {
                                      _controller.value = _controller.value * Matrix4.diagonal3Values(0.77, 0.77, 1.0);
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  _ZoomButton(
                                    icon: Icons.center_focus_strong_rounded,
                                    tooltip: 'Reset view',
                                    onPressed: () {
                                      _controller.value = Matrix4.identity();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // Bottom Zones and Features Bar
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20, vertical: isCompact ? 8 : 12),
                    decoration: const ShapeDecoration(
                      color: Palette.panel,
                      shape: Border(top: BorderSide(color: Palette.line, width: 1.2)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text('ZONES: ', style: titleStyle(12, color: Palette.boneDim, spacing: 1)),
                          const SizedBox(width: 8),
                          for (final z in map.zones.values) ...[
                            Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: const ShapeDecoration(
                                color: Color(0x66000000),
                                shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.line)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: hexColor(z.color),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white70, width: 1),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(z.name, style: bodyStyle(12, color: Palette.bone)),
                                ],
                              ),
                            ),
                          ],
                          if (map.river) ...[
                            const SizedBox(width: 8),
                            const _Badge(label: 'RIVER MAP', color: Color(0xFF4A90E2)),
                          ],
                          if (map.oneWay.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            const _Badge(label: 'ONE-WAY DOORS', color: Palette.brass),
                          ],
                          if (map.stairs.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            const _Badge(label: 'STAIRWAYS', color: Palette.confirmHi),
                          ],
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

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC0A0D13),
      shape: const ChamferBorder(cut: 6, side: BorderSide(color: Palette.line)),
      child: InkWell(
        customBorder: const ChamferBorder(cut: 6),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Palette.bone, size: 20),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.15),
        shape: ChamferBorder(cut: 4, side: BorderSide(color: color.withValues(alpha: 0.6))),
      ),
      child: Text(label, style: titleStyle(10.5, color: color, spacing: 0.8)),
    );
  }
}
