import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../acl/data/acl_api.dart';
import '../../acl/presentation/acl_admin_screen.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/change_password_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
      backgroundColor: const Color(0xFF1E1B3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditProfileSheet(current: current),
    );
    if (updated != null && mounted) {
      setState(() => _me = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Profile',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit profile',
            onPressed: me == null ? null : _edit,
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
        child: SafeArea(child: _buildBody(me)),
      ),
    );
  }

  Widget _buildBody(UserProfile? me) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null || me == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error ?? 'Could not load profile.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: const Color(0xFFFF6B7A))),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileHeader(user: me),
          const SizedBox(height: 20),
          if ((me.bio ?? '').trim().isNotEmpty) ...[
            _SectionTitle('About'),
            const SizedBox(height: 8),
            _BioCard(bio: me.bio!),
            const SizedBox(height: 20),
          ],
          _SectionTitle('Account'),
          const SizedBox(height: 10),
          _RowTile(
            icon: Icons.tune,
            label: 'Notification & app settings',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _RowTile(
            icon: Icons.lock_outline,
            label: 'Change password',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          if ((_permissions ?? const [])
              .contains('institution.manage_admins')) ...[
            const SizedBox(height: 10),
            _RowTile(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Manage roles & permissions',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AclAdminScreen()),
              ),
            ),
          ],
          if ((_permissions ?? const []).isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionTitle('Your permissions (${_permissions!.length})'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _permissions!
                  .map((p) => _PermChip(label: p))
                  .toList(),
            ),
          ],
          const SizedBox(height: 32),
          Text(
            'User ID: ${me.id}\nInstitution: ${widget.me.institutionId}',
            textAlign: TextAlign.center,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: Colors.white24,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            child: Text(
              user.initials,
              style: GoogleFonts.outfit(
                fontSize: 26,
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
                  user.fullName ?? '(no name)',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 8),
                if ((user.status ?? '').isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: Text(
                      (user.status ?? '').toUpperCase(),
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

class _BioCard extends StatelessWidget {
  const _BioCard({required this.bio});
  final String bio;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        bio,
        style: GoogleFonts.inter(
            fontSize: 13, color: Colors.white.withValues(alpha: 0.8)),
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
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
          letterSpacing: 1.2,
        ),
      );
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                ),
                child: Icon(icon, color: const Color(0xFF8A9CF5), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

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
            fontSize: 11, color: const Color(0xFFB3BCF5)),
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit profile',
              style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 14),
          _AvatarPickerRow(
            currentUrl: _avatarUrl,
            uploading: _uploadingAvatar,
            onPick: _pickAvatar,
          ),
          const SizedBox(height: 14),
          _Field(
            label: 'Full name',
            controller: _nameCtrl,
          ),
          const SizedBox(height: 12),
          _Field(
            label: 'Bio',
            controller: _bioCtrl,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _Field(
            label: 'Phone number (optional)',
            controller: _phoneCtrl,
          ),
          const SizedBox(height: 14),
          Text('Status',
              style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _statusChoices.map((s) {
              final selected = s == _status;
              return ChoiceChip(
                label: Text(s),
                selected: selected,
                labelStyle: GoogleFonts.inter(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12,
                ),
                selectedColor: const Color(0xFF667EEA),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                onSelected: (_) => setState(() => _status = s),
              );
            }).toList(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: GoogleFonts.inter(
                    color: const Color(0xFFFF6B7A), fontSize: 12)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar slot used inside the profile + group edit sheets. Tapping it
/// opens the gallery picker and uploads via [AvatarPicker]; the parent
/// rebuilds with the new presigned URL.
class _AvatarPickerRow extends StatelessWidget {
  const _AvatarPickerRow({
    required this.currentUrl,
    required this.uploading,
    required this.onPick,
  });
  final String? currentUrl;
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
              Container(
                width: 72,
                height: 72,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                ),
                child: hasUrl
                    ? Image.network(
                        currentUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.person,
                              color: Colors.white70, size: 32),
                        ),
                      )
                    : const Icon(Icons.person,
                        color: Colors.white70, size: 32),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF667EEA),
                ),
                child: uploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.edit,
                        color: Colors.white, size: 14),
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
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
