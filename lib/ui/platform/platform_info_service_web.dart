/// Web: reads the browser with package:web and dart:js_interop. Only compiled for the web.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'platform_info.dart';
import 'platform_info_service.dart';

PlatformInfoService createPlatformInfoService() => WebPlatformInfoService();

class WebPlatformInfoService implements PlatformInfoService {
  WebPlatformInfoService() {
    _changes = StreamController<void>.broadcast(
      onListen: () {
        web.document.addEventListener('fullscreenchange', _onChange);
        web.document.addEventListener('webkitfullscreenchange', _onChange);
      },
      onCancel: () {
        web.document.removeEventListener('fullscreenchange', _onChange);
        web.document.removeEventListener('webkitfullscreenchange', _onChange);
      },
    );
  }

  late final StreamController<void> _changes;
  late final JSFunction _onChange = ((web.Event _) => _changes.add(null)).toJS;

  static bool _flag(JSObject o, String name) {
    try {
      return o.getProperty<JSAny?>(name.toJS).dartify() == true;
    } catch (_) {
      return false;
    }
  }

  static bool _has(JSObject o, String name) {
    try {
      return o.has(name);
    } catch (_) {
      return false;
    }
  }

  @override
  PlatformInfo read() {
    final nav = web.window.navigator;
    var standalone = false;
    try {
      // Safari's own flag; the display-mode query covers Android and desktop installs.
      standalone = _flag(nav as JSObject, 'standalone') || web.window.matchMedia('(display-mode: standalone)').matches;
    } catch (_) {}
    final doc = web.document as JSObject;
    final root = web.document.documentElement as JSObject?;
    final supported =
        _flag(doc, 'fullscreenEnabled') ||
        _flag(doc, 'webkitFullscreenEnabled') ||
        (root != null && (_has(root, 'requestFullscreen') || _has(root, 'webkitRequestFullscreen')));
    return PlatformInfo(
      userAgent: nav.userAgent,
      platform: nav.platform,
      maxTouchPoints: nav.maxTouchPoints,
      isStandalone: standalone,
      fullscreenSupported: supported,
    );
  }

  @override
  bool get isFullscreen {
    final doc = web.document as JSObject;
    try {
      return doc.getProperty<JSAny?>('fullscreenElement'.toJS) != null || doc.getProperty<JSAny?>('webkitFullscreenElement'.toJS) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestFullscreen() {
    // Everything up to the JS call is synchronous, so it runs inside the tap's user gesture.
    try {
      final root = web.document.documentElement as JSObject?;
      if (root == null) return Future.value(false);
      final JSAny? result;
      if (_has(root, 'requestFullscreen')) {
        result = root.callMethod<JSAny?>('requestFullscreen'.toJS);
      } else if (_has(root, 'webkitRequestFullscreen')) {
        result = root.callMethod<JSAny?>('webkitRequestFullscreen'.toJS);
      } else {
        return Future.value(false);
      }
      final lockLandscape = read().deviceKind == DeviceKind.android;
      if (result.isA<JSPromise>()) {
        return (result as JSPromise).toDart.then((_) {
          if (lockLandscape) _lockLandscape();
          return true;
        }, onError: (_) => false);
      }
      // Older WebKit answers with nothing: the state a moment later tells.
      return Future<bool>.delayed(const Duration(milliseconds: 250), () => isFullscreen);
    } catch (_) {
      return Future.value(false);
    }
  }

  void _lockLandscape() {
    try {
      web.window.screen.orientation.lock('landscape').toDart.then((_) {}, onError: (_) {});
    } catch (_) {}
  }

  @override
  Future<void> exitFullscreen() async {
    try {
      final doc = web.document as JSObject;
      final JSAny? r;
      if (_has(doc, 'exitFullscreen')) {
        r = doc.callMethod<JSAny?>('exitFullscreen'.toJS);
      } else if (_has(doc, 'webkitExitFullscreen')) {
        r = doc.callMethod<JSAny?>('webkitExitFullscreen'.toJS);
      } else {
        return;
      }
      if (r.isA<JSPromise>()) await (r as JSPromise).toDart;
      try {
        web.window.screen.orientation.unlock();
      } catch (_) {}
    } catch (_) {}
  }

  @override
  Stream<void> get fullscreenChanges => _changes.stream;
}
