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
  double level = 1;
  ReleaseMode loopMode = ReleaseMode.release;
  int plays = 0;

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
    playing = path;
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
