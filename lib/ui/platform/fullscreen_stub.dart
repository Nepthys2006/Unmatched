/// Apps: always full screen, landscape is set by the platform.
library;

bool get canToggleFullscreen => false;
bool get isFullscreen => true;
Future<void> toggleFullscreen() async {}
