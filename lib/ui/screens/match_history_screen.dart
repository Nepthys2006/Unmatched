/// Match history: every match saved on this device, newest first, with where it is on its way to
/// the server (pending / synced / failed) and what the server did with the rating.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../net/match_record.dart';
import '../services.dart';
import '../shapes.dart';
import '../sync_indicator.dart';
import '../theme.dart';
import '../widgets.dart';

class MatchHistoryScreen extends StatelessWidget {
  const MatchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return Scaffold(
      body: TableBackground(
        child: SafeArea(
          child: Column(
            children: [
              const ScreenHeader(title: 'Match history'),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: ListenableBuilder(
                  listenable: Listenable.merge([s.sync, s.matches]),
                  builder: (context, _) => Row(
                    children: [
                      Flexible(child: SyncIndicator(maxWidth: 420, onTap: s.sync.signedIn ? () => s.sync.nudge() : null)),
                      const SizedBox(width: 12),
                      PlateButton(
                        key: const ValueKey('sync-now'),
                        label: s.sync.state.name == 'syncing' ? 'Syncing…' : 'Sync now',
                        icon: Icons.sync_rounded,
                        style: PlateStyle.secondary,
                        height: 38,
                        fontSize: 14,
                        onPressed: s.sync.signedIn && s.sync.state.name != 'syncing' ? () => s.sync.nudge() : null,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: s.matches,
                  builder: (context, _) {
                    final list = s.matches.all;
                    if (list.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.history_rounded, size: 40, color: Palette.muted),
                            const SizedBox(height: 8),
                            Text('No matches yet', style: titleStyle(20, color: Palette.boneDim)),
                            const SizedBox(height: 4),
                            Text('Finished matches show up here, online or not.', style: bodyStyle(14, color: Palette.muted)),
                          ],
                        ),
                      );
                    }
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 940),
                        child: Scrollbar(
                          child: ListView.separated(
                            key: const ValueKey('history-list'),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => MatchTile(record: list[i]),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the history.
class MatchTile extends StatelessWidget {
  const MatchTile({super.key, required this.record});
  final MatchRecord record;

  static String when(DateTime t) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = t.toLocal();
    return '${months[l.month - 1]} ${l.day} · ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String length(int seconds) => seconds < 60 ? '${seconds}s' : '${(seconds / 60).round()} min';

  @override
  Widget build(BuildContext context) {
    final r = record;
    final data = context.services.data;
    final mine = data.heroes[r.myHero];
    final theirs = data.heroes[r.opponentHero];
    final (String syncLabel, IconData syncIcon, Color syncColor) = switch (r.syncStatus) {
      SyncStatus.pending => ('Pending', Icons.schedule_rounded, Palette.brass),
      SyncStatus.synced => ('Synced', Icons.cloud_done_rounded, Palette.good),
      SyncStatus.failed => ('Failed', Icons.error_outline_rounded, Palette.danger),
    };
    final ratingColor = r.serverResult == 'counted' ? (r.mmrDelta >= 0 ? Palette.good : Palette.danger) : Palette.muted;
    return Semantics(
      label: '${r.won ? 'Victory' : 'Defeat'} with ${mine?.name ?? r.myHero} against ${r.opponentName.isEmpty ? 'the AI' : r.opponentName}, $syncLabel',
      child: Container(
        key: ValueKey('match-${r.matchId}'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: ShapeDecoration(
          color: Palette.panel.withValues(alpha: 0.92),
          shape: ChamferBorder(cut: 8, side: BorderSide(color: (r.won ? Palette.good : Palette.danger).withValues(alpha: 0.45))),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 560;
            final heroes = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _hero(mine?.avatar, Palette.gold),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('VS', style: titleStyle(12, color: Palette.muted))),
                _hero(theirs?.avatar, Palette.bone.withValues(alpha: 0.5)),
              ],
            );
            final headline = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.won ? 'VICTORY' : 'DEFEAT', style: titleStyle(17, color: r.won ? Palette.good : Palette.danger, spacing: 1)),
                    const SizedBox(width: 8),
                    _Chip(r.mode.wire),
                  ],
                ),
                Text(
                  '${mine?.name ?? r.myHero} vs ${theirs?.name ?? (r.opponentHero.isEmpty ? '—' : r.opponentHero)}'
                  '${r.opponentName.isEmpty ? '' : ' · ${r.opponentName}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle(13.5, color: Palette.boneDim),
                ),
                Text('${when(r.playedAt)} · ${length(r.durationSeconds)}', style: bodyStyle(12.5, color: Palette.muted)),
                if (r.endLabel != null)
                  Text(r.endLabel!, key: ValueKey('ended-${r.matchId}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(12.5, color: Palette.brass)),
              ],
            );
            final status = Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.ratingLabel.toUpperCase(), key: ValueKey('rating-${r.matchId}'), style: titleStyle(14, color: ratingColor, spacing: 0.6)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(syncIcon, size: 15, color: syncColor),
                    const SizedBox(width: 4),
                    Text(syncLabel.toUpperCase(), key: ValueKey('sync-${r.matchId}'), style: titleStyle(12.5, color: syncColor, spacing: 0.8)),
                  ],
                ),
                if (r.syncStatus != SyncStatus.synced && r.lastError != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.min(260, c.maxWidth * 0.5)),
                    child: Text(r.lastError!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: bodyStyle(11.5, color: Palette.muted)),
                  ),
              ],
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [heroes, const SizedBox(width: 10), Expanded(child: headline)]),
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: status),
                ],
              );
            }
            return Row(
              children: [
                heroes,
                const SizedBox(width: 14),
                Expanded(child: headline),
                const SizedBox(width: 12),
                status,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _hero(String? asset, Color ring) => asset == null
      ? Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: ShapeDecoration(color: Palette.bgDeep, shape: HexBorder(side: BorderSide(color: ring))),
          child: const Icon(Icons.smart_toy_rounded, size: 20, color: Palette.muted),
        )
      : Avatar(asset, size: 42, ring: ring, ringWidth: 1.6);
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: ShapeDecoration(
      color: Palette.bgDeep,
      shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.bone.withValues(alpha: 0.3))),
    ),
    child: Text(text, style: titleStyle(11, color: Palette.boneDim, spacing: 0.8)),
  );
}
