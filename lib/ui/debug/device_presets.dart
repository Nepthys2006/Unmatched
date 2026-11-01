/// The devices the debug panel can pretend to be, and the self-check that proves the detection and
/// help rules still give the right answer for each of them.
library;

import '../platform/platform_info.dart';

class DevicePreset {
  const DevicePreset({
    required this.name,
    required this.info,
    required this.expectedDevice,
    required this.expectedBrowser,
    required this.expectedHelp,
    required this.expectedAction,
  });

  final String name;
  final PlatformInfo info;
  final DeviceKind expectedDevice;
  final BrowserKind expectedBrowser;

  /// Whether the Home Screen help should open by itself on this device (not dismissed, not standalone).
  final bool expectedHelp;
  final FullscreenAction expectedAction;
}

const _iphoneSafari = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const _iphoneChrome = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.153 Mobile/15E148 Safari/604.1';
const _ipadDesktop = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
const _ipadMobile = 'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const _ipadChrome = 'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.153 Mobile/15E148 Safari/604.1';
const _mac = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
const _android = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
const _windows = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const devicePresets = <DevicePreset>[
  DevicePreset(
    name: 'iPhone Safari',
    info: PlatformInfo(userAgent: _iphoneSafari, platform: 'iPhone', maxTouchPoints: 5),
    expectedDevice: DeviceKind.iphone,
    expectedBrowser: BrowserKind.safari,
    expectedHelp: true,
    expectedAction: FullscreenAction.help,
  ),
  DevicePreset(
    name: 'iPhone Chrome',
    info: PlatformInfo(userAgent: _iphoneChrome, platform: 'iPhone', maxTouchPoints: 5),
    expectedDevice: DeviceKind.iphone,
    expectedBrowser: BrowserKind.other,
    expectedHelp: true,
    expectedAction: FullscreenAction.help,
  ),
  DevicePreset(
    name: 'iPad Safari (desktop mode)',
    info: PlatformInfo(userAgent: _ipadDesktop, platform: 'MacIntel', maxTouchPoints: 5, fullscreenSupported: true),
    expectedDevice: DeviceKind.ipad,
    expectedBrowser: BrowserKind.safari,
    expectedHelp: true,
    expectedAction: FullscreenAction.apiThenHelp,
  ),
  DevicePreset(
    name: 'iPad Safari (mobile mode)',
    info: PlatformInfo(userAgent: _ipadMobile, platform: 'iPad', maxTouchPoints: 5, fullscreenSupported: true),
    expectedDevice: DeviceKind.ipad,
    expectedBrowser: BrowserKind.safari,
    expectedHelp: true,
    expectedAction: FullscreenAction.apiThenHelp,
  ),
  DevicePreset(
    name: 'iPad Chrome',
    info: PlatformInfo(userAgent: _ipadChrome, platform: 'iPad', maxTouchPoints: 5, fullscreenSupported: true),
    expectedDevice: DeviceKind.ipad,
    expectedBrowser: BrowserKind.other,
    expectedHelp: true,
    expectedAction: FullscreenAction.apiThenHelp,
  ),
  DevicePreset(
    name: 'Android Chrome',
    info: PlatformInfo(userAgent: _android, platform: 'Linux armv81', maxTouchPoints: 5, fullscreenSupported: true),
    expectedDevice: DeviceKind.android,
    expectedBrowser: BrowserKind.other,
    expectedHelp: false,
    expectedAction: FullscreenAction.api,
  ),
  DevicePreset(
    name: 'Mac',
    info: PlatformInfo(userAgent: _mac, platform: 'MacIntel', maxTouchPoints: 0, fullscreenSupported: true),
    expectedDevice: DeviceKind.mac,
    expectedBrowser: BrowserKind.other,
    expectedHelp: false,
    expectedAction: FullscreenAction.api,
  ),
  DevicePreset(
    name: 'Windows',
    info: PlatformInfo(userAgent: _windows, platform: 'Win32', fullscreenSupported: true),
    expectedDevice: DeviceKind.windows,
    expectedBrowser: BrowserKind.other,
    expectedHelp: false,
    expectedAction: FullscreenAction.api,
  ),
];

class SelfCheckResult {
  const SelfCheckResult(this.name, this.reason);
  final String name;

  /// Null: passed. Otherwise why it failed.
  final String? reason;
  bool get passed => reason == null;
}

/// Runs the rules against every preset (and the standalone and dismissed variants). Pure: the same
/// answer on every device. Returns one result per check, failures with their reason.
List<SelfCheckResult> runSelfCheck() {
  final out = <SelfCheckResult>[];
  void check(String name, Object? actual, Object? expected) =>
      out.add(SelfCheckResult(name, actual == expected ? null : 'expected $expected but got $actual'));

  for (final p in devicePresets) {
    check('${p.name}: device', p.info.deviceKind, p.expectedDevice);
    if (p.info.isIos) check('${p.name}: browser', p.info.browser, p.expectedBrowser);
    check('${p.name}: help shows by itself', shouldShowFullscreenHelp(p.info, dismissed: false, inMatch: false), p.expectedHelp);
    check('${p.name}: never in a match', shouldShowFullscreenHelp(p.info, dismissed: false, inMatch: true), false);
    check('${p.name}: not after it was dismissed', shouldShowFullscreenHelp(p.info, dismissed: true, inMatch: false), false);
    check('${p.name}: not when installed', shouldShowFullscreenHelp(p.info.copyWith(isStandalone: true), dismissed: false, inMatch: false), false);
    check('${p.name}: button action', fullscreenActionFor(p.info), p.expectedAction);
    check('${p.name}: no button when installed', fullscreenActionFor(p.info.copyWith(isStandalone: true)), FullscreenAction.hidden);
  }
  // The iPad trap: a Mac that has a touch screen is an iPad, one that has none is not.
  check('Macintosh with touch is an iPad', const PlatformInfo(userAgent: _mac, platform: 'MacIntel', maxTouchPoints: 5).deviceKind, DeviceKind.ipad);
  check('Macintosh without touch is a Mac', const PlatformInfo(userAgent: _mac, platform: 'MacIntel').deviceKind, DeviceKind.mac);
  return out;
}
