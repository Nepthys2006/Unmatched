/// Persistent player profile statistics and match history.
///
/// Results are kept in two separate books: matches against real players (PvP) and matches against
/// the computer (PvE). Only PvP moves the MMR (matchmaking rating, an Elo rating), so beating the
/// AI can never inflate a player's standing against people.
library;

import 'dart:convert';
import 'dart:math' as math;

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

/// Wins and losses in one kind of match.
class Record {
  const Record({this.wins = 0, this.losses = 0});

  final int wins;
  final int losses;

  int get matches => wins + losses;

  /// 0..100; 0 when nothing has been played.
  double get winRate => matches == 0 ? 0.0 : wins / matches * 100.0;

  Record plus({required bool won}) => Record(wins: wins + (won ? 1 : 0), losses: losses + (won ? 0 : 1));

  Map<String, Object> toJson() => {'matches': matches, 'wins': wins, 'losses': losses, 'winRate': winRate};

  factory Record.fromJson(Object? json) {
    if (json is! Map) return const Record();
    final w = (json['wins'] as num?)?.toInt() ?? 0;
    final l = (json['losses'] as num?)?.toInt();
    final m = (json['matches'] as num?)?.toInt();
    return Record(wins: math.max(0, w), losses: math.max(0, l ?? ((m ?? w) - w)));
  }
}

/// The rating ladder: the badge a player's MMR earns.
enum MmrTier {
  rookie('Rookie', 0),
  duelist('Duelist', 900),
  veteran('Veteran', 1100),
  champion('Champion', 1300),
  legend('Legend', 1500),
  immortal('Immortal', 1700);

  const MmrTier(this.label, this.floor);
  final String label;

  /// The lowest MMR in this tier.
  final int floor;

  static MmrTier of(int mmr) => values.lastWhere((t) => mmr >= t.floor, orElse: () => rookie);

  /// The next tier up, or null at the top.
  MmrTier? get next => index + 1 < values.length ? values[index + 1] : null;
}

/// MMR arithmetic (Elo): everyone starts at [start]; a result moves the rating by how surprising
/// it was. New players move faster for their first [provisional] ranked matches.
abstract final class Mmr {
  static const start = 1000;
  static const provisional = 10;

