import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../../../services/chat_service.dart';
import '../../auth/domain/auth_models.dart';
import '../../groups/presentation/group_members_screen.dart';
import '../../media/data/media_api.dart';
import '../../media/data/media_uploader.dart';
import '../data/chat_api.dart';
import '../domain/chat_attachment.dart';
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
  final _mediaApi = MediaApi();
  final _uploader = MediaUploader();
  final _imagePicker = ImagePicker();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  Conversation? _conversation;
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  _UploadState? _upload;
  StreamSubscription<Map<String, dynamic>>? _messageSub;

  /// When non-null the composer is in "edit" mode — sending will PATCH
  /// this message instead of POSTing a new one.
  Message? _editing;

  /// Last message id we reported to `/read`. Prevents spamming on every
  /// incoming WS frame.
  String? _lastReadMessageId;

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

      _markReadUpToLatest();
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
    _markReadUpToLatest();
  }

  /// Fire-and-forget POST /conversations/{id}/read. Dedupes by the last
  /// message id so opening a chat with N messages doesn't thrash the
  /// endpoint.
  void _markReadUpToLatest() {
    final conv = _conversation;
    if (conv == null || _messages.isEmpty) return;
    final latest = _messages.last;
    if (latest.id == _lastReadMessageId) return;
    _lastReadMessageId = latest.id;
    _api
        .markRead(conversationId: conv.id, lastReadMessageId: latest.id)
        .catchError((_) {});
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    final conv = _conversation;
    if (text.isEmpty || conv == null) return;
    setState(() => _sending = true);

    try {
      if (_editing != null) {
        // PATCH the existing message. Backend doesn't broadcast edits
        // over WS yet, so we merge the updated row locally.
        final updated = await _api.editMessage(
          messageId: _editing!.id,
          content: text,
        );
        if (!mounted) return;
        setState(() {
          _messages = _messages
              .map((m) => m.id == updated.id ? updated : m)
              .toList();
          _editing = null;
          _inputController.clear();
          _sending = false;
        });
      } else {
        // Send via REST, then append the server-returned row immediately.
        // Some backends (AWS prod today) don't fan the REST send out over
        // WebSocket, so we can't wait for a WS echo — it may never arrive.
        // If a WS echo does come later, [_onWsMessage] dedupes by id.
        final created = await _api.sendMessage(
          conversationId: conv.id,
          content: text,
        );
        if (!mounted) return;
        setState(() {
          if (!_messages.any((m) => m.id == created.id)) {
            _messages = [..._messages, created];
          }
          _inputController.clear();
          _sending = false;
        });
        _scrollToBottomSoon();
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '${e.code}: ${e.message}';
      });
    }
  }

  /// Open the long-press actions sheet for one of my own messages.
  /// Plain-text messages expose Edit/Delete/Copy; attachment messages
  /// only offer Delete (editing content would drop the attachment).
  void _showMessageActions(Message msg) {
    if (msg.isDeleted || msg.senderId != widget.me.id) return;
    final parsed = ChatAttachment.parse(msg.content);
    final canEdit = !parsed.hasAttachment;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCreamCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 6, bottom: 8),
                decoration: BoxDecoration(
                  color: kHairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (canEdit)
                _ActionRow(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: () {
                    Navigator.pop(ctx);
                    _beginEdit(msg);
                  },
                ),
              _ActionRow(
                icon: Icons.copy_all_outlined,
                label: 'Copy',
                onTap: () {
                  Navigator.pop(ctx);
                  final toCopy = parsed.hasAttachment ? parsed.text : msg.content;
                  Clipboard.setData(ClipboardData(text: toCopy));
                },
              ),
              _ActionRow(
                icon: Icons.delete_outline,
                label: 'Delete',
                destructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _beginEdit(Message msg) {
    setState(() {
      _editing = msg;
      _inputController.text = msg.content;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: msg.content.length),
      );
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _inputController.clear();
    });
  }

  Future<void> _deleteMessage(Message msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCreamCard,
        surfaceTintColor: kCreamCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: kHairline),
        ),
        title: Text(
          'Delete message?',
          style: GoogleFonts.playfairDisplay(
            color: kInkDark,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'The message will be marked as deleted for everyone in this chat.',
          style: GoogleFonts.inter(fontSize: 13, color: kInkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: kInkMuted),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: kDangerInk,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteMessage(msg.id);
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == msg.id
                ? Message(
                    id: m.id,
                    conversationId: m.conversationId,
                    senderId: m.senderId,
                    senderName: m.senderName,
                    content: m.content,
                    createdAt: m.createdAt,
                    editedAt: m.editedAt,
                    deletedAt: DateTime.now(),
                  )
                : m)
            .toList();
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = '${e.code}: ${e.message}');
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

  // ---- attachment flow ------------------------------------------------

  void _showAttachSheet() {
    if (_upload != null || _conversation == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttachDock(
        onPickImage: (src) {
          Navigator.pop(context);
          _pickImage(src);
        },
        onPickVideo: (src) {
          Navigator.pop(context);
          _pickVideo(src);
        },
        onPickFile: () {
          Navigator.pop(context);
          _pickFile();
        },
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _imagePicker.pickImage(source: source);
      if (xfile == null) return;
      await _uploadAndSend(File(xfile.path), xfile.name,
          mimeHint: xfile.mimeType);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Picker failed: $e');
    }
  }

  /// Pick a video from the library or record a new one. 5 min camera cap
  /// keeps the upload comfortably under the backend's 100 MB ceiling.
  Future<void> _pickVideo(ImageSource source) async {
    try {
      final xfile = await _imagePicker.pickVideo(
        source: source,
        maxDuration: source == ImageSource.camera
            ? const Duration(minutes: 5)
            : null,
      );
      if (xfile == null) return;
      // Android gallery returns cached temp files without an extension —
      // pass the picker's mimeType through so the uploader skips its
      // filename-based sniff entirely.
      await _uploadAndSend(File(xfile.path), xfile.name,
          mimeHint: xfile.mimeType);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Picker failed: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      final path = res?.files.single.path;
      if (path == null) return;
      await _uploadAndSend(File(path), res!.files.single.name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Picker failed: $e');
    }
  }

  /// 3-step upload → send a chat message whose content encodes the
  /// attachment (see [ChatAttachment.encode]). The caption is whatever the
  /// user has already typed in the composer; it gets cleared on success.
  Future<void> _uploadAndSend(
    File file,
    String name, {
    String? mimeHint,
  }) async {
    final conv = _conversation;
    if (conv == null) return;
    final caption = _inputController.text.trim();
    setState(() {
      _error = null;
      _upload = _UploadState(name: name);
    });
    try {
      final media = await _uploader.upload(
        file: file,
        fileName: name,
        mimeType: mimeHint,
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() => _upload = _UploadState(
                name: name,
                sentBytes: sent,
                totalBytes: total,
              ));
        },
      );
      final encoded = ChatAttachment.encode(
        ChatAttachment(
          mediaId: media.id,
          fileName: media.fileName,
          mimeType: media.mimeType,
          fileSize: media.fileSize,
        ),
        caption: caption,
      );
      final created =
          await _api.sendMessage(conversationId: conv.id, content: encoded);
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == created.id)) {
          _messages = [..._messages, created];
        }
        _inputController.clear();
        _upload = null;
      });
    } on MediaUploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _upload = null;
        _error = e.message;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _upload = null;
        _error = '${e.code}: ${e.message}';
      });
    }
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
    final initials = _initialsFor(widget.groupName);
    return Scaffold(
      backgroundColor: kCream,
      appBar: CreamAppBar(
        title: widget.groupName,
        leadingAvatar: CreamAvatar(
          seed: widget.groupName,
          initials: initials,
          size: 36,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined, color: kAccentDeep),
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
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_error != null)
                _ErrorBanner(text: _error!, onDismiss: () {
                  setState(() => _error = null);
                }),
              if (_upload != null) _UploadBanner(state: _upload!),
              if (_editing != null)
                _EditingBanner(onCancel: _cancelEdit),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kAccentDeep))
                    : _messages.isEmpty
                        ? _EmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                            itemCount: _messages.length,
                            itemBuilder: (ctx, i) => _MessageBubble(
                              msg: _messages[i],
                              isMine: _messages[i].senderId == widget.me.id,
                              mediaApi: _mediaApi,
                              onLongPress: _showMessageActions,
                            ),
                          ),
              ),
              _Composer(
                controller: _inputController,
                enabled: !_sending && _conversation != null && _upload == null,
                sending: _sending,
                onSend: _send,
                onAttach: _showAttachSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.isMine,
    required this.mediaApi,
    required this.onLongPress,
  });
  final Message msg;
  final bool isMine;
  final MediaApi mediaApi;
  final ValueChanged<Message> onLongPress;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine ? kAccent : Colors.white;
    final textColor = isMine ? Colors.white : kInkDark;
    final mutedColor = isMine
        ? Colors.white.withValues(alpha: 0.85)
        : kInkMuted;
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;

    final parsed = msg.isDeleted
        ? const ParsedMessage(text: '')
        : ChatAttachment.parse(msg.content);

    return Container(
      alignment: align,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: GestureDetector(
          onLongPress: isMine && !msg.isDeleted
              ? () => onLongPress(msg)
              : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMine ? 18 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 18),
              ),
              border: isMine
                  ? null
                  : Border.all(color: kHairline, width: 0.6),
              boxShadow: isMine
                  ? null
                  : [
                      BoxShadow(
                        color: const Color(0xFF6B4A22).withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kAccentDeep,
                      ),
                    ),
                  ),
                if (msg.isDeleted)
                  Text(
                    '(deleted)',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: mutedColor,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else ...[
                  if (parsed.hasAttachment)
                    _AttachmentView(
                      attachment: parsed.attachment!,
                      mediaApi: mediaApi,
                      isMine: isMine,
                    ),
                  if (parsed.hasAttachment && parsed.hasText)
                    const SizedBox(height: 6),
                  if (parsed.hasText || !parsed.hasAttachment)
                    _LinkifiedText(
                      text: parsed.text.isEmpty ? msg.content : parsed.text,
                      textColor: textColor,
                      isMine: isMine,
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_formatTime(msg.createdAt)}${msg.isEdited ? ' · edited' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: mutedColor,
                        ),
                      ),
                      if (isMine && !msg.isDeleted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.done_all,
                          size: 14,
                          color: mutedColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
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

/// Renders an attached image inline (once its presigned URL is fetched)
/// or a tappable file row for documents/video/audio. Presigned URLs
/// expire in ~1 h so we fetch lazily and refetch on retry, per media.md
/// §"Common pitfalls" row "Caching download_url for hours".
class _AttachmentView extends StatefulWidget {
  const _AttachmentView({
    required this.attachment,
    required this.mediaApi,
    required this.isMine,
  });
  final ChatAttachment attachment;
  final MediaApi mediaApi;
  final bool isMine;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  String? _url;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.isImage) {
      _fetchUrl();
    }
  }

  Future<void> _fetchUrl() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await widget.mediaApi.getDownloadUrl(widget.attachment.mediaId);
      if (!mounted) return;
      setState(() {
        _url = url;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _openExternally() async {
    try {
      final url = _url ?? await widget.mediaApi.getDownloadUrl(widget.attachment.mediaId);
      if (!mounted) return;
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _error = 'Could not open download URL.');
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    if (att.isImage) return _buildImage();
    return _buildFileRow();
  }

  Widget _buildImage() {
    if (_loading) {
      return const SizedBox(
        width: 220,
        height: 140,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: kAccentDeep),
        ),
      );
    }
    if (_url == null) {
      return _buildFileRow();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: _openExternally,
        child: Image.network(
          _url!,
          width: 240,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildFileRow(),
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const SizedBox(
                  width: 220,
                  height: 140,
                  child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kAccentDeep),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFileRow() {
    final att = widget.attachment;
    final isMine = widget.isMine;
    final fg = isMine ? Colors.white : kInkDark;
    final fgMuted = isMine ? Colors.white.withValues(alpha: 0.85) : kInkMuted;
    final chipBg = isMine
        ? Colors.white.withValues(alpha: 0.18)
        : kAccent.withValues(alpha: 0.12);
    final iconColor = isMine ? Colors.white : kAccentDeep;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openExternally,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withValues(alpha: 0.12)
              : kCreamField,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMine
                ? Colors.white.withValues(alpha: 0.25)
                : kHairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chipBg,
              ),
              child: Icon(_iconFor(att), color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    att.fileName,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_formatBytes(att.fileSize)} · tap to open',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: fgMuted,
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: kDangerInk,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(ChatAttachment a) {
    if (a.isImage) return Icons.image_outlined;
    if (a.isVideo) return Icons.videocam_outlined;
    if (a.isAudio) return Icons.audiotrack_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatBytes(int b) {
    if (b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Renders text with auto-detected URLs + email addresses as tappable
/// links. Plain text runs inherit the bubble's body style; link runs are
/// underlined and tinted to stand out on both mine/theirs bubbles.
class _LinkifiedText extends StatelessWidget {
  const _LinkifiedText({
    required this.text,
    required this.textColor,
    required this.isMine,
  });

  final String text;
  final Color textColor;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = GoogleFonts.inter(
      fontSize: 14.5,
      color: textColor,
      height: 1.35,
    );
    final linkColor = isMine ? Colors.white : kAccentDeep;
    final linkStyle = bodyStyle.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
      fontWeight: FontWeight.w600,
    );
    return SelectableLinkify(
      text: text,
      style: bodyStyle,
      linkStyle: linkStyle,
      options: const LinkifyOptions(humanize: false, looseUrl: true),
      linkifiers: const [UrlLinkifier(), EmailLinkifier()],
      onOpen: (link) async {
        final uri = Uri.tryParse(link.url);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });
  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(
        color: kCream,
        border: Border(top: BorderSide(color: kHairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: kCreamField,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: kHairline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: enabled ? onAttach : null,
                      tooltip: 'Attach a file or photo',
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.attach_file_rounded,
                        color: enabled ? kAccentDeep : kInkSubtle,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        enabled: enabled,
                        maxLines: 5,
                        minLines: 1,
                        cursorColor: kAccentDeep,
                        textInputAction: TextInputAction.newline,
                        style: GoogleFonts.inter(
                          color: kInkDark,
                          fontSize: 14.5,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Write a message',
                          hintStyle: GoogleFonts.inter(
                            color: kInkSubtle,
                            fontSize: 14.5,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: enabled ? kAccent : kAccent.withValues(alpha: 0.5),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onSend : null,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(13),
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
            const Icon(Icons.chat_bubble_outline,
                size: 56, color: kInkSubtle),
            const SizedBox(height: 14),
            Text(
              'No messages yet — say hello.',
              style: GoogleFonts.inter(color: kInkMuted, fontSize: 14),
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
        color: kDangerBg.withValues(alpha: 0.10),
        border: Border.all(color: kDangerBg.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: kDangerInk, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(color: kDangerInk, fontSize: 12)),
          ),
          IconButton(
              icon: const Icon(Icons.close, size: 16, color: kDangerInk),
              onPressed: onDismiss),
        ],
      ),
    );
  }
}

class _UploadState {
  const _UploadState({
    required this.name,
    this.sentBytes = 0,
    this.totalBytes = 0,
  });
  final String name;
  final int sentBytes;
  final int totalBytes;

  double? get fraction =>
      totalBytes > 0 ? (sentBytes / totalBytes).clamp(0.0, 1.0) : null;
}

class _UploadBanner extends StatelessWidget {
  const _UploadBanner({required this.state});
  final _UploadState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: kCreamCard,
        border: Border.all(color: kHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.cloud_upload, color: kAccentDeep, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Uploading ${state.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kInkDark,
                ),
              ),
            ),
            if (state.fraction != null)
              Text('${(state.fraction! * 100).round()}%',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: kInkMuted)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.fraction,
              minHeight: 4,
              backgroundColor: kHairline,
              valueColor: const AlwaysStoppedAnimation<Color>(kAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditingBanner extends StatelessWidget {
  const _EditingBanner({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: kAccent.withValues(alpha: 0.12),
        border: Border.all(color: kAccent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, color: kAccentDeep, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editing message — send to save, or cancel.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: kInkDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: kAccentDeep),
            onPressed: onCancel,
            tooltip: 'Cancel edit',
          ),
        ],
      ),
    );
  }
}

/// One row in the message long-press menu.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? kDangerInk : kInkDark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 16),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dark slim bottom sheet pinned along the screen edge with the 5 attach
/// options laid out as a horizontal dock. Reuses [_AttachDockItem] for
/// each tab so all five share the same icon-circle + label treatment.
class _AttachDock extends StatelessWidget {
  const _AttachDock({
    required this.onPickImage,
    required this.onPickVideo,
    required this.onPickFile,
  });
  final ValueChanged<ImageSource> onPickImage;
  final ValueChanged<ImageSource> onPickVideo;
  final VoidCallback onPickFile;

  static const _surface = Color(0xFF2A2520);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttachDockItem(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      onTap: () => onPickImage(ImageSource.gallery),
                    ),
                    _AttachDockItem(
                      icon: Icons.photo_camera_outlined,
                      label: 'Camera',
                      onTap: () => onPickImage(ImageSource.camera),
                    ),
                    _AttachDockItem(
                      icon: Icons.video_library_outlined,
                      label: 'Video',
                      onTap: () => onPickVideo(ImageSource.gallery),
                    ),
                    _AttachDockItem(
                      icon: Icons.videocam_outlined,
                      label: 'Record',
                      onTap: () => onPickVideo(ImageSource.camera),
                    ),
                    _AttachDockItem(
                      icon: Icons.insert_drive_file_outlined,
                      label: 'File',
                      onTap: onPickFile,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One column-shaped tab inside [_AttachDock]: round icon chip + caption.
class _AttachDockItem extends StatelessWidget {
  const _AttachDockItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kAccent.withValues(alpha: 0.18),
                ),
                child: Icon(icon, color: kAccent, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
