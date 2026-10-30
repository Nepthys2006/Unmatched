/// An incoming match invite: who is challenging you (main hero, rating), with a 60 second
/// countdown to accept or decline.
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../../net/online_presence.dart';
import '../profile/profile_widgets.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

class InviteBannerDialog extends StatefulWidget {
  const InviteBannerDialog({
    super.key,
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final MatchInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  static Future<void> show(
    BuildContext context, {
    required MatchInvite invite,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InviteBannerDialog(invite: invite, onAccept: onAccept, onDecline: onDecline),
    );
  }

  @override
  State<InviteBannerDialog> createState() => _InviteBannerDialogState();
}

class _InviteBannerDialogState extends State<InviteBannerDialog> {
  static const _total = 60;
  Timer? _timer;
  int _secondsRemaining = _total;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = _left();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _left();
      if (!mounted) return;
      setState(() => _secondsRemaining = left);
      if (left <= 0) _finish(accept: false);
    });
  }

  int _left() => widget.invite.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, _total);

  /// Closes the dialog once and tells the caller the answer.
  void _finish({required bool accept}) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    _dismiss();
    (accept ? widget.onAccept : widget.onDecline)();
  }

  /// Removes this dialog's own route. A plain `pop()` takes whatever route is on top, which is
  /// not this dialog if a screen change happened underneath it (a match starting, say).
  void _dismiss() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invite;
    final profile = inv.fromProfile;
    final main = profile.mainHeroId == null ? null : context.services.data.heroes[profile.mainHeroId];
    final urgent = _secondsRemaining < 15;
    final timeColor = urgent ? Palette.danger : Palette.bone;
    final compact = compactHeight(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Panel(
            padding: EdgeInsets.fromLTRB(20, compact ? 12 : 16, 20, compact ? 14 : 18),
            cut: 14,
            highlight: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('MATCH INVITATION', style: titleStyle(22, color: Palette.gold, spacing: 1.6))),
                    Semantics(
                      label: '$_secondsRemaining seconds left',
                      excludeSemantics: true,
                      child: Container(
                        width: 54,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: Palette.panelHi,
                          shape: HexBorder(side: BorderSide(color: timeColor.withValues(alpha: 0.8), width: 1.5)),
                        ),
                        child: Text('${_secondsRemaining}s', style: titleStyle(15, color: timeColor, spacing: 0)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const DecoRule(width: 180, opacity: 0.35),
                SizedBox(height: compact ? 10 : 14),
                Row(
                  children: [
                    HeroAvatar(hero: main, size: compact ? 56 : 66, fallbackLetter: inv.fromName.isEmpty ? '?' : inv.fromName[0]),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inv.fromName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle(24, spacing: 1)),
                          const SizedBox(height: 5),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              MmrChip(profile),
                              if (main != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                  decoration: ShapeDecoration(
                                    color: plateColor(hexColor(main.color)),
                                    shape: PlateBorder(slant: 0.3, side: BorderSide(color: Palette.bone.withValues(alpha: 0.55))),
                                  ),
                                  child: Text(main.name.toUpperCase(), style: titleStyle(11.5, color: Colors.white, spacing: 0.8)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('challenges you to an online match.', style: bodyStyle(15, color: Palette.bone)),
                const SizedBox(height: 2),
                Text('Accept to join the lobby, then pick your hero and the battlefield together.', style: bodyStyle(13, color: Palette.boneDim)),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: 4,
                    color: Palette.line,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (_secondsRemaining / _total).clamp(0.0, 1.0),
                      child: Container(color: urgent ? Palette.danger : Palette.gold),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 12 : 16),
                Row(
                  children: [
                    Expanded(child: PlateButton(label: 'Decline', style: PlateStyle.secondary, height: 48, fontSize: 17, onPressed: () => _finish(accept: false))),
                    const SizedBox(width: 12),
                    Expanded(child: PlateButton(label: 'Accept', icon: Icons.check_rounded, style: PlateStyle.confirm, height: 48, fontSize: 17, onPressed: () => _finish(accept: true))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
