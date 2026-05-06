import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../../../services/chat_service.dart';
import '../../auth/domain/auth_models.dart';
import '../../groups/data/groups_api.dart';
import '../../groups/presentation/group_members_screen.dart';
import '../../media/data/media_api.dart';
import '../../media/data/media_uploader.dart';
import '../../media/data/media_url_resolver.dart';
import '../../media/domain/media_models.dart';
import '../../media/presentation/media_vault_picker_screen.dart';
import '../../users/domain/user_models.dart';
import '../data/chat_api.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_models.dart';
import '../domain/chat_type.dart';

/// Live chat screen for a DM, group, or channel conversation.
/// Opens a conversation for the given [groupId] on load, then lists messages
/// with a text input to send new ones. Header actions and composer are
/// gated by [chatType] — DMs never show group-only widgets like the
/// "Members" button.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.me,
    required this.chatType,
    this.topicId,
    this.peer,
    this.canPost = true,
  });

  final String groupId;
  final String groupName;
  final AuthUser me;

  /// What kind of conversation this is. Drives every header / composer gate.
  final ChatType chatType;

  /// If set, the screen opens the conversation for this topic within a
  /// topics-mode group. Simple-mode groups leave this null.
  final String? topicId;

  /// The other participant in a DM. Used by the title-tap peer profile
  /// sheet. Ignored for [ChatType.group] / [ChatType.channel].
  final UserProfile? peer;

  /// For [ChatType.channel]: whether the current user is allowed to post.
  /// Non-admins get a muted composer. Always true for DM/group.
  final bool canPost;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ChatApi();
  final _mediaApi = MediaApi();
  final _groupsApi = GroupsApi();
  final _uploader = MediaUploader();
  final _imagePicker = ImagePicker();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  Conversation? _conversation;
  // Stored newest-first (index 0 = newest). Paired with a reverse
  // ListView so the most-recent message is pinned to the bottom edge of
  // the screen on every (re)build — no manual jumpTo, no mid-list flash.
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  _UploadState? _upload;
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<void>? _connectedSub;
  StreamSubscription<String>? _membershipSub;

  // Live member count surfaced under the AppBar title for groups /
  // channels. Null until the first GET /groups/{id} resolves; null
  // also for DMs (we never query the synthetic 2-person group).
  int? _memberCount;

  // Older-page lazy loading.
  bool _loadingMore = false;
  bool _hasMore = true;
  static const _pageLimit = 50;
  static const _loadMoreThresholdPx = 200;

  // "↓ N new messages" pill — number of message.new frames received
  // while the user is NOT at the bottom of the chat.
  int _unseenCount = 0;
  bool _atBottom = true;
  static const _atBottomThresholdPx = 100;

  /// When non-null the composer is in "edit" mode — sending will PATCH
  /// this message instead of POSTing a new one.
  Message? _editing;

  /// Last message id we reported to `/read`. Prevents spamming on every
  /// incoming WS frame.
  String? _lastReadMessageId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
      // Server returns newest-first; we keep that order so a reverse
      // ListView renders the freshest message at the bottom edge with
      // zero scroll math. No `.reversed` here — that produced the
      // mid-list flash Shreyas reported (feedback 10).
      final msgs = await _api.listMessages(conv.id, limit: _pageLimit);
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _messages = msgs;
        _loading = false;
        _hasMore = msgs.length >= _pageLimit;
        _atBottom = true;
        _unseenCount = 0;
      });

      // Subscribe for real-time message.new frames for this conversation.
      ChatService.instance.subscribe(conv.id);
      _messageSub?.cancel();
      _messageSub = ChatService.instance.messages(conv.id).listen(_onWsMessage);

      // After a WS reconnect (token rotation, network blip), re-pull the
      // history so any messages that landed on the server while we were
      // disconnected show up. Dedupe by id keeps it idempotent.
      _connectedSub?.cancel();
      _connectedSub = ChatService.instance.connected.listen((_) {
        _resyncMessages();
      });

      // Keep the AppBar member count in sync with cross-device adds /
      // removes. DMs don't subscribe — their 2-person backing group
      // never matters to the user.
      if (widget.chatType != ChatType.dm) {
        _membershipSub?.cancel();
        _membershipSub =
            ChatService.instance.groupMembershipChanged.listen((gid) {
          if (gid == widget.groupId) _loadMemberCount();
        });
        _loadMemberCount();
      }

      _markReadUpToLatest();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message}';
        _loading = false;
      });
    }
  }

  /// Pull the latest member count from `GET /groups/{id}` and stash
  /// it on local state. Used for the AppBar subtitle on group / channel
  /// chats. Silent on failure — the previous count stays.
  Future<void> _loadMemberCount() async {
    try {
      final group = await _groupsApi.getGroup(widget.groupId);
      if (!mounted) return;
      setState(() => _memberCount = group.memberCount);
    } on ApiError {
      // Best-effort; subtitle just stays at whatever it last showed.
    }
  }

  /// Re-fetch the latest page of messages and merge by id. Called after
  /// every WS reconnect so the chat catches up on anything sent during
  /// the gap. Until the backend exposes a `since=<id>` filter, the cheapest
  /// correct thing to do is re-pull the latest page and dedupe.
  Future<void> _resyncMessages() async {
    final conv = _conversation;
    if (conv == null || !mounted) return;
    try {
      final fresh = await _api.listMessages(conv.id, limit: _pageLimit);
      if (!mounted) return;
      final byId = <String, Message>{
        for (final m in _messages) m.id: m,
      };
      for (final m in fresh) {
        byId[m.id] = m;
      }
      // Keep newest-first to match the reverse ListView's expectation.
      final merged = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _messages = merged);
      _markReadUpToLatest();
    } on ApiError {
      // Best-effort; the next user-driven action will surface real errors.
    }
  }

  /// Merge a live message pushed over the WS. Dedupe by id so the
  /// sender's own REST-posted message doesn't render twice (server
  /// echoes it back). New messages always go to index 0 (newest) of the
  /// reverse-ordered list. Auto-scroll only if the user is already at
  /// the bottom — otherwise bump the unseen-pill counter so a reader
  /// scrolled into history isn't yanked away from what they're reading.
  void _onWsMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    final Message msg;
    try {
      msg = Message.fromJson(payload);
    } catch (_) {
      return;
    }
    if (_messages.any((m) => m.id == msg.id)) return;
    final mine = msg.senderId == widget.me.id;
    setState(() {
      _messages = [msg, ..._messages];
      if (!_atBottom && !mine) _unseenCount += 1;
    });
    if (_atBottom || mine) {
      _scrollToBottom();
      _markReadUpToLatest();
    }
  }

  /// Fire-and-forget POST /conversations/{id}/read. Dedupes by the
  /// newest message id so opening a chat with N messages doesn't thrash
  /// the endpoint.
  void _markReadUpToLatest() {
    final conv = _conversation;
    if (conv == null || _messages.isEmpty) return;
    final latest = _messages.first;
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
        // Send via REST, then prepend the server-returned row immediately
        // (index 0 = newest in the reverse-ordered list). Some backends
        // (AWS prod today) don't fan the REST send out over WebSocket,
        // so we can't wait for a WS echo — it may never arrive. If a WS
        // echo does come later, [_onWsMessage] dedupes by id.
        final created = await _api.sendMessage(
          conversationId: conv.id,
          content: text,
        );
        if (!mounted) return;
        setState(() {
          if (!_messages.any((m) => m.id == created.id)) {
            _messages = [created, ..._messages];
          }
          _inputController.clear();
          _sending = false;
          _unseenCount = 0;
        });
        _scrollToBottom();
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

  /// Scroll to the bottom (newest message). In reverse-list coordinates
  /// the bottom is `pixels == 0`. No-op if the controller isn't attached
  /// yet (covers the very first frame after _bootstrap).
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Scroll-position listener — drives lazy load + the "↓ N new"
  /// pill. Reverse list, so:
  ///   pixels ≈ 0           → user is parked at the newest message
  ///   pixels → maxScrollExtent → user is reading the oldest visible
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    final wasAtBottom = _atBottom;
    final atBottomNow = pos.pixels < _atBottomThresholdPx;
    if (wasAtBottom != atBottomNow) {
      setState(() {
        _atBottom = atBottomNow;
        if (atBottomNow) _unseenCount = 0;
      });
      if (atBottomNow) _markReadUpToLatest();
    }

    if (pos.pixels > pos.maxScrollExtent - _loadMoreThresholdPx) {
      _loadMore();
    }
  }

  /// Fetch the next-older page and append to the tail of [_messages]
  /// (oldest end of the reverse list). Idempotent against concurrent
  /// triggers via [_loadingMore]. Stops paging once the server returns
  /// fewer rows than the page limit.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final conv = _conversation;
    if (conv == null || _messages.isEmpty) return;
    _loadingMore = true;
    try {
      final oldestId = _messages.last.id;
      final older = await _api.listMessages(
        conv.id,
        limit: _pageLimit,
        beforeId: oldestId,
      );
      if (!mounted) return;
      if (older.isEmpty) {
        setState(() => _hasMore = false);
        return;
      }
      // Server returns newest-first within the page; the entire page is
      // older than everything we already have, so a plain concat keeps
      // global newest-first ordering. Dedupe just in case.
      final seen = _messages.map((m) => m.id).toSet();
      final fresh = older.where((m) => !seen.contains(m.id)).toList();
      setState(() {
        _messages = [..._messages, ...fresh];
        if (fresh.length < _pageLimit) _hasMore = false;
      });
    } on ApiError {
      // Silent — next scroll-to-top will retry.
    } finally {
      _loadingMore = false;
    }
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
        onPickFromVault: () {
          Navigator.pop(context);
          _pickFromVault();
        },
      ),
    );
  }

  /// Push the vault picker, then re-share the chosen items by sending
  /// one chat message per selected media. The bytes already exist in
  /// S3 — no new upload — so this is just a chat send. Server-side
  /// privacy guard rejects the share if any media_id isn't owned by
  /// the sender (chat_routes.send_message).
  Future<void> _pickFromVault() async {
    final conv = _conversation;
    if (conv == null) return;
    final picked = await Navigator.of(context).push<List<MediaFile>>(
      MaterialPageRoute(
        builder: (_) => const MediaVaultPickerScreen(),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final caption = _inputController.text.trim();
    setState(() => _sending = true);
    try {
      // Use the first selection's caption; subsequent items share the
      // bubble layout but send without a caption to avoid double-text.
      var first = true;
      for (final m in picked) {
        final encoded = ChatAttachment.encode(
          ChatAttachment(
            mediaId: m.id,
            fileName: m.fileName,
            mimeType: m.mimeType,
            fileSize: m.fileSize,
          ),
          caption: first ? caption : null,
        );
        final created = await _api.sendMessage(
          conversationId: conv.id,
          content: encoded,
          mediaIds: [m.id],
        );
        if (!mounted) return;
        setState(() {
          if (!_messages.any((x) => x.id == created.id)) {
            _messages = [created, ..._messages];
          }
        });
        first = false;
      }
      if (!mounted) return;
      setState(() {
        _inputController.clear();
        _sending = false;
        _unseenCount = 0;
      });
      _scrollToBottom();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '${e.code}: ${e.message}';
      });
    }
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
      final created = await _api.sendMessage(
        conversationId: conv.id,
        content: encoded,
        mediaIds: [media.id],
      );
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == created.id)) {
          _messages = [created, ..._messages];
        }
        _inputController.clear();
        _upload = null;
        _unseenCount = 0;
      });
      _scrollToBottom();
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
    _connectedSub?.cancel();
    _membershipSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFor(widget.groupName);
    final isDm = widget.chatType == ChatType.dm;
    final isChannel = widget.chatType == ChatType.channel;
    final composerEnabled = !_sending &&
        _conversation != null &&
        _upload == null &&
        (!isChannel || widget.canPost);
    String? subtitle;
    if (!isDm && _memberCount != null) {
      final n = _memberCount!;
      subtitle = isChannel
          ? '$n ${n == 1 ? 'subscriber' : 'subscribers'}'
          : '$n ${n == 1 ? 'member' : 'members'}';
    }
    return Scaffold(
      backgroundColor: kCream,
      appBar: CreamAppBar(
        title: widget.groupName,
        subtitle: subtitle,
        // DMs: tapping the title opens the peer's profile sheet, not the
        // current user's own profile. Groups/channels keep the default tap.
        onTitleTap: isDm ? _showPeerProfile : null,
        leadingAvatar: CreamAvatar(
          seed: widget.groupName,
          initials: initials,
          size: 36,
        ),
        actions: [
          // Members icon is group-only. DMs back a synthetic 2-person group
          // server-side, but exposing that to the user is wrong UX.
          if (!isDm)
            IconButton(
              icon: const Icon(Icons.people_alt_outlined, color: kAccentDeep),
              tooltip: isChannel ? 'Subscribers' : 'Members',
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
                        : Stack(
                            children: [
                              // reverse: true → index 0 renders at the
                              // bottom edge, so a fresh chat naturally
                              // pins to the latest message with no
                              // jumpTo. Pagination loads index N+ at the
                              // tail (older), so growing the list
                              // doesn't shift the currently-visible
                              // newest content.
                              ListView.builder(
                                controller: _scrollController,
                                reverse: true,
                                padding: const EdgeInsets.fromLTRB(
                                    12, 12, 12, 16),
                                itemCount: _messages.length,
                                itemBuilder: (ctx, i) => _MessageBubble(
                                  msg: _messages[i],
                                  isMine: _messages[i].senderId == widget.me.id,
                                  mediaApi: _mediaApi,
                                  onLongPress: _showMessageActions,
                                ),
                              ),
                              if (!_atBottom && _unseenCount > 0)
                                Positioned(
                                  right: 16,
                                  bottom: 16,
                                  child: _UnseenPill(
                                    count: _unseenCount,
                                    onTap: () {
                                      setState(() => _unseenCount = 0);
                                      _scrollToBottom();
                                    },
                                  ),
                                ),
                            ],
                          ),
              ),
              if (isChannel && !widget.canPost)
                const _MutedComposer(text: 'Only admins can post in this channel.')
              else
                _Composer(
                  controller: _inputController,
                  enabled: composerEnabled,
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

  /// DM title-tap → show the other user's read-only profile in a bottom
  /// sheet. Falls back to a "no info" message if the caller didn't pass
  /// [ChatScreen.peer] (e.g. opened from a deep-link before the user list
  /// has loaded).
  void _showPeerProfile() {
    final peer = widget.peer;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCreamCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _PeerProfileSheet(peer: peer, fallbackName: widget.groupName),
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
  late final MediaUrlResolver _resolver = MediaUrlResolver(
    api: widget.mediaApi,
    mediaId: widget.attachment.mediaId,
  );
  String? _url;
  bool _loading = false;
  String? _error;
  bool _terminallyMissing = false;

  // Bumped on every successful refetch so Image.network rebuilds
  // against the new URL without an explicit setState dance.
  int _imageGeneration = 0;
  // Tracks whether the in-flight Image.network failed once already so
  // we know to flip to the "Media unavailable" state instead of looping.
  bool _hasRetriedThisLoad = false;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.isImage) {
      _resolveUrl();
    }
  }

  Future<void> _resolveUrl({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await _resolver.resolve(forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _url = url;
        _imageGeneration += 1;
        _hasRetriedThisLoad = false;
        _loading = false;
      });
    } on MediaUnavailableException {
      if (!mounted) return;
      setState(() {
        _terminallyMissing = true;
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

  /// Called by the Image.network errorBuilder — silently refetches the
  /// presigned URL once and rebuilds. If even the refetch errors we
  /// fall back to [_buildFileRow] so the user can at least tap to
  /// download.
  void _onImageNetworkFailed() {
    if (_hasRetriedThisLoad) return;
    _hasRetriedThisLoad = true;
    // Fire-and-forget; the next `_resolveUrl` setState will rebuild.
    _resolveUrl(force: true);
  }

  Future<void> _openExternally() async {
    try {
      final url = await _resolver.resolve();
      if (!mounted) return;
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _error = 'Could not open download URL.');
      }
    } on MediaUnavailableException {
      if (!mounted) return;
      setState(() => _terminallyMissing = true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    if (_terminallyMissing) {
      return _MediaUnavailable(onRetry: () {
        setState(() => _terminallyMissing = false);
        if (att.isImage) _resolveUrl(force: true);
      });
    }
    // MIME-driven dispatch — never trust the filename extension. Backend
    // sets Content-Disposition: inline for image/video/audio (see
    // src/modules/media/services/media_service.py:get_download_url) so
    // the presigned URL is safe to feed straight to the inline players.
    if (att.isImage) return _buildImage();
    if (att.isVideo) {
      return _VideoBubble(
        attachment: att,
        mediaApi: widget.mediaApi,
        isMine: widget.isMine,
      );
    }
    if (att.isAudio) {
      return _AudioBubble(
        attachment: att,
        mediaApi: widget.mediaApi,
        isMine: widget.isMine,
      );
    }
    // PDFs + every other document type: download + open in the OS
    // viewer. Per Shreyas this is intentional and must not change.
    return _buildFileRow();
  }

  Widget _buildImage() {
    if (_loading || _url == null) {
      return const SizedBox(
        width: 220,
        height: 140,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: kAccentDeep),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: _openExternally,
        child: Image.network(
          _url!,
          // Force a rebuild of the underlying NetworkImage when we
          // refetch — without a key, Flutter can otherwise cache the
          // failed image and never retry the new URL.
          key: ValueKey('${widget.attachment.mediaId}#$_imageGeneration'),
          width: 240,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) {
            // Schedule the refetch off this build phase. If we've
            // already retried once this load, fall through to the
            // tap-to-download row instead of looping.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _onImageNetworkFailed();
            });
            return _hasRetriedThisLoad
                ? _buildFileRow()
                : const SizedBox(
                    width: 220,
                    height: 140,
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kAccentDeep),
                    ),
                  );
          },
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
    required this.onPickFromVault,
  });
  final ValueChanged<ImageSource> onPickImage;
  final ValueChanged<ImageSource> onPickVideo;
  final VoidCallback onPickFile;
  final VoidCallback onPickFromVault;

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
                    _AttachDockItem(
                      icon: Icons.cloud_outlined,
                      label: 'Vault',
                      onTap: onPickFromVault,
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

/// Replaces the message composer when the user is not allowed to post —
/// currently only used for [ChatType.channel] when [ChatScreen.canPost]
/// is false.
class _MutedComposer extends StatelessWidget {
  const _MutedComposer({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: kCream,
        border: Border(top: BorderSide(color: kHairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 16, color: kInkSubtle),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: kInkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only peer info sheet shown when the user taps the title bar of a
/// DM. Mirrors the cream profile look but never exposes editing affordances
/// or "current user" actions — this is the *other* person.
class _PeerProfileSheet extends StatelessWidget {
  const _PeerProfileSheet({required this.peer, required this.fallbackName});
  final UserProfile? peer;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final name = peer?.fullName ?? peer?.email ?? fallbackName;
    final email = peer?.email;
    final bio = peer?.bio;
    final isOnline = peer?.isOnline ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 6, bottom: 18),
                decoration: BoxDecoration(
                  color: kHairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Center(
              child: CreamAvatar(
                seed: name,
                initials: peer?.initials ?? _seedInitials(name),
                size: 76,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              name,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: kInkDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isOnline ? 'Online now' : 'Direct message',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isOnline ? kOnlineGreen : kInkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (email != null && email.isNotEmpty) ...[
              const SizedBox(height: 18),
              _PeerInfoRow(icon: Icons.email_outlined, label: 'Email', value: email),
            ],
            if (bio != null && bio.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PeerInfoRow(icon: Icons.info_outline, label: 'Bio', value: bio),
            ],
            if (peer == null) ...[
              const SizedBox(height: 18),
              Text(
                'Profile info is not available right now.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: kInkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _seedInitials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0].substring(0, 1).toUpperCase();
  }
}

class _PeerInfoRow extends StatelessWidget {
  const _PeerInfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kCreamField,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kHairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kAccentDeep, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: kInkSubtle,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: kInkDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "↓ N new messages" pill shown over the message list when an inbound
/// message arrives while the user is scrolled away from the bottom.
/// Tapping animates the list to the newest message and resets the
/// counter — keeps the reader's place intact unless they ask to leave.
class _UnseenPill extends StatelessWidget {
  const _UnseenPill({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 new message' : '$count new messages';
    return Material(
      color: kAccentDeep,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline video bubble. Until the user taps Play we render a poster-shaped
/// placeholder with a play button — cheap, no network. On tap we fetch the
/// presigned URL, hand it to a `VideoPlayerController`, and let `chewie`
/// drive controls. The player stays inline (Telegram-style) — no extra
/// route, no `url_launcher`.
class _VideoBubble extends StatefulWidget {
  const _VideoBubble({
    required this.attachment,
    required this.mediaApi,
    required this.isMine,
  });
  final ChatAttachment attachment;
  final MediaApi mediaApi;
  final bool isMine;

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  late final MediaUrlResolver _resolver = MediaUrlResolver(
    api: widget.mediaApi,
    mediaId: widget.attachment.mediaId,
  );
  VideoPlayerController? _video;
  ChewieController? _chewie;
  bool _loading = false;
  String? _error;
  bool _terminallyMissing = false;

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || _chewie != null) return;
    setState(() {
      _loading = true;
      _error = null;
      _terminallyMissing = false;
    });
    // Try once with the cached/fresh URL; on failure assume the URL
    // expired and force a refetch before giving up. Mirrors the audit
    // 5.5/5.8 mitigation — the user shouldn't ever see a 403.
    if (await _attemptLoad(forceRefresh: false)) return;
    if (!mounted) return;
    if (_terminallyMissing) return;
    if (await _attemptLoad(forceRefresh: true)) return;
    if (!mounted) return;
    setState(() {
      _error = 'Could not load video.';
      _loading = false;
    });
  }

  Future<bool> _attemptLoad({required bool forceRefresh}) async {
    try {
      final url = await _resolver.resolve(forceRefresh: forceRefresh);
      final video = VideoPlayerController.networkUrl(Uri.parse(url));
      await video.initialize();
      if (!mounted) {
        await video.dispose();
        return true;
      }
      final chewie = ChewieController(
        videoPlayerController: video,
        autoPlay: true,
        looping: false,
        aspectRatio: video.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: kAccent,
          handleColor: kAccent,
          bufferedColor: kHairline,
          backgroundColor: Colors.black54,
        ),
        placeholder: const ColoredBox(color: Colors.black),
      );
      setState(() {
        _video = video;
        _chewie = chewie;
        _loading = false;
      });
      return true;
    } on MediaUnavailableException {
      if (!mounted) return true;
      setState(() {
        _terminallyMissing = true;
        _loading = false;
      });
      return true;
    } on ApiError {
      // Caller decides whether to retry with a forced refetch.
      return false;
    } catch (_) {
      // VideoPlayer initialise / network error — likely a 403 on the
      // signed URL. Swallow and let the caller try again with a fresh
      // URL.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_terminallyMissing) {
      return _MediaUnavailable(onRetry: _load);
    }
    if (_chewie != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: _video!.value.aspectRatio,
          child: Chewie(controller: _chewie!),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: _loading ? null : _load,
        child: Container(
          width: 240,
          height: 140,
          color: Colors.black.withValues(alpha: 0.78),
          alignment: Alignment.center,
          child: _loading
              ? const CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.4)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kAccent.withValues(alpha: 0.92),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _error!,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFFFFB3B3),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Inline audio bubble: play/pause button + a thin scrubber row. Uses
/// `just_audio` so we don't have to manage AVAudioSession ourselves.
/// Lazily initialised — the URL fetch only fires on first tap.
class _AudioBubble extends StatefulWidget {
  const _AudioBubble({
    required this.attachment,
    required this.mediaApi,
    required this.isMine,
  });
  final ChatAttachment attachment;
  final MediaApi mediaApi;
  final bool isMine;

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  late final MediaUrlResolver _resolver = MediaUrlResolver(
    api: widget.mediaApi,
    mediaId: widget.attachment.mediaId,
  );
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  bool _terminallyMissing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _terminallyMissing = false;
    });
    if (await _attemptLoad(forceRefresh: false)) return;
    if (!mounted) return;
    if (_terminallyMissing) return;
    if (await _attemptLoad(forceRefresh: true)) return;
    if (!mounted) return;
    setState(() {
      _error = 'Could not load audio.';
      _loading = false;
    });
  }

  Future<bool> _attemptLoad({required bool forceRefresh}) async {
    try {
      final url = await _resolver.resolve(forceRefresh: forceRefresh);
      await _player.setUrl(url);
      if (!mounted) return true;
      setState(() {
        _loaded = true;
        _loading = false;
      });
      return true;
    } on MediaUnavailableException {
      if (!mounted) return true;
      setState(() {
        _terminallyMissing = true;
        _loading = false;
      });
      return true;
    } on ApiError {
      return false;
    } catch (_) {
      // setUrl on an expired presigned link surfaces as a generic
      // PlatformException — let the caller retry with forceRefresh.
      return false;
    }
  }

  Future<void> _toggle() async {
    if (!_loaded) {
      await _ensureLoaded();
      if (!_loaded) return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      // If we ran to the end, restart from 0 instead of staying paused.
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_terminallyMissing) {
      return _MediaUnavailable(onRetry: _ensureLoaded);
    }
    final isMine = widget.isMine;
    final fg = isMine ? Colors.white : kInkDark;
    final fgMuted = isMine ? Colors.white.withValues(alpha: 0.85) : kInkMuted;
    final chipBg = isMine
        ? Colors.white.withValues(alpha: 0.18)
        : kAccent.withValues(alpha: 0.12);
    final iconColor = isMine ? Colors.white : kAccentDeep;
    final trackColor = isMine
        ? Colors.white.withValues(alpha: 0.35)
        : kHairline;
    final fillColor = isMine ? Colors.white : kAccent;

    return Container(
      width: 240,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withValues(alpha: 0.12) : kCreamField,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMine ? Colors.white.withValues(alpha: 0.25) : kHairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: chipBg,
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: iconColor,
                          ),
                        )
                      : Icon(
                          _player.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: iconColor,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (_, posSnap) {
              final pos = posSnap.data ?? Duration.zero;
              final dur = _player.duration ?? Duration.zero;
              final fraction = (dur.inMilliseconds == 0)
                  ? 0.0
                  : (pos.inMilliseconds / dur.inMilliseconds)
                      .clamp(0.0, 1.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 3,
                      backgroundColor: trackColor,
                      valueColor: AlwaysStoppedAnimation<Color>(fillColor),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(pos),
                        style: GoogleFonts.inter(fontSize: 10, color: fgMuted),
                      ),
                      Text(
                        _loaded && dur > Duration.zero
                            ? _fmt(dur)
                            : (widget.attachment.fileSize > 0
                                ? _formatBytesShort(widget.attachment.fileSize)
                                : '--:--'),
                        style: GoogleFonts.inter(fontSize: 10, color: fgMuted),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: GoogleFonts.inter(fontSize: 10, color: kDangerInk),
              ),
            ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _formatBytesShort(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Terminal placeholder for a chat bubble whose media is gone for good
/// (404 from `/media/{id}/download` — the row was deleted server-side
/// or the media was rotated past recoverable). Kept small enough to sit
/// inside a regular text bubble, with a Retry tap so transient routing
/// failures don't trap the user.
class _MediaUnavailable extends StatelessWidget {
  const _MediaUnavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kCreamField,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kHairline),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kDangerBg.withValues(alpha: 0.16),
            ),
            child: const Icon(Icons.broken_image_outlined,
                color: kDangerInk, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Media unavailable',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kInkDark,
                  ),
                ),
                Text(
                  'The file may have been deleted.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: kInkMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: kAccentDeep,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
