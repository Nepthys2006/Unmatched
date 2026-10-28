/// The 3D battlefield: the 3D Map table's models (`assets/maps3d/<id>.glb`) drawn by Three.js in a
/// web view (assets/web3d/), with the match screen's HUD on top. The page only draws and takes
/// no input: the match screen handles every touch (so its buttons always come first), sends
/// camera moves and taps to the page, and gets taps back in map coordinates.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../engine/defs.dart';
import 'host_stub.dart'
    if (dart.library.io) 'host_io.dart'
    if (dart.library.js_interop) 'host_web.dart'
    as host;

/// Every battlefield is a printed-style map (assets/maps); the 3D board lays its art on a slab on
/// the table, with the fighters as figures.
bool hasModel(MapDef map) => map.art != null;

/// Screenshot of the 3D map, for map pickers: the map's own art (MapPreview) serves for both views.
String? modelThumb(MapDef map) => null;

/// Whether this platform can show the 3D board (Android, iOS, Windows and the web).
bool get board3dSupported => host.supported;

enum Board3DStatus { loading, ready, failed }

/// Talks to one 3D board page.
class Board3DController {
  Board3DController({
    required this.map,
    required Map<String, Object> graphics,
    required this.homeSide,
  }) : _graphics = graphics,
       antialias = graphics['aa'] == true;

  final MapDef map;

  /// Settings.graphics3d. Antialiasing is fixed when the page starts; the rest can change live.
  Map<String, Object> _graphics;
  final bool antialias;

  /// +1 if the player's start is on the near (+y) half of the board, -1 if on the far half.
  final int homeSide;

  final ValueNotifier<Board3DStatus> status = ValueNotifier(
    Board3DStatus.loading,
  );
  final ValueNotifier<double> progress = ValueNotifier(0);

  /// Frames drawn per second, when Settings > Show FPS is on.
  final ValueNotifier<int?> fps = ValueNotifier(null);
  String? error;

  /// Taps on the board, in map coordinates.
  final StreamController<Offset> _taps = StreamController.broadcast();
  Stream<Offset> get taps => _taps.stream;

  void Function(String json)? _raw;
  bool _open = false;
  String? _lastState;
  bool _disposed = false;

  bool get ready => status.value == Board3DStatus.ready;

  /// Sends a message once the page is listening; the latest board state is kept and replayed.
  void send(Map<String, Object?> msg) {
    final json = jsonEncode(msg);
    if (msg['t'] == 'state') {
      if (json == _lastState) return;
      _lastState = json;
    }
    if (_open) _raw?.call(json);

    //set function for reset when graphics is hard to load
  }

  /// Applies changed graphics settings to the running page.
  void setGraphics(Map<String, Object> g) {
    if (mapEquals(g, _graphics)) return;
    _graphics = g;
    if (g['fps'] != true) fps.value = null;
    send({'t': 'gfx', 'gfx': g});
  }

  /// Host side: how to reach the page.
  void bind(void Function(String json) raw) => _raw = raw;

  /// Host side: a message from the page.
  void receive(Object? raw) {
    if (_disposed) return;
    Map<String, Object?>? m;
    try {
      final v = raw is String ? jsonDecode(raw) : raw;
      if (v is Map) m = v.cast<String, Object?>();
    } catch (_) {
      return;
    }
    if (m == null) return;
    switch (m['t']) {
      case 'loaded':
        if (_open) return;
        _open = true;
        _raw?.call(jsonEncode(_init()));
        if (_lastState != null) _raw?.call(_lastState!);
      case 'progress':
        progress.value = (m['p'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0;
      case 'ready':
        status.value = Board3DStatus.ready;
      case 'error':
        debugPrint('3D board: ${m['msg']}');
        if (m['fatal'] == true && status.value != Board3DStatus.ready) {
          fail('${m['msg']}');
        }
      case 'fps':
        fps.value = (m['v'] as num?)?.round();
      case 'tap':
        final x = (m['x'] as num?)?.toDouble(),
            y = (m['y'] as num?)?.toDouble();
        if (x != null && y != null) _taps.add(Offset(x, y));
    }
  }

  /// Host side: the page could not be shown at all.
  void fail(String why) {
    if (_disposed || status.value == Board3DStatus.failed) return;
    error = why;
    status.value = Board3DStatus.failed;
  }

  Map<String, Object?> _init() => {
    't': 'init',
    if (map.art case final art?)
      'art': {'file': '../maps/${art.file}', 'w': art.w, 'h': art.h, 'unitPx': art.unitPx}
    else
      'glb': '../maps3d/${map.id}.glb',
    'gfx': _graphics,
    'home': homeSide,
    'spaces': [
      for (final s in map.spaces) {'id': s.id, 'x': s.x, 'y': s.y},
    ],
    'links': [
      for (final (a, b) in map.links) [a, b],
    ],
  };

  void dispose() {
    _disposed = true;
    _raw = null;
    _taps.close();
    status.dispose();
    progress.dispose();
    fps.dispose();
  }
}

/// The web view showing the board for [controller].
class Board3DView extends StatelessWidget {
  const Board3DView({super.key, required this.controller});
  final Board3DController controller;

  @override
  Widget build(BuildContext context) => host.buildHost(controller);
}
