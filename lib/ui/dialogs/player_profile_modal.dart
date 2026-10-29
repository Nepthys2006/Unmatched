/// Player Profile & Statistics Modal viewable for self or any online player.
library;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../../net/profile_stats.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

class PlayerProfileModal extends StatelessWidget {
  const PlayerProfileModal({
    super.key,
    required this.name,
    this.status = 'idle',
    Map<String, Object?>? summary,
    Map<String, Object?>? statsPayload,
    this.isSelf = false,
  }) : statsPayload = statsPayload ?? summary;

  final String name;
  final String status;
  final Map<String, Object?>? statsPayload;
  final bool isSelf;

  static void show(
    BuildContext context, {
    required String name,
    String status = 'idle',
    Map<String, Object?>? statsPayload,
    bool isSelf = false,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => PlayerProfileModal(
        name: name,
        status: status,
        statsPayload: statsPayload,
        isSelf: isSelf,
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final Map<String, Object?> payload = statsPayload ??
        (isSelf ? ProfileStats.instance.toSummaryPayload() : const {});

    final totalMatches = (payload['totalMatches'] as num?)?.toInt() ?? (isSelf ? ProfileStats.instance.totalMatches : 0);
    final wins = (payload['wins'] as num?)?.toInt() ?? (isSelf ? ProfileStats.instance.wins : 0);
    final losses = (payload['losses'] as num?)?.toInt() ?? (isSelf ? ProfileStats.instance.losses : 0);
    final overallWinRate = (payload['overallWinRate'] as num?)?.toDouble() ?? (isSelf ? ProfileStats.instance.overallWinRate : 0.0);

    List<HeroStats> topHeroes = [];
    if (payload['top5'] is List) {
      topHeroes = [
        for (final item in payload['top5'] as List)
          if (item is Map) HeroStats.fromJson(item.cast<String, Object?>()),
      ];
    } else if (isSelf) {
      topHeroes = ProfileStats.instance.top5Heroes;
    }

    List<RecentMatch> recentMatches = [];
    if (payload['recent'] is List) {
      recentMatches = [
        for (final item in payload['recent'] as List)
          if (item is Map) RecentMatch.fromJson(item.cast<String, Object?>()),
      ];
    } else if (isSelf) {
      recentMatches = ProfileStats.instance.recentMatches;
    }

    final (statusColor, statusText) = switch (status) {
      'matching' => (Palette.gold, 'MATCHING'),
      'inGame' => (const Color(0xFF10B981), 'IN GAME'),
      _ => (Palette.boneDim, 'ONLINE - IDLE'),
    };

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: Panel(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top header bar with close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name.toUpperCase(),
                                  style: titleStyle(22, weight: FontWeight.w800, spacing: 1.1),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelf) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Palette.gold.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Palette.gold.withValues(alpha: 0.4)),
                                  ),
                                  child: Text('YOU', style: titleStyle(10, color: Palette.gold, weight: FontWeight.w700)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text(statusText, style: titleStyle(12, color: statusColor, weight: FontWeight.w700)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Palette.boneDim),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Stats Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Palette.panelHi.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Palette.line.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TOTAL MATCHES', style: titleStyle(11, color: Palette.boneDim, weight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('$totalMatches', style: titleStyle(24, weight: FontWeight.w800)),
                            Text('$wins W  ·  $losses L', style: bodyStyle(12, color: Palette.muted)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Palette.panelHi.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Palette.line.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('OVERALL WIN RATE', style: titleStyle(11, color: Palette.boneDim, weight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('${overallWinRate.toStringAsFixed(1)}%', style: titleStyle(24, color: Palette.gold, weight: FontWeight.w800)),
                            Text(totalMatches == 0 ? 'No games yet' : '$wins wins in $totalMatches games', style: bodyStyle(12, color: Palette.muted)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Palette.line),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top 5 Heroes
                        Text('TOP 5 MOST PLAYED HEROES', style: titleStyle(13, color: Palette.gold, spacing: 1.1, weight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (topHeroes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text('No hero records yet', style: bodyStyle(13, color: Palette.boneDim)),
                            ),
                          )
                        else
                          for (var i = 0; i < topHeroes.length; i++)
                            _HeroStatsRow(rank: i + 1, stats: topHeroes[i], data: s.data),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Palette.line),
                        const SizedBox(height: 12),
                        // Recent Matches
                        Text('RECENT MATCHES HISTORY', style: titleStyle(13, color: Palette.gold, spacing: 1.1, weight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (recentMatches.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text('No recent matches recorded', style: bodyStyle(13, color: Palette.boneDim)),
                            ),
                          )
                        else
                          for (final m in recentMatches)
                            _RecentMatchRow(match: m, timeStr: _formatTimestamp(m.timestamp), data: s.data),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroStatsRow extends StatelessWidget {
  const _HeroStatsRow({required this.rank, required this.stats, required this.data});
  final int rank;
  final HeroStats stats;
  final GameData data;

  @override
  Widget build(BuildContext context) {
    final hero = data.heroes[stats.heroId];
    final heroName = hero?.name ?? stats.heroId;
    final winRate = stats.winRate;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Palette.bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.line.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('#$rank', style: titleStyle(14, color: Palette.gold, weight: FontWeight.w700)),
              const SizedBox(width: 10),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: hero != null ? hexColor(hero.color) : Palette.panelHi,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    heroName.isNotEmpty ? heroName[0] : '?',
                    style: titleStyle(14, color: Colors.white, weight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(heroName, style: titleStyle(14, weight: FontWeight.w700)),
                    Text('${stats.matches} matches played', style: bodyStyle(12, color: Palette.boneDim)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${winRate.toStringAsFixed(0)}% Win Rate',
                    style: titleStyle(13, color: winRate >= 50 ? Palette.good : Palette.danger, weight: FontWeight.w700),
                  ),
                  Text('(${stats.wins}W - ${stats.losses}L)', style: bodyStyle(11, color: Palette.muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 5,
              width: double.infinity,
              color: Palette.line.withValues(alpha: 0.6),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (winRate / 100.0).clamp(0.0, 1.0),
                child: Container(color: winRate >= 50 ? Palette.good : Palette.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentMatchRow extends StatelessWidget {
  const _RecentMatchRow({required this.match, required this.timeStr, required this.data});
  final RecentMatch match;
  final String timeStr;
  final GameData data;

  @override
  Widget build(BuildContext context) {
    final myHero = data.heroes[match.heroId]?.name ?? match.heroId;
    final oppHero = data.heroes[match.opponentHeroId]?.name ?? match.opponentHeroId;
    final mapName = data.maps[match.mapId]?.name ?? match.mapId;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.bg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Palette.line.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: match.victory ? Palette.good.withValues(alpha: 0.2) : Palette.danger.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: match.victory ? Palette.good : Palette.danger),
            ),
            child: Text(
              match.victory ? 'VICTORY' : 'DEFEAT',
              style: titleStyle(11, color: match.victory ? Palette.good : Palette.danger, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$myHero  vs  ${match.opponentName} ($oppHero)', style: titleStyle(13, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text('$mapName  ·  ${match.mode.toUpperCase()}', style: bodyStyle(11, color: Palette.boneDim)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(timeStr, style: bodyStyle(11, color: Palette.muted)),
        ],
      ),
    );
  }
}
