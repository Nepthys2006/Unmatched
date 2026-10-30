import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unmatched_game/ui/audio.dart';
import 'package:unmatched_game/ui/settings.dart';

/// What the fake "device" does with audio, so a test can make mp3s fail or block autoplay.
class Device {
  bool failMp3 = false;
  bool blockAll = false; // a browser that hasn't had a tap yet

  /// Android: a player that starts while another holds audio focus makes that one lose it
  /// ("focus lost", which the plugin handles by pausing it for good). Players set up to mix with
  /// others never ask for focus.
  bool focusStealing = false;

  /// The fake pretends setAudioContext was never called (the code as it was before the fix).
  bool ignoreContext = false;
  final List<FakePlayer> players = [];
  int errorsThrown = 0;
}

/// A stand-in for [AudioPlayer] that records what is playing. Every call takes a moment, so calls
/// that overlap in the app overlap here too.
class FakePlayer extends Fake implements AudioPlayer {
  FakePlayer(this.id, this.device) {
    device.players.add(this);
  }
  final String id;
  final Device device;
  String? playing; // asset path, or null when stopped
  String? lastSource;
  double level = 1;
  ReleaseMode loopMode = ReleaseMode.release;
  int plays = 0;
  int resumes = 0;
  bool lostFocus = false;
  AudioContext? context;

  /// Android: a player asks for audio focus unless it plays "mixed with others".
  bool get requestsFocus => context == null || context!.android.audioFocus != AndroidAudioFocus.none;

  @override
  Future<void> setAudioContext(AudioContext ctx) async {
    await _tick();
    if (!device.ignoreContext) context = ctx;
  }

  @override
  Future<void> resume() async {
    await _tick();
    resumes++;
    if (playing == null && lastSource != null) {
      playing = lastSource;
      lostFocus = false;
    }
  }

  Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 2));

  @override
  Future<void> stop() async {
    await _tick();
    playing = null;
  }

  @override
  Future<void> setVolume(double v) async {
    await _tick();
    level = v;
  }

  @override
  Future<void> setReleaseMode(ReleaseMode m) async {
    await _tick();
    loopMode = m;
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    await _tick();
    final path = (source as AssetSource).path;
    if (device.blockAll || (device.failMp3 && path.endsWith('.mp3'))) {
      device.errorsThrown++;
      throw Exception('cannot play $path');
    }
    if (device.focusStealing && requestsFocus) {
      for (final other in device.players) {
        if (other != this && other.requestsFocus && other.playing != null) {
          other.playing = null; // focus lost: paused for good
          other.lostFocus = true;
        }
      }
    }
    playing = path;
    lastSource = path;
    plays++;
    if (volume != null) level = volume;
  }
}

