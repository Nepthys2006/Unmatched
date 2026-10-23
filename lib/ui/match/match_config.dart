/// What the setup screens decide: mode, map, AI level and every seat's hero.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../engine/ai.dart';
import '../../engine/defs.dart';
import '../theme.dart';

enum GameMode { duel, teams2, teams3, ffa }

extension GameModeX on GameMode {
  String get label => switch (this) {
    GameMode.duel => '1 v 1',
    GameMode.teams2 => '2 v 2',
    GameMode.teams3 => '3 v 3',
    GameMode.ffa => 'Free-for-all',
  };

  String get blurb => switch (this) {
    GameMode.duel => 'The classic duel. You against one AI hero.',
    GameMode.teams2 => 'You and an AI ally against two AI heroes.',
    GameMode.teams3 => 'Three heroes a side. You and two AI allies.',
    GameMode.ffa => 'Everyone for themselves. Last hero standing wins.',
  };

  /// Players for the fixed modes; free-for-all picks 2–5.
  int get fixedPlayers => switch (this) {
    GameMode.duel => 2,
    GameMode.teams2 => 4,
    GameMode.teams3 => 6,
    GameMode.ffa => 4,
  };
  bool get isTeams => this == GameMode.teams2 || this == GameMode.teams3;
}

extension AiLevelX on AiLevel {
  String get label => switch (this) {
    AiLevel.easy => 'Easy',
    AiLevel.medium => 'Medium',
    AiLevel.hard => 'Hard',
    AiLevel.insane => 'Insane',
  };
  String get blurb => switch (this) {
    AiLevel.easy => 'Makes mistakes. Good for learning a hero.',
    AiLevel.medium => 'Solid play with the odd slip.',
    AiLevel.hard => 'Manages its hand and picks its fights.',
    AiLevel.insane => 'Near-perfect choices. No mercy.',
  };
  Color get color => switch (this) {
    AiLevel.easy => const Color(0xFF6BD08A),
    AiLevel.medium => Palette.brass,
    AiLevel.hard => const Color(0xFFF08A3C),
    AiLevel.insane => Palette.danger,
  };
}

/// Maps that can host [mode] with [players] seats.
List<MapDef> mapsFor(GameData data, GameMode mode, int players) {
  int starts(MapDef m) => m.spaces.where((s) => s.start != null).length;
  final out = switch (mode) {
    GameMode.duel => data.mapsFor('1v1'),
    GameMode.teams2 => data.mapsFor('2v2'),
    GameMode.teams3 => data.mapsFor('3v3'),
    GameMode.ffa => [if (players == 2) ...data.mapsFor('1v1'), ...data.mapsFor('ffa').where((m) => starts(m) >= players)],
  };
  return out;
}

class MatchConfig {
  MatchConfig({required this.mode, required this.players, required this.map, required this.ai, required this.heroIds});

  final GameMode mode;
  final int players;
  final MapDef map;
  final AiLevel ai;

  /// One hero per seat; seat 0 is the human.
  final List<String> heroIds;

  /// Team per seat for team play (seats alternate teams); null for 1v1 and free-for-all.
  List<int>? get teams => mode.isTeams ? [for (var i = 0; i < players; i++) i % 2] : null;

  /// Fills the AI seats with random heroes, all different from each other and from [human].
  static List<String> randomLineup(GameData data, String human, int players, [math.Random? rng]) {
    final pool = data.heroes.keys.where((h) => h != human).toList()..shuffle(rng ?? math.Random());
    return [human, ...pool.take(players - 1)];
  }

  MatchConfig rematch() => MatchConfig(mode: mode, players: players, map: map, ai: ai, heroIds: heroIds);
}
