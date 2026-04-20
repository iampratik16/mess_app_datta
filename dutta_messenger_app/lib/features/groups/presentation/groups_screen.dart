import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/errors/api_error.dart';
import '../../auth/domain/auth_models.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../dm/data/dm_repository.dart';
import '../data/groups_api.dart';
import '../domain/group_models.dart';
import 'topics_screen.dart';

/// Lists groups for the current institution. Tap a row to open its chat.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.me});
  final AuthUser me;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _api = GroupsApi();
  bool _loading = true;
  String? _error;
  List<Group> _groups = [];

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
      final groups = await _api.listGroups();
      if (!mounted) return;
      setState(() {
        // Hide DM convention groups — they live in DmListScreen.
        _groups = groups.where((g) => !DmRepository.isDmGroup(g)).toList();
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

  Future<void> _createGroupDialog() async {
    final result = await showDialog<_NewGroupResult>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (result == null) return;
    try {
      final group = await _api.createGroup(
        name: result.name,
        description: result.description,
        mode: result.mode,
      );
      if (!mounted) return;
      setState(() => _groups = [group, ..._groups]);
      _openGroup(group);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = '${e.code}: ${e.message}');
    }
  }

  /// Route the tap based on mode — spec §11: simple → straight to chat,
  /// topics → topic list first.
  void _openGroup(Group g) {
    if (g.mode == 'topics') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TopicsScreen(group: g, me: widget.me),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            groupId: g.id,
            groupName: g.name,
            me: widget.me,
          ),
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
        title: Text('Groups',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF667EEA),
        onPressed: _createGroupDialog,
        child: const Icon(Icons.add, color: Colors.white),
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
          child: RefreshIndicator(
            color: const Color(0xFF667EEA),
            onRefresh: _load,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white70))
                : _error != null
                    ? _ErrorState(text: _error!, onRetry: _load)
                    : _groups.isEmpty
                        ? const _EmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                            itemCount: _groups.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (ctx, i) => _GroupRow(
                              group: _groups[i],
                              onTap: () => _openGroup(_groups[i]),
                            ),
                          ),
          ),
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.onTap});
  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = group.name.isEmpty ? '?' : group.name[0].toUpperCase();
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
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                ),
                child: Text(
                  initial,
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.memberCount} members · ${group.mode}',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.groups_outlined,
              size: 56, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'No groups yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to create one',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
          ),
        ],
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFFF6B7A), size: 48),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: const Color(0xFFFF6B7A), fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

class _NewGroupResult {
  const _NewGroupResult({
    required this.name,
    required this.mode,
    this.description,
  });
  final String name;
  final String mode;
  final String? description;
}

/// Create-group modal with name + description + mode picker, per
/// spec §1. Mode cannot be changed after creation, so this is the
/// only place the user picks it.
class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _mode = 'simple';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1B3A),
      title: Text('New group',
          style: GoogleFonts.outfit(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'e.g. Staff Room',
                hintStyle: TextStyle(color: Colors.white30),
              ),
              maxLength: 255,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: Colors.white70),
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
            const SizedBox(height: 12),
            Text('Type',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70)),
            const SizedBox(height: 6),
            _ModeTile(
              value: 'simple',
              groupValue: _mode,
              title: 'Simple',
              subtitle: 'One chat, one timeline (like WhatsApp)',
              onTap: () => setState(() => _mode = 'simple'),
            ),
            _ModeTile(
              value: 'topics',
              groupValue: _mode,
              title: 'Topics',
              subtitle: 'Channels inside the group (like Slack)',
              onTap: () => setState(() => _mode = 'topics'),
            ),
            const SizedBox(height: 4),
            Text(
              'You cannot change this later.',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _NewGroupResult(
                name: name,
                mode: _mode,
                description: _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFF667EEA)
                : Colors.white.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
          color: selected
              ? const Color(0xFF667EEA).withValues(alpha: 0.12)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? const Color(0xFF8A9CF5) : Colors.white38,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.white54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