Future<void> settle([int ms = 500]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late Settings settings;
  late Device device;
  late Audio audio;
  final unexpected = <Object>[];

  /// Runs [body]; errors the audio code lets escape into the zone are collected in [unexpected],
  /// while a failed expect() in the body fails the test as usual.
  Future<void> run(Future<void> Function() body) {
    final done = Completer<void>();
    runZonedGuarded(() async {
      try {
        await body();
        done.complete();
      } catch (e, st) {
        done.completeError(e, st);
      }
    }, (e, st) => unexpected.add(e));
    return done.future;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await Settings.load();
    settings.musicVolume = 0.6;
    device = Device();
    unexpected.clear();
    audio = Audio(settings, playerFactory: (id) => FakePlayer(id, device), fadeStep: const Duration(milliseconds: 1));
  });

  FakePlayer music() => device.players.firstWhere((p) => p.id == 'music');

  test('rapid switching ends on the last track, playing, at the music volume', () async {
    await run(() async {
      for (final m in [Music.menu, Music.battle, Music.menu, Music.battle, Music.victory, Music.menu, Music.battle]) {
        audio.music(m);
      }
      await settle();
      expect(music().playing, 'audio/battle_theme.mp3');
      expect(music().loopMode, ReleaseMode.loop);
      expect(music().level, closeTo(settings.musicVolume * Music.battle.gain, 0.001));
    });
    expect(unexpected, isEmpty);
  });

  test('a long random storm of switches, stops and taps never throws and always settles on the last request', () async {
    final rng = Random(42);
    await run(() async {
      Music? last;
      var stopped = false;
      for (var i = 0; i < 300; i++) {
        switch (rng.nextInt(4)) {
          case 0:
            audio.stopMusic();
            stopped = true;
            last = null;
          case 1:
            audio.userGesture();
          default:
            last = Music.values[rng.nextInt(Music.values.length)];
            audio.music(last);
            stopped = false;
        }
        if (rng.nextBool()) await Future<void>.delayed(Duration(milliseconds: rng.nextInt(6)));
      }
      await settle(800);
      final p = music();
      if (stopped || last == null) {
        expect(p.playing, isNull);
      } else {
        expect(p.playing, 'audio/${last.file}');
      }
    });
    expect(unexpected, isEmpty);
  });

  test('stopping during a fade-in leaves silence and nothing restarts it', () async {
    await run(() async {
      audio.music(Music.battle);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      audio.stopMusic();
      await settle();
      expect(music().playing, isNull);
    });
    expect(unexpected, isEmpty);
  });

  test('when the mp3 will not play the wav fallback does, and a later track still works', () async {
    device.failMp3 = true;
    await run(() async {
      audio.music(Music.menu);
      await settle();
      expect(music().playing, 'audio/menu.wav');
      audio.music(Music.battle);
      await settle();
      expect(music().playing, 'audio/battle.wav');
    });
    expect(unexpected, isEmpty);
  });

  test('autoplay blocked: nothing throws, and the next tap starts the music', () async {
    device.blockAll = true;
    await run(() async {
      audio.music(Music.menu);
      await settle();
      expect(device.players.where((p) => p.id == 'music').single.playing, isNull);
      device.blockAll = false; // the player tapped
      audio.userGesture();
      await settle();
      expect(music().playing, 'audio/menu_theme.mp3');
      expect(music().level, closeTo(settings.musicVolume * Music.menu.gain, 0.001));
    });
    expect(unexpected, isEmpty);
  });

  test('opening match after match: menu, battle, victory, menu, battle ... ends clean every time', () async {
    await run(() async {
      for (var i = 0; i < 10; i++) {
        audio.music(Music.menu);
        await settle(60);
        audio.music(Music.battle); // a match starts
        await settle(60);
        if (i.isEven) {
          audio.music(Music.victory); // won
          expect(Music.victory.loop, isFalse);
        } else {
          audio.stopMusic(); // lost
        }
        await settle(60);
      }
      audio.music(Music.menu);
      await settle();
      expect(music().playing, 'audio/menu_theme.mp3');
      expect(device.players.where((p) => p.id == 'music').length, 1, reason: 'one music player, reused');
    });
    expect(unexpected, isEmpty);
  });

  test('changing the volume mid-track applies, and silent sfx volume plays nothing', () async {
    await run(() async {
      audio.music(Music.menu);
      await settle();
      settings.update((x) => x.musicVolume = 0.2);
      await settle(50);
      expect(music().level, closeTo(0.2 * Music.menu.gain, 0.001));
      settings.update((x) => x.sfxVolume = 0);
      audio.sfx(Sfx.click);
      await settle(50);
      expect(device.players.where((p) => p.id.startsWith('sfx')), isEmpty);
    });
    expect(unexpected, isEmpty);
  });

  group('sound effects and the music (Android audio focus)', () {
    /// Every sound effect once, several times over, spaced past the same-sound guard.
    Future<void> clicksAndHits() async {
      for (var round = 0; round < 6; round++) {
        for (final s in Sfx.values) {
          audio.sfx(s);
        }
        await settle(80);
      }
    }

    test('a click or any other sound effect never silences the music', () async {
      device.focusStealing = true;
      await run(() async {
        audio.music(Music.battle);
        await settle();
        await clicksAndHits();
        await settle();
        expect(music().playing, 'audio/battle_theme.mp3');
        expect(music().lostFocus, isFalse);
        for (final p in device.players) {
          expect(p.requestsFocus, isFalse, reason: '${p.id} would ask Android for audio focus');
        }
      });
      expect(unexpected, isEmpty);
    });

    test('control: without the fix the same sounds DO silence the music (the fake reproduces the bug)', () async {
      device
        ..focusStealing = true
        ..ignoreContext = true;
      await run(() async {
        audio.music(Music.battle);
        await settle();
        await clicksAndHits();
        await settle();
        expect(music().lostFocus, isTrue);
        expect(music().playing, isNull);
      });
    });

    test('opening Settings in a match: taps and clicks around it leave the battle music playing', () async {
      device.focusStealing = true;
      await run(() async {
        audio.music(Music.menu);
        await settle();
        audio.music(Music.battle); // the match starts
        await settle();
        for (var i = 0; i < 8; i++) {
          audio.userGesture(); // every button press taps...
          audio.sfx(Sfx.click, volume: 0.45); // ...and clicks
          await settle(80);
        }
        await settle();
        expect(music().playing, 'audio/battle_theme.mp3');
      });
    });

    test('if the system pauses the music anyway, the next tap brings it back', () async {
      await run(() async {
        audio.music(Music.battle);
        await settle();
        music().playing = null; // a call or another app paused it
        audio.userGesture();
        await settle();
        expect(music().playing, 'audio/battle_theme.mp3');
        expect(music().resumes, 1);
      });
      expect(unexpected, isEmpty);
    });

    test('ensureMusic is throttled, and leaves stopped music and the one-shot victory theme alone', () async {
      await run(() async {
        audio.music(Music.battle);
        await settle();
        for (var i = 0; i < 30; i++) {
          audio.ensureMusic();
        }
        await settle();
        expect(music().resumes, 1, reason: 'thirty calls in a row ask the player once');

        audio.stopMusic();
        await settle();
        audio.ensureMusic();
        await settle();
        expect(music().playing, isNull, reason: 'music that was stopped on purpose stays stopped');
      });
      // The victory theme plays once: when it has finished it must not start again.
      final fresh = Audio(settings, playerFactory: (id) => FakePlayer(id, device), fadeStep: const Duration(milliseconds: 1));
      await run(() async {
        fresh.music(Music.victory);
        await settle();
        final victory = device.players.lastWhere((p) => p.id == 'music');
        victory.playing = null; // it finished
        final before = victory.resumes;
        fresh.ensureMusic();
        await settle();
        expect(victory.resumes, before);
        expect(victory.playing, isNull);
      });
      expect(unexpected, isEmpty);
    });

    test('a failing setAudioContext (an unsupported platform) never stops music or sounds', () async {
      device.blockAll = false;
      final broken = Audio(settings, playerFactory: (id) => _NoContextPlayer(id, device), fadeStep: const Duration(milliseconds: 1));
      await run(() async {
        broken.music(Music.battle);
        broken.sfx(Sfx.click);
        await settle();
        final m = device.players.firstWhere((p) => p.id == 'music');
        expect(m.playing, 'audio/battle_theme.mp3');
        expect(device.players.where((p) => p.id.startsWith('sfx')).every((p) => p.plays > 0), isTrue);
      });
      expect(unexpected, isEmpty);
    });
  });

  test('a flood of sound effects, all failing, never throws and uses at most 6 players', () async {
    device.blockAll = true;
    await run(() async {
      for (var i = 0; i < 200; i++) {
        audio.sfx(Sfx.values[i % Sfx.values.length]);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await settle(200);
      expect(device.players.where((p) => p.id.startsWith('sfx')).length, lessThanOrEqualTo(6));
    });
    expect(unexpected, isEmpty);
  });
}

/// A player on a platform where setAudioContext is not supported: it throws.
class _NoContextPlayer extends FakePlayer {
  _NoContextPlayer(super.id, super.device);

  @override
  Future<void> setAudioContext(AudioContext ctx) async => throw UnsupportedError('no audio contexts here');
}
