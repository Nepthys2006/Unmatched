/// The Full Screen button's brain: what it does on this device, the dismissed flag, and whether the
/// automatic help may show. No widgets in here, so every decision is unit tested with fake devices.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fullscreen_help_storage.dart';
import 'platform_info.dart';
import 'platform_info_service.dart';

/// What happened when the button was pressed.
enum FullscreenPress {
  entered,
  exited,

  /// The Home Screen help should open (iPhone, or iPad where the Fullscreen API is missing or refused).
  showHelp,

  /// Nothing to do (no button on this device).
  nothing,
}

class FullscreenController extends ChangeNotifier {
  FullscreenController({required this._platform, required this._storage}) {
    // The real device and flag, kept before anything can be swapped in (the debug panel).
    _realPlatform = _platform;
    _realStorage = _storage;
    _listen();
  }

  PlatformInfoService _platform;
  FullscreenHelpStorage _storage;
  late final PlatformInfoService _realPlatform;
  late final FullscreenHelpStorage _realStorage;
  StreamSubscription<void>? _sub;
  bool _disposed = false;

  /// The player closed the help before.
  bool dismissed = false;

  /// A match is running (the menu stays mounted underneath it): the help never shows then.
  /// Set without notifying: the match screen sets it while it is being built, and nothing on screen
  /// depends on it (it only decides whether the help may pop up).
  bool inMatch = false;

  /// True while a simulated device is in use (the debug panel); real data is untouched.
  bool simulated = false;

  PlatformInfoService get platform => _platform;
  PlatformInfo get info => _platform.read();
  FullscreenAction get action => fullscreenActionFor(info);
  bool get isFullscreen => _platform.isFullscreen;

  /// Hidden when running from the Home Screen (already full screen) or when nothing can be offered.
  bool get buttonVisible => action != FullscreenAction.hidden;

  /// iPad: real full screen can be interrupted by system gestures, so "install the app" is offered
  /// as the better way next to the button.
  bool get installOptionVisible => info.deviceKind == DeviceKind.ipad && !info.isStandalone;

  /// The help may pop up by itself right now.
  bool get shouldAutoShowHelp => shouldShowFullscreenHelp(info, dismissed: dismissed, inMatch: inMatch);

  void _listen() {
    unawaited(_sub?.cancel());
    _sub = _platform.fullscreenChanges.listen((_) => _notify());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Reads the saved flag. A storage failure leaves it false (the help may show once more).
  Future<void> load() async {
    try {
      dismissed = await _storage.readDismissed();
    } catch (_) {
      dismissed = false;
    }
    _notify();
  }

  Future<void> markDismissed() async {
    dismissed = true;
    _notify();
    try {
      await _storage.writeDismissed(true);
    } catch (_) {}
  }

  Future<void> clearDismissed() async {
    dismissed = false;
    _notify();
    try {
      await _storage.writeDismissed(false);
    } catch (_) {}
  }

  /// Swaps the device (the debug panel's simulator) and the storage. Passing no storage keeps the
  /// current one. [simulated] devices should come with a [MemoryFullscreenHelpStorage] so the
  /// real flag is never touched.
  Future<void> useService(PlatformInfoService service, {FullscreenHelpStorage? storage, bool simulated = true}) async {
    _platform = service;
    if (storage != null) _storage = storage;
    this.simulated = simulated;
    _listen();
    await load();
  }

  /// Back to the real device and the real saved flag (the debug panel's "Use the real device").
  Future<void> restoreReal() => useService(_realPlatform, storage: _realStorage, simulated: false);

  /// The Full Screen button was pressed. **Call this synchronously from the tap handler**: the
  /// Fullscreen API call is made before this returns, inside the user gesture, which Safari needs.
  Future<FullscreenPress> press() {
    switch (action) {
      case FullscreenAction.hidden:
        return Future.value(FullscreenPress.nothing);
      case FullscreenAction.help:
        // iPhone in a browser: pages can't go full screen, never even try.
        return Future.value(FullscreenPress.showHelp);
      case FullscreenAction.api:
      case FullscreenAction.apiThenHelp:
        if (_platform.isFullscreen) {
          return _platform.exitFullscreen().then((_) {
            _notify();
            return FullscreenPress.exited;
          });
        }
        final Future<bool> request;
        try {
          request = _platform.requestFullscreen(); // synchronous start: still inside the gesture
        } catch (_) {
          return Future.value(_failed());
        }
        return request.then(
          (ok) {
            _notify();
            return ok ? FullscreenPress.entered : _failed();
          },
          onError: (_) => _failed(),
        );
    }
  }

  FullscreenPress _failed() => action == FullscreenAction.apiThenHelp ? FullscreenPress.showHelp : FullscreenPress.nothing;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
