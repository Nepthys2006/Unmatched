/// The hidden test panel for the Full Screen help: live device facts, a device simulator, a few
/// buttons and a self-check. Only shown in debug builds or when the page is opened with `?debug=1`;
/// a release build for normal players never shows it. Everything it does is simulation: it swaps the
/// injected platform service and uses its own in-memory "dismissed" flag, so it never touches real
/// user data, saved matches or a running game.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dialogs/fullscreen_help_dialog.dart';
import '../invite_flow.dart' show appNavigatorKey;
import '../platform/fullscreen_controller.dart';
import '../platform/fullscreen_help_storage.dart';
import '../platform/platform_info.dart';
import '../platform/platform_info_service.dart';
import '../platform/viewport_guard.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'device_presets.dart';

abstract final class DebugPanel {
  /// Debug builds, or `?debug=1` in the page's address.
  static bool get enabled {
    if (kDebugMode) return true;
    try {
      return Uri.base.queryParameters['debug'] == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> open(BuildContext context) => showDialog<void>(context: context, builder: (_) => const DebugPanelDialog());
}

/// The small DEBUG tab in the corner that opens the panel.
class DebugPanelLauncher extends StatelessWidget {
  const DebugPanelLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    final services = context.services;
    if (!services.debugPanel) return const SizedBox.shrink();
    Widget tab(Key key, String label, VoidCallback onTap) => Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, style: const TextStyle(color: Palette.gold, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ),
    );
    return Positioned(
      left: 0,
      bottom: 0,
      child: SafeArea(
        child: Material(
          color: const Color(0xB30A0D13),
          child: ValueListenableBuilder<Size?>(
            valueListenable: services.simulatedWindow,
            builder: (context, sim, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tab(const ValueKey('debug-launcher'), 'DEBUG', () {
                  final ctx = appNavigatorKey.currentContext;
                  if (ctx != null) DebugPanel.open(ctx);
                }),
                // A simulated small window may put the "make this window larger" notice over the panel
                // itself, so the way back lives here, above everything.
                if (sim != null) tab(const ValueKey('debug-reset-window'), 'RESET WINDOW', () => services.simulatedWindow.value = null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DebugPanelDialog extends StatefulWidget {
  const DebugPanelDialog({super.key});
  @override
  State<DebugPanelDialog> createState() => _DebugPanelDialogState();
}

class _DebugPanelDialogState extends State<DebugPanelDialog> {
  FakePlatformInfoService? _fake;
  List<SelfCheckResult>? _results;

  FullscreenController get _c => context.services.fullscreen;

  /// Starts (or changes) the simulated device. A fresh in-memory flag is used, so the real one is safe.
  /// Changes one thing about the simulated device (always from its current state, never a stale copy).
  Future<void> _modify(PlatformInfo Function(PlatformInfo) change) => _simulate(change(_c.info));

  Future<void> _simulate(PlatformInfo info, {FakeFullscreen? behavior}) async {
    final fake = _fake ?? FakePlatformInfoService(info, behavior: behavior ?? FakeFullscreen.succeeds);
    fake
      ..info = info
      ..behavior = behavior ?? fake.behavior;
    if (_fake == null) {
      _fake = fake;
      await _c.useService(fake, storage: MemoryFullscreenHelpStorage());
    }
    if (mounted) setState(() {});
  }

  Future<void> _real() async {
    final services = context.services;
    await services.fullscreen.restoreReal();
    _fake = null;
    services.simulatedWindow.value = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final mq = MediaQuery.of(context);
    final c = s.fullscreen;
    return Dialog(
      backgroundColor: Palette.panel,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: ListenableBuilder(
          listenable: Listenable.merge([c, s.simulatedWindow]),
          builder: (context, _) {
            final info = c.info;
            // The real window in real pixels (the dialog itself sits inside the app's UI scaling).
            final view = View.of(context);
            final realSize = view.physicalSize / view.devicePixelRatio;
            final notice = viewportNotice(s.simulatedWindow.value ?? realSize, info);
            final rows = <(String, String)>[
              ('simulating', c.simulated ? 'yes (nothing real is touched)' : 'no, this is the real device'),
              ('device kind', info.deviceKind.name),
              ('browser', '${info.browser.name} (${info.browserName})'),
              ('userAgent', info.userAgent),
              ('platform', info.platform),
              ('maxTouchPoints', '${info.maxTouchPoints}'),
              ('isStandalone', '${info.isStandalone}'),
              ('fullscreen supported', '${info.fullscreenSupported}'),
              ('fullscreen now', '${c.isFullscreen}'),
              ('dismissed flag', '${c.dismissed}'),
              ('button action', c.action.name),
              ('orientation', mq.orientation.name),
              ('window size', '${(s.simulatedWindow.value ?? realSize).width.round()} x ${(s.simulatedWindow.value ?? realSize).height.round()}'),
              ('safe area (l t r b)', '${mq.padding.left.round()} ${mq.padding.top.round()} ${mq.padding.right.round()} ${mq.padding.bottom.round()}'),
              ('screen notice', notice?.name ?? 'none'),
              ('would the dialog show now?', c.shouldAutoShowHelp ? 'YES' : 'no'),
            ];
            return Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DEBUG PANEL', style: titleStyle(20, color: Palette.gold, spacing: 1.4)),
                    const SizedBox(height: 8),
                    for (final (k, v) in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 170, child: Text(k, style: bodyStyle(12.5, color: Palette.muted))),
                            Expanded(child: Text(v, key: ValueKey('debug-$k'), style: bodyStyle(12.5, color: Palette.bone, weight: FontWeight.w600))),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    const SectionLabel('Pretend to be'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in devicePresets)
                          _chip(p.name, () => _simulate(p.info), key: 'preset-${p.name}', selected: c.simulated && info.userAgent == p.info.userAgent && info.platform == p.info.platform),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip('Standalone: ${info.isStandalone ? 'on' : 'off'}', () => _modify((i) => i.copyWith(isStandalone: !i.isStandalone)), key: 'toggle-standalone'),
                        _chip('Fullscreen API: ${info.fullscreenSupported ? 'on' : 'off'}', () => _modify((i) => i.copyWith(fullscreenSupported: !i.fullscreenSupported)), key: 'toggle-fullscreen'),
                        _chip('API refuses', () => _simulate(_c.info, behavior: FakeFullscreen.refuses), key: 'api-refuses'),
                        _chip('API throws', () => _simulate(_c.info, behavior: FakeFullscreen.throws), key: 'api-throws'),
                        _chip('API works', () => _simulate(_c.info, behavior: FakeFullscreen.succeeds), key: 'api-works'),
                        _chip('Use the real device', _real, key: 'use-real'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const SectionLabel('Actions'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip('Force show dialog', () => FullscreenHelpDialog.show(context, device: info.deviceKind, browser: info.browser), key: 'force-dialog'),
                        _chip('Clear dismissed flag', () => c.clearDismissed(), key: 'clear-dismissed'),
                        _chip('Simulate portrait', () => s.simulatedWindow.value = Size(realSize.shortestSide, realSize.longestSide), key: 'sim-portrait'),
                        _chip('Simulate Split View width', () => s.simulatedWindow.value = Size(507, realSize.height), key: 'sim-split'),
                        _chip('Reset window size', () => s.simulatedWindow.value = null, key: 'sim-reset'),
                        _chip('Run self-check', () => setState(() => _results = runSelfCheck()), key: 'self-check'),
                      ],
                    ),
                    if (_results case final results?) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${results.where((r) => r.passed).length} PASS · ${results.where((r) => !r.passed).length} FAIL',
                        key: const ValueKey('self-check-summary'),
                        style: titleStyle(15, color: results.every((r) => r.passed) ? Palette.good : Palette.danger),
                      ),
                      for (final r in results)
                        Text(
                          '${r.passed ? 'PASS' : 'FAIL'}  ${r.name}${r.passed ? '' : ' — ${r.reason}'}',
                          style: bodyStyle(12, color: r.passed ? Palette.boneDim : Palette.danger),
                        ),
                    ],
                    const SizedBox(height: 14),
                    Align(alignment: Alignment.centerRight, child: _chip('Close', () => Navigator.of(context).pop(), key: 'debug-close')),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap, {required String key, bool selected = false}) => InkWell(
    key: ValueKey(key),
    onTap: onTap,
    customBorder: const ChamferBorder(cut: 6),
    child: Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: selected ? Palette.gold.withValues(alpha: 0.25) : Palette.bgDeep,
        shape: ChamferBorder(cut: 6, side: BorderSide(color: selected ? Palette.gold : Palette.bone.withValues(alpha: 0.3))),
      ),
      child: Text(label, style: bodyStyle(13, color: Palette.bone, weight: FontWeight.w600)),
    ),
  );
}
