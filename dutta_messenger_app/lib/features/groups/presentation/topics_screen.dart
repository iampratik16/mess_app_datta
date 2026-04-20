import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
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
          backgroundColor: const Color(0xFFFF4757),
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
        backgroundColor: const Color(0xFF1E1B3A),
        title: Text('Delete "${t.name}"?',
            style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'All messages in this topic will be lost. This cannot be undone.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
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

    final snapshot = _topics;
    setState(() => _topics = _topics.where((x) => x.id != t.id).toList());
    try {
      await _api.deleteTopic(groupId: widget.group.id, topicId: t.id);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _topics = snapshot);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFF4757),
          content: Text('Delete failed: ${e.message}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.group.name,
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700, fontSize: 17)),
            Text(
              _loading ? 'Loading…' : '${_topics.length} topics',
              style:
                  GoogleFonts.inter(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF667EEA),
              onPressed: _createTopic,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('New topic',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
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
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: const Color(0xFFFF6B7A), fontSize: 13)),
        ),
      );
    }
    if (_topics.isEmpty) {
      return Center(
        child: Text('No topics yet',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _topics.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
    return Material(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Text(
                  topic.iconEmoji?.isNotEmpty == true
                      ? topic.iconEmoji!
                      : '#',
                  style: GoogleFonts.inter(
                    fontSize: topic.iconEmoji?.isNotEmpty == true ? 20 : 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(topic.name,
                              style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                        ),
                        if (topic.isDefault)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text('· default',
                                style: GoogleFonts.inter(
                                    fontSize: 11, color: Colors.white38)),
                          ),
                      ],
                    ),
                    if (topic.description?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          topic.description!,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.white54),
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
                      color: Color(0xFFFF6B7A)),
                  tooltip: 'Delete topic',
                  onPressed: onDelete,
                )
              else
                const Icon(Icons.chevron_right, color: Colors.white38),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1B3A),
      title: Text('New topic',
          style: GoogleFonts.outfit(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              maxLength: 255,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'e.g. homework',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
            TextField(
              controller: _emojiCtrl,
              maxLength: 10,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Icon emoji (optional)',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: '📝',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              maxLength: 2000,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
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
          child: const Text('Create'),
        ),
      ],
    );
  }
}
