/// The right [PlatformInfoService] for this build: the browser on the web, a stub elsewhere.
library;

export 'platform_info_service_stub.dart' if (dart.library.js_interop) 'platform_info_service_web.dart' show createPlatformInfoService;
