import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/auth_events.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../../../services/chat_service.dart';
import '../../acl/data/acl_api.dart';
import '../../acl/presentation/acl_admin_screen.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/change_password_screen.dart';
import '../../auth/presentation/invite_user_screen.dart';
import '../../media/data/avatar_picker.dart';
import '../data/users_api.dart';
import '../domain/user_models.dart';
import 'settings_screen.dart';

/// Own profile screen — view + edit `full_name`, `bio`, `status`, and
/// jump points for Settings, Change password, and Permissions. Calls
/// `GET /users/me` on load so it always reflects the server, not a
/// stale login payload.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.me});
  final AuthUser me;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _usersApi = UsersApi();
  final _aclApi = AclApi();

  UserProfile? _me;
  List<String>? _permissions;
  bool _loading = true;
  String? _error;
  StreamSubscription<void>? _roleChangedSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // When another device (e.g. an admin promoting / demoting this
    // user) rotates roles, the server pushes user.role_changed over WS.
    // Reload the profile so the permissions list reflects truth without
    // requiring a sign-out (audit 4.7 / Shreyas feedback #8).
    _roleChangedSub = ChatService.instance.roleChanged.listen((_) {
      if (mounted) _bootstrap();
    });
  }

  @override
  void dispose() {
    _roleChangedSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        _usersApi.me(),
        _aclApi.permissionsFor(widget.me.id).catchError((_) => <String>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _me = results[0] as UserProfile;
        _permissions = (results[1] as List).whereType<String>().toList();
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

  Future<void> _edit() async {
    final current = _me;
    if (current == null) return;
    final updated = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCreamCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _EditProfileSheet(current: current),
    );
    if (updated != null && mounted) {
      setState(() => _me = updated);
    }
  }

  Future<void> _signOut() async {
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
          'Sign out?',
          style: GoogleFonts.playfairDisplay(
            color: kInkDark,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          "You'll be returned to the sign-in screen. "
          'Push notifications for this device will stop.',
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
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Funnel through the global AuthEvents bus so the shell handles WS
    // disconnect, FCM revoke, token clear, and navigation in exactly the
    // same code path as session-expired and revoked logouts.
    AuthEvents.instance.emit(AuthEvent.userLoggedOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: const CreamAppBar(title: 'Settings'),
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: kAccentDeep));
    }
    final me = _me;
    if (_error != null || me == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? 'Could not load profile.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: kDangerInk),
          ),
        ),
      );
    }

    final perms = _permissions ?? const <String>[];
    final canManageAcl = perms.contains('institution.manage_admins');
    final isAdmin = perms.any((p) => p.startsWith('institution.'));
    final roleLabel = isAdmin ? 'ADMIN' : 'MEMBER';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileHeaderCard(
            user: me,
            roleLabel: roleLabel,
            institutionId: widget.me.institutionId,
            onTap: _edit,
          ),
          const SizedBox(height: 22),
          const _SectionHeader('ACCOUNT'),
          _SettingsCard(
            children: [
              if (isAdmin)
                _SettingsTile(
                  icon: Icons.mark_email_read_outlined,
                  title: 'Invitations',
                  subtitle: 'Invite a new user via email',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const InviteUserScreen()),
                  ),
                ),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Change password',
                subtitle: 'Sign out of other sessions',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.notifications_none,
                title: 'Notifications',
                subtitle: 'Push, muted chats',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              if (canManageAcl)
                _SettingsTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Roles & permissions',
                  subtitle: 'Manage who can do what',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AclAdminScreen()),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionHeader('INSTITUTION'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.business_outlined,
                title: 'Institution',
                subtitle: widget.me.institutionId,
              ),
              _SettingsTile(
                icon: Icons.access_time,
                title: 'About Datta',
                subtitle: 'Version 1.0.0 · request log',
              ),
            ],
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kDangerInk,
                  side: BorderSide(
                    color: kDangerInk.withValues(alpha: 0.5),
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Sign out',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Datta · build 7197905 · api/v1',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: kInkSubtle.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White-card user header. Shows avatar, name (serif), email, and a tiny
/// caps strip with "{ROLE} · {INSTITUTION}". Tap opens the edit sheet.
class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.user,
    required this.roleLabel,
    required this.institutionId,
    required this.onTap,
  });

  final UserProfile user;
  final String roleLabel;
  final String institutionId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCreamCard,
      child: InkWell(
        onTap: onTap,
        splashColor: kAccent.withValues(alpha: 0.08),
        highlightColor: kAccent.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              CreamAvatar(
                seed: user.fullName ?? user.email ?? '?',
                initials: user.initials,
                size: 64,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName ?? '(no name)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: kInkDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        color: kInkMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$roleLabel  ·  ${_shortInstitution(institutionId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kAccentDeep,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: kInkSubtle),
            ],
          ),
        ),
      ),
    );
  }

  String _shortInstitution(String id) {
    // Truncated UUID is the most useful piece of info we currently have
    // for the institution. Replace once a name endpoint exists.
    if (id.length <= 12) return id.toUpperCase();
    return '${id.substring(0, 8).toUpperCase()}…';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: kInkMuted,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

/// Rounded cream container that wraps a vertical stack of [_SettingsTile]s
/// with a thin hairline divider between them.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(const Padding(
          padding: EdgeInsets.only(left: 76),
          child: Divider(height: 1, thickness: 1, color: kHairline),
        ));
      }
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kCreamCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(children: rows),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: kAccent.withValues(alpha: 0.08),
        highlightColor: kAccent.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kCreamField,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kHairline),
                ),
                child: Icon(icon, color: kInkDark, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
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
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: kInkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: kInkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal sheet that PATCHes `/users/me` with whatever the user changed.
class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.current});
  final UserProfile current;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _api = UsersApi();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _phoneCtrl;
  late String _status;
  String? _avatarUrl;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _error;

  static const _statusChoices = ['online', 'away', 'busy', 'offline'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.current.fullName ?? '');
    _bioCtrl = TextEditingController(text: widget.current.bio ?? '');
    _phoneCtrl = TextEditingController(text: '');
    _avatarUrl = widget.current.avatarUrl;
    _status = (widget.current.status ?? 'online').toLowerCase();
    if (!_statusChoices.contains(_status)) _status = 'online';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
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

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _api.updateMe(
        fullName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        status: _status,
        avatarUrl: _avatarUrl == widget.current.avatarUrl ? null : _avatarUrl,
        phoneNumber: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, updated);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
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
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 14,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: kHairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Edit profile',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: kInkDark,
              ),
            ),
            const SizedBox(height: 14),
            _AvatarPickerRow(
              currentUrl: _avatarUrl,
              fallbackInitials: widget.current.initials,
              fallbackSeed:
                  widget.current.fullName ?? widget.current.email ?? '?',
              uploading: _uploadingAvatar,
              onPick: _pickAvatar,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Full name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Bio'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              cursorColor: kAccentDeep,
              style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
              decoration: _fieldDecoration('Phone number (optional)'),
            ),
            const SizedBox(height: 14),
            Text(
              'Status',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kInkMuted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statusChoices.map((s) {
                final selected = s == _status;
                return ChoiceChip(
                  label: Text(s),
                  selected: selected,
                  showCheckmark: false,
                  labelStyle: GoogleFonts.inter(
                    color: selected ? kCream : kInkDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  selectedColor: kAccent,
                  backgroundColor: kCreamField,
                  side: BorderSide(
                    color: selected ? kAccent : kHairline,
                  ),
                  onSelected: (_) => setState(() => _status = s),
                );
              }).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: GoogleFonts.inter(color: kDangerInk, fontSize: 12)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        'Save',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar slot used inside the profile edit sheet. Tapping opens the
/// gallery picker; the parent rebuilds with the new presigned URL.
class _AvatarPickerRow extends StatelessWidget {
  const _AvatarPickerRow({
    required this.currentUrl,
    required this.fallbackInitials,
    required this.fallbackSeed,
    required this.uploading,
    required this.onPick,
  });
  final String? currentUrl;
  final String fallbackInitials;
  final String fallbackSeed;
  final bool uploading;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasUrl = currentUrl != null && currentUrl!.isNotEmpty;
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: uploading ? null : onPick,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              if (hasUrl)
                ClipOval(
                  child: Image.network(
                    currentUrl!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => CreamAvatar(
                      seed: fallbackSeed,
                      initials: fallbackInitials,
                      size: 72,
                    ),
                  ),
                )
              else
                CreamAvatar(
                  seed: fallbackSeed,
                  initials: fallbackInitials,
                  size: 72,
                ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: kAccentDeep,
                ),
                child: uploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.edit, color: Colors.white, size: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            uploading
                ? 'Uploading…'
                : hasUrl
                    ? 'Tap the avatar to change'
                    : 'Tap to set a profile photo',
            style: GoogleFonts.inter(fontSize: 13, color: kInkMuted),
          ),
        ),
      ],
    );
  }
}

