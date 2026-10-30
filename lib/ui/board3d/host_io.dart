/// Native hosts for the 3D board: Android and iOS use the system web view, Windows uses WebView2.
/// The page and models are served from the app's asset bundle by a loopback-only HTTP server,
/// since web views won't load ES modules or fetch .glb files from file URLs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

import '../theme.dart';
import 'board3d.dart';

bool get supported => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

Widget buildHost(Board3DController c) {
  if (Platform.isWindows) return _WindowsHost(c);
  if (Platform.isAndroid || Platform.isIOS) return _MobileHost(c);
  c.fail('3D board not supported on this platform');
  return const SizedBox.expand();
}

/// Serves assets/web3d, assets/maps (the boards' art), assets/maps3d, assets/fonts and assets/heroes
/// (the fighters' figures and tokens) from the bundle on 127.0.0.1.
abstract final class _AssetServer {
  static Future<Uri>? _base;
  static const _allowed = ['assets/web3d/', 'assets/maps/', 'assets/maps3d/', 'assets/fonts/', 'assets/heroes/'];

  static Future<Uri> start() => _base ??= _start();

  static Future<Uri> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_serve);
    return Uri.parse('http://127.0.0.1:${server.port}/');
  }

  static Future<void> _serve(HttpRequest r) async {
    final res = r.response;
    try {
      final key = Uri.decodeComponent(r.uri.path).replaceFirst('/', '');
      if (r.method != 'GET' || key.contains('..') || !_allowed.any(key.startsWith)) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final data = await rootBundle.load(key);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      res.headers
        ..set(HttpHeaders.contentTypeHeader, _mime(key))
        ..set(HttpHeaders.cacheControlHeader, 'no-cache')
        ..contentLength = bytes.length;
      res.add(bytes);
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    } finally {
      await res.close();
    }
  }

  static String _mime(String key) => switch (key.split('.').last) {
    'html' => 'text/html; charset=utf-8',
    'js' => 'text/javascript; charset=utf-8',
    'glb' => 'model/gltf-binary',
    'webp' => 'image/webp',
    'json' => 'application/json',
    'ttf' => 'font/ttf',
    _ => 'application/octet-stream',
  };
}

class _MobileHost extends StatefulWidget {
  const _MobileHost(this.c);
  final Board3DController c;

  @override
  State<_MobileHost> createState() => _MobileHostState();
}

class _MobileHostState extends State<_MobileHost> {
  late final wf.WebViewController _wv = wf.WebViewController()
    ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
    ..setBackgroundColor(Palette.bgDeep)
    ..addJavaScriptChannel('FlutterBoard', onMessageReceived: (m) => widget.c.receive(m.message))
    ..setNavigationDelegate(
      wf.NavigationDelegate(
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) widget.c.fail(e.description);
        },
      ),
    );

  @override
  void initState() {
    super.initState();
    widget.c.bind((json) => _wv.runJavaScript('window.board&&window.board.receive(${jsonEncode(json)})').catchError((_) {}));
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final base = await _AssetServer.start();
      if (mounted) await _wv.loadRequest(base.resolve('assets/web3d/index.html'));
    } catch (e) {
      widget.c.fail('$e');
    }
  }

  @override
  // Display only (the match screen wraps it in IgnorePointer and forwards gestures).
  Widget build(BuildContext context) => wf.WebViewWidget(controller: _wv);
}

class _WindowsHost extends StatefulWidget {
  const _WindowsHost(this.c);
  final Board3DController c;

  @override
  State<_WindowsHost> createState() => _WindowsHostState();
}

/// Whether the Windows web view has an area worth capturing. A minimized window, or one dragged to a
/// sliver, lays the view out at (almost) nothing; a texture can't follow that.
@visibleForTesting
bool webviewAreaUsable(Size size) => size.width >= 8 && size.height >= 8;

class _WindowsHostState extends State<_WindowsHost> with WidgetsBindingObserver {
  final ww.WebviewController _wv = ww.WebviewController();
  StreamSubscription<dynamic>? _sub;
  Timer? _settle;
  bool _ready = false;
  bool _suspended = false;
  bool _disposed = false;
  bool _wasUsable = true;

  /// Part of the Webview's key: bumping it re-mounts the widget, which reports its size to the
  /// plugin again and so restarts the capture at the window's current size.
  int _epoch = 0;
  static bool _envInited = false;

  static Future<void> _ensureEnv() async {
    if (_envInited) return;
    _envInited = true;
    try {
      await ww.WebviewController.initializeEnvironment(
        additionalArguments: '--force-high-performance-gpu --enable-gpu-rasterization',
      );
    } catch (_) {}
  }

  bool _wvDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _disposeWebview() async {
    if (_wvDisposed) return;
    _wvDisposed = true;
    await _sub?.cancel();
    _sub = null;
    try {
      await _wv.dispose();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready || _disposed) return;
    switch (state) {
      // Minimized (or the app left the screen): stop capturing, so nothing is copied into a
      // surface Flutter isn't showing.
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        unawaited(_suspend());
      case AppLifecycleState.resumed:
        unawaited(_resume());
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _suspend() async {
    if (_suspended) return;
    _suspended = true;
    _settle?.cancel();
    try {
      await _wv.suspend();
    } catch (_) {}
  }

  Future<void> _resume() async {
    if (!_suspended) return;
    _suspended = false;
    try {
      await _wv.resume();
    } catch (_) {}
    _remount();
    // The window may still be getting its size back; once more when it has settled.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 500), () {
      if (!_disposed && !_suspended) _remount();
    });
  }

  void _remount() {
    if (_disposed || !mounted) return;
    setState(() => _epoch++);
  }

  Future<void> _load() async {
    try {
      await _ensureEnv();
      await _wv.initialize();
      if (_disposed) {
        await _disposeWebview();
        return;
      }
      await _wv.setBackgroundColor(Palette.bgDeep);
      _sub = _wv.webMessage.listen(widget.c.receive);
      widget.c.bind((json) => _wv.postWebMessage(json).catchError((_) {}));
      final base = await _AssetServer.start();
      await _wv.loadUrl(base.resolve('assets/web3d/index.html').toString());
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      // Usually the WebView2 runtime is missing.
      widget.c.fail('$e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _settle?.cancel();
    unawaited(_disposeWebview());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        final usable = webviewAreaUsable(box.biggest);
        // Coming back from (almost) nothing: mount a fresh Webview so it reports the new size.
        if (usable && !_wasUsable) _epoch++;
        _wasUsable = usable;
        if (!usable) return const SizedBox.expand();
        return KeyedSubtree(key: ValueKey(_epoch), child: ww.Webview(_wv));
      },
    );
  }
}
