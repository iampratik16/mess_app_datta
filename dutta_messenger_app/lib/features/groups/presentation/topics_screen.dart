import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../../auth/domain/auth_models.dart';
import '../../chat/presentation/chat_screen.dart';
import '../data/groups_api.dart';
import '../domain/group_models.dart';
import 'group_members_screen.dart';

/// Topic sidebar for topics-mode groups (spec §9–§11). Lists topics,
/// opens a chat per topic, and lets admins create / delete topics.
class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key, required this.group, required this.me});

  final Group group;
  final AuthUser me;

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  final _api = GroupsApi();
  bool _loading = true;
  String? _error;
  List<Topic> _topics = [];
  String? _myRole; // discovered from the members list; null = unknown
  int? _memberCount; // best-effort from members list

  bool get _canManage => _myRole == 'owner' || _myRole == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topicsFuture = _api.listTopics(widget.group.id);
      final membersFuture = _api.listMembers(widget.group.id);
      final topics = await topicsFuture;
      final members = await membersFuture;
      if (!mounted) return;
      String? role;
      for (final m in members) {
        if (m.userId == widget.me.id) {
          role = m.role;
          break;
        }
      }
      setState(() {
        _topics = topics;
        _myRole = role;
        _memberCount = members.length;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message}';
        _loading = false;
      });
    }
  }

  void _openTopic(Topic t) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          groupId: widget.group.id,
          groupName: '${widget.group.name} · ${t.name}',
          me: widget.me,
          topicId: t.id,
        ),
      ),
    );
  }

  Future<void> _createTopic() async {
    final result = await showDialog<_NewTopicResult>(
      context: context,
      builder: (_) => const _CreateTopicDialog(),
    );
    if (result == null) return;
    try {
      final topic = await _api.createTopic(
        groupId: widget.group.id,
        name: result.name,
        description: result.description,
        iconEmoji: result.iconEmoji,
      );
      if (!mounted) return;
      setState(() => _topics = [..._topics, topic]);
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kDangerInk,
          content: Text('Create failed: ${e.message}'),
        ),
      );
    }
  }

  Future<void> _deleteTopic(Topic t) async {
    if (t.isDefault) return;
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
          'Delete "${t.name}"?',
          style: GoogleFonts.playfairDisplay(
            color: kInkDark,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'All messages in this topic will be lost. This cannot be undone.',
          style: GoogleFonts.inter(color: kInkMuted, fontSize: 13),
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

    final snapshot = _topics;
    setState(() => _topics = _topics.where((x) => x.id != t.id).toList());
    try {
      await _api.deleteTopic(groupId: widget.group.id, topicId: t.id);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _topics = snapshot);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kDangerInk,
          content: Text('Delete failed: ${e.message}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: CreamAppBar(
        title: widget.group.name,
        subtitle: _subtitle(),
        leadingAvatar: CreamAvatar(
          seed: widget.group.name,
          initials: widget.group.name.isEmpty
              ? '?'
              : widget.group.name.substring(0, 1).toUpperCase(),
          size: 36,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined, color: kAccentDeep),
            tooltip: 'Members',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupMembersScreen(
                  groupId: widget.group.id,
                  groupName: widget.group.name,
                  me: widget.me,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: kAccentDeep),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              elevation: 2,
              onPressed: _createTopic,
              icon: const Icon(Icons.add),
              label: Text(
                'New topic',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  String _subtitle() {
    if (_loading) return 'Loading…';
    final parts = <String>[];
    if (_memberCount != null) {
      parts.add(
          '${_memberCount!} ${_memberCount == 1 ? 'member' : 'members'}');
    }
    parts.add('${_topics.length} ${_topics.length == 1 ? 'topic' : 'topics'}');
    return parts.join(' · ');
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: kAccentDeep));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: kDangerInk, fontSize: 13)),
        ),
      );
    }
    if (_topics.isEmpty) {
      return Center(
        child: Text(
          'No topics yet',
          style: GoogleFonts.inter(color: kInkMuted, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
      itemCount: _topics.length,
      separatorBuilder: (_, _) => kListDivider,
      itemBuilder: (ctx, i) {
        final t = _topics[i];
        return _TopicRow(
          topic: t,
          onTap: () => _openTopic(t),
          onDelete:
              _canManage && !t.isDefault ? () => _deleteTopic(t) : null,
        );
      },
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.topic,
    required this.onTap,
    required this.onDelete,
  });
  final Topic topic;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final glyph = topic.iconEmoji?.isNotEmpty == true ? topic.iconEmoji! : '#';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: kAccent.withValues(alpha: 0.08),
        highlightColor: kAccent.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CreamSquareAvatar(glyph: glyph),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            topic.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: kInkDark,
                            ),
                          ),
                        ),
                        if (topic.isDefault) ...[
                          const SizedBox(width: 8),
                          const CreamTag(
                            label: 'default',
                            tone: CreamTagTone.muted,
                          ),
                        ],
                      ],
                    ),
                    if (topic.description?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          topic.description!,
                          style: GoogleFonts.inter(
                              fontSize: 13, color: kInkMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: kDangerInk),
                  tooltip: 'Delete topic',
                  onPressed: onDelete,
                )
              else
                const Icon(Icons.chevron_right, color: kInkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewTopicResult {
  const _NewTopicResult({
    required this.name,
    this.description,
    this.iconEmoji,
  });
  final String name;
  final String? description;
  final String? iconEmoji;
}

class _CreateTopicDialog extends StatefulWidget {
  const _CreateTopicDialog();

  @override
  State<_CreateTopicDialog> createState() => _CreateTopicDialogState();
}

class _CreateTopicDialogState extends State<_CreateTopicDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 13),
      floatingLabelStyle:
          GoogleFonts.inter(color: kAccentDeep, fontSize: 13),
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: kInkSubtle.withValues(alpha: 0.6)),
      filled: true,
      fillColor: kCreamField,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      counterStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 11),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kCreamCard,
      surfaceTintColor: kCreamCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kHairline),
      ),
      title: Text(
        'New topic',
        style: GoogleFonts.playfairDisplay(
          color: kInkDark,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              maxLength: 255,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Name', hint: 'e.g. homework'),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _emojiCtrl,
              maxLength: 10,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Icon emoji (optional)', hint: '📝'),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              maxLength: 2000,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Description (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: kInkMuted),
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _NewTopicResult(
                name: name,
                description: _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
                iconEmoji: _emojiCtrl.text.trim().isEmpty
                    ? null
                    : _emojiCtrl.text.trim(),
              ),
            );
          },
          child: Text(
            'Create',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
