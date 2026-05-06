import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../../../services/chat_service.dart';
import '../../auth/domain/auth_models.dart';
import '../../media/data/avatar_picker.dart';
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
  Set<String> _onlineUserIds = {};
  StreamSubscription<String>? _membershipSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Live composition updates from another device (admin adds/removes
    // someone while this screen is open). Refetch on hits to our id.
    _membershipSub =
        ChatService.instance.groupMembershipChanged.listen((groupId) {
      if (mounted && groupId == widget.groupId) _refetchMembers();
    });
  }

  @override
  void dispose() {
    _membershipSub?.cancel();
    super.dispose();
  }

  String? get _myRole {
    for (final m in _members) {
      if (m.userId == widget.me.id) return m.role;
    }
    return null;
  }

  bool get _canManage => _myRole == 'owner' || _myRole == 'admin';
  bool get _isOwner => _myRole == 'owner';

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
      // Best-effort presence overlay; failure is silent.
      Set<String> online = const {};
      try {
        online = await _usersApi
            .bulkOnlineStatus(hydrated.map((m) => m.userId));
      } on ApiError {
        online = const {};
      }
      if (!mounted) return;
      setState(() {
        _members = hydrated;
        _group = group;
        _onlineUserIds = online;
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (_) => _AddMemberSheet(excludedUserIds: existingIds),
    );
    if (added == null || !mounted) return;

    // Optimistic append for snappy feedback, then on success follow up
    // with a full _refetchMembers() to reconcile against the server
    // truth (audit 3.1 option b — the response itself is just an
    // {reused, role} ack and doesn't carry the full member list). On
    // failure roll the optimistic row back.
    final snapshot = _members;
    setState(() {
      _members = [
        ..._members,
        GroupMember(userId: added.id, role: 'member', user: added),
      ];
    });
    try {
      await _api.addMember(groupId: widget.groupId, userId: added.id);
      await _refetchMembers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Added ${added.fullName ?? added.email ?? "user"}'),
        ),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _members = snapshot);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kDangerInk,
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
        avatarUrl: result.avatarUrl,
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
          backgroundColor: kDangerInk,
          content: Text('Update failed: ${e.message}'),
        ),
      );
    }
  }

  Future<void> _archiveGroup() async {
    final ok = await _showCreamConfirm(
      context: context,
      title: 'Archive "${widget.groupName}"?',
      body:
          'The group disappears from everyone\'s list. Messages are kept '
          'and deep links still work. There is no unarchive yet.',
      confirmLabel: 'Archive',
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
          backgroundColor: kDangerInk,
          content: Text('Archive failed: ${e.message}'),
        ),
      );
    }
  }

  Future<void> _removeMember(GroupMember m) async {
    if (m.role == 'owner' || m.userId == widget.me.id) return;
    final confirmed = await _showCreamConfirm(
      context: context,
      title: 'Remove ${m.user?.fullName ?? m.userId}?',
      body: 'They will stop receiving new messages in this group. '
          'Past messages stay visible to them.',
      confirmLabel: 'Remove',
    );
    if (confirmed != true) return;

    final snapshot = _members;
    setState(() =>
        _members = _members.where((x) => x.userId != m.userId).toList());
    try {
      await _api.removeMember(groupId: widget.groupId, userId: m.userId);
      // Same pattern as add — reconcile from the server's authoritative
      // member list rather than trusting our optimistic local state.
      await _refetchMembers();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _members = snapshot);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kDangerInk,
          content: Text('Remove failed: ${e.message}'),
        ),
      );
    }
  }

  /// GET /groups/{id}/members — reconcile local state with the server
  /// truth. Used by add/remove flows immediately after the mutation
  /// succeeds. Hydration of missing user profiles + presence overlay
  /// match what [_load] does on first mount, so the row visuals don't
  /// "jump" between optimistic and reconciled state.
  Future<void> _refetchMembers() async {
    try {
      final raw = await _api.listMembers(widget.groupId);
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
      Set<String> online = const {};
      try {
        online = await _usersApi
            .bulkOnlineStatus(hydrated.map((m) => m.userId));
      } on ApiError {
        online = const {};
      }
      if (!mounted) return;
      setState(() {
        _members = hydrated;
        _onlineUserIds = online;
      });
    } on ApiError {
      // Silent on refetch failure — the optimistic state stays as-is
      // and the next manual refresh / next mutation will reconcile.
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
      backgroundColor: kCream,
      appBar: CreamAppBar(
        title: widget.groupName,
        subtitle: _loading
            ? 'Loading…'
            : '${_members.length} ${_members.length == 1 ? 'member' : 'members'}',
        leadingAvatar: CreamAvatar(
          seed: widget.groupName,
          initials: widget.groupName.isEmpty
              ? '?'
              : widget.groupName.substring(0, 1).toUpperCase(),
          size: 36,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kAccentDeep),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
          if (_canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: kAccentDeep),
              color: kCreamCard,
              surfaceTintColor: kCreamCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: kHairline),
              ),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _editGroup();
                  case 'archive':
                    _archiveGroup();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    const Icon(Icons.edit, size: 18, color: kInkMuted),
                    const SizedBox(width: 10),
                    Text('Edit group',
                        style: GoogleFonts.inter(
                          color: kInkDark,
                          fontWeight: FontWeight.w600,
                        )),
                  ]),
                ),
                if (_isOwner)
                  PopupMenuItem(
                    value: 'archive',
                    child: Row(children: [
                      const Icon(Icons.archive_outlined,
                          size: 18, color: kDangerInk),
                      const SizedBox(width: 10),
                      Text('Archive group',
                          style: GoogleFonts.inter(
                            color: kDangerInk,
                            fontWeight: FontWeight.w600,
                          )),
                    ]),
                  ),
              ],
            ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              elevation: 2,
              onPressed: _openAddMemberSheet,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text('Add member',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(top: false, child: _buildBody(sorted)),
      ),
    );
  }

  Widget _buildBody(List<GroupMember> rows) {
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
    if (rows.isEmpty) {
      return Center(
        child: Text('No members yet',
            style: GoogleFonts.inter(color: kInkMuted, fontSize: 14)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
      itemCount: rows.length + 1,
      separatorBuilder: (_, i) => i == 0
          ? const SizedBox.shrink()
          : kListDivider,
      itemBuilder: (ctx, i) {
        if (i == 0) return _MemberCountHeader(count: rows.length);
        final m = rows[i - 1];
        final canRemove =
            _canManage && m.role != 'owner' && m.userId != widget.me.id;
        return _MemberRow(
          member: m,
          isMe: m.userId == widget.me.id,
          isOnline: _onlineUserIds.contains(m.userId),
          onRemove: canRemove ? () => _removeMember(m) : null,
        );
      },
    );
  }
}

/// Big count above the member rows. Demo wanted a prominent affordance
/// rather than just the AppBar subtitle — easier to spot when the
/// members list grows.
class _MemberCountHeader extends StatelessWidget {
  const _MemberCountHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kAccent.withValues(alpha: 0.18),
            ),
            child: const Icon(Icons.groups, color: kAccentDeep, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count ${count == 1 ? 'member' : 'members'}',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: kInkDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                count == 1
                    ? 'You\'re the only one here yet.'
                    : 'Everyone with access to this group.',
                style: GoogleFonts.inter(fontSize: 12, color: kInkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.onRemove,
    this.isOnline = false,
  });
  final GroupMember member;
  final bool isMe;
  final bool isOnline;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final user = member.user;
    final initials = user?.initials ?? '?';
    final name = user?.fullName ?? '(unknown)';
    final email = user?.email ?? member.userId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CreamAvatar(
            seed: name,
            initials: initials,
            online: isOnline,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kInkDark,
                        ),
                      ),
                    ),
                    if (isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('(you)',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: kInkSubtle)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: GoogleFonts.inter(fontSize: 13, color: kInkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _RoleChip(role: member.role),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: kDangerInk),
              tooltip: 'Remove from group',
              onPressed: onRemove,
            )
          else
            const SizedBox(width: 8),
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
    final tone = switch (role) {
      'owner' => CreamTagTone.accent,
      'admin' => CreamTagTone.info,
      _ => CreamTagTone.muted,
    };
    return CreamTag(
      label: role.toUpperCase(),
      tone: tone,
    );
  }
}

