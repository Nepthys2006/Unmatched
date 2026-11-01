{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings on purpose: Flutter's own worker (flutter_service_worker.js) is a stub that
// unregisters itself, and it would replace and then remove the app's real offline worker (sw.js, registered
// from index.html) because both live at the same scope.
_flutter.loader.load();
