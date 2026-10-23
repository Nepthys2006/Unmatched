/// Music and sound effects. Every call is fire-and-forget and never throws: audio is optional
/// (tests, browsers that block autoplay, devices without output).
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'settings.dart';

enum Music { menu, battle }

enum Sfx { card, hit, whoosh, step, reveal, victory, click, heal }

class Audio {
  Audio(this.settings, {this.enabled = true}) {
    settings.addListener(_onSettings);
  }

  final Settings settings;

  /// False in tests: no platform channels are touched at all.
  final bool enabled;

  AudioPlayer? _music;
  Music? _current;
  bool _musicStarted = false;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  final Map<Sfx, DateTime> _last = {};

  void _onSettings() {
    if (!enabled) return;
    _guard(() async => _music?.setVolume(settings.musicVolume));
  }

  void _guard(Future<void> Function() f) {
    try {
      unawaited(f().catchError((Object _) {}));
    } catch (_) {}
  }

  /// Starts (or switches to) a looping track.
  void music(Music m) {
    if (!enabled) return;
    if (_current == m && _musicStarted) return;
    _current = m;
    _guard(() async {
      final p = _music ??= AudioPlayer(playerId: 'music');
      await p.stop();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(AssetSource('audio/${m.name}.wav'), volume: settings.musicVolume);
      _musicStarted = true;
    });
  }

  /// Browsers only allow audio after a user gesture: retry the music on the first tap.
  void userGesture() {
    if (!enabled || _musicStarted || _current == null) return;
    final m = _current!;
    _current = null;
    music(m);
  }

  void stopMusic() {
    if (!enabled) return;
    _current = null;
    _musicStarted = false;
    _guard(() async => _music?.stop());
  }

  void sfx(Sfx s, {double volume = 1}) {
    if (!enabled || settings.sfxVolume <= 0) return;
    // Don't stack the same sound within 60 ms (a burst of steps or hits).
    final now = DateTime.now();
    final last = _last[s];
    if (last != null && now.difference(last).inMilliseconds < 60) return;
    _last[s] = now;
    _guard(() async {
      if (_pool.length < 6) {
        final p = AudioPlayer(playerId: 'sfx${_pool.length}');
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
      final p = _pool[_next++ % _pool.length];
      await p.stop();
      await p.play(AssetSource('audio/${s.name}.wav'), volume: (settings.sfxVolume * volume).clamp(0, 1));
    });
  }
}
