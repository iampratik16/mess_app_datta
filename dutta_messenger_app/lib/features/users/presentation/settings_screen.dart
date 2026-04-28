import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../services/push_token_service.dart';
import '../data/users_api.dart';
import '../domain/user_models.dart';

/// Notification + appearance settings backed by /users/me/settings.
/// Each toggle/select PATCHes immediately; nothing is batched.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = UsersApi();
  UserSettings? _settings;
  bool _loading = true;
  String? _error;
  bool _saving = false;

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
      final s = await _api.settings();
      if (!mounted) return;
      setState(() {
        _settings = s;
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

  Future<void> _retryPush() async {
    setState(() {});
    await PushTokenService.instance.registerForCurrentUser();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _save({
    bool? notificationMessages,
    bool? notificationGroups,
    bool? notificationSound,
    String? theme,
    String? language,
  }) async {
    setState(() => _saving = true);
    try {
      final updated = await _api.updateSettings(
        notificationMessages: notificationMessages,
        notificationGroups: notificationGroups,
        notificationSound: notificationSound,
        theme: theme,
        language: language,
      );
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _saving = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Settings',
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
        child: SafeArea(child: _buildBody(s)),
      ),
    );
  }

  Widget _buildBody(UserSettings? s) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null && s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: const Color(0xFFFF6B7A))),
        ),
      );
    }
    if (s == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section('Notifications'),
        _SwitchTile(
          label: 'Direct messages',
          value: s.notificationMessages,
          onChanged: _saving
              ? null
              : (v) => _save(notificationMessages: v),
        ),
        _SwitchTile(
          label: 'Group messages',
          value: s.notificationGroups,
          onChanged: _saving
              ? null
              : (v) => _save(notificationGroups: v),
        ),
        _SwitchTile(
          label: 'Notification sound',
          value: s.notificationSound,
          onChanged: _saving
              ? null
              : (v) => _save(notificationSound: v),
        ),
        const SizedBox(height: 12),
        _Section('Push notifications'),
        _PushStatusTile(
          state: PushTokenService.instance.state,
          error: PushTokenService.instance.lastError,
          onRetry: _retryPush,
        ),
        const SizedBox(height: 12),
        _Section('Appearance'),
        _ChoiceTile(
          label: 'Theme',
          value: s.theme,
          choices: const ['system', 'light', 'dark'],
          onSelect: _saving ? null : (v) => _save(theme: v),
        ),
        _ChoiceTile(
          label: 'Language',
          value: s.language,
          choices: const ['en', 'hi', 'fr', 'es'],
          onSelect: _saving ? null : (v) => _save(language: v),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: const Color(0xFFFF6B7A), fontSize: 12)),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: Colors.white54,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF667EEA),
        title: Text(label,
            style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w500)),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

/// Surfaces the current FCM registration state. The actual register
/// call happens at sign-in; this tile shows whether it succeeded and
/// offers a retry. Three real states matter to the user:
///   - registered: device will receive pushes
///   - notConfigured: this build doesn't ship Firebase config — no push
///   - permissionDenied / failed: actionable
class _PushStatusTile extends StatelessWidget {
  const _PushStatusTile({
    required this.state,
    required this.error,
    required this.onRetry,
  });
  final PushState state;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle, color) = switch (state) {
      PushState.idle => (
        Icons.notifications_off_outlined,
        'Not registered',
        'Sign out and back in to register this device.',
        const Color(0xFF8A9CF5),
      ),
      PushState.initializing => (
        Icons.sync,
        'Registering…',
        'Asking the OS for a push token.',
        const Color(0xFF8A9CF5),
      ),
      PushState.notConfigured => (
        Icons.notifications_paused_outlined,
        'Push not configured on this build',
        'Add GoogleService-Info.plist (iOS) / google-services.json '
            '(Android) and reinstall to enable push delivery.',
        const Color(0xFFF59E0B),
      ),
      PushState.permissionDenied => (
        Icons.notifications_off_outlined,
        'Permission denied',
        'Enable notifications in iOS / Android settings, then retry.',
        const Color(0xFFFF6B7A),
      ),
      PushState.registered => (
        Icons.notifications_active_outlined,
        'Registered',
        'This device will receive push notifications.',
        const Color(0xFF2ED573),
      ),
      PushState.failed => (
        Icons.error_outline,
        'Registration failed',
        error ?? 'Unknown error',
        const Color(0xFFFF6B7A),
      ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white60,
                    )),
              ],
            ),
          ),
          if (state != PushState.registered &&
              state != PushState.initializing)
            TextButton(
              onPressed: onRetry,
              child: Text('Retry',
                  style: GoogleFonts.inter(
                      color: const Color(0xFF8A9CF5), fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.value,
    required this.choices,
    required this.onSelect,
  });
  final String label;
  final String value;
  final List<String> choices;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: choices.map((c) {
              final sel = c == value;
              return ChoiceChip(
                label: Text(c),
                selected: sel,
                labelStyle: GoogleFonts.inter(
                  color: sel ? Colors.white : Colors.white70,
                  fontSize: 12,
                ),
                selectedColor: const Color(0xFF667EEA),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                onSelected: onSelect == null ? null : (_) => onSelect!(c),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
