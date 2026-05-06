import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
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
      backgroundColor: kCream,
      appBar: const CreamAppBar(title: 'Settings'),
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(top: false, child: _buildBody(s)),
      ),
    );
  }

  Widget _buildBody(UserSettings? s) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: kAccentDeep));
    }
    if (_error != null && s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: kDangerInk)),
        ),
      );
    }
    if (s == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        const _Section('Notifications'),
        _SwitchTile(
          label: 'Direct messages',
          value: s.notificationMessages,
          onChanged: _saving ? null : (v) => _save(notificationMessages: v),
        ),
        _SwitchTile(
          label: 'Group messages',
          value: s.notificationGroups,
          onChanged: _saving ? null : (v) => _save(notificationGroups: v),
        ),
        _SwitchTile(
          label: 'Notification sound',
          value: s.notificationSound,
          onChanged: _saving ? null : (v) => _save(notificationSound: v),
        ),
        const SizedBox(height: 14),
        const _Section('Push notifications'),
        _PushStatusTile(
          state: PushTokenService.instance.state,
          error: PushTokenService.instance.lastError,
          onRetry: _retryPush,
        ),
        const SizedBox(height: 14),
        const _Section('Appearance'),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: kDangerInk, fontSize: 12)),
          ),
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
        child: CreamFieldLabel(label: label),
      );
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: kCreamCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline),
      ),
      child: child,
    );
  }
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
    return _CardShell(
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: kAccent,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: kInkSubtle.withValues(alpha: 0.35),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        title: Text(label,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: kInkDark,
              fontWeight: FontWeight.w700,
            )),
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
    final (icon, title, subtitle, fg) = switch (state) {
      PushState.idle => (
        Icons.notifications_off_outlined,
        'Not registered',
        'Sign out and back in to register this device.',
        kInkMuted,
      ),
      PushState.initializing => (
        Icons.sync,
        'Registering…',
        'Asking the OS for a push token.',
        kAccentDeep,
      ),
      PushState.notConfigured => (
        Icons.notifications_paused_outlined,
        'Push not configured on this build',
        'Add GoogleService-Info.plist (iOS) / google-services.json '
            '(Android) and reinstall to enable push delivery.',
        kAccentDeep,
      ),
      PushState.permissionDenied => (
        Icons.notifications_off_outlined,
        'Permission denied',
        'Enable notifications in iOS / Android settings, then retry.',
        kDangerInk,
      ),
      PushState.registered => (
        Icons.notifications_active_outlined,
        'Registered',
        'This device will receive push notifications.',
        const Color(0xFF3F7A4F),
      ),
      PushState.failed => (
        Icons.error_outline,
        'Registration failed',
        error ?? 'Unknown error',
        kDangerInk,
      ),
    };
    return _CardShell(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: kInkDark,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: kInkMuted,
                      height: 1.35,
                    )),
              ],
            ),
          ),
          if (state != PushState.registered &&
              state != PushState.initializing)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: kAccentDeep,
              ),
              child: Text('Retry',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700)),
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
    return _CardShell(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 16,
                color: kInkDark,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.map((c) {
              final sel = c == value;
              return ChoiceChip(
                label: Text(c),
                selected: sel,
                showCheckmark: false,
                avatar: sel
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
                labelStyle: GoogleFonts.inter(
                  color: sel ? kCream : kInkDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                selectedColor: kAccent,
                backgroundColor: kCreamField,
                side: BorderSide(color: sel ? kAccent : kHairline),
                onSelected: onSelect == null ? null : (_) => onSelect!(c),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
