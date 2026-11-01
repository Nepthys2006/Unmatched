/// Every platform that is not the web: the app is already full screen, so nothing is offered.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

import 'platform_info.dart';
import 'platform_info_service.dart';

PlatformInfoService createPlatformInfoService() => StubPlatformInfoService();

class StubPlatformInfoService implements PlatformInfoService {
  @override
  PlatformInfo read() {
    final ua = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iPhone',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'Macintosh',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => '',
    };
    // A native app is "installed": no Home Screen help, no browser full screen button.
    return PlatformInfo(userAgent: ua, isStandalone: true);
  }

  @override
  bool get isFullscreen => true;

  @override
  Future<bool> requestFullscreen() => Future.value(false);

  @override
  Future<void> exitFullscreen() async {}

  @override
  Stream<void> get fullscreenChanges => const Stream.empty();
}