  static int delta({required int mine, required int theirs, required bool won, required int rankedMatches}) {
    final expected = 1 / (1 + math.pow(10, (theirs - mine) / 400));
    final k = rankedMatches < provisional ? 40 : 24;
    return (k * ((won ? 1 : 0) - expected)).round();
  }
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
    this.pvp = false,
    this.mmrChange = 0,
  });

  final bool victory;
  final String heroId;
  final String opponentName;
  final String opponentHeroId;
  final String mapId;
  final String mode;
  final DateTime timestamp;

  /// Against real players (false: against the AI).
  final bool pvp;

  /// The MMR gained or lost (PvP only).
  final int mmrChange;

  Map<String, Object> toJson() => {
    'victory': victory,
    'heroId': heroId,
    'opponentName': opponentName,
    'opponentHeroId': opponentHeroId,
    'mapId': mapId,
    'mode': mode,
    'timestamp': timestamp.toIso8601String(),
    'pvp': pvp,
    'mmrChange': mmrChange,
  };

  factory RecentMatch.fromJson(Map<String, Object?> json) {
    final mode = json['mode'] as String? ?? 'duel';
    return RecentMatch(
      victory: json['victory'] == true,
      heroId: json['heroId'] as String? ?? '',
      opponentName: json['opponentName'] as String? ?? 'Opponent',
      opponentHeroId: json['opponentHeroId'] as String? ?? '',
      mapId: json['mapId'] as String? ?? '',
      mode: mode,
      timestamp: json['timestamp'] != null ? (DateTime.tryParse('${json['timestamp']}') ?? DateTime.now()) : DateTime.now(),
      // Older saves had no flag: "online" matches were against people, "local" ones against the AI.
      pvp: json['pvp'] is bool ? json['pvp'] as bool : mode == 'online',
      mmrChange: (json['mmrChange'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A player's profile as shown to anyone: read from the summary payload that travels with
/// presence, lobby seats and invites (or built from the local stats). Tolerates missing and
/// older payloads, so a peer on an earlier build never breaks the screen.
class PlayerProfile {
  const PlayerProfile({
    this.pvp = const Record(),
    this.pve = const Record(),
    this.mmr = Mmr.start,
    this.mainHeroId,
    this.topHeroes = const [],
    this.recent = const [],
  });

  final Record pvp;
  final Record pve;
  final int mmr;

  /// The most played hero.
  final String? mainHeroId;
  final List<HeroStats> topHeroes;
  final List<RecentMatch> recent;

  int get totalMatches => pvp.matches + pve.matches;
  int get totalWins => pvp.wins + pve.wins;
  int get totalLosses => pvp.losses + pve.losses;

  /// A rating only means something once a PvP match has been played.
  bool get ranked => pvp.matches > 0;
  MmrTier get tier => MmrTier.of(mmr);

  /// Reads a summary payload; null or malformed input gives an empty profile.
  factory PlayerProfile.fromPayload(Map<String, Object?>? p) {
    if (p == null) return const PlayerProfile();
    try {
      final top = <HeroStats>[
        if (p['top5'] is List)
          for (final item in p['top5'] as List)
            if (item is Map) HeroStats.fromJson(item.cast<String, Object?>()),
      ];
      final recent = <RecentMatch>[
        if (p['recent'] is List)
          for (final item in p['recent'] as List)
            if (item is Map) RecentMatch.fromJson(item.cast<String, Object?>()),
      ];
      // A payload from before the split has only totals; count them as AI matches.
      final hasSplit = p['pvp'] is Map || p['pve'] is Map;
      final pve = hasSplit
          ? Record.fromJson(p['pve'])
          : Record(wins: (p['wins'] as num?)?.toInt() ?? 0, losses: (p['losses'] as num?)?.toInt() ?? 0);
      final main = p['mainHero'];
      return PlayerProfile(
        pvp: Record.fromJson(p['pvp']),
        pve: pve,
        mmr: (p['mmr'] as num?)?.toInt() ?? Mmr.start,
        mainHeroId: main is String && main.isNotEmpty ? main : (top.isEmpty ? null : top.first.heroId),
        topHeroes: top,
        recent: recent,
      );
    } catch (_) {
      return const PlayerProfile();
    }
  }
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

  Record pvp = const Record();
  Record pve = const Record();
  int mmr = Mmr.start;
  int peakMmr = Mmr.start;
  final Map<String, HeroStats> heroRecords = {};
  final List<RecentMatch> recentMatches = [];

  int get totalMatches => pvp.matches + pve.matches;
  int get wins => pvp.wins + pve.wins;
  int get losses => pvp.losses + pve.losses;
  double get overallWinRate => totalMatches == 0 ? 0.0 : (wins / totalMatches) * 100.0;

  List<HeroStats> get top5Heroes {
    final list = heroRecords.values.toList()
      ..sort((a, b) {
        final c = b.matches.compareTo(a.matches);
        return c != 0 ? c : b.wins.compareTo(a.wins);
      });
    return list.take(5).toList();
  }

  /// The most played hero, or null before the first match.
  String? get mainHeroId {
    final t = top5Heroes;
    return t.isEmpty ? null : t.first.heroId;
  }

  PlayerProfile get profile => PlayerProfile.fromPayload(toSummaryPayload());

  /// Records a finished match. [pvp] means at least one opponent was a real player; then
  /// [opponentMmr] (the opponents' average, if known) sets how far the rating moves.
  /// Returns the MMR change (0 for matches against the AI).
  int recordMatch({
    required bool won,
    required String heroId,
    required String opponentName,
    required String opponentHeroId,
    required String mapId,
    required String mode,
    bool pvp = false,
    int? opponentMmr,
  }) {
    var change = 0;
    if (pvp) {
      change = Mmr.delta(mine: mmr, theirs: opponentMmr ?? Mmr.start, won: won, rankedMatches: this.pvp.matches);
      this.pvp = this.pvp.plus(won: won);
      mmr = math.max(0, mmr + change);
      peakMmr = math.max(peakMmr, mmr);
    } else {
      pve = pve.plus(won: won);
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
        pvp: pvp,
        mmrChange: change,
      ),
    );
    if (recentMatches.length > 40) {
      recentMatches.removeLast();
    }

    notifyListeners();
    _save();
    return change;
  }

  /// What travels with presence, lobby seats and invites. The totals and `overallWinRate` keys
  /// are kept for peers on earlier builds.
  Map<String, Object> toSummaryPayload() => {
    'totalMatches': totalMatches,
    'wins': wins,
    'losses': losses,
    'overallWinRate': overallWinRate,
    'pvp': pvp.toJson(),
    'pve': pve.toJson(),
    'mmr': mmr,
    'mainHero': ?mainHeroId,
    'top5': [for (final h in top5Heroes) h.toJson()],
    'recent': [for (final m in recentMatches.take(5)) m.toJson()],
  };

  /// The small part of the profile an invite carries: rating, main hero and win rates.
  Map<String, Object> toBadgePayload() => {
    'pvp': pvp.toJson(),
    'pve': pve.toJson(),
    'mmr': mmr,
    'mainHero': ?mainHeroId,
  };

  void _load() {
    final p = _prefs;
    if (p == null) return;
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
    if (p.containsKey('stats_pvp_wins') || p.containsKey('stats_pve_wins')) {
      pvp = Record(wins: p.getInt('stats_pvp_wins') ?? 0, losses: p.getInt('stats_pvp_losses') ?? 0);
      pve = Record(wins: p.getInt('stats_pve_wins') ?? 0, losses: p.getInt('stats_pve_losses') ?? 0);
      mmr = p.getInt('stats_mmr') ?? Mmr.start;
      peakMmr = p.getInt('stats_mmr_peak') ?? mmr;
    } else {
      // Saved before the split: the matches in the history that were online were against people
      // (the history keeps the last 40), everything else counts as against the AI.
      final totalW = p.getInt('stats_wins') ?? 0;
      final totalL = p.getInt('stats_losses') ?? 0;
      final pvpW = recentMatches.where((m) => m.pvp && m.victory).length;
      final pvpL = recentMatches.where((m) => m.pvp && !m.victory).length;
      pvp = Record(wins: math.min(pvpW, totalW), losses: math.min(pvpL, totalL));
      pve = Record(wins: totalW - pvp.wins, losses: totalL - pvp.losses);
    }
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setInt('stats_totalMatches', totalMatches);
      await p.setInt('stats_wins', wins);
      await p.setInt('stats_losses', losses);
      await p.setInt('stats_pvp_wins', pvp.wins);
      await p.setInt('stats_pvp_losses', pvp.losses);
      await p.setInt('stats_pve_wins', pve.wins);
      await p.setInt('stats_pve_losses', pve.losses);
      await p.setInt('stats_mmr', mmr);
      await p.setInt('stats_mmr_peak', peakMmr);
      await p.setString('stats_heroes', jsonEncode({for (final e in heroRecords.entries) e.key: e.value.toJson()}));
      await p.setString('stats_recent', jsonEncode([for (final m in recentMatches) m.toJson()]));
    } catch (_) {}
  }
}
