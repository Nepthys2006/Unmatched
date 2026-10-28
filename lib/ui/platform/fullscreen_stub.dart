/// Apps: always full screen, landscape is set by the platform.
library;

bool get canToggleFullscreen => false;
bool get isFullscreen => true;

/// Whether the app was launched from the home screen (PWA / standalone mode). Always false on
/// native apps — they're always full screen.
bool get isStandaloneApp => true;

/// Whether this is an iPhone in Safari (no element fullscreen, no orientation lock). Always
/// false on native apps.
bool get isIphoneSafari => false;

/// Whether the iOS "Add to Home Screen" hint has already been shown and dismissed.
bool get iosHintShown => false;

/// Mark the iOS hint as shown so it is not shown again.
void markIosHintShown() {}

void addFullscreenChangeListener(void Function() listener) {}
void removeFullscreenChangeListener(void Function() listener) {}

Future<void> toggleFullscreen() async {}
