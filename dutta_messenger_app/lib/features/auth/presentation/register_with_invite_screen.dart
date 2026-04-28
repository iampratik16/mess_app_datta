import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../services/chat_service.dart';
import '../../../services/push_token_service.dart';
import '../../home/presentation/home_screen.dart';
import '../data/auth_repository.dart';

/// POST /api/v1/auth/register — complete registration using an invite token.
/// Reachable from LoginScreen for users who received an invite email.
/// On success persists tokens, opens the chat WS, and lands on Home.
class RegisterWithInviteScreen extends StatefulWidget {
  const RegisterWithInviteScreen({super.key, this.prefilledEmail});
  final String? prefilledEmail;

  @override
  State<RegisterWithInviteScreen> createState() =>
      _RegisterWithInviteScreenState();
}

class _RegisterWithInviteScreenState extends State<RegisterWithInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _repo = AuthRepository();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledEmail != null) {
      _emailCtrl.text = widget.prefilledEmail!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await _repo.registerWithInvite(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        fullName: _nameCtrl.text.trim(),
        invitationToken: _tokenCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
      );
      final token = await SecureTokenStorage.getAccessToken();
      if (token != null) ChatService.instance.connect(token);
      unawaited(PushTokenService.instance.registerForCurrentUser());
      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
        (route) => false,
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unexpected error: $e';
        _busy = false;
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
        title: Text('Register with invite',
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
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Welcome to DuttaMessenger',
                      style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    'Paste the invite token from your invitation email and pick '
                    'your password. Direct sign-up is disabled — only invited '
                    'users can join.',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: Colors.white60),
                  ),
                  const SizedBox(height: 22),
                  _Field(
                    label: 'Full name',
                    controller: _nameCtrl,
                    icon: Icons.badge_outlined,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Email (must match the invite)',
                    controller: _emailCtrl,
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Valid email required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Phone number (optional)',
                    controller: _phoneCtrl,
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Choose password',
                    controller: _passwordCtrl,
                    icon: Icons.lock_outline,
                    obscure: _obscure,
                    suffix: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Minimum 8 characters'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Invite token',
                    controller: _tokenCtrl,
                    icon: Icons.key_outlined,
                    helper:
                        'Paste the token from your invitation email or link.',
                    validator: (v) =>
                        (v == null || v.trim().length < 8) ? 'Required' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color:
                            const Color(0xFFFF4757).withValues(alpha: 0.15),
                        border: Border.all(
                            color: const Color(0xFFFF4757)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFFFF6B7A)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF667EEA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text('Create account & sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
    this.helper,
    this.validator,
  });
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final String? helper;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF667EEA), width: 1.5),
        ),
      ),
    );
  }
}
