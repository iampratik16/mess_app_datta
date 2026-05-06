import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (_) => _UserRolesSheet(user: user, allRoles: _roles),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: const CreamAppBar(title: 'Roles & permissions'),
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingRoles) {
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
          color: kCreamCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available roles (${_roles.length})',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: kInkMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _roles.map((r) => _RoleCatalogChip(role: r)).toList(),
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
        cursorColor: kAccentDeep,
        style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
        decoration: creamInputDecoration(
          hint: 'Search a user to manage their roles',
          prefixIcon: const Icon(Icons.search, color: kInkSubtle),
        ),
      ),
    );
  }

  Widget _buildUsersList() {
    if (_loadingUsers && _users.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: kAccentDeep));
    }
    if (_users.isEmpty) {
      return Center(
        child: Text('No users match',
            style: GoogleFonts.inter(color: kInkMuted, fontSize: 14)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      itemCount: _users.length,
      separatorBuilder: (_, _) => kListDivider,
      itemBuilder: (ctx, i) {
        final u = _users[i];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openUserSheet(u),
            splashColor: kAccent.withValues(alpha: 0.08),
            highlightColor: kAccent.withValues(alpha: 0.04),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CreamAvatar(
                    seed: u.fullName ?? u.email ?? '?',
                    initials: u.initials,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.fullName ?? '(no name)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kInkDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          u.email ?? u.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 13, color: kInkMuted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kAccent.withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: kAccentDeep, size: 18),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Role catalog chip — system roles get an amber lock badge, custom roles
/// get the muted info tone.
class _RoleCatalogChip extends StatelessWidget {
  const _RoleCatalogChip({required this.role});
  final AclRole role;

  @override
  Widget build(BuildContext context) {
    if (role.isSystem) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: kAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 12, color: kAccentDeep),
            const SizedBox(width: 4),
            Text(
              role.name,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kAccentDeep,
              ),
            ),
          ],
        ),
      );
    }
    return CreamTag(label: role.name, tone: CreamTagTone.info);
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
          backgroundColor: kDangerInk,
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
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
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
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
                    _UserHeader(user: widget.user),
                    const SizedBox(height: 18),
                    Text(
                      'Roles',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: kInkDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: kAccentDeep),
                        ),
                      )
                    else if (_error != null)
                      Text(_error!,
                          style: GoogleFonts.inter(
                              color: kDangerInk, fontSize: 13))
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
                            Text(
                              'Effective permissions (${_permissions.length})',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: kInkDark,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_permissions.isEmpty)
                              Text('None',
                                  style: GoogleFonts.inter(
                                      fontSize: 13, color: kInkMuted))
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _permissions
                                    .map((p) => _PermissionChip(label: p))
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
        CreamAvatar(
          seed: user.fullName ?? user.email ?? '?',
          initials: user.initials,
          size: 56,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.fullName ?? '(no name)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: kInkDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user.email ?? user.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: kInkMuted, fontSize: 13),
              ),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: assigned
            ? kAccent.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: assigned
              ? kAccent.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.65),
          width: assigned ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: role.isSystem
                  ? kAccent.withValues(alpha: 0.18)
                  : const Color(0xFF4F6E7B).withValues(alpha: 0.18),
            ),
            child: Icon(
              role.isSystem ? Icons.lock_outline : Icons.shield_outlined,
              size: 18,
              color: role.isSystem
                  ? kAccentDeep
                  : const Color(0xFF3A5460),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.name,
                    style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: kInkDark)),
                if ((role.description ?? '').isNotEmpty)
                  Text(role.description!,
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: kInkMuted)),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: kAccentDeep, strokeWidth: 2),
            )
          else
            Switch(
              value: assigned,
              onChanged: (_) => onToggle(),
              activeThumbColor: Colors.white,
              activeTrackColor: kAccent,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: kInkSubtle.withValues(alpha: 0.35),
              trackOutlineColor:
                  WidgetStateProperty.all(Colors.transparent),
            ),
        ],
      ),
    );
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: kAccent.withValues(alpha: 0.12),
        border: Border.all(color: kAccent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: kAccentDeep),
      ),
    );
  }
}
