/// LAN play: hosting and discovery on native platforms, joining everywhere.
library;

export 'lan_web.dart' if (dart.library.io) 'lan_io.dart';
