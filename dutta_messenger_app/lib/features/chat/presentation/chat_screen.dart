import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../services/chat_service.dart';
import '../../auth/domain/auth_models.dart';
import '../../groups/presentation/group_members_screen.dart';
import '../data/chat_api.dart';
import '../domain/chat_models.dart';

/// Live chat screen for a group conversation.
/// Opens a conversation for the given [groupId] on load, then lists messages
/// with a text input to send new ones.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.me,
    this.topicId,
  });

  final String groupId;
  final String groupName;
  final AuthUser me;

  /// If set, the screen opens the conversation for this topic within a
  /// topics-mode group. Simple-mode groups leave this null.
  final String? topicId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ChatApi();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  Conversation? _conversation;
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _messageSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// One-time history load + subscribe to the real-time stream.
  /// The WebSocket itself is owned by [ChatService] (opened at login) and
  /// survives navigation; this screen only attaches a listener to one
  /// conversation's stream.
  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conv = await _api.openGroupConversation(
        widget.groupId,
        topicId: widget.topicId,
      );
      final msgs = await _api.listMessages(conv.id);
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _messages = msgs.reversed.toList();
        _loading = false;
      });
      _scrollToBottomSoon();

      // Subscribe for real-time message.new frames for this conversation.
      ChatService.instance.subscribe(conv.id);
      _messageSub?.cancel();
      _messageSub = ChatService.instance.messages(conv.id).listen(_onWsMessage);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message}';
        _loading = false;
      });
    }
  }

  /// Merge a live message pushed over the WS. Dedupe by id so the sender's
  /// own REST-posted message doesn't render twice (server echoes it back).
  void _onWsMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    final Message msg;
    try {
      msg = Message.fromJson(payload);
    } catch (_) {
      return;
    }
    if (_messages.any((m) => m.id == msg.id)) return;
    setState(() => _messages = [..._messages, msg]);
    _scrollToBottomSoon();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    final conv = _conversation;
    if (text.isEmpty || conv == null) return;
    setState(() => _sending = true);

    // Send via REST. The server persists the message and broadcasts it
    // over the WS to every subscriber — including us — so the sender's
    // bubble is added by [_onWsMessage] on the echo (no optimistic add).
    try {
      await _api.sendMessage(conversationId: conv.id, content: text);
      if (!mounted) return;
      setState(() {
        _inputController.clear();
        _sending = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '${e.code}: ${e.message}';
      });
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    // Cancel the stream listener; do NOT disconnect the WS — it must
    // survive screen changes. The singleton closes only on logout.
    _messageSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.groupName,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'Members',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupMembersScreen(
                  groupId: widget.groupId,
                  groupName: widget.groupName,
                  me: widget.me,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0C29),
              Color(0xFF302B63),
              Color(0xFF24243E),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (_error != null)
                _ErrorBanner(text: _error!, onDismiss: () {
                  setState(() => _error = null);
                }),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white70))
                    : _messages.isEmpty
                        ? _EmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                            itemCount: _messages.length,
                            itemBuilder: (ctx, i) => _MessageBubble(
                              msg: _messages[i],
                              isMine: _messages[i].senderId == widget.me.id,
                            ),
                          ),
              ),
              _Composer(
                controller: _inputController,
                enabled: !_sending && _conversation != null,
                sending: _sending,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.isMine});
  final Message msg;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final color = isMine
        ? const Color(0xFF667EEA)
        : Colors.white.withValues(alpha: 0.09);
    final textColor = isMine ? Colors.white : Colors.white.withValues(alpha: 0.9);
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;

    return Container(
      alignment: align,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMine && msg.senderName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    msg.senderName!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),
              Text(
                msg.isDeleted ? '(deleted)' : msg.content,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: textColor,
                  fontStyle: msg.isDeleted ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_formatTime(msg.createdAt)}${msg.isEdited ? ' · edited' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: (isMine ? Colors.white : Colors.white54)
                        .withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: const Color(0xFF667EEA),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onSend : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(
              'No messages yet — say hello.',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text, required this.onDismiss});
  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFFF4757).withValues(alpha: 0.15),
        border: Border.all(
            color: const Color(0xFFFF4757).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: Color(0xFFFF6B7A), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(
                    color: const Color(0xFFFF6B7A), fontSize: 12)),
          ),
          IconButton(
              icon:
                  const Icon(Icons.close, size: 16, color: Color(0xFFFF6B7A)),
              onPressed: onDismiss),
        ],
      ),
    );
  }
}
