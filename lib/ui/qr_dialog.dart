/// Shareable QR code dialog for LAN and multiplayer matches.
/// Allows iOS and mobile devices to scan the host screen with their camera and join directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'shapes.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shows a shareable QR code dialog encoding [url].
Future<void> showQrShareDialog(
  BuildContext context, {
  required String url,
  String title = 'SCAN TO JOIN ON iOS / MOBILE',
  String subtitle = 'Point an iPhone, iPad, or mobile camera at this screen to open and play directly in Safari on the same Wi-Fi.',
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close QR code',
    barrierColor: const Color(0xB8000000),
    pageBuilder: (ctx, _, _) => SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxH = constraints.maxHeight;
              final isCompact = maxH < 600;
              final isVeryCompact = maxH < 440;
              final qrSize = isVeryCompact ? 130.0 : (isCompact ? 165.0 : 200.0);
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: maxH - 24,
                ),
                child: Container(
                  margin: EdgeInsets.all(isCompact ? 12 : 20),
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 18 : 24,
                    isCompact ? 14 : 20,
                    isCompact ? 18 : 24,
                    isCompact ? 14 : 20,
                  ),
                  decoration: const ShapeDecoration(
                    color: Palette.panel,
                    shape: ChamferBorder(
                      cut: 12,
                      side: BorderSide(color: Palette.brass, width: 1.6),
                    ),
                    shadows: [
                      BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 8)),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.qr_code_2_rounded, color: Palette.brass, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title.toUpperCase(),
                                style: titleStyle(isCompact ? 16 : 19, color: Palette.brass, spacing: 0.8),
                              ),
                            ),
                            HexButton(
                              icon: Icons.close_rounded,
                              size: 32,
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                        if (!isVeryCompact) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: bodyStyle(isCompact ? 12 : 13, color: Palette.boneDim),
                          ),
                        ],
                        SizedBox(height: isCompact ? 10 : 16),
                        Center(
                          child: Container(
                            padding: EdgeInsets.all(isCompact ? 8 : 12),
                            decoration: const ShapeDecoration(
                              color: Colors.white,
                              shape: ChamferBorder(cut: 8),
                              shadows: [
                                BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4)),
                              ],
                            ),
                            child: QrImageView(
                              data: url,
                              version: QrVersions.auto,
                              size: qrSize,
                              gapless: true,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                            ),
                          ),
                        ),
                        SizedBox(height: isCompact ? 10 : 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: const ShapeDecoration(
                            color: Color(0x66000000),
                            shape: ChamferBorder(
                              cut: 6,
                              side: BorderSide(color: Palette.line),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.link_rounded, size: 16, color: Palette.boneDim),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  url,
                                  style: titleStyle(isCompact ? 13 : 14, color: Palette.brass, spacing: 0.4),
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18, color: Palette.bone),
                                tooltip: 'Copy URL',
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: url));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Address copied to clipboard!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: isCompact ? 12 : 16),
                        PlateButton(
                          label: 'Done',
                          style: PlateStyle.primary,
                          height: isCompact ? 40 : 44,
                          fontSize: isCompact ? 15 : 16,
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(c), child: child),
      );
    },
  );
}
