import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../users/data/users_api.dart';
import '../../users/domain/user_models.dart';
import '../data/acl_api.dart';

/// Admin-only screen.
///
/// Backend endpoints used (all require `institution.manage_admins`):
///   GET    /acl/roles
///   GET    /acl/users/{user_id}/permissions   (returns roles + permissions)
///   POST   /acl/users/{user_id}/roles         (assign)
///   DELETE /acl/users/{user_id}/roles/{role_id} (revoke)
///
/// Search a user via `/users/search`, tap them, see their current roles,
/// flip the per-role switch to assign or revoke.
class AclAdminScreen extends StatefulWidget {
  const AclAdminScreen({super.key});

  @override
  State<AclAdminScreen> createState() => _AclAdminScreenState();
}

class _AclAdminScreenState extends State<AclAdminScreen> {
  final _aclApi = AclApi();
  final _usersApi = UsersApi();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loadingRoles = true;
  bool _loadingUsers = false;
  String? _error;
  List<AclRole> _roles = const [];
  List<UserProfile> _users = const [];
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final roles = await _aclApi.listRoles();
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _loadingRoles = false;
      });
      _runUserSearch('a');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'PERMISSION_DENIED' || e.isForbidden
            ? "You don't have permission to manage roles."
            : e.message;
        _loadingRoles = false;
      });
    }
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _runUserSearch(q));
  }

  Future<void> _runUserSearch(String q) async {
    _lastQuery = q;
    setState(() => _loadingUsers = true);
    try {
      final results = await _usersApi.search(q);
      if (!mounted || _lastQuery != q) return;
      setState(() {
        _users = results;
        _loadingUsers = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingUsers = false;
      });
    }
  }

  Future<void> _openUserSheet(UserProfile user) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1B3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _UserRolesSheet(user: user, allRoles: _roles),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Roles & permissions',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
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
    if (_loadingRoles) {
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
    return Column(
      children: [
        _buildRoleCatalog(),
        _buildSearchBar(),
        Expanded(child: _buildUsersList()),
      ],
    );
  }

  Widget _buildRoleCatalog() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Available roles (${_roles.length})',
                style: GoogleFonts.inter(
                    fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _roles.map((r) => _RoleChip(role: r)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onQueryChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search a user to manage their roles',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.07),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildUsersList() {
    if (_loadingUsers && _users.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_users.isEmpty) {
      return Center(
        child: Text('No users match',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final u = _users[i];
        return Material(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openUserSheet(u),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                    child: Text(u.initials,
                        style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.fullName ?? '(no name)',
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(u.email ?? u.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.white54)),
                      ],
                    ),
                  ),
                  const Icon(Icons.shield_outlined, color: Colors.white54),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final AclRole role;
  @override
  Widget build(BuildContext context) {
    final color =
        role.isSystem ? const Color(0xFFF59E0B) : const Color(0xFF8A9CF5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (role.isSystem) ...[
            const Icon(Icons.lock_outline,
                size: 11, color: Color(0xFFF59E0B)),
            const SizedBox(width: 4),
          ],
          Text(role.name,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

/// Per-user editor: renders the full role catalog as toggles based on the
/// user's current `/acl/users/{id}/permissions` snapshot. Each flip calls
/// the assign or revoke endpoint and re-reads to surface the latest
/// effective permissions.
class _UserRolesSheet extends StatefulWidget {
  const _UserRolesSheet({required this.user, required this.allRoles});
  final UserProfile user;
  final List<AclRole> allRoles;

  @override
  State<_UserRolesSheet> createState() => _UserRolesSheetState();
}

class _UserRolesSheetState extends State<_UserRolesSheet> {
  final _aclApi = AclApi();

  bool _loading = true;
  String? _error;
  Set<String> _assignedRoleIds = {};
  List<String> _permissions = const [];
  final Set<String> _busyRoleIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _aclApi.snapshotFor(widget.user.id);
      if (!mounted) return;
      setState(() {
        _assignedRoleIds = snap.roleIds;
        _permissions = snap.permissions;
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

  Future<void> _toggle(AclRole role) async {
    if (_busyRoleIds.contains(role.id)) return;
    final assigned = _assignedRoleIds.contains(role.id);
    setState(() => _busyRoleIds.add(role.id));
    try {
      if (assigned) {
        await _aclApi.revokeRole(userId: widget.user.id, roleId: role.id);
        if (!mounted) return;
        setState(() => _assignedRoleIds.remove(role.id));
      } else {
        await _aclApi.assignRole(userId: widget.user.id, roleId: role.id);
        if (!mounted) return;
        setState(() => _assignedRoleIds.add(role.id));
      }
      final snap = await _aclApi.snapshotFor(widget.user.id);
      if (!mounted) return;
      setState(() => _permissions = snap.permissions);
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFF4757),
          content: Text(assigned
              ? 'Revoke failed: ${e.message}'
              : 'Assign failed: ${e.message}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyRoleIds.remove(role.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _UserHeader(user: widget.user),
              const SizedBox(height: 16),
              Text('Roles',
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: Colors.white70)),
                )
              else if (_error != null)
                Text(_error!,
                    style: GoogleFonts.inter(
                        color: const Color(0xFFFF6B7A), fontSize: 13))
              else
                Expanded(
                  child: ListView(
                    children: [
                      ...widget.allRoles.map((r) {
                        final on = _assignedRoleIds.contains(r.id);
                        final busy = _busyRoleIds.contains(r.id);
                        return _RoleToggleTile(
                          role: r,
                          assigned: on,
                          busy: busy,
                          onToggle: () => _toggle(r),
                        );
                      }),
                      const SizedBox(height: 18),
                      Text('Effective permissions (${_permissions.length})',
                          style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (_permissions.isEmpty)
                        Text('None',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: Colors.white54))
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _permissions
                              .map((p) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      color: const Color(0xFF667EEA)
                                          .withValues(alpha: 0.15),
                                      border: Border.all(
                                          color: const Color(0xFF667EEA)
                                              .withValues(alpha: 0.35)),
                                    ),
                                    child: Text(p,
                                        style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            color:
                                                const Color(0xFFB3BCF5))),
                                  ))
                              .toList(),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            ),
          ),
          child: Text(user.initials,
              style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.fullName ?? '(no name)',
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              Text(user.email ?? user.id,
                  style: GoogleFonts.inter(
                      color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoleToggleTile extends StatelessWidget {
  const _RoleToggleTile({
    required this.role,
    required this.assigned,
    required this.busy,
    required this.onToggle,
  });
  final AclRole role;
  final bool assigned;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: assigned
            ? const Color(0xFF667EEA).withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.04),
        border: Border.all(
            color: assigned
                ? const Color(0xFF667EEA).withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(role.isSystem ? Icons.lock_outline : Icons.shield_outlined,
              size: 18,
              color: role.isSystem
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF8A9CF5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.name,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                if ((role.description ?? '').isNotEmpty)
                  Text(role.description!,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white70, strokeWidth: 2),
            )
          else
            Switch(
              value: assigned,
              onChanged: (_) => onToggle(),
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF667EEA),
            ),
        ],
      ),
    );
  }
}
