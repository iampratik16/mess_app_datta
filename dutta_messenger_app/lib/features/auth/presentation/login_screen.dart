import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/auth_repository.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/config/app_config.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/ui/app_theme.dart';
import '../../../services/chat_service.dart';
import '../../../services/push_token_service.dart';
import '../../home/presentation/home_screen.dart';
import 'create_institution_screen.dart';
import 'register_with_invite_screen.dart';

/// Premium login screen for DuttaMessenger.
/// Integrates with the backend via AuthRepository.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController =
      TextEditingController(text: AppConfig.defaultLoginEmail);
  final _passwordController =
      TextEditingController(text: AppConfig.defaultLoginPassword);
  final _repo = AuthRepository();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _repo.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Open the persistent WS connection for this user.
      // One socket per logged-in user; survives screen changes until logout.
      final token = await SecureTokenStorage.getAccessToken();
      if (token != null) ChatService.instance.connect(token);
      // Best-effort FCM registration. Runs in background — no UI block.
      // Errors and the no-Firebase-config case are surfaced via Settings.
      unawaited(PushTokenService.instance.registerForCurrentUser());
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
      );
    } on ApiError catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kCream, kCreamDeep],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 24),
                        _buildLogo(),
                        const SizedBox(height: 32),
                        _buildLoginCard(),
                        const SizedBox(height: 18),
                        _buildAlternateActions(),
                        const SizedBox(height: 14),
                        _buildServerInfo(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kAccent.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/datta_uni_logo.jpg',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'DuttaMessenger',
          style: GoogleFonts.playfairDisplay(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: kInkDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Private Institutional Messaging',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: kInkMuted,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: kCreamCard,
        border: Border.all(color: kHairline),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6B4A22).withValues(alpha: 0.06),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sign In',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: kInkDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter your credentials to access the platform',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: kInkMuted,
                ),
              ),
              const SizedBox(height: 22),

              // Email field
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                validator: (v) =>
                    v == null || !v.contains('@') ? 'Valid email required' : null,
              ),
              const SizedBox(height: 14),

              // Password field
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline,
                obscure: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: kInkSubtle,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) =>
                    v == null || v.length < 6 ? 'Min 6 characters' : null,
              ),

              // Error message
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFFE07260).withValues(alpha: 0.10),
                    border: Border.all(
                      color: const Color(0xFFE07260).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFB94A33), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFFB94A33),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 22),

              // Login button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    disabledBackgroundColor: kAccent.withValues(alpha: 0.55),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                    shadowColor: kAccentDeep,
                  ).copyWith(
                    overlayColor: WidgetStateProperty.all(
                      kAccentDeep.withValues(alpha: 0.15),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Sign In',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      cursorColor: kAccentDeep,
      style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 13),
        floatingLabelStyle:
            GoogleFonts.inter(color: kAccentDeep, fontSize: 13),
        prefixIcon: Icon(icon, color: kInkSubtle, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: kCreamField,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kHairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kHairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB94A33)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB94A33), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildAlternateActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.mark_email_read_outlined,
              size: 18, color: kAccentDeep),
          label: Text(
            'Have an invite?',
            style: GoogleFonts.inter(
              color: kAccentDeep,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RegisterWithInviteScreen(
                prefilledEmail: _emailController.text.trim().isEmpty
                    ? null
                    : _emailController.text.trim(),
              ),
            ),
          ),
        ),
        Container(
          width: 1,
          height: 14,
          color: kHairline,
        ),
        TextButton.icon(
          icon: const Icon(Icons.business_outlined,
              size: 18, color: kAccentDeep),
          label: Text(
            'Create institution',
            style: GoogleFonts.inter(
              color: kAccentDeep,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const CreateInstitutionScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildServerInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        'Connected to: ${AppConfig.apiBaseUrl}',
        textAlign: TextAlign.center,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          color: kInkSubtle.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