/// Reusable confirmation dialog with the cream/amber treatment. Used by
/// the archive and remove flows so they don't drift in style.
Future<bool?> _showCreamConfirm({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kCreamCard,
      surfaceTintColor: kCreamCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kHairline),
      ),
      title: Text(
        title,
        style: GoogleFonts.playfairDisplay(
          color: kInkDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        body,
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
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Glassmorphic add-member sheet: backdrop-blur over translucent cream
/// with a hairline highlight, debounced user search, and tappable rows.
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
        height: MediaQuery.of(context).size.height * 0.72,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    kCream.withValues(alpha: 0.78),
                    kCreamDeep.withValues(alpha: 0.82),
                  ],
                ),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: kInkSubtle.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kAccent.withValues(alpha: 0.18),
                          ),
                          child: const Icon(Icons.person_add_alt_1,
                              color: kAccentDeep, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Add member',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: kInkDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _GlassSearchField(
                      controller: _searchCtrl,
                      onChanged: _onQueryChanged,
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _buildList()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _results.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: kAccentDeep));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: GoogleFonts.inter(color: kDangerInk, fontSize: 13)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searchCtrl.text.trim().isEmpty
              ? 'Type to search your institution'
              : 'No matching users',
          style: GoogleFonts.inter(color: kInkMuted, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final u = _results[i];
        return _GlassUserTile(
          user: u,
          onTap: () => Navigator.pop(context, u),
        );
      },
    );
  }
}

