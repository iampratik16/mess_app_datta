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
      backgroundColor: const Color(0xFF1E1B3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
        backgroundColor: const Color(0xFF1E1B3A),
        title: Text('Delete message?',
            style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'The message will be marked as deleted for everyone in this chat.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4757)),
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
      backgroundColor: const Color(0xFF1E1B3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AttachTile(
                icon: Icons.photo_library_outlined,
                label: 'Photo library',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              _AttachTile(
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              _AttachTile(
                icon: Icons.video_library_outlined,
                label: 'Video library',
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.gallery);
                },
              ),
              _AttachTile(
                icon: Icons.videocam_outlined,
                label: 'Record a video',
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.camera);
                },
              ),
              _AttachTile(
                icon: Icons.insert_drive_file_outlined,
                label: 'File (PDF, DOC, …)',
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            ],
          ),
        ),
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
              if (_upload != null) _UploadBanner(state: _upload!),
              if (_editing != null)
                _EditingBanner(onCancel: _cancelEdit),
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
    final color = isMine
        ? const Color(0xFF667EEA)
        : Colors.white.withValues(alpha: 0.09);
    final textColor = isMine ? Colors.white : Colors.white.withValues(alpha: 0.9);
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;

    final parsed = msg.isDeleted
        ? const ParsedMessage(text: '')
        : ChatAttachment.parse(msg.content);

    return Container(
      alignment: align,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        child: GestureDetector(
          onLongPress: isMine && !msg.isDeleted
              ? () => onLongPress(msg)
              : null,
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
              if (msg.isDeleted)
                Text(
                  '(deleted)',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: textColor,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else ...[
                if (parsed.hasAttachment)
                  _AttachmentView(
                    attachment: parsed.attachment!,
                    mediaApi: mediaApi,
                    textColor: textColor,
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
    required this.textColor,
  });
  final ChatAttachment attachment;
  final MediaApi mediaApi;
  final Color textColor;

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
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      );
    }
    if (_url == null) {
      return _buildFileRow();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
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
                        strokeWidth: 2, color: Colors.white70),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFileRow() {
    final att = widget.attachment;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _openExternally,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              child: Icon(_iconFor(att), color: widget.textColor, size: 18),
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
                      fontWeight: FontWeight.w600,
                      color: widget.textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_formatBytes(att.fileSize)} · tap to open',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: widget.textColor.withValues(alpha: 0.75),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: const Color(0xFFFF6B7A),
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
    final bodyStyle = GoogleFonts.inter(fontSize: 14, color: textColor);
    final linkColor = isMine ? Colors.white : const Color(0xFFB6C2FF);
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
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: enabled ? onAttach : null,
            tooltip: 'Attach a file or photo',
            icon: Icon(
              Icons.attach_file_rounded,
              color: enabled ? Colors.white70 : Colors.white24,
            ),
          ),
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
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.cloud_upload,
                color: Color(0xFF8A9CF5), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Uploading ${state.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            if (state.fraction != null)
              Text('${(state.fraction! * 100).round()}%',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Colors.white70)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.fraction,
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF8A9CF5)),
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
        color: const Color(0xFF667EEA).withValues(alpha: 0.18),
        border: Border.all(
            color: const Color(0xFF667EEA).withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined,
              color: Color(0xFF8A9CF5), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editing message — send to save, or cancel.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                size: 16, color: Color(0xFF8A9CF5)),
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
    final color = destructive ? const Color(0xFFFF6B7A) : Colors.white;
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

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF8A9CF5)),
            const SizedBox(width: 14),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
