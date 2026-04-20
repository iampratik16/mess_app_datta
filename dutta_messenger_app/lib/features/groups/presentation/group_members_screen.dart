import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../auth/domain/auth_models.dart';
import '../../users/data/users_api.dart';
import '../../users/domain/user_models.dart';
import '../data/groups_api.dart';
import '../domain/group_models.dart';

/// Lists members of a group. If the caller is owner or admin, exposes
/// add + remove UI per `docs/ui-contract/groups.md` §6–§8.
class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.me,
  });

  final String groupId;
  final String groupName;
  final AuthUser me;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  final _api = GroupsApi();
  final _usersApi = UsersApi();
  bool _loading = true;
  String? _error;
  List<GroupMember> _members = [];
  Group? _group;

  String? get _myRole {
    for (final m in _members) {
      if (m.userId == widget.me.id) return m.role;
    }
    return null;
  }

  bool get _canManage => _myRole == 'owner' || _myRole == 'admin';
  bool get _isOwner => _myRole == 'owner';

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
      final rawFuture = _api.listMembers(widget.groupId);
      final groupFuture = _api.getGroup(widget.groupId);
      final raw = await rawFuture;
      // Hydrate missing user profiles in parallel — /members returns only
      // {user_id, role, joined_at}; /users/{id} fills in name + email.
      final hydrated = await Future.wait(raw.map((m) async {
        if (m.user != null) return m;
        try {
          final u = await _usersApi.getById(m.userId);
          return GroupMember(
            userId: m.userId,
            role: m.role,
            user: u,
            joinedAt: m.joinedAt,
          );
        } on ApiError {
          return m;
        }
      }));
      final group = await groupFuture;
      if (!mounted) return;
      setState(() {
        _members = hydrated;
        _group = group;
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

  Future<void> _openAddMemberSheet() async {
    final existingIds = _members.map((m) => m.userId).toSet();
    final added = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1B3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddMemberSheet(excludedUserIds: existingIds),
    );
    if (added == null || !mounted) return;

    // Optimistic append + rollback on failure.
    setState(() {
      _members = [
        ..._members,
        GroupMember(userId: added.id, role: 'member', user: added),
      ];
    });
    try {
      await _api.addMember(groupId: widget.groupId, userId: added.id);
      // Server response is idempotent (reused:true if already a member).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Added ${added.fullName ?? added.email ?? "user"}'),
        ),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _members = _members.where((m) => m.userId != added.id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFF4757),
          content: Text('Add failed: ${e.message}'),
        ),
      );
    }
  }

  Future<void> _editGroup() async {
    final g = _group;
    if (g == null) return;
    final result = await showDialog<_EditGroupResult>(
      context: context,
      builder: (_) => _EditGroupDialog(initial: g),
    );
    if (result == null) return;
    try {
      final updated = await _api.updateGroup(
        groupId: widget.groupId,
        name: result.name,
        description: result.description,
      );
      if (!mounted) return;
      setState(() => _group = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Group updated'),
        ),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFF4757),
          content: Text('Update failed: ${e.message}'),
        ),
      );
    }
  }

  Future<void> _archiveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B3A),
        title: Text('Archive "${widget.groupName}"?',
            style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'The group disappears from everyone\'s list. Messages are kept '
          'and deep links still work. There is no unarchive yet.',
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
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.archiveGroup(widget.groupId);
      if (!mounted) return;
      // Pop back through members → chat → groups so the list refreshes.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFF4757),
          content: Text('Archive failed: ${e.message}'),
        ),
      );
    }
  }

  Future<void> _removeMember(GroupMember m) async {
    if (m.role == 'owner' || m.userId == widget.me.id) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B3A),
        title: Text('Remove ${m.user?.fullName ?? m.userId}?',
            style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'They will stop receiving new messages in this group. '
          'Past messages stay visible to them.',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final snapshot = _members;
    setState(() =>
        _members = _members.where((x) => x.userId != m.userId).toList());
    try {
      await _api.removeMember(groupId: widget.groupId, userId: m.userId);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _members = snapshot);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFF4757),
          content: Text('Remove failed: ${e.message}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sort: owner → admin → member, then by name.
    const roleOrder = {'owner': 0, 'admin': 1, 'member': 2};
    final sorted = [..._members]..sort((a, b) {
        final ra = roleOrder[a.role] ?? 99;
        final rb = roleOrder[b.role] ?? 99;
        if (ra != rb) return ra.compareTo(rb);
        final na = a.user?.fullName ?? '';
        final nb = b.user?.fullName ?? '';
        return na.compareTo(nb);
      });
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.groupName,
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700, fontSize: 17)),
            Text(
              _loading ? 'Loading…' : '${_members.length} members',
              style:
                  GoogleFonts.inter(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          if (_canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              color: const Color(0xFF1E1B3A),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _editGroup();
                  case 'archive':
                    _archiveGroup();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit, size: 18, color: Colors.white70),
                    SizedBox(width: 10),
                    Text('Edit group', style: TextStyle(color: Colors.white)),
                  ]),
                ),
                if (_isOwner)
                  const PopupMenuItem(
                    value: 'archive',
                    child: Row(children: [
                      Icon(Icons.archive_outlined,
                          size: 18, color: Color(0xFFFF6B7A)),
                      SizedBox(width: 10),
                      Text('Archive group',
                          style: TextStyle(color: Color(0xFFFF6B7A))),
                    ]),
                  ),
              ],
            ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF667EEA),
              onPressed: _openAddMemberSheet,
              icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
              label: const Text('Add member',
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
        child: SafeArea(child: _buildBody(sorted)),
      ),
    );
  }

  Widget _buildBody(List<GroupMember> rows) {
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
    if (rows.isEmpty) {
      return Center(
        child: Text('No members yet',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final m = rows[i];
        final canRemove =
            _canManage && m.role != 'owner' && m.userId != widget.me.id;
        return _MemberRow(
          member: m,
          isMe: m.userId == widget.me.id,
          onRemove: canRemove ? () => _removeMember(m) : null,
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.onRemove,
  });
  final GroupMember member;
  final bool isMe;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final user = member.user;
    final initials = user?.initials ?? '?';
    final name = user?.fullName ?? '(unknown)';
    final email = user?.email ?? member.userId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
            ),
            child: Text(
              initials,
              style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
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
                      child: Text(name,
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                    if (isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('(you)',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.white38)),
                      ),
                  ],
                ),
                Text(email,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _RoleChip(role: member.role),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: Color(0xFFFF6B7A)),
              tooltip: 'Remove from group',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;
  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      'owner' => const Color(0xFFF59E0B),
      'admin' => const Color(0xFF8A9CF5),
      _ => Colors.white54,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        role.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Debounced user-search sheet. Tapping a row returns the selected
/// [UserProfile] to the caller.
class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({required this.excludedUserIds});
  final Set<String> excludedUserIds;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _api = UsersApi();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<UserProfile> _results = [];
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _runSearch('a'); // prime with 1-char query — backend accepts it
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    _lastQuery = q;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await _api.search(q);
      if (!mounted || _lastQuery != q) return;
      setState(() {
        _results = all
            .where((u) => !widget.excludedUserIds.contains(u.id))
            .toList();
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1,
                      color: Color(0xFF8A9CF5)),
                  const SizedBox(width: 10),
                  Text('Add member',
                      style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchCtrl,
                onChanged: _onQueryChanged,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search name or email',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _results.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: GoogleFonts.inter(
                color: const Color(0xFFFF6B7A), fontSize: 13)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searchCtrl.text.trim().isEmpty
              ? 'Type to search your institution'
              : 'No matching users',
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final u = _results[i];
        return Material(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(context, u),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                    ),
                    child: Text(u.initials,
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.fullName ?? '(no name)',
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        Text(u.email ?? u.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.white54)),
                      ],
                    ),
                  ),
                  const Icon(Icons.add_circle_outline,
                      color: Color(0xFF8A9CF5)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditGroupResult {
  const _EditGroupResult({this.name, this.description});
  final String? name;
  final String? description;
}

class _EditGroupDialog extends StatefulWidget {
  const _EditGroupDialog({required this.initial});
  final Group initial;

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.initial.name);
  late final TextEditingController _descCtrl =
      TextEditingController(text: widget.initial.description ?? '');

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
      title:
          Text('Edit group', style: GoogleFonts.outfit(color: Colors.white)),
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
              ),
            ),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              maxLength: 2000,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Description',
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
            final newName = _nameCtrl.text.trim();
            final newDesc = _descCtrl.text.trim();
            Navigator.pop(
              context,
              _EditGroupResult(
                // Only send fields that actually changed — the PATCH
                // endpoint treats nulls as "leave unchanged" per spec §4.
                name: newName.isNotEmpty && newName != widget.initial.name
                    ? newName
                    : null,
                description: newDesc != (widget.initial.description ?? '')
                    ? newDesc
                    : null,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
