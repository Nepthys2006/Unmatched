/// Full screen in landscape for the web build (the apps are full screen already).
library;

export 'fullscreen_stub.dart' if (dart.library.js_interop) 'fullscreen_web.dart';
