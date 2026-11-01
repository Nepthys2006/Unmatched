/// What kind of device and browser the app runs in, worked out from what the browser reports.
///
/// Flutter's `defaultTargetPlatform` can't be trusted for this: iPadOS 13+ Safari asks for the
/// desktop site by default and says it is a Mac ("Macintosh" in the user agent, "MacIntel" as the
/// platform), so Flutter sees an iPad as a Mac. The only tell is touch: a real Mac reports no touch
/// points, an iPad reports five. This file is pure Dart (no dart:html / package:web) so every rule
/// can be unit tested with made-up user agents.
library;

enum DeviceKind { iphone, ipad, android, mac, windows, linux, other }

/// Safari, or any other browser. On iOS every browser is WebKit underneath, but only Safari has
/// the Share button in the same place, so the help text differs.
enum BrowserKind { safari, other }

class PlatformInfo {
  const PlatformInfo({
    this.userAgent = '',
    this.platform = '',
    this.maxTouchPoints = 0,
    this.isStandalone = false,
    this.fullscreenSupported = false,
  });

  final String userAgent;

  /// `navigator.platform` ("MacIntel" on an iPad in desktop mode).
  final String platform;

  /// `navigator.maxTouchPoints`: 0 on a Mac, 5 on an iPad.
  final int maxTouchPoints;

  /// Launched from the Home Screen (`navigator.standalone` or `display-mode: standalone`).
  final bool isStandalone;

  /// The page can ask for full screen (`document.fullscreenEnabled`, or the webkit-prefixed
  /// variants). Not a promise that the request will be granted.
  final bool fullscreenSupported;

  /// The classification rules, in this order:
  /// iPhone in the UA -> iPhone; iPad in the UA ("Request Mobile Website") -> iPad;
  /// Macintosh and more than one touch point -> iPad (the default iPadOS desktop mode);
  /// Macintosh without touch -> a real Mac.
  DeviceKind get deviceKind {
    final ua = userAgent;
    if (ua.contains('iPhone') || ua.contains('iPod')) return DeviceKind.iphone;
    if (ua.contains('iPad')) return DeviceKind.ipad;
    if (ua.contains('Macintosh') || platform == 'MacIntel') {
      return maxTouchPoints > 1 ? DeviceKind.ipad : DeviceKind.mac;
    }
    if (ua.contains('Android')) return DeviceKind.android;
    if (ua.contains('Windows') || platform.startsWith('Win')) return DeviceKind.windows;
    if (ua.contains('Linux') || ua.contains('X11') || platform.startsWith('Linux')) return DeviceKind.linux;
    return DeviceKind.other;
  }

  bool get isIos => deviceKind == DeviceKind.iphone || deviceKind == DeviceKind.ipad;

  /// CriOS (Chrome), FxiOS (Firefox), EdgiOS (Edge), OPiOS (Opera) and friends are "other"; on iOS
  /// anything without those markers is Safari. Off iOS the question isn't asked.
  BrowserKind get browser {
    if (!isIos) return BrowserKind.other;
    return _iosOtherBrowser.hasMatch(userAgent) ? BrowserKind.other : BrowserKind.safari;
  }

  static final _iosOtherBrowser = RegExp(r'CriOS|FxiOS|EdgiOS|OPiOS|OPT/|GSA/|DuckDuckGo|Brave');

  /// A readable name for the debug panel.
  String get browserName {
    final ua = userAgent;
    if (ua.contains('CriOS')) return 'Chrome (iOS)';
    if (ua.contains('FxiOS')) return 'Firefox (iOS)';
    if (ua.contains('EdgiOS')) return 'Edge (iOS)';
    if (ua.contains('OPiOS')) return 'Opera (iOS)';
    if (ua.contains('Edg/')) return 'Edge';
    if (ua.contains('Firefox/')) return 'Firefox';
    if (ua.contains('Chrome/')) return 'Chrome';
    if (ua.contains('Safari/')) return 'Safari';
    return ua.isEmpty ? 'unknown' : 'other';
  }

  PlatformInfo copyWith({String? userAgent, String? platform, int? maxTouchPoints, bool? isStandalone, bool? fullscreenSupported}) => PlatformInfo(
    userAgent: userAgent ?? this.userAgent,
    platform: platform ?? this.platform,
    maxTouchPoints: maxTouchPoints ?? this.maxTouchPoints,
    isStandalone: isStandalone ?? this.isStandalone,
    fullscreenSupported: fullscreenSupported ?? this.fullscreenSupported,
  );

  @override
  bool operator ==(Object other) =>
      other is PlatformInfo &&
      other.userAgent == userAgent &&
      other.platform == platform &&
      other.maxTouchPoints == maxTouchPoints &&
      other.isStandalone == isStandalone &&
      other.fullscreenSupported == fullscreenSupported;

  @override
  int get hashCode => Object.hash(userAgent, platform, maxTouchPoints, isStandalone, fullscreenSupported);

  @override
  String toString() => 'PlatformInfo($deviceKind, ${browser.name}, standalone: $isStandalone, fullscreen: $fullscreenSupported)';
}

/// Whether the "add to Home Screen" help should pop up by itself: ONLY on an iPhone or iPad, not
/// when already running from the Home Screen, not when the player dismissed it before, and never
/// during a match.
bool shouldShowFullscreenHelp(PlatformInfo info, {required bool dismissed, required bool inMatch}) =>
    info.isIos && !info.isStandalone && !dismissed && !inMatch;

/// What the "Full Screen" button does on this device.
enum FullscreenAction {
  /// No button (already running from the Home Screen, or nothing to offer).
  hidden,

  /// Desktop and Android: the Fullscreen API.
  api,

  /// iPad: try the Fullscreen API inside the tap, and open the help if it is missing or refused.
  apiThenHelp,

  /// iPhone in a browser: the Fullscreen API doesn't work for pages; open the help directly.
  help,
}

FullscreenAction fullscreenActionFor(PlatformInfo info) {
  if (info.isStandalone) return FullscreenAction.hidden;
  switch (info.deviceKind) {
    case DeviceKind.iphone:
      return FullscreenAction.help;
    case DeviceKind.ipad:
      return info.fullscreenSupported ? FullscreenAction.apiThenHelp : FullscreenAction.help;
    case DeviceKind.android || DeviceKind.mac || DeviceKind.windows || DeviceKind.linux || DeviceKind.other:
      return info.fullscreenSupported ? FullscreenAction.api : FullscreenAction.hidden;
  }
}

/// The step 1 wording needs three variants (Share is at the bottom of iPhone Safari, at the top
/// right of iPad Safari, and elsewhere in other browsers).
enum ShareStep { iphoneSafari, ipadSafari, otherBrowser }

ShareStep shareStepFor(DeviceKind device, BrowserKind browser) {
  if (browser == BrowserKind.other) return ShareStep.otherBrowser;
  return device == DeviceKind.ipad ? ShareStep.ipadSafari : ShareStep.iphoneSafari;
}
