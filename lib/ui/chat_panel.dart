/// The multiplayer chat: a panel with the lobby's messages (who said it, in their seat colour),
/// quick phrases for a one-tap "Good luck!", and a box to type in; the button that opens it, with
/// how many messages came in since it was last open; and the lobby screen's slide-in sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/chat.dart';
import 'theme.dart';
import 'widgets.dart';

const _phrases = ['Good luck!', 'Nice move', 'Ouch!', 'Well played', 'One moment…', 'GG'];

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.chat, required this.onSend, required this.colorOf, this.mySeat, this.onClose});
  final ChatLog chat;
  final void Function(String text) onSend;
  final Color Function(int seat) colorOf;
  final int? mySeat;
  final VoidCallback? onClose;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? quick]) {
    final t = cleanChat(quick ?? _text.text);
    if (t.isEmpty) return;
    widget.onSend(t);
    if (quick == null) {
      _text.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Panel(
      key: const ValueKey('chat-panel'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      cut: 12,
      color: Palette.bgDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_rounded, size: 18, color: Palette.gold),
              const SizedBox(width: 8),
              Expanded(child: Text('CHAT', style: titleStyle(18, spacing: 1.6))),
              if (widget.onClose != null) HexButton(icon: Icons.close_rounded, tooltip: 'Close chat', size: 34, onPressed: widget.onClose),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.chat,
              builder: (_, _) {
                final ms = widget.chat.messages;
                if (ms.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hi to the table.',
                      style: bodyStyle(14, color: Palette.muted),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.only(right: 4),
                  itemCount: ms.length,
                  itemBuilder: (_, i) => _line(ms[ms.length - 1 - i]),
                );
              },
            ),
          ),
          if (!typing) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _phrases.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => _Phrase(_phrases[i], onTap: () => _send(_phrases[i])),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat-input'),
                  controller: _text,
                  focusNode: _focus,
                  maxLength: chatMaxLength,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))],
                  onSubmitted: (_) => _send(),
                  style: bodyStyle(16),
                  decoration: InputDecoration(
                    hintText: 'Message',
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFF0A0D13),
                    border: OutlineInputBorder(borderSide: BorderSide(color: Palette.gold.withValues(alpha: 0.3))),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Palette.gold.withValues(alpha: 0.3))),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Palette.gold)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              HexButton(key: const ValueKey('chat-send'), icon: Icons.send_rounded, tooltip: 'Send', size: 38, onPressed: _send),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(ChatMessage m) {
    final mine = m.seat == widget.mySeat;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: mine ? 'You  ' : '${m.name}  ',
              style: titleStyle(14, color: widget.colorOf(m.seat), spacing: 0.3),
            ),
            TextSpan(text: m.text, style: bodyStyle(14.5, color: mine ? Palette.boneDim : Palette.bone)),
          ],
        ),
      ),
    );
  }
}

class _Phrase extends StatelessWidget {
  const _Phrase(this.text, {required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF141A26),
    shape: StadiumBorder(side: BorderSide(color: Palette.gold.withValues(alpha: 0.35))),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(child: Text(text, style: bodyStyle(13, color: Palette.bone))),
      ),
    ),
  );
}

/// Opens the chat; a gold count of the messages that came while it was closed.
class ChatButton extends StatelessWidget {
  const ChatButton({super.key, required this.chat, required this.onPressed, this.size = 44});
  final ChatLog chat;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: chat,
    builder: (_, _) {
      final n = chat.unread;
      return Stack(
        children: [
          HexButton(icon: Icons.forum_rounded, tooltip: 'Chat', size: size, onPressed: onPressed),
          if (n > 0)
            Positioned(
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('chat-unread'),
                  constraints: BoxConstraints(minWidth: size * 0.4),
                  height: size * 0.4,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Palette.gold,
                    borderRadius: BorderRadius.circular(size * 0.2),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 4)],
                  ),
                  alignment: Alignment.center,
                  child: Text(n > 9 ? '9+' : '$n', style: titleStyle(size * 0.27, color: Palette.bgDeep, spacing: 0)),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// The chat sliding in from the right over the lobby.
Future<void> showChatSheet(
  BuildContext context, {
  required ChatLog chat,
  required void Function(String text) onSend,
  required Color Function(int seat) colorOf,
  int? mySeat,
}) async {
  chat.open = true;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close chat',
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) {
      final size = MediaQuery.sizeOf(ctx);
      return SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: size.width < 520 ? size.width - 20 : 360,
              child: Material(
                color: Colors.transparent,
                child: ChatPanel(chat: chat, onSend: onSend, colorOf: colorOf, mySeat: mySeat, onClose: () => Navigator.of(ctx).pop()),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: a, child: child),
    ),
  );
  chat.open = false;
}
