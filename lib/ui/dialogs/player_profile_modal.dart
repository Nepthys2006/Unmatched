/// Player profile: who they are, their main hero, MMR and the PvP / PvE win rates, then their
/// favourite heroes and recent matches. Opened for yourself, for anyone in the Active Players
/// list and for the people in a lobby.
library;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../../net/profile_stats.dart';
import '../profile/profile_widgets.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

class PlayerProfileModal extends StatefulWidget {
  const PlayerProfileModal({
    super.key,
    required this.name,
    this.status = 'idle',
    Map<String, Object?>? summary,
    Map<String, Object?>? statsPayload,
    this.isSelf = false,
    this.onInvite,
  }) : statsPayload = statsPayload ?? summary;

  final String name;
  final String status;
  final Map<String, Object?>? statsPayload;
  final bool isSelf;

  /// Shows an Invite button (profiles opened from the Active Players list).
  final VoidCallback? onInvite;

  static Future<void> show(
    BuildContext context, {
    required String name,
    String status = 'idle',
    Map<String, Object?>? statsPayload,
    bool isSelf = false,
    VoidCallback? onInvite,
  }) {
    return showDialog<void>(
      context: context,
      barrierLabel: 'Close profile',
      builder: (_) => PlayerProfileModal(name: name, status: status, statsPayload: statsPayload, isSelf: isSelf, onInvite: onInvite),
    );
  }

  @override
  State<PlayerProfileModal> createState() => _PlayerProfileModalState();
}

class _PlayerProfileModalState extends State<PlayerProfileModal> {
  int _tab = 0; // 0 = heroes, 1 = recent

  static String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final data = context.services.data;
    final payload = widget.statsPayload ?? (widget.isSelf ? ProfileStats.instance.toSummaryPayload() : null);
    final profile = PlayerProfile.fromPayload(payload);
    final main = profile.mainHeroId == null ? null : data.heroes[profile.mainHeroId];
    final mainMatches = profile.topHeroes.where((h) => h.heroId == profile.mainHeroId).firstOrNull?.matches ?? 0;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 600;
    final compact = compactHeight(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 8 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 780, maxHeight: (size.height - (compact ? 16 : 48)).clamp(0.0, 540.0)),
          child: Panel(
            padding: EdgeInsets.fromLTRB(18, compact ? 10 : 14, 18, compact ? 12 : 16),
            cut: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, profile, main),
                const SizedBox(height: 4),
                const DecoRule(width: 200, opacity: 0.35),
                SizedBox(height: compact ? 8 : 12),
                Flexible(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: compact ? 188 : 224, child: HeroShowcase(hero: main, matches: mainMatches, isSelf: widget.isSelf)),
                            const SizedBox(width: 16),
                            Expanded(child: _details(context, profile, data, compact)),
                          ],
                        )
                      : _details(context, profile, data, compact),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, PlayerProfile profile, HeroDef? main) {
    return Row(
      children: [
        if (MediaQuery.sizeOf(context).width < 600) ...[HeroAvatar(hero: main, size: 40, fallbackLetter: widget.name.isEmpty ? '?' : widget.name[0]), const SizedBox(width: 10)],
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
                child: Text(widget.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle(26, spacing: 1.2)),
              ),
              if (widget.isSelf)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: ShapeDecoration(
                    color: Palette.gold.withValues(alpha: 0.14),
                    shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.gold.withValues(alpha: 0.6))),
                  ),
                  child: Text('YOU', style: titleStyle(11, color: Palette.gold, spacing: 1)),
                )
              else
                StatusChip(widget.status),
            ],
          ),
        ),
        if (widget.onInvite != null && !widget.isSelf) ...[
          PlateButton(
            label: 'Invite',
            icon: Icons.send_rounded,
            height: 40,
            fontSize: 15,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onInvite!();
            },
          ),
          const SizedBox(width: 10),
        ],
        HexButton(icon: Icons.close_rounded, tooltip: 'Close', size: 40, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _details(BuildContext context, PlayerProfile profile, GameData data, bool compact) {
    return LayoutBuilder(
      builder: (context, c) {
        final stacked = c.maxWidth < 430;
        final rates = IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: WinRateBlock(label: 'VS PLAYERS', icon: Icons.groups_rounded, record: profile.pvp, dense: compact)),
              const SizedBox(width: 10),
              Expanded(child: WinRateBlock(label: 'VS AI', icon: Icons.smart_toy_rounded, record: profile.pve, dense: compact)),
            ],
          ),
        );
        final top = stacked
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: MmrBadge(profile, size: 72)), const SizedBox(height: 10), rates])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  MmrBadge(profile, size: compact ? 78 : 92),
                  const SizedBox(width: 14),
                  Expanded(child: rates),
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            top,
            SizedBox(height: compact ? 8 : 12),
            Row(
              children: [
                ChoiceTile(label: 'Top heroes', selected: _tab == 0, height: 34, minWidth: 100, onTap: () => setState(() => _tab = 0)),
                const SizedBox(width: 8),
                ChoiceTile(label: 'Recent matches', selected: _tab == 1, height: 34, minWidth: 120, onTap: () => setState(() => _tab = 1)),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: _tab == 0 ? _heroList(profile, data) : _recentList(profile, data),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(String text) => Center(
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(text, style: bodyStyle(13, color: Palette.boneDim))),
  );

  Widget _heroList(PlayerProfile profile, GameData data) {
    if (profile.topHeroes.isEmpty) return _empty('No hero records yet');
    return ListView.separated(
      shrinkWrap: true,
      itemCount: profile.topHeroes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _HeroRow(rank: i + 1, stats: profile.topHeroes[i], hero: data.heroes[profile.topHeroes[i].heroId], isMain: profile.topHeroes[i].heroId == profile.mainHeroId),
    );
  }

  Widget _recentList(PlayerProfile profile, GameData data) {
    if (profile.recent.isEmpty) return _empty('No recent matches recorded');
    return ListView.separated(
      shrinkWrap: true,
      itemCount: profile.recent.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _RecentRow(match: profile.recent[i], when: _ago(profile.recent[i].timestamp), data: data),
    );
  }
}