/// Frosted-glass search input — translucent fill so the backdrop blur
/// behind the sheet remains visible through the field.
class _GlassSearchField extends StatelessWidget {
  const _GlassSearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: true,
        cursorColor: kAccentDeep,
        style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search name or email',
          hintStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: kInkSubtle),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

/// One row inside the glassmorphic add-member sheet — translucent card
/// with a [CreamAvatar] and an amber + chip on the trailing edge.
class _GlassUserTile extends StatelessWidget {
  const _GlassUserTile({required this.user, required this.onTap});
  final UserProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = user.fullName ?? '(no name)';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: kAccent.withValues(alpha: 0.10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              CreamAvatar(seed: name, initials: user.initials, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kInkDark,
                      ),
                    ),
                    Text(
                      user.email ?? user.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: kInkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kAccent.withValues(alpha: 0.20),
                ),
                child: const Icon(Icons.add, color: kAccentDeep, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditGroupResult {
  const _EditGroupResult({this.name, this.description, this.avatarUrl});
  final String? name;
  final String? description;
  final String? avatarUrl;
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
  String? _avatarUrl;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.initial.avatarUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() => _uploadingAvatar = true);
    final url = await AvatarPicker.pickAndUpload(context);
    if (!mounted) return;
    setState(() {
      _uploadingAvatar = false;
      if (url != null) _avatarUrl = url;
    });
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 13),
        floatingLabelStyle:
            GoogleFonts.inter(color: kAccentDeep, fontSize: 13),
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

  @override
  Widget build(BuildContext context) {
    final hasAvatar = _avatarUrl != null && _avatarUrl!.isNotEmpty;
    return AlertDialog(
      backgroundColor: kCreamCard,
      surfaceTintColor: kCreamCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kHairline),
      ),
      title: Text(
        'Edit group',
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
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: _uploadingAvatar ? null : _pickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: kAccent,
                        ),
                        child: hasAvatar
                            ? Image.network(
                                _avatarUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                    Icons.groups,
                                    color: Colors.white,
                                    size: 28),
                              )
                            : const Icon(Icons.groups,
                                color: Colors.white, size: 28),
                      ),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: kAccentDeep,
                        ),
                        child: _uploadingAvatar
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.edit,
                                color: Colors.white, size: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _uploadingAvatar
                        ? 'Uploading…'
                        : hasAvatar
                            ? 'Tap to change icon'
                            : 'Tap to set group icon',
                    style: GoogleFonts.inter(fontSize: 12, color: kInkMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              maxLength: 255,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Name'),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              maxLength: 2000,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Description'),
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
                avatarUrl:
                    _avatarUrl == widget.initial.avatarUrl ? null : _avatarUrl,
              ),
            );
          },
          child: Text(
            'Save',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
