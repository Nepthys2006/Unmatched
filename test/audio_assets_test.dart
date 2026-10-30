import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/ui/audio.dart';

void main() {
  test('every music track and its fallback is in assets/audio and non-empty', () {
    for (final m in Music.values) {
      for (final f in [m.file, m.fallback]) {
        final file = File('assets/audio/$f');
        expect(file.existsSync(), isTrue, reason: '$f is missing');
        expect(file.lengthSync(), greaterThan(1000), reason: '$f is empty');
        expect(f.contains(RegExp(r'[ ()]')), isFalse, reason: '$f has spaces/brackets (breaks asset URLs on the web)');
      }
    }
  });

  test('every sound effect has its wav', () {
    for (final s in Sfx.values) {
      expect(File('assets/audio/${s.name}.wav').existsSync(), isTrue, reason: '${s.name}.wav is missing');
    }
  });

  test('only the victory track plays once; the others loop', () {
    expect(Music.victory.loop, isFalse);
    expect(Music.menu.loop && Music.battle.loop, isTrue);
  });
}
