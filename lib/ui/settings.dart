/// Player settings, persisted with shared_preferences.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Quality { low, medium, high, ultra }

enum AnimSpeed { slow, normal, fast }

/// How long each combat step stays on screen (reveal, effects, values, result).
enum CombatPace { normal, slow, slower }

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

  /// Texture filter quality for a picture of unknown on-screen size (High and Ultra: bicubic).
  FilterQuality get filterQuality => switch (this) {
    Quality.low => FilterQuality.low,
    Quality.medium => FilterQuality.medium,
    Quality.high || Quality.ultra => FilterQuality.high,
  };

  /// Texture filter for a picture drawn at [screenPxPerImagePx] (above 1: magnified). Bicubic
  /// (high) is the sharpest way to enlarge, but it samples no mipmaps, so a picture shrunk with
  /// it shimmers and looks pixelated; shrinking uses mipmapped bilinear (medium) instead.
  FilterQuality filterFor(double screenPxPerImagePx) => switch (this) {
    Quality.low => FilterQuality.low,
    Quality.medium => FilterQuality.medium,
    Quality.high || Quality.ultra => screenPxPerImagePx > 1 ? FilterQuality.high : FilterQuality.medium,
  };

  /// Target width limit for decoding map textures (null = native 100% resolution for crystal sharpness).
  int? get maxTextureWidth => switch (this) {
    Quality.low => 1536,
    Quality.medium => 2560,
    Quality.high || Quality.ultra => null,
  };

  /// Procedural vector board rasterization scale multiplier.
  double get bakeScale => switch (this) {
    Quality.low => 1.5,
    Quality.medium => 2.2,
    Quality.high => 3.2,
    Quality.ultra => 4.0,
  };

  /// Step of the highlights' breathing pulse on the 2D board. Each step repaints the board layer,
  /// so it stays at a vsync divisor (30 or 20 a second) that a 0.9 s pulse doesn't need more of;
  /// a faster one only took frame time from the camera and the moving pieces.
  Duration get pulseStep => switch (this) {
    Quality.low || Quality.medium => const Duration(milliseconds: 50),
    Quality.high || Quality.ultra => const Duration(milliseconds: 33),
  };
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

extension CombatPaceX on CombatPace {
  String get label => switch (this) {
    CombatPace.normal => 'Normal',
    CombatPace.slow => 'Slow',
    CombatPace.slower => 'Very slow',
  };

  /// Multiplies the combat steps' delays (on top of the animation speed).
  double get factor => switch (this) {
    CombatPace.normal => 1.0,
    CombatPace.slow => 1.7,
    CombatPace.slower => 2.6,
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

  /// The signed-in account's session token (empty: not signed in). The username above is then
  /// the account's name.
  String accountToken = '';
  bool get signedIn => accountToken.isNotEmpty;
  /// High everywhere: the 3D board's frame-rate governor keeps phones at 60 fps by itself.
  Quality quality = Quality.high;
  AnimSpeed animSpeed = AnimSpeed.normal;
  CombatPace combatPace = CombatPace.slow;
  double musicVolume = 0.6;
  double sfxVolume = 0.8;

  /// Ask "Are you sure?" before attacking.
  bool confirmActions = true;

  /// Play on the 3D map models instead of the flat 2D board (where the platform and map allow).
  bool board3d = true;

  // 3D map graphics. Choosing a quality preset sets all of these; each can then be changed.

  /// Render resolution as a share of the screen's pixels (0.5–1.5), within the quality's pixel
  /// budget.
  double renderScale = 1;

  /// Trade resolution and effects for a steady 60 fps when frames run long.
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
      Quality.low => (0.75, Shadows.off, false, false, false),
      Quality.medium => (0.9, Shadows.low, true, true, false),
      Quality.high => (1.0, Shadows.medium, true, true, false),
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
    // texture, figure and badge detail, and the pixel budget
    'tier': quality.index,
  };

  void _read() {
    final p = _prefs;
    if (p == null) return;
    username = p.getString('username') ?? '';
    accountToken = p.getString('accountToken') ?? '';
    applyPreset(_pick(Quality.values, p.getInt('quality')) ?? quality);
    animSpeed = _pick(AnimSpeed.values, p.getInt('animSpeed')) ?? animSpeed;
    combatPace = _pick(CombatPace.values, p.getInt('combatPace')) ?? combatPace;
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
  static T? _pick<T>(List<T> values, int? i) =>
      i != null && i >= 0 && i < values.length ? values[i] : null;

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setString('username', username);
      await p.setString('accountToken', accountToken);
      await p.setInt('quality', quality.index);
      await p.setInt('animSpeed', animSpeed.index);
      await p.setInt('combatPace', combatPace.index);
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
