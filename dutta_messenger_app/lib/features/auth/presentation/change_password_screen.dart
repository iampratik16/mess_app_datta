import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../data/auth_api.dart';

/// Form that POSTs /auth/change-password. Requires the current password
/// so that a leaked session token alone cannot change credentials.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _api = AuthApi();

  bool _saving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await _api.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _success = 'Password updated.';
        _saving = false;
        _currentCtrl.clear();
        _newCtrl.clear();
        _confirmCtrl.clear();
      });
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
    return Scaffold(
      backgroundColor: kCream,
      appBar: const CreamAppBar(title: 'Change password'),
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CreamInfoBanner(
                    text: TextSpan(
                      children: [
                        TextSpan(text: 'Changing your password '),
                        TextSpan(
                          text: 'signs you out everywhere else',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: ". You'll need to sign in again on other "
                              'devices.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const CreamFieldLabel(label: 'Current password'),
                  const SizedBox(height: 8),
                  _PasswordField(
                    controller: _currentCtrl,
                    obscure: _obscureCurrent,
                    onToggle: () => setState(
                        () => _obscureCurrent = !_obscureCurrent),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 18),
                  CreamFieldLabel(
                    label: 'New password',
                    trailing: Text(
                      'Minimum 8 characters',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: kInkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PasswordField(
                    controller: _newCtrl,
                    obscure: _obscureNew,
                    onToggle: () =>
                        setState(() => _obscureNew = !_obscureNew),
                    validator: (v) {
                      if (v == null || v.length < 8) {
                        return 'Minimum 8 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const CreamFieldLabel(label: 'Confirm new password'),
                  const SizedBox(height: 8),
                  _PasswordField(
                    controller: _confirmCtrl,
                    obscure: _obscureConfirm,
                    onToggle: () => setState(
                        () => _obscureConfirm = !_obscureConfirm),
                    validator: (v) =>
                        v != _newCtrl.text ? "Doesn't match" : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        style:
                            GoogleFonts.inter(color: kDangerInk, fontSize: 13)),
                  ],
                  if (_success != null) ...[
                    const SizedBox(height: 14),
                    Text(_success!,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF3F7A4F),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            kAccent.withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.4),
                            )
                          : Text(
                              'Update password',
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
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
    required this.validator,
  });
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6B4A22).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        validator: validator,
        obscureText: obscure,
        cursorColor: kAccentDeep,
        style: GoogleFonts.inter(
          color: kInkDark,
          fontSize: 16,
          letterSpacing: 1.2,
        ),
        decoration: creamInputDecoration(
          fillColor: Colors.white,
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              color: kInkSubtle,
            ),
            onPressed: onToggle,
          ),
        ).copyWith(
          // Inputs in the reference are tall, white, label-less — the
          // section header above stands in for the floating label.
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
