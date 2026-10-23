/// Player settings, persisted with shared_preferences.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Quality { low, medium, high }

enum AnimSpeed { slow, normal, fast }

extension QualityX on Quality {
  String get label => switch (this) {
    Quality.low => 'Low',
    Quality.medium => 'Medium',
    Quality.high => 'High',
  };

  /// Glowing orbs and highlights (soft shadows).
  bool get glow => this != Quality.low;

  /// Hit sparks and other particles.
  bool get particles => this == Quality.high;

  /// Camera push-in during combat.
  bool get cameraEffects => this != Quality.low;

  /// Screen shake on hits.
  bool get shake => this == Quality.high;

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

class Settings extends ChangeNotifier {
  Settings._(this._prefs);

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

  /// Multiplies every presentation delay. Tests set it to 0.
  double? speedOverride;
  double get speed => speedOverride ?? animSpeed.factor;

  bool get hasUsername => username.trim().isNotEmpty;

  void _read() {
    final p = _prefs;
    if (p == null) return;
    username = p.getString('username') ?? '';
    quality = _pick(Quality.values, p.getInt('quality')) ?? quality;
    animSpeed = _pick(AnimSpeed.values, p.getInt('animSpeed')) ?? animSpeed;
    musicVolume = p.getDouble('musicVolume') ?? musicVolume;
    sfxVolume = p.getDouble('sfxVolume') ?? sfxVolume;
    confirmActions = p.getBool('confirmActions') ?? confirmActions;
    board3d = p.getBool('board3d') ?? board3d;
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
