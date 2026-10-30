# Local changes to webview_windows 0.4.0

Vendored from pub.dev (`dependency_overrides` in the app's pubspec.yaml). Changes, all in `windows/`:

* `texture_bridge_gpu.cc/.h` - the surface handed to Flutter is never stale, null or zero-sized.
  Before, minimizing or shrinking the window made the capture 0x0, `CreateTexture2D` failed, and the
  descriptor still pointed at the freed texture: Flutter's raster thread crashed in
  `flutter_windows.dll` (access violation) or the board stayed black after enlarging again.
  A new surface is built on the side and swapped in only on success; `GetSurfaceDescriptor`
  returns no frame instead of a stale one; stopping drops the surface and the old capture frame.
* `texture_bridge.cc` - `Start()` never makes a frame pool at 0x0 (it starts at 1x1; the first frame
  resizes it), checks the frame pool was made, and cleans up when the session can't start; the
  frame pool is only resized to a non-empty window; the pool is released on stop.

When upgrading the plugin, re-apply these (or drop them if upstream fixed the same crash).