class _HeroRow extends StatelessWidget {
  const _HeroRow({required this.rank, required this.stats, required this.hero, required this.isMain});
  final int rank;
  final HeroStats stats;
  final HeroDef? hero;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    final rate = stats.winRate;
    final color = rate >= 50 ? Palette.good : Palette.danger;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: ShapeDecoration(
        color: Palette.bg.withValues(alpha: 0.5),
        shape: ChamferBorder(cut: 7, side: BorderSide(color: Palette.line.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          SizedBox(width: 22, child: Text('$rank', style: titleStyle(15, color: Palette.gold))),
          HeroAvatar(hero: hero, size: 34, fallbackLetter: stats.heroId.isEmpty ? '?' : stats.heroId[0]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text((hero?.name ?? stats.heroId).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle(15, spacing: 0.8))),
                    if (isMain) ...[const SizedBox(width: 6), const Icon(Icons.star_rounded, size: 14, color: Palette.gold)],
                  ],
                ),
                Text('${stats.matches} ${stats.matches == 1 ? 'match' : 'matches'}', style: bodyStyle(12, color: Palette.muted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${rate.round()}%', style: titleStyle(17, color: color)),
              Text('${stats.wins}W · ${stats.losses}L', style: bodyStyle(11.5, color: Palette.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.match, required this.when, required this.data});
  final RecentMatch match;
  final String when;
  final GameData data;

  @override
  Widget build(BuildContext context) {
    final myHero = data.heroes[match.heroId]?.name ?? match.heroId;
    final oppHero = data.heroes[match.opponentHeroId]?.name ?? match.opponentHeroId;
    final map = data.maps[match.mapId]?.name ?? match.mapId;
    final win = match.victory;
    final c = win ? Palette.good : Palette.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: ShapeDecoration(
        color: Palette.bg.withValues(alpha: 0.4),
        shape: ChamferBorder(cut: 7, side: BorderSide(color: Palette.line.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: ShapeDecoration(
              color: c.withValues(alpha: 0.16),
              shape: PlateBorder(slant: 0.25, side: BorderSide(color: c)),
            ),
            child: Text(win ? 'VICTORY' : 'DEFEAT', style: titleStyle(11.5, color: c, spacing: 0.6)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$myHero  vs  ${match.opponentName}${oppHero.isEmpty ? '' : ' ($oppHero)'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle(13.5, spacing: 0.4),
                ),
                Text('${match.pvp ? 'PvP' : 'vs AI'}  ·  $map  ·  $when', maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(11.5, color: Palette.boneDim)),
              ],
            ),
          ),
          if (match.pvp && match.mmrChange != 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${match.mmrChange > 0 ? '+' : ''}${match.mmrChange}',
                style: titleStyle(15, color: match.mmrChange > 0 ? Palette.good : Palette.danger),
              ),
            ),
        ],
      ),
    );
  }
}
