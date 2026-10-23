/// Player settings, persisted with shared_preferences.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Quality { low, medium, high, ultra }

enum AnimSpeed { slow, normal, fast }

extension QualityX on Quality {
  String get label => switch (this) {
    Quality.low => 'Low',
    Quality.medium => 'Medium',
    Quality.high => 'High',
    Quality.ultra => 'Ultra',
  };

  /// Glowing orbs and highlights (soft shadows).
  bool get glow => this != Quality.low;

  /// Hit sparks and other particles.
  bool get particles => index >= Quality.high.index;

  /// Camera push-in during combat.
  bool get cameraEffects => this != Quality.low;

  /// Screen shake on hits.
  bool get shake => index >= Quality.high.index;

  /// Pulsing highlights (animated every frame).
  bool get pulse => this != Quality.low;
}

extension AnimSpeedX on AnimSpeed {
  String get label => switch (this) {
    AnimSpeed.slow => 'Slow',
    AnimSpeed.normal => 'Normal',
    AnimSpeed.fast => 'Fast',
  };
  double get factor => switch (this) {
    AnimSpeed.slow => 1.6,
    AnimSpeed.normal => 1.0,
    AnimSpeed.fast => 0.5,
  };
}

/// 3D map shadow detail.
enum Shadows { off, low, medium, high }

extension ShadowsX on Shadows {
  String get label => switch (this) {
    Shadows.off => 'Off',
    Shadows.low => 'Low',
    Shadows.medium => 'Medium',
    Shadows.high => 'High',
  };
}

class Settings extends ChangeNotifier {
  Settings._(this._prefs) {
    applyPreset(quality);
  }

  static Future<Settings> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final s = Settings._(prefs);
    s._read();
    return s;
  }

  /// In-memory settings (tests, previews).
  factory Settings.memory() => Settings._(null);

  final SharedPreferences? _prefs;

  String username = '';
  Quality quality = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS
      ? Quality.medium
      : Quality.high;
  AnimSpeed animSpeed = AnimSpeed.normal;
  double musicVolume = 0.6;
  double sfxVolume = 0.8;

  /// Ask "Are you sure?" before attacking.
  bool confirmActions = true;

  /// Play on the 3D map models instead of the flat 2D board (where the platform and map allow).
  bool board3d = true;

  // 3D map graphics. Choosing a quality preset sets all of these; each can then be changed.

  /// Render resolution as a share of the screen's pixels (0.5–1.5).
  double renderScale = 1;

  /// Lower the resolution by itself when frames run long.
  bool autoResolution = true;
  Shadows shadows = Shadows.medium;
  bool antialias = true;

  /// Glow on the orbs, highlights and bright spots.
  bool bloom = true;

  /// Soft contact shadows in corners and under objects (costly).
  bool ambientOcclusion = false;

  /// Trees, rocks, buildings and water around the spaces.
  bool scenery = true;
  double brightness = 1;

  /// Name plates over the fighters.
  double labelSize = 1;
  bool showFps = false;

  /// Multiplies every presentation delay. Tests set it to 0.
  double? speedOverride;
  double get speed => speedOverride ?? animSpeed.factor;

  bool get hasUsername => username.trim().isNotEmpty;

  /// Sets the quality and the 3D graphics that go with it.
  void applyPreset(Quality q) {
    quality = q;
    final (scale, shadow, aa, glow, ao) = switch (q) {
      Quality.low => (0.6, Shadows.off, false, false, false),
      Quality.medium => (0.8, Shadows.low, true, true, false),
      Quality.high => (1.0, Shadows.medium, true, true, true),
      Quality.ultra => (1.25, Shadows.high, true, true, true),
    };
    renderScale = scale;
    shadows = shadow;
    antialias = aa;
    bloom = glow;
    ambientOcclusion = ao;
    autoResolution = true;
    scenery = true;
  }

  /// What the 3D page needs (see assets/web3d/board.js).
  Map<String, Object> get graphics3d => {
    'scale': renderScale,
    'auto': autoResolution,
    'shadows': shadows.index,
    'aa': antialias,
    'bloom': bloom,
    'ao': ambientOcclusion,
    'scenery': scenery,
    'brightness': brightness,
    'labels': labelSize,
    'fps': showFps,
  };

  void _read() {
    final p = _prefs;
    if (p == null) return;
    username = p.getString('username') ?? '';
    applyPreset(_pick(Quality.values, p.getInt('quality')) ?? quality);
    animSpeed = _pick(AnimSpeed.values, p.getInt('animSpeed')) ?? animSpeed;
    musicVolume = p.getDouble('musicVolume') ?? musicVolume;
    sfxVolume = p.getDouble('sfxVolume') ?? sfxVolume;
    confirmActions = p.getBool('confirmActions') ?? confirmActions;
    board3d = p.getBool('board3d') ?? board3d;
    renderScale = p.getDouble('renderScale') ?? renderScale;
    autoResolution = p.getBool('autoResolution') ?? autoResolution;
    shadows = _pick(Shadows.values, p.getInt('shadows')) ?? shadows;
    antialias = p.getBool('antialias') ?? antialias;
    bloom = p.getBool('bloom') ?? bloom;
    ambientOcclusion = p.getBool('ambientOcclusion') ?? ambientOcclusion;
    scenery = p.getBool('scenery') ?? scenery;
    brightness = p.getDouble('brightness') ?? brightness;
    labelSize = p.getDouble('labelSize') ?? labelSize;
    showFps = p.getBool('showFps') ?? showFps;
  }

  /// The stored enum index, if it is a valid one (elementAtOrNull throws on negatives).
  static T? _pick<T>(List<T> values, int? i) => i != null && i >= 0 && i < values.length ? values[i] : null;

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setString('username', username);
      await p.setInt('quality', quality.index);
      await p.setInt('animSpeed', animSpeed.index);
      await p.setDouble('musicVolume', musicVolume);
      await p.setDouble('sfxVolume', sfxVolume);
      await p.setBool('confirmActions', confirmActions);
      await p.setBool('board3d', board3d);
      await p.setDouble('renderScale', renderScale);
      await p.setBool('autoResolution', autoResolution);
      await p.setInt('shadows', shadows.index);
      await p.setBool('antialias', antialias);
      await p.setBool('bloom', bloom);
      await p.setBool('ambientOcclusion', ambientOcclusion);
      await p.setBool('scenery', scenery);
      await p.setDouble('brightness', brightness);
      await p.setDouble('labelSize', labelSize);
      await p.setBool('showFps', showFps);
    } catch (_) {
      // Storage can be unavailable (private browsing); settings then last for the session.
    }
  }

  void update(void Function(Settings s) change) {
    change(this);
    notifyListeners();
    _save();
  }
}
