/// Where the platform facts come from, behind an interface so tests (and the debug panel) can
/// swap in a fake device. The real implementation reads the browser (web only); on every other
/// platform a stub answers, so Android, iOS, Windows and Linux builds never touch browser code.
library;

import 'dart:async';

import 'platform_info.dart';

abstract class PlatformInfoService {
  /// What the device reports right now (standalone and fullscreen support can change).
  PlatformInfo read();

  /// The page is showing full screen at the moment.
  bool get isFullscreen;

  /// Asks the browser for full screen. This MUST be called synchronously from the tap handler (a
  /// user gesture): Safari refuses it anywhere else. The call is made before this returns; the
  /// future says whether the page ended up full screen. A real implementation never throws.
  Future<bool> requestFullscreen();

  Future<void> exitFullscreen();

  /// Fires when full screen is entered or left (including by the system: a swipe, the Esc key).
  Stream<void> get fullscreenChanges;
}

/// How a fake device answers a full screen request.
enum FakeFullscreen {
  /// The API works.
  succeeds,

  /// The request is refused (Safari blocking it).
  refuses,

  /// The request throws.
  throws,

  /// The API does not exist.
  missing,
}

/// A device that is only a description. Used by tests and by the debug panel's simulator.
class FakePlatformInfoService implements PlatformInfoService {
  FakePlatformInfoService(this._info, {this.behavior = FakeFullscreen.succeeds});

  PlatformInfo _info;
  FakeFullscreen behavior;
  bool _full = false;
  final _changes = StreamController<void>.broadcast();

  /// How many times the Fullscreen API was called, and how many exits.
  int requests = 0;
  int exits = 0;

  set info(PlatformInfo v) {
    _info = v;
    _changes.add(null);
  }

  @override
  PlatformInfo read() => _info;

  @override
  bool get isFullscreen => _full;

  /// The system leaves or enters full screen by itself.
  void setFullscreen(bool on) {
    _full = on;
    _changes.add(null);
  }

  @override
  Future<bool> requestFullscreen() {
    requests++;
    switch (behavior) {
      case FakeFullscreen.succeeds:
        setFullscreen(true);
        return Future.value(true);
      case FakeFullscreen.refuses:
      case FakeFullscreen.missing:
        return Future.value(false);
      case FakeFullscreen.throws:
        // Real implementations catch and answer false; a fake that throws proves callers cope.
        throw StateError('Fullscreen blocked');
    }
  }

  @override
  Future<void> exitFullscreen() async {
    exits++;
    setFullscreen(false);
  }

  @override
  Stream<void> get fullscreenChanges => _changes.stream;

  void dispose() => _changes.close();
}
