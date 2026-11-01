/// The small "3 matches waiting to sync" / "All synced" chip.
library;

import 'package:flutter/material.dart';

import '../net/match_sync.dart';
import 'services.dart';
import 'shapes.dart';
import 'theme.dart';

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, this.onTap, this.maxWidth = 280});

  /// What a tap does (open the history, or sync now).
  final VoidCallback? onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.sync, s.matches]),
      builder: (context, _) {
        final sync = s.sync;
        final pending = sync.pendingCount;
        final signedIn = sync.signedIn;
        final (IconData icon, Color color) = switch ((signedIn, sync.state, pending)) {
          (false, _, _) => (Icons.cloud_off_rounded, Palette.muted),
          (_, SyncState.syncing, _) => (Icons.sync_rounded, Palette.select),
          (_, SyncState.offline, _) => (Icons.cloud_off_rounded, Palette.brass),
          (_, _, > 0) => (Icons.cloud_upload_rounded, Palette.brass),
          _ when sync.failedCount > 0 => (Icons.error_outline_rounded, Palette.danger),
          _ => (Icons.cloud_done_rounded, Palette.good),
        };
        return Semantics(
          button: onTap != null,
          label: sync.summary,
          child: GestureDetector(
            key: const ValueKey('sync-indicator'),
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: ShapeDecoration(
                  color: const Color(0xCC0A0D13),
                  shape: ChamferBorder(cut: 6, side: BorderSide(color: color.withValues(alpha: 0.55))),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        sync.summary,
                        key: const ValueKey('sync-summary'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(13, color: Palette.boneDim, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
