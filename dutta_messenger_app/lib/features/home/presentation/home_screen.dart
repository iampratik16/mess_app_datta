import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../../../services/chat_service.dart';
import '../../../services/push_token_service.dart';
import '../../acl/data/acl_api.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/login_screen.dart';
import '../../dm/presentation/dm_list_screen.dart';
import '../../groups/presentation/groups_screen.dart';
import '../../media/presentation/media_screen.dart';
import '../../notifications/presentation/notifications_bell.dart';
import '../../users/presentation/profile_screen.dart';
import '../../users/presentation/users_screen.dart';

/// Landing screen shown after a successful sign in.
/// Displays the authenticated user, exposes the invite flow, and lets the
/// user log out. A temporary home until the chat module is wired up.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final AuthUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = AuthRepository();
  final _aclApi = AclApi();
  bool _isInviting = false;
  String? _inviteStatus;
  String? _inviteToken;
  String? _inviteUrl;
  List<String>? _permissions;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final perms = await _aclApi.permissionsFor(widget.user.id);
      if (!mounted) return;
      setState(() => _permissions = perms);
    } on ApiError {
      if (!mounted) return;
      setState(() => _permissions = const []);
    }
  }

  Future<void> _invite() async {
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => const _InviteDialog(),
    );

    if (email == null || email.isEmpty) return;

    setState(() {
      _isInviting = true;
      _inviteStatus = null;
      _inviteToken = null;
      _inviteUrl = null;
    });
    try {
      final res = await _repo.inviteUser(email: email);
      setState(() {
        _inviteStatus = res.message;
        _inviteToken = res.token;
        _inviteUrl = res.inviteUrl;
      });
    } on ApiError catch (e) {
      setState(() => _inviteStatus = 'Error: ${e.message}');
    } finally {
      if (mounted) setState(() => _isInviting = false);
    }
  }

  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$label copied'),
      ),
    );
  }

  Future<void> _logout() async {
    ChatService.instance.disconnect();
    // Best-effort FCM cleanup before clearing the bearer token; uses the
    // current session to call DELETE /notifications/tokens/{id}.
    await PushTokenService.instance.revokeAndForget();
    await _repo.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('DuttaMessenger',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        actions: [
          const NotificationsBell(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
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
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UserCard(user: user),
                const SizedBox(height: 20),
                _SectionTitle('Quick actions'),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.person_add_alt_1,
                  label: 'Invite user',
                  subtitle: 'Send an invitation email',
                  trailing: _isInviting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right,
                          color: Colors.white54),
                  onTap: _isInviting ? null : _invite,
                ),
                if (_inviteStatus != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF2ED573).withValues(alpha: 0.12),
                      border: Border.all(
                        color: const Color(0xFF2ED573).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _inviteStatus!,
                          style: GoogleFonts.inter(
                            color: const Color(0xFF2ED573),
                            fontSize: 13,
                          ),
                        ),
                        if (_inviteToken != null) ...[
                          const SizedBox(height: 10),
                          _InviteTokenRow(
                            label: 'Token',
                            value: _inviteToken!,
                            mono: true,
                            onCopy: () =>
                                _copyToClipboard(_inviteToken!, 'Token'),
                          ),
                        ],
                        if (_inviteUrl != null) ...[
                          const SizedBox(height: 6),
                          _InviteTokenRow(
                            label: 'Invite URL',
                            value: _inviteUrl!,
                            onCopy: () =>
                                _copyToClipboard(_inviteUrl!, 'URL'),
                          ),
                        ],
                        if (_inviteToken != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Paste the token in Login → "Have an invite?" '
                            'to register that user.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white60,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _ActionTile(
                  icon: Icons.groups_outlined,
                  label: 'Groups',
                  subtitle: 'Browse or create group chats',
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white54),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => GroupsScreen(me: widget.user)),
                  ),
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.chat_bubble_outline,
                  label: 'Direct messages',
                  subtitle: 'One-on-one conversations',
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white54),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DmListScreen(me: widget.user),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.people_alt_outlined,
                  label: 'People',
                  subtitle: 'Browse users in your institution',
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white54),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => UsersScreen(me: widget.user)),
                  ),
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.cloud_upload_outlined,
                  label: 'Media',
                  subtitle: 'Upload images, videos, and files',
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white54),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MediaScreen()),
                  ),
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.person_outline,
                  label: 'Profile & settings',
                  subtitle: 'Edit your profile, change password, app settings',
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white54),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => ProfileScreen(me: widget.user)),
                  ),
                ),
                if (_permissions != null && _permissions!.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _SectionTitle('Your permissions (${_permissions!.length})'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _permissions!
                        .take(12)
                        .map((p) => _PermChip(label: p))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 28),
                _SectionTitle('Coming soon'),
                const SizedBox(height: 12),
                _DisabledTile(
                  icon: Icons.forum_outlined,
                  label: 'Topics',
                ),
                const SizedBox(height: 32),
                Text(
                  'Institution: ${user.institutionId}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white24,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});
  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final initials = user.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            child: Text(
              initials.isEmpty ? 'U' : initials,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${user.fullName}',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  child: Text(
                    user.status.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
          letterSpacing: 1.2,
        ),
      );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF667EEA).withValues(alpha: 0.25),
                ),
                child: Icon(icon, color: const Color(0xFF8A9CF5), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        )),
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _DisabledTile extends StatelessWidget {
  const _DisabledTile({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 14),
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white54,
              )),
          const Spacer(),
          Text('Coming soon',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.white38,
                fontStyle: FontStyle.italic,
              )),
        ],
      ),
    );
  }
}

/// Compact one-line row that shows an invite token / URL with a copy
/// button. Used in the Home invite-result card so the admin can grab the
/// value without leaving the app.
class _InviteTokenRow extends StatelessWidget {
  const _InviteTokenRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.mono = false,
  });
  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white)
        : GoogleFonts.inter(fontSize: 11, color: Colors.white);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              )),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            style: style,
            maxLines: 2,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Copy',
          onPressed: onCopy,
        ),
      ],
    );
  }
}

/// Cream/amber Invite-user dialog. Title in serif; the input + Invite
/// trigger are laid out as a single inline row that matches the reference
/// design. Pops the entered email back to the caller (or null on Cancel).
class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCreamCard,
      surfaceTintColor: kCreamCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: kHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invite user',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: kInkDark,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kHairline),
                    ),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      cursorColor: kAccentDeep,
                      onSubmitted: (_) => _submit(),
                      style: GoogleFonts.inter(
                        color: kInkDark,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'new-user@ananda.edu',
                        hintStyle: GoogleFonts.inter(
                          color: kInkSubtle,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _hasText ? _submit : null,
                  style: TextButton.styleFrom(
                    foregroundColor: kAccentDeep,
                    disabledForegroundColor: kInkSubtle,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Invite',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: kInkMuted),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill shown for each ACL permission the current user has.
class _PermChip extends StatelessWidget {
  const _PermChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF667EEA).withValues(alpha: 0.15),
        border: Border.all(
            color: const Color(0xFF667EEA).withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          color: const Color(0xFFB3BCF5),
        ),
      ),
    );
  }
}
