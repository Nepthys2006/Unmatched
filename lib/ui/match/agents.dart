/// The two kinds of seat in a match: the person holding the phone, and paced AI.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../engine/game.dart';
import '../../engine/prompt.dart';

/// Hands every prompt to the UI and waits for the indices the player picks.
class HumanAgent implements Agent {
  HumanAgent(this.onPrompt);
  final void Function(Prompt prompt, Completer<List<int>> answer) onPrompt;

  @override
  Future<List<int>> decide(Game game, Prompt prompt) {
    final c = Completer<List<int>>();
    onPrompt(prompt, c);
    return c.future;
  }
}

/// An AI that pauses before turn actions so the player can follow what it does.
class PacedAgent implements Agent {
  PacedAgent(this.inner, {required this.think, this.onThinking});
  final Agent inner;

  /// Milliseconds to "think" before a prompt of this kind (0 = answer at once).
  final int Function(Prompt p) think;
  final void Function(Prompt p)? onThinking;

  @override
  Future<List<int>> decide(Game game, Prompt prompt) async {
    final ms = think(prompt);
    if (ms > 0) {
      onThinking?.call(prompt);
      await Future<void>.delayed(Duration(milliseconds: ms));
    }
    return inner.decide(game, prompt);
  }
}

/// Logs how long each decision of [inner] took (`--dart-define=UMCCC_LOG=true`), for testing the
/// UMCCC Model on a device.
class TimedAgent implements Agent {
  TimedAgent(this.inner, this.name);
  final Agent inner;
  final String name;
  int _n = 0;
  int _totalMs = 0;
  int _maxMs = 0;

  @override
  Future<List<int>> decide(Game game, Prompt prompt) async {
    final sw = Stopwatch()..start();
    final r = await inner.decide(game, prompt);
    if (prompt.ask == Ask.action && prompt.choices.length > 1) {
      final ms = sw.elapsedMilliseconds;
      _n++;
      _totalMs += ms;
      if (ms > _maxMs) _maxMs = ms;
      debugPrint('[$name] turn ${game.turnNumber} move $_n: $ms ms (avg ${_totalMs ~/ _n}, max $_maxMs) '
          'choices=${prompt.choices.length} pick=${r.isEmpty ? '-' : r.first}');
    }
    return r;
  }
}
