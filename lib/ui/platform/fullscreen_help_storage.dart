/// Remembers that the player closed the "Full screen on iPhone / iPad" help. On the web
/// shared_preferences keeps it in localStorage; private browsing and blocked storage can throw, so
/// every read and write is wrapped: failing to remember must never break the app.
library;

import 'package:shared_preferences/shared_preferences.dart';

abstract class FullscreenHelpStorage {
  Future<bool> readDismissed();
  Future<void> writeDismissed(bool value);
}

class SharedPrefsFullscreenHelpStorage implements FullscreenHelpStorage {
  const SharedPrefsFullscreenHelpStorage();

  static const key = 'fullscreen_help_dismissed';

  @override
  Future<bool> readDismissed() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> writeDismissed(bool value) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(key, value);
    } catch (_) {}
  }
}

/// Keeps the flag in memory only: the debug panel's simulator uses it so playing with the help
/// never touches the real flag, and tests use it for a fake that can also fail.
class MemoryFullscreenHelpStorage implements FullscreenHelpStorage {
  MemoryFullscreenHelpStorage({this.dismissed = false, this.failing = false});

  bool dismissed;

  /// Every call throws (storage blocked).
  bool failing;
  int writes = 0;

  @override
  Future<bool> readDismissed() async {
    if (failing) throw StateError('storage blocked');
    return dismissed;
  }

  @override
  Future<void> writeDismissed(bool value) async {
    if (failing) throw StateError('storage blocked');
    writes++;
    dismissed = value;
  }
}
