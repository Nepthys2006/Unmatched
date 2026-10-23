/// Web host for the 3D board: the page runs in a same-origin iframe and talks by postMessage.
library;

import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'board3d.dart';

bool get supported => true;

Widget buildHost(Board3DController c) => _WebHost(c);

class _WebHost extends StatefulWidget {
  const _WebHost(this.c);
  final Board3DController c;

  @override
  State<_WebHost> createState() => _WebHostState();
}

class _WebHostState extends State<_WebHost> {
  static int _views = 0;
  late final String _type = 'board3d-${_views++}';
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener = _onMessage.toJS;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_type, (int id) {
      final f = web.HTMLIFrameElement()
        ..src = ui_web.assetManager.getAssetUrl('assets/web3d/index.html')
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        // Display only: every click goes to the game, which forwards camera moves and taps.
        ..style.pointerEvents = 'none';
      _frame = f;
      return f;
    });
    web.window.addEventListener('message', _listener);
    widget.c.bind((json) => _frame?.contentWindow?.postMessage(json.toJS, '*'.toJS));
  }

  void _onMessage(web.MessageEvent e) {
    final data = e.data;
    if (data == null || !data.isA<JSString>()) return;
    final s = (data as JSString).toDart;
    if (!s.startsWith('board3d:')) return;
    // Only the iframe this widget made.
    final frame = _frame?.contentWindow;
    if (frame == null || !identical(e.source, frame) && e.source != frame) return;
    widget.c.receive(s.substring(8));
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _type);
}
