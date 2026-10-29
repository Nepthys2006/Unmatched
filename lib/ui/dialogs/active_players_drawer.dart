/// Active Players Presence Drawer & Directory.
library;

import 'package:flutter/material.dart';

import '../../net/online_presence.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player_profile_modal.dart';

class ActivePlayersDrawer extends StatelessWidget {
  const ActivePlayersDrawer({
    super.key,
    this.onlineUsers,
    required this.onInvite,
  });

  final List<OnlineUser>? onlineUsers;
  final Future<void> Function(OnlineUser user) onInvite;

  static void show(
    BuildContext context, {
    required Future<void> Function(OnlineUser user) onInvite,
  }) {
    OnlinePresenceService.instance.refresh();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ActivePlayersDrawer(onInvite: onInvite),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OnlinePresenceService.instance,
      builder: (context, _) {
        final users = onlineUsers ?? OnlinePresenceService.instance.onlineUsers;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 600),
            child: Panel(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.people_alt_rounded, color: Palette.gold, size: 24),
                          const SizedBox(width: 8),
                          Text('ACTIVE PLAYERS', style: titleStyle(18, weight: FontWeight.w800, spacing: 1.1)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Palette.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Palette.gold.withValues(alpha: 0.4)),
                            ),
                            child: Text('${users.length} ONLINE', style: titleStyle(11, color: Palette.gold, weight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, color: Palette.boneDim),
                            tooltip: 'Refresh',
                            onPressed: () => OnlinePresenceService.instance.refresh(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Palette.boneDim),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Palette.line),
                  const SizedBox(height: 12),
                  if (users.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          const Icon(Icons.person_search_rounded, size: 48, color: Palette.boneDim),
                          const SizedBox(height: 12),
                          Text('No other players online right now.', style: bodyStyle(14, color: Palette.boneDim)),
                          const SizedBox(height: 4),
                          Text('Invite friends or create a lobby to play!', style: bodyStyle(12, color: Palette.muted)),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, i) {
                          final u = users[i];
                          final (statusColor, statusLabel) = switch (u.status) {
                            'matching' => (Palette.gold, 'Matching'),
                            'inGame' => (const Color(0xFF10B981), 'In Game'),
                            _ => (Palette.boneDim, 'Online - Idle'),
                          };

                          final canInvite = u.status == 'idle' || u.status == 'matching';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Palette.bg.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Palette.line.withValues(alpha: 0.4)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              onTap: () => PlayerProfileModal.show(
                                context,
                                name: u.name,
                                status: u.status,
                                statsPayload: u.stats,
                              ),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Palette.panelHi,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                    style: titleStyle(18, color: Palette.gold, weight: FontWeight.w800),
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      u.name,
                                      style: titleStyle(15, weight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                                        const SizedBox(width: 4),
                                        Text(statusLabel, style: titleStyle(10, color: statusColor, weight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Tap to inspect profile stats',
                                style: bodyStyle(11, color: Palette.muted),
                              ),
                              trailing: canInvite
                                  ? PlateButton(
                                      label: 'Invite',
                                      icon: Icons.send_rounded,
                                      height: 38,
                                      fontSize: 13,
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        onInvite(u);
                                      },
                                    )
                                  : null,
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
      },
    );
  }
}
