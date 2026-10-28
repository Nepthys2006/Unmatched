/// Web: the page asks the browser for full screen and, where allowed (Android Chrome), locks the
/// screen to landscape. Browsers only allow this from a tap or key press.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get canToggleFullscreen => true;
bool get isFullscreen =>
    web.document.fullscreenElement != null ||
    web.document.documentElement?.classList.contains('ios-enlarged') == true;

Future<void> toggleFullscreen() async {
  try {
    web.window.dispatchEvent(web.Event('toggle-app-fullscreen'));
  } catch (_) {}

  try {
    if (isFullscreen) {
      if (web.document.fullscreenElement != null) {
        await web.document.exitFullscreen().toDart;
      }
      web.document.documentElement?.classList.remove('ios-enlarged');
      return;
    }
    final el = web.document.documentElement;
    if (el != null) {
      try {
        await el.requestFullscreen().toDart;
        await web.window.screen.orientation.lock('landscape').toDart;
      } catch (_) {
        // Desktop browsers refuse orientation lock; iPhone Safari has no element full screen.
        el.classList.add('ios-enlarged');
      }
    }
  } catch (_) {
    web.document.documentElement?.classList.toggle('ios-enlarged');
  }
}
