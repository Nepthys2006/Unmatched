/// Web: the page asks the browser for full screen and, where allowed (Android Chrome), locks the
/// screen to landscape. Browsers only allow this from a tap or key press.
///
/// On iPhone Safari no element fullscreen exists — the "Full screen" button instead shows a
/// one-time hint explaining how to add the app to the home screen for borderless play.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

// ------------------------------------------------------------------ platform detection

bool get _isIOS =>
    _ua.contains('iPad') ||
    _ua.contains('iPhone') ||
    _ua.contains('iPod') ||
    (web.window.navigator.platform == 'MacIntel' && web.window.navigator.maxTouchPoints > 1);

String get _ua => web.window.navigator.userAgent;

/// Whether this is an iPhone (not iPad) in Safari — no element fullscreen, no orientation lock.
bool get isIphoneSafari =>
    (_ua.contains('iPhone') || _ua.contains('iPod')) && !isStandaloneApp;

/// Whether the app was installed (Add to Home Screen) and launched from there.
bool get isStandaloneApp {
  // navigator.standalone is Safari-only and true when launched from the home screen.
  // The display-mode media query catches Chrome/Android standalone installs.
  // But NOT during element fullscreen (Chrome matches `fullscreen` display-mode when
  // in element fullscreen, which is *not* a standalone install).
  if (web.document.fullscreenElement != null) return false;
  final standalone = _jsNavigatorStandalone;
  if (standalone != null) return standalone;
  return web.window.matchMedia('(display-mode: standalone)').matches ||
      web.window.matchMedia('(display-mode: fullscreen)').matches;
}

/// Safari's proprietary `navigator.standalone` — `true` when launched from the home screen,
/// `false` when in Safari, `null` on non-Apple browsers.
bool? get _jsNavigatorStandalone {
  try {
    final v = _getNavigatorStandalone();
    if (v == null) return null;
    return v.dartify() == true;
  } catch (_) {
    return null;
  }
}

@JS('_agy_navigator_standalone')
external JSAny? _getNavigatorStandalone();

/// Whether the fullscreen button should be shown: never on iPhone Safari (the button shows
/// the hint instead, via the FullscreenButton widget), and not when already standalone.
bool get canToggleFullscreen {
  if (isStandaloneApp) return false;
  if (isIphoneSafari) return false;
  return true;
}

bool get isFullscreen => web.document.fullscreenElement != null;

/// Whether the iOS "Add to Home Screen" hint has been shown before (remembered in
/// localStorage so it doesn't nag every session).
bool get iosHintShown {
  try {
    return web.window.localStorage.getItem('ios-pwa-tip-shown') == '1';
  } catch (_) {
    return false;
  }
}

/// Mark the iOS hint as shown.
void markIosHintShown() {
  try {
    web.window.localStorage.setItem('ios-pwa-tip-shown', '1');
  } catch (_) {}
}

final List<void Function()> _fullscreenListeners = [];
bool _hasInstalledFullscreenListeners = false;

void _onNativeFullscreenChange(web.Event _) {
  for (final listener in List.of(_fullscreenListeners)) {
    listener();
  }
}

void addFullscreenChangeListener(void Function() listener) {
  _fullscreenListeners.add(listener);
  if (!_hasInstalledFullscreenListeners) {
    _hasInstalledFullscreenListeners = true;
    web.document.addEventListener('fullscreenchange', _onNativeFullscreenChange.toJS);
    web.document.addEventListener('webkitfullscreenchange', _onNativeFullscreenChange.toJS);
  }
}

void removeFullscreenChangeListener(void Function() listener) {
  _fullscreenListeners.remove(listener);
}

/// Toggle full screen. On Android Chrome / desktop this enters element fullscreen and locks
/// landscape (catching failures on platforms that don't support it). On exit it unlocks.
Future<void> toggleFullscreen() async {
  try {
    if (isFullscreen) {
      // Leave fullscreen.
      await web.document.exitFullscreen().toDart;
      // Unlock orientation so the rotate overlay can take over.
      try {
        web.window.screen.orientation.unlock();
      } catch (_) {}
      return;
    }

    final el = web.document.documentElement;
    if (el == null) return;

    // iPad Safari: webkitRequestFullscreen.
    if (_isIOS) {
      try {
        _callWebkitRequestFullscreen(el);
        // iOS has no orientation lock API; skip.
      } catch (_) {}
      return;
    }

    // Android Chrome / desktop: standard requestFullscreen, then lock landscape.
    try {
      await el.requestFullscreen().toDart;
    } catch (_) {
      return; // Can't go fullscreen (e.g. not inside a user gesture).
    }
    // Now try to lock to landscape. This will succeed on Android Chrome and fail harmlessly
    // on desktop browsers.
    try {
      await web.window.screen.orientation.lock('landscape').toDart;
    } catch (_) {
      // Desktop browsers refuse orientation lock — that's fine.
    }
  } catch (_) {
    // Catch-all to avoid uncaught JS errors on exotic browsers.
  }
}

void _callWebkitRequestFullscreen(web.Element el) {
  try {
    _rawWebkitRequestFullscreen(el);
  } catch (_) {}
}

@JS('_agy_webkitRequestFullscreen')
external void _rawWebkitRequestFullscreen(web.Element el);
