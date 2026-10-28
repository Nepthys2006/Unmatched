/// Table talk in multiplayer lobbies and matches. Messages go through the host, which numbers
/// them and passes them to everyone (over LAN, or the lobby's Realtime channel online); online the
/// host also keeps them in the `chat_messages` table while the lobby lives, and deletes them when
/// the match ends (`chat_post` / `chat_clear`, see online.dart).
library;

import 'package:flutter/foundation.dart';

import 'link.dart';

/// The longest message, in characters.
const chatMaxLength = 200;

/// How many messages a lobby keeps (older ones scroll away).
const chatKeep = 200;

class ChatMessage {
  const ChatMessage({required this.id, required this.seat, required this.name, required this.text, required this.at});

  /// The host's number for it: 1, 2, 3... in the order everyone sees them.
  final int id;
  final int seat;
  final String name;
  final String text;
  final DateTime at;

  Msg toJson() => {'id': id, 'seat': seat, 'name': name, 'text': text, 'at': at.millisecondsSinceEpoch};

  static ChatMessage? fromJson(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], seat = m['seat'], name = m['name'], text = m['text'], at = m['at'];
    if (id is! int || seat is! int || name is! String || text is! String) return null;
    final clean = cleanChat(text);
    if (clean.isEmpty) return null;
    return ChatMessage(
      id: id,
      seat: seat,
      name: name.length > 40 ? name.substring(0, 40) : name,
      text: clean,
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.now(),
    );
  }
}

/// [s] as one line of at most [chatMaxLength] characters: control characters and runs of
/// spaces and line breaks collapsed, the ends trimmed.
String cleanChat(String s) {
  final one = s.replaceAll(RegExp(r'[\u0000-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2066-\u2069]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (one.length <= chatMaxLength) return one;
  // Don't cut a surrogate pair (an emoji) in half.
  var end = chatMaxLength;
  final c = one.codeUnitAt(end - 1);
  if (c >= 0xD800 && c <= 0xDBFF) end--;
  return one.substring(0, end).trimRight();
}

/// The lobby's messages, oldest first, and how many arrived while the chat was closed.
class ChatLog extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Messages not seen yet (the chat panel was closed when they came).
  int unread = 0;

  /// Whether the chat panel is open (messages count as seen).
  bool get open => _open;
  bool _open = false;
  set open(bool v) {
    if (_open == v && (!v || unread == 0)) return;
    _open = v;
    if (v) unread = 0;
    notifyListeners();
  }

  /// The highest message number received.
  int get lastId => _messages.isEmpty ? 0 : _messages.last.id;

  /// The first message number missing before [lastId] (lost on the way), or null.
  int? get gap {
    var want = _floor;
    for (final m in _messages) {
      if (m.id < want) continue;
      if (m.id != want) return want;
      want++;
    }
    return null;
  }

  /// Messages before this number are gone for good (scrolled away on the host).
  int _floor = 1;

  /// The newest message from someone else (the match screen shows it for a moment).
  ChatMessage? latestIncoming;

  /// Adds messages (ignoring ones already here); [mine] is this device's seat. [from] is where
  /// a history the host sent starts.
  void addAll(Iterable<ChatMessage> ms, {int? mine, int? from}) {
    if (from != null && from > _floor) _floor = from;
    var added = false;
    for (final m in ms) {
      final at = _messages.indexWhere((x) => x.id >= m.id);
      if (at >= 0 && _messages[at].id == m.id) continue;
      if (at < 0) {
        _messages.add(m);
      } else {
        _messages.insert(at, m);
      }
      added = true;
      if (m.seat != mine) {
        if (!_open) unread++;
        if (m.id > (latestIncoming?.id ?? 0)) latestIncoming = m;
      }
    }
    if (!added) return;
    if (_messages.length > chatKeep) {
      _messages.removeRange(0, _messages.length - chatKeep);
      _floor = _messages.first.id;
    }
    notifyListeners();
  }

  void add(ChatMessage m, {int? mine}) => addAll([m], mine: mine);
}
