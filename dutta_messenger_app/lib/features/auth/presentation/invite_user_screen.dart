import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../data/auth_repository.dart';

/// Standalone invite-user flow: an admin enters an email, the server
/// returns a one-time invite token + URL, and we surface both with copy
/// buttons so the admin can hand them off via whatever channel they
/// prefer. Replaces the inline section that used to live on Home before
/// the bottom-nav shell took its place.
class InviteUserScreen extends StatefulWidget {
  const InviteUserScreen({super.key});

  @override
  State<InviteUserScreen> createState() => _InviteUserScreenState();
}

class _InviteUserScreenState extends State<InviteUserScreen> {
  final _repo = AuthRepository();
  final _emailCtrl = TextEditingController();
  bool _hasText = false;
  bool _busy = false;
  String? _error;
  String? _statusMessage;
  String? _token;
  String? _url;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(() {
      final has = _emailCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _statusMessage = null;
      _token = null;
      _url = null;
    });
    try {
      final res = await _repo.inviteUser(email: email);
      if (!mounted) return;
      setState(() {
        _statusMessage = res.message;
        _token = res.token;
        _url = res.inviteUrl;
        _busy = false;
        _emailCtrl.clear();
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$label copied'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: const CreamAppBar(title: 'Invite user'),
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Send an invitation',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: kInkDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Direct sign-up is disabled. Each new account starts with '
                  'an invite — paste the resulting token in Login → '
                  '"Have an invite?" to register that user.',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: kInkMuted, height: 1.4),
                ),
                const SizedBox(height: 22),
                const CreamFieldLabel(label: 'Email'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kHairline),
                        ),
                        child: TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofocus: true,
                          cursorColor: kAccentDeep,
                          onSubmitted: (_) => _submit(),
                          style: GoogleFonts.inter(
                              color: kInkDark, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'new-user@ananda.edu',
                            hintStyle: GoogleFonts.inter(
                                color: kInkSubtle, fontSize: 14),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: (!_hasText || _busy) ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: kAccent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              kAccent.withValues(alpha: 0.45),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.4),
                              )
                            : Text(
                                'Invite',
                                style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: kDangerBg.withValues(alpha: 0.10),
                      border:
                          Border.all(color: kDangerBg.withValues(alpha: 0.40)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: kDangerInk, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: kDangerInk)),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_statusMessage != null) ...[
                  const SizedBox(height: 18),
                  _SuccessCard(
                    message: _statusMessage!,
                    token: _token,
                    url: _url,
                    onCopyToken: _token == null
                        ? null
                        : () => _copy(_token!, 'Token'),
                    onCopyUrl:
                        _url == null ? null : () => _copy(_url!, 'URL'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.message,
    required this.token,
    required this.url,
    required this.onCopyToken,
    required this.onCopyUrl,
  });

  final String message;
  final String? token;
  final String? url;
  final VoidCallback? onCopyToken;
  final VoidCallback? onCopyUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFDDEBE0),
        border: Border.all(
          color: const Color(0xFF6BAE5E).withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6BAE5E).withValues(alpha: 0.20),
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: Color(0xFF3F7A4F), size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    color: kInkDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (token != null) ...[
            const SizedBox(height: 12),
            _ValueRow(label: 'Token', value: token!, mono: true, onCopy: onCopyToken!),
          ],
          if (url != null) ...[
            const SizedBox(height: 6),
            _ValueRow(label: 'URL', value: url!, onCopy: onCopyUrl!),
          ],
          if (token != null) ...[
            const SizedBox(height: 10),
            Text(
              'Paste the token in Login → "Have an invite?" to register '
              'that user.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: kInkMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
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
        ? GoogleFonts.jetBrainsMono(
            fontSize: 12, color: kInkDark, fontWeight: FontWeight.w600)
        : GoogleFonts.inter(fontSize: 12, color: kInkDark);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: kHairline,
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: kInkMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(value, style: style, maxLines: 2),
        ),
        IconButton(
          icon: const Icon(Icons.copy_all_outlined,
              size: 18, color: kAccentDeep),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Copy',
          onPressed: onCopy,
        ),
      ],
    );
  }
}
