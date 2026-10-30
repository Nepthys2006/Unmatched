/// Active Players: who is online, with their main hero, MMR and win rates, and a button to invite
/// them to a match. Tap anyone to open their profile.
library;

import 'package:flutter/material.dart';

import '../../engine/defs.dart';
import '../../net/online_presence.dart';
import '../../net/profile_stats.dart';
import '../invite_flow.dart';
import '../profile/profile_widgets.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player_profile_modal.dart';

class ActivePlayersDrawer extends StatelessWidget {
  const ActivePlayersDrawer({
    super.key,
    this.onlineUsers,
    required this.onInvite,
  });

  /// Overrides the live directory (tests).
  final List<OnlineUser>? onlineUsers;
  final void Function(OnlineUser user) onInvite;

  /// Opens the list. Inviting someone creates a lobby and sends the invite ([inviteToMatch]) unless
  /// [onInvite] says otherwise.
  static Future<void> show(
    BuildContext context, {
    Future<void> Function(OnlineUser user)? onInvite,
    List<OnlineUser>? onlineUsers,
  }) {
    OnlinePresenceService.instance.refresh();
    // The screen that opened the list, still there once the list is closed.
    final screen = context;
    return showDialog<void>(
      context: context,
      barrierLabel: 'Close Active Players',
      builder: (_) => ActivePlayersDrawer(
        onlineUsers: onlineUsers,
        onInvite: (user) {
          if (!screen.mounted) return;
          (onInvite ?? (u) => inviteToMatch(screen, u))(user);
        },
      ),
    );
  }

  /// Open lobbies first, then idle players, then those mid-match; strongest rating first.
  static List<OnlineUser> sorted(Iterable<OnlineUser> users) {
    int rank(OnlineUser u) => switch (u.status) {
      'matching' => 0,
      'inGame' => 2,
      _ => 1,
    };
    return users.toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        final m = b.profile.mmr.compareTo(a.profile.mmr);
        return m != 0 ? m : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = compactHeight(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 8 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 680, maxHeight: size.height - (compact ? 16 : 48)),
          child: ListenableBuilder(
            listenable: OnlinePresenceService.instance,
            builder: (context, _) {
              final users = sorted(onlineUsers ?? OnlinePresenceService.instance.onlineUsers);
              return Panel(
                padding: EdgeInsets.fromLTRB(18, compact ? 10 : 14, 18, compact ? 12 : 16),
                cut: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, users.length),
                    const SizedBox(height: 4),
                    const DecoRule(width: 200, opacity: 0.35),
                    SizedBox(height: compact ? 8 : 12),
                    if (users.isEmpty)
                      _empty()
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: users.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _PlayerCard(user: users[i], onInvite: onInvite),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int count) => Row(
    children: [
      Expanded(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text('ACTIVE PLAYERS', style: titleStyle(26, spacing: 1.4)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: ShapeDecoration(
                color: Palette.gold.withValues(alpha: 0.14),
                shape: ChamferBorder(cut: 4, side: BorderSide(color: Palette.gold.withValues(alpha: 0.6))),
              ),
              child: Text('$count ONLINE', style: titleStyle(11.5, color: Palette.gold, spacing: 1)),
            ),
          ],
        ),
      ),
      HexButton(icon: Icons.refresh_rounded, tooltip: 'Refresh', size: 40, onPressed: () => OnlinePresenceService.instance.refresh()),
      const SizedBox(width: 8),
      HexButton(icon: Icons.close_rounded, tooltip: 'Close', size: 40, onPressed: () => Navigator.of(context).pop()),
    ],
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.person_search_rounded, size: 44, color: Palette.boneDim),
        const SizedBox(height: 10),
        Text('NO OTHER PLAYERS ONLINE', style: titleStyle(17, color: Palette.boneDim, spacing: 1.2)),
        const SizedBox(height: 4),
        Text('Create a lobby and friends can join it from the list.', textAlign: TextAlign.center, style: bodyStyle(13, color: Palette.muted)),
      ],
    ),
  );
}

/// One player: main hero portrait, name and status, main hero plate, win rates and MMR.
class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.user, required this.onInvite});
  final OnlineUser user;
  final void Function(OnlineUser user) onInvite;

  @override
  Widget build(BuildContext context) {
    final data = context.services.data;
    final profile = user.profile;
    final main = profile.mainHeroId == null ? null : data.heroes[profile.mainHeroId];
    final accent = main == null ? Palette.line : readable(hexColor(main.color));
    final canInvite = user.status != 'inGame';
    const shape = ChamferBorder(cut: 9);

    void openProfile() => PlayerProfileModal.show(
      context,
      name: user.name,
      status: user.status,
      statsPayload: user.stats,
      onInvite: canInvite ? () => onInvite(user) : null,
    );

    return Semantics(
      button: true,
      label: '${user.name}, ${presenceStyle(user.status).label}${profile.ranked ? ', rating ${profile.mmr}' : ''}. Open profile',
      child: Material(
        color: Palette.bg.withValues(alpha: 0.55),
        shape: ChamferBorder(cut: 9, side: BorderSide(color: accent.withValues(alpha: main == null ? 0.5 : 0.45))),
        child: InkWell(
          customBorder: shape,
          onTap: openProfile,
          child: LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 470;
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                child: Row(
                  children: [
                    HeroAvatar(hero: main, size: 48, fallbackLetter: user.name.isEmpty ? '?' : user.name[0]),
                    const SizedBox(width: 14),
                    Expanded(child: _identity(profile, main, narrow)),
                    const SizedBox(width: 10),
                    _actions(profile, canInvite, narrow),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _identity(PlayerProfile profile, HeroDef? main, bool narrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(child: Text(user.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle(18, spacing: 0.9))),
            const SizedBox(width: 8),
            StatusChip(user.status),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: [
            if (main != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: ShapeDecoration(
                  color: plateColor(hexColor(main.color)),
                  shape: PlateBorder(slant: 0.3, side: BorderSide(color: Palette.bone.withValues(alpha: 0.55))),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 12, color: Palette.gold),
                    const SizedBox(width: 4),
                    Text(main.name.toUpperCase(), style: titleStyle(11.5, color: Colors.white, spacing: 0.8)),
                  ],
                ),
              )
            else
              Text('NEW PLAYER', style: titleStyle(11.5, color: Palette.muted, spacing: 0.8)),
            Text(
              'PvP ${profile.pvp.matches == 0 ? '—' : '${profile.pvp.winRate.round()}%'}  ·  AI ${profile.pve.matches == 0 ? '—' : '${profile.pve.winRate.round()}%'}',
              style: bodyStyle(12, color: Palette.boneDim, weight: FontWeight.w600),
            ),
            if (narrow) MmrChip(profile),
          ],
        ),
      ],
    );
  }

  Widget _actions(PlayerProfile profile, bool canInvite, bool narrow) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (!narrow) ...[MmrChip(profile), const SizedBox(height: 7)],
      if (canInvite)
        PlateButton(label: 'Invite', icon: Icons.send_rounded, width: 112, height: 38, fontSize: 14, onPressed: () => onInvite(user))
      else
        Text('IN A MATCH', style: titleStyle(12, color: Palette.muted, spacing: 1)),
    ],
  );
}
