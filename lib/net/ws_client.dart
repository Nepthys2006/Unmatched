/// A player's WebSocket connection to a LAN host (works on phones, desktops and the web).
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'link.dart';

class WsClientLink implements ClientLink {
  WsClientLink._(this._ch) {
    _ch.stream.listen(
      (data) {
        if (data is! String) return;
        try {
          final m = jsonDecode(data);
          if (m is Map) _messages.add(m.cast<String, Object?>());
        } catch (_) {}
      },
      onDone: () => _finish(null),
      onError: (Object e) => _finish('Connection error: $e'),
    );
  }

  static Future<WsClientLink> connect(Uri uri) async {
    final ch = WebSocketChannel.connect(uri);
    await ch.ready.timeout(const Duration(seconds: 8));
    return WsClientLink._(ch);
  }

  final WebSocketChannel _ch;
  final StreamController<Msg> _messages = StreamController.broadcast();
  final Completer<String?> _done = Completer();

  void _finish(String? why) {
    if (!_done.isCompleted) _done.complete(why);
  }

  @override
  Stream<Msg> get messages => _messages.stream;
  @override
  Future<String?> get done => _done.future;

  @override
  void send(Msg m) {
    if (!_done.isCompleted) _ch.sink.add(jsonEncode(m));
  }

  @override
  Future<void> close() async {
    _finish(null);
    await _ch.sink.close();
  }
}
