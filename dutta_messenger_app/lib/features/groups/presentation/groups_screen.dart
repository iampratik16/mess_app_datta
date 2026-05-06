import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/errors/api_error.dart';
import '../../../services/chat_service.dart';
import '../../auth/domain/auth_models.dart';
import '../../chat/domain/chat_type.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../dm/data/dm_repository.dart';
import '../data/groups_api.dart';
import '../domain/group_models.dart';
import '../../notifications/presentation/notifications_bell.dart';
import 'topics_screen.dart';
import '../../../core/ui/app_theme.dart';

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
  StreamSubscription<String>? _membershipSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Live membership updates: when any group the user belongs to gains
    // or loses a member, refetch the list so the row count reflects
    // truth without a manual pull-to-refresh.
    _membershipSub =
        ChatService.instance.groupMembershipChanged.listen((groupId) {
      if (!mounted) return;
      if (_groups.any((g) => g.id == groupId)) _load();
    });
  }

  @override
  void dispose() {
    _membershipSub?.cancel();
    super.dispose();
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
            chatType: ChatType.group,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: CreamAppBar(
        title: 'Groups',
        subtitle: (!_loading && _error == null)
            ? '${_groups.length} ${_groups.length == 1 ? 'group' : 'groups'}'
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kAccentDeep),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
          const NotificationsBell(),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: FloatingActionButton(
          backgroundColor: kAccent,
          foregroundColor: Colors.white,
          elevation: 2,
          onPressed: _createGroupDialog,
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kCream, kCreamDeep],
          ),
        ),
        child: SafeArea(
          top: false,
          child: RefreshIndicator(
            color: kAccentDeep,
            backgroundColor: kCream,
            onRefresh: _load,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kAccentDeep))
                : _error != null
                    ? _ErrorState(text: _error!, onRetry: _load)
                    : _groups.isEmpty
                        ? const _EmptyState()
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(0, 4, 0, 130),
                            itemCount: _groups.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              thickness: 1,
                              color: kHairline,
                              indent: 84,
                              endIndent: 16,
                            ),
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
    final avatarColor = avatarColorFor(group.name);
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
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatarColor,
                ),
                child: Text(
                  initial,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kInkDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${group.memberCount} ${group.memberCount == 1 ? 'member' : 'members'} · ${group.mode}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: kInkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kInkSubtle),
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
          const SizedBox(height: 140),
          const Icon(Icons.groups_outlined, size: 56, color: kInkSubtle),
          const SizedBox(height: 14),
          Text(
            'No groups yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: kInkDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap + to create one',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: kInkMuted, fontSize: 14),
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
                  color: Color(0xFFB94A33), size: 48),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: const Color(0xFFB94A33), fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
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

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 13),
      floatingLabelStyle:
          GoogleFonts.inter(color: kAccentDeep, fontSize: 13),
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: kInkSubtle.withValues(alpha: 0.6)),
      filled: true,
      fillColor: const Color(0xFFFFFBF4),
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
      backgroundColor: const Color(0xFFFBF3E7),
      surfaceTintColor: const Color(0xFFFBF3E7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kHairline),
      ),
      title: Text(
        'New group',
        style: GoogleFonts.playfairDisplay(
          color: kInkDark,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Name', hint: 'e.g. Staff Room'),
              maxLength: 255,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              maxLines: 2,
              maxLength: 2000,
              decoration: _fieldDecoration('Description (optional)'),
            ),
            const SizedBox(height: 12),
            Text(
              'Type',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kInkMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 6),
            Text(
              'You cannot change this later.',
              style: GoogleFonts.inter(fontSize: 11, color: kInkSubtle),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: kInkMuted),
          child: Text('Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
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
              _NewGroupResult(
                name: name,
                mode: _mode,
                description: _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
              ),
            );
          },
          child: Text('Create',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? kAccent : kHairline,
            width: selected ? 1.5 : 1,
          ),
          color: selected ? kAccent.withValues(alpha: 0.08) : null,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? kAccentDeep : kInkSubtle,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kInkDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: kInkMuted,
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
}
