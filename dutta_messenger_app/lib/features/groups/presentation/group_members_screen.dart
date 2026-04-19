import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/errors/api_error.dart';
import '../../users/data/users_api.dart';
import '../data/groups_api.dart';

/// Lists the members of a group. Read-only view of who's in the room.
class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  final _api = GroupsApi();
  final _usersApi = UsersApi();
  bool _loading = true;
  String? _error;
  List<GroupMember> _members = [];

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
      final raw = await _api.listMembers(widget.groupId);
      // Hydrate missing user profiles in parallel. The list endpoint
      // returns only {user_id, role, joined_at}; /users/{id} supplies
      // the name + email needed by the row.
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
      if (!mounted) return;
      setState(() {
        _members = hydrated;
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
              style: GoogleFonts.inter(
                  fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _load),
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
    if (_members.isEmpty) {
      return Center(
        child: Text('No members yet',
            style:
                GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
      );
    }
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _MemberRow(member: sorted[i]),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});
  final GroupMember member;

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
                Text(name,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(email,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _RoleChip(role: member.role),
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
