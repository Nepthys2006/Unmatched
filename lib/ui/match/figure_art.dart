/// The fighters' pictures for the 2D board: each hero's miniature (`assets/heroes/<id>/figure*.webp`,
/// cut off its printed base by tool/make_figures.py) and each sidekick's round token. Decoded once,
/// small, and shared; the board repaints when one arrives.
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../engine/state.dart';

/// A decoded figure and where its printed base was: [baseW] wide, centred [baseX] from the left
/// (both in the picture's pixels), so it can stand on a podium at its real size.
class FigureImage {
  FigureImage(this.image, this.baseW, this.baseX, {this.token = false});
  final ui.Image image;
  final double baseW;
  final double baseX;

  /// A sidekick's round token rather than a miniature.
  final bool token;
}

class FigureArt {
  FigureArt._();
  static final FigureArt instance = FigureArt._();

  /// Bumps whenever a picture finishes loading.
  final ValueNotifier<int> loaded = ValueNotifier(0);

  Map<String, List<Map<String, dynamic>>>? _index;
  Future<void>? _indexLoad;
  final Map<String, FigureImage?> _images = {};
  final Set<String> _pending = {};

  /// Which of a hero's figures [f] is: heroes with several hero fighters (the three Raptors) get
  /// one each.
  static int variantOf(Fighter f) => f.isHero ? f.owner.fighters.where((x) => x.isHero).toList().indexOf(f) : 0;

  /// The picture for [f], or null while it loads (or if there is none: the board draws an orb).
  FigureImage? of(Fighter f) {
    final hero = f.owner.hero.id;
    final key = f.isHero ? '$hero#${variantOf(f)}' : '$hero/${f.def.id}';
    if (_images.containsKey(key)) return _images[key];
    if (_pending.add(key)) _load(key, f, hero);
    return null;
  }

  Future<void> _load(String key, Fighter f, String hero) async {
    FigureImage? img;
    try {
      if (f.isHero) {
        await (_indexLoad ??= _loadIndex());
        final list = _index?[hero];
        if (list != null && list.isNotEmpty) {
          final spec = list[variantOf(f).clamp(0, list.length - 1)];
          final asset = 'assets/${(spec['file'] as String).replaceFirst('../', '')}';
          img = FigureImage(await _decode(asset, 220), (spec['baseW'] as num).toDouble() * _scale(spec, 220),
              (spec['baseX'] as num).toDouble() * _scale(spec, 220));
        }
      } else {
        final image = await _decode('assets/heroes/$hero/${f.def.id}.webp', 128);
        img = FigureImage(image, image.width.toDouble(), image.width / 2, token: true);
      }
    } catch (e) {
      debugPrint('figure $key: $e');
    }
    _images[key] = img;
    _pending.remove(key);
    loaded.value++;
  }

  /// How much a picture shrinks when decoded at most [max] pixels tall.
  static double _scale(Map<String, dynamic> spec, int max) {
    final h = (spec['h'] as num).toDouble();
    return h > max ? max / h : 1;
  }

  Future<void> _loadIndex() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/web3d/figures.json')) as Map<String, dynamic>;
    _index = {for (final e in raw.entries) e.key: [for (final s in e.value as List) s as Map<String, dynamic>]};
  }

  static Future<ui.Image> _decode(String asset, int maxH) async {
    final data = await rootBundle.load(asset);
    final probe = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await probe.getNextFrame();
    final h = frame.image.height;
    if (h <= maxH) return frame.image;
    frame.image.dispose();
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetHeight: maxH);
    return (await codec.getNextFrame()).image;
  }
}
