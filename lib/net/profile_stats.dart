/// Persistent player profile statistics and match history.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HeroStats {
  const HeroStats({
    required this.heroId,
    required this.matches,
    required this.wins,
    required this.losses,
  });

  final String heroId;
  final int matches;
  final int wins;
  final int losses;

  double get winRate => matches == 0 ? 0.0 : (wins / matches) * 100.0;

  Map<String, Object> toJson() => {
    'heroId': heroId,
    'matches': matches,
    'wins': wins,
    'losses': losses,
  };

  factory HeroStats.fromJson(Map<String, Object?> json) => HeroStats(
    heroId: json['heroId'] as String? ?? '',
    matches: (json['matches'] as num?)?.toInt() ?? 0,
    wins: (json['wins'] as num?)?.toInt() ?? 0,
    losses: (json['losses'] as num?)?.toInt() ?? 0,
  );
}

class RecentMatch {
  const RecentMatch({
    required this.victory,
    required this.heroId,
    required this.opponentName,
    required this.opponentHeroId,
    required this.mapId,
    required this.mode,
    required this.timestamp,
  });

  final bool victory;
  final String heroId;
  final String opponentName;
  final String opponentHeroId;
  final String mapId;
  final String mode;
  final DateTime timestamp;

  Map<String, Object> toJson() => {
    'victory': victory,
    'heroId': heroId,
    'opponentName': opponentName,
    'opponentHeroId': opponentHeroId,
    'mapId': mapId,
    'mode': mode,
    'timestamp': timestamp.toIso8601String(),
  };

  factory RecentMatch.fromJson(Map<String, Object?> json) => RecentMatch(
    victory: json['victory'] == true,
    heroId: json['heroId'] as String? ?? '',
    opponentName: json['opponentName'] as String? ?? 'Opponent',
    opponentHeroId: json['opponentHeroId'] as String? ?? '',
    mapId: json['mapId'] as String? ?? '',
    mode: json['mode'] as String? ?? 'duel',
    timestamp: json['timestamp'] != null
        ? (DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now())
        : DateTime.now(),
  );
}

class ProfileStats extends ChangeNotifier {
  ProfileStats._(this._prefs) {
    _load();
  }

  static ProfileStats? _instance;
  static ProfileStats get instance => _instance ??= ProfileStats._(null);

  static Future<ProfileStats> load(SharedPreferences? prefs) async {
    final s = ProfileStats._(prefs);
    _instance = s;
    return s;
  }

  final SharedPreferences? _prefs;

  int totalMatches = 0;
  int wins = 0;
  int losses = 0;
  final Map<String, HeroStats> heroRecords = {};
  final List<RecentMatch> recentMatches = [];

  double get overallWinRate => totalMatches == 0 ? 0.0 : (wins / totalMatches) * 100.0;

  List<HeroStats> get top5Heroes {
    final list = heroRecords.values.toList()
      ..sort((a, b) {
        final c = b.matches.compareTo(a.matches);
        return c != 0 ? c : b.wins.compareTo(a.wins);
      });
    return list.take(5).toList();
  }

  void recordMatch({
    required bool won,
    required String heroId,
    required String opponentName,
    required String opponentHeroId,
    required String mapId,
    required String mode,
  }) {
    totalMatches++;
    if (won) {
      wins++;
    } else {
      losses++;
    }

    final current = heroRecords[heroId] ?? HeroStats(heroId: heroId, matches: 0, wins: 0, losses: 0);
    heroRecords[heroId] = HeroStats(
      heroId: heroId,
      matches: current.matches + 1,
      wins: current.wins + (won ? 1 : 0),
      losses: current.losses + (won ? 0 : 1),
    );

    recentMatches.insert(
      0,
      RecentMatch(
        victory: won,
        heroId: heroId,
        opponentName: opponentName,
        opponentHeroId: opponentHeroId,
        mapId: mapId,
        mode: mode,
        timestamp: DateTime.now(),
      ),
    );
    if (recentMatches.length > 40) {
      recentMatches.removeLast();
    }

    notifyListeners();
    _save();
  }

  Map<String, Object> toSummaryPayload() => {
    'totalMatches': totalMatches,
    'wins': wins,
    'losses': losses,
    'overallWinRate': overallWinRate,
    'top5': [for (final h in top5Heroes) h.toJson()],
    'recent': [for (final m in recentMatches.take(5)) m.toJson()],
  };

  void _load() {
    final p = _prefs;
    if (p == null) return;
    totalMatches = p.getInt('stats_totalMatches') ?? 0;
    wins = p.getInt('stats_wins') ?? 0;
    losses = p.getInt('stats_losses') ?? 0;
    final heroesJson = p.getString('stats_heroes');
    if (heroesJson != null) {
      try {
        final map = jsonDecode(heroesJson) as Map;
        for (final entry in map.entries) {
          heroRecords[entry.key as String] = HeroStats.fromJson((entry.value as Map).cast<String, Object?>());
        }
      } catch (_) {}
    }
    final recentJson = p.getString('stats_recent');
    if (recentJson != null) {
      try {
        final list = jsonDecode(recentJson) as List;
        for (final item in list) {
          recentMatches.add(RecentMatch.fromJson((item as Map).cast<String, Object?>()));
        }
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setInt('stats_totalMatches', totalMatches);
      await p.setInt('stats_wins', wins);
      await p.setInt('stats_losses', losses);
      await p.setString('stats_heroes', jsonEncode({for (final e in heroRecords.entries) e.key: e.value.toJson()}));
      await p.setString('stats_recent', jsonEncode([for (final m in recentMatches) m.toJson()]));
    } catch (_) {}
  }
}

