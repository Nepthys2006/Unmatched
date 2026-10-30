/// Music and sound effects. Every call is fire-and-forget and never throws: audio is optional
/// (tests, browsers that block autoplay, devices without output).
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'settings.dart';

/// A music track: the mp3 to play, the older synthesized wav to fall back on if the mp3 can't be
/// played (a codec the device lacks, a failed download), whether it loops, and a level trim.
///
/// The trims keep the music well under the sound effects and the three tracks level with each
/// other (measured RMS: menu -22 dB, battle -19 dB, victory -23 dB; the effects sit near -15 dB).
/// The player's music slider scales on top of them.
enum Music {
  menu('menu_theme.mp3', 'menu.wav', gain: 0.7),
  battle('battle_theme.mp3', 'battle.wav', gain: 0.55),
  victory('victory_theme.mp3', 'victory.wav', loop: false, gain: 0.8);

  const Music(this.file, this.fallback, {this.loop = true, required this.gain});
  final String file;
  final String fallback;
  final bool loop;
  final double gain;
}

enum Sfx { card, hit, whoosh, step, reveal, victory, click, heal }

class Audio {
  Audio(
    this.settings, {
    this.enabled = true,
    AudioPlayer Function(String playerId)? playerFactory,
    this.fadeStep = const Duration(milliseconds: 50),
  }) : _newPlayer = playerFactory ?? ((id) => AudioPlayer(playerId: id)) {
    settings.addListener(_onSettings);
  }

  final Settings settings;

  /// False in tests: no platform channels are touched at all.
  final bool enabled;

  /// Tests pass fakes here (and a short [fadeStep]) to exercise the switching logic.
  final AudioPlayer Function(String playerId) _newPlayer;
  final Duration fadeStep;

  static const _fadeInSteps = 14;
  static const _fadeOutSteps = 5;

  /// Every player plays alongside the others and never asks Android for audio focus.
  ///
  /// By default each player requests focus when it starts, and Android answers the player that
  /// held it (the music) with a permanent "focus lost", which the plugin handles by pausing it for
  /// good. So every click or hit sound silenced the music until the next track change. Mixing
  /// with others means no sound can pause another. (On the web and Windows this is ignored.)
  static final AudioContext _mix = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

  AudioPlayer? _music;
  Music? _current;
  bool _musicStarted = false;
  bool _musicPrepared = false;
  DateTime _lastEnsure = DateTime.fromMillisecondsSinceEpoch(0);

  /// The track loaded in the player (its trim applies to the volume), which may differ from
  /// [_current] while a change is under way.
  Music? _track;

  double get _musicLevel => (settings.musicVolume * (_track?.gain ?? 1)).clamp(0.0, 1.0);

  /// Bumped by every track change, so a slower earlier change notices it was overtaken and stops.
  int _generation = 0;
  final List<AudioPlayer> _pool = [];

  /// One entry per pool player: completes once it is set up (never with an error).
  final List<Future<void>> _poolReady = [];
  int _next = 0;
  final Map<Sfx, DateTime> _last = {};

  void _onSettings() {
    if (!enabled) return;
    _guard(() async => _music?.setVolume(_musicLevel));
  }

  void _guard(Future<void> Function() f) {
    try {
      unawaited(f().catchError((Object _) {}));
    } catch (_) {}
  }

  /// Sets [p] up to play alongside everything else (see [_mix]). Never throws.
  Future<void> _mixWithOthers(AudioPlayer p, {ReleaseMode? releaseMode}) async {
    try {
      await p.setAudioContext(_mix);
    } catch (_) {}
    if (releaseMode == null) return;
    try {
      await p.setReleaseMode(releaseMode);
    } catch (_) {}
  }

  /// Starts (or switches to) a track: the old one fades out, the new one fades in.
  void music(Music m) {
    if (!enabled) return;
    if (_current == m && _musicStarted) return;
    _current = m;
    final gen = ++_generation;
    _guard(() async {
      final p = _music ??= _newPlayer('music');
      if (!_musicPrepared) {
        _musicPrepared = true;
        await _mixWithOthers(p);
      }
      if (_musicStarted) await _fadeOut(p, gen);
      if (gen != _generation) return;
      await p.stop();
      if (gen != _generation) return;
      _musicStarted = false;
      await p.setReleaseMode(m.loop ? ReleaseMode.loop : ReleaseMode.stop);
      if (gen != _generation) return;
      _track = m;
      try {
        await p.play(AssetSource('audio/${m.file}'), volume: 0);
      } catch (_) {
        // The mp3 won't play here: use the plain wav. If that fails too (autoplay blocked), the
        // error ends this call and the next tap retries from the top.
        if (gen != _generation) return;
        await p.play(AssetSource('audio/${m.fallback}'), volume: 0);
      }
      if (gen != _generation) return;
      _musicStarted = true;
      await _fadeIn(p, gen);
    });
  }

  Future<void> _fadeIn(AudioPlayer p, int gen) async {
    for (var i = 1; i <= _fadeInSteps; i++) {
      await Future<void>.delayed(fadeStep);
      if (gen != _generation) return;
      await p.setVolume(_musicLevel * i / _fadeInSteps);
    }
  }

  Future<void> _fadeOut(AudioPlayer p, int gen) async {
    for (var i = _fadeOutSteps - 1; i >= 0; i--) {
      if (gen != _generation) return;
      await p.setVolume(_musicLevel * i / _fadeOutSteps);
      await Future<void>.delayed(fadeStep);
    }
  }

  /// Browsers only allow audio after a user gesture: retry the music on the first tap. Once it is
  /// playing, a tap also checks it was not paused behind our back (see [ensureMusic]).
  void userGesture() {
    if (!enabled || _current == null) return;
    if (_musicStarted) {
      ensureMusic();
      return;
    }
    final m = _current!;
    _current = null;
    music(m);
  }

  /// Puts the music back if the system paused or stopped it without us asking (a phone call, another
  /// app taking over the audio, the app coming back from the background). Resuming a player that
  /// is already playing does nothing, so this is safe to call at any time. Looping tracks only:
  /// the victory theme plays once and must not start again. At most once every 2 seconds.
  void ensureMusic() {
    final m = _current;
    final p = _music;
    if (!enabled || m == null || p == null || !_musicStarted || !m.loop) return;
    final now = DateTime.now();
    if (now.difference(_lastEnsure) < const Duration(seconds: 2)) return;
    _lastEnsure = now;
    final gen = _generation;
    _guard(() async {
      if (gen != _generation) return;
      await p.resume();
    });
  }

  void stopMusic() {
    if (!enabled) return;
    _current = null;
    _musicStarted = false;
    _generation++;
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
        // Added before the first await: overlapping calls must see the pool already grown.
        final fresh = _newPlayer('sfx${_pool.length}');
        _pool.add(fresh);
        _poolReady.add(_mixWithOthers(fresh, releaseMode: ReleaseMode.stop));
      }
      final i = _next++ % _pool.length;
      await _poolReady[i]; // set up (and mixing with others) before its first sound
      final p = _pool[i];
      await p.stop();
      await p.play(AssetSource('audio/${s.name}.wav'), volume: (settings.sfxVolume * volume).clamp(0, 1));
    });
  }
}
