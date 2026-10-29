/// Real-time invite notification dialog with 60s countdown timer.
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../../net/online_presence.dart';
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

  static void show(
    BuildContext context, {
    required MatchInvite invite,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InviteBannerDialog(
        invite: invite,
        onAccept: onAccept,
        onDecline: onDecline,
      ),
    );
  }

  @override
  State<InviteBannerDialog> createState() => _InviteBannerDialogState();
}

class _InviteBannerDialogState extends State<InviteBannerDialog> {
  Timer? _timer;
  int _secondsRemaining = 60;

  @override
  void initState() {
    super.initState();
    _calcRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _calcRemaining();
      if (_secondsRemaining <= 0) {
        _timer?.cancel();
        if (mounted) {
          Navigator.of(context).pop();
          widget.onDecline();
        }
      }
    });
  }

  void _calcRemaining() {
    final diff = widget.invite.expiresAt.difference(DateTime.now()).inSeconds;
    if (mounted) {
      setState(() {
        _secondsRemaining = diff.clamp(0, 60);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Panel(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.sports_kabaddi_rounded, color: Palette.gold, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'MATCH INVITATION',
                      style: titleStyle(18, color: Palette.gold, weight: FontWeight.w800, spacing: 1.1),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Palette.panelHi,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Palette.line),
                    ),
                    child: Text(
                      '${_secondsRemaining}s',
                      style: titleStyle(13, color: _secondsRemaining < 15 ? Palette.danger : Palette.bone, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RichText(
                text: TextSpan(
                  style: bodyStyle(15, color: Palette.bone),
                  children: [
                    TextSpan(
                      text: widget.invite.fromName,
                      style: titleStyle(16, weight: FontWeight.w800, color: Palette.bone),
                    ),
                    const TextSpan(text: ' has challenged you to an online match!'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Accept to join the lobby and choose heroes and map together.',
                style: bodyStyle(13, color: Palette.boneDim),
              ),
              const SizedBox(height: 18),
              // Progress indicator for countdown
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 4,
                  width: double.infinity,
                  color: Palette.line,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (_secondsRemaining / 60.0).clamp(0.0, 1.0),
                    child: Container(color: _secondsRemaining < 15 ? Palette.danger : Palette.gold),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: PlateButton(
                      label: 'Decline',
                      style: PlateStyle.secondary,
                      height: 48,
                      fontSize: 15,
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onDecline();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PlateButton(
                      label: 'Accept',
                      height: 48,
                      fontSize: 15,
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onAccept();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
