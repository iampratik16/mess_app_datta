import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../data/auth_api.dart';

/// POST /api/v1/auth/institutions — multi-tenant bootstrap. Creates a new
/// institution row only; does not create a user. After this returns, an
/// admin must invite the first user from a separately-provisioned account.
class CreateInstitutionScreen extends StatefulWidget {
  const CreateInstitutionScreen({super.key});

  @override
  State<CreateInstitutionScreen> createState() =>
      _CreateInstitutionScreenState();
}

class _CreateInstitutionScreenState extends State<CreateInstitutionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _domainCtrl = TextEditingController();
  final _maxUsersCtrl = TextEditingController(text: '50');
  final _maxGroupsCtrl = TextEditingController(text: '20');
  final _api = AuthApi();

  String _tier = 'free';
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _created;

  static const _tiers = ['free', 'pro', 'enterprise'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _domainCtrl.dispose();
    _maxUsersCtrl.dispose();
    _maxGroupsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _api.createInstitution(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        domain: _domainCtrl.text.trim(),
        subscriptionTier: _tier,
        maxUsers: int.tryParse(_maxUsersCtrl.text.trim()) ?? 50,
        maxGroups: int.tryParse(_maxGroupsCtrl.text.trim()) ?? 20,
      );
      if (!mounted) return;
      setState(() {
        _created = res;
        _busy = false;
      });
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
        title: Text('Create institution',
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
            child: _created != null
                ? _SuccessCard(
                    institution: _created!,
                    onClose: () => Navigator.pop(context),
                  )
                : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bootstrap a new tenant',
              style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'Each institution is fully isolated. After creation an admin '
            'with seeded credentials can sign in and start inviting users.',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
          ),
          const SizedBox(height: 22),
          _Field(
            label: 'Institution name',
            controller: _nameCtrl,
            icon: Icons.business_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          _Field(
            label: 'Description (optional)',
            controller: _descCtrl,
            icon: Icons.notes_outlined,
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          _Field(
            label: 'Email domain (optional, e.g. acme.com)',
            controller: _domainCtrl,
            icon: Icons.alternate_email,
          ),
          const SizedBox(height: 18),
          Text('Subscription tier',
              style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _tiers.map((t) {
              final selected = t == _tier;
              return ChoiceChip(
                label: Text(t),
                selected: selected,
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  color: selected ? Colors.white : Colors.white70,
                ),
                selectedColor: const Color(0xFF667EEA),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                onSelected: (_) => setState(() => _tier = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'Max users',
                  controller: _maxUsersCtrl,
                  icon: Icons.group_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1) return 'Min 1';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(
                  label: 'Max groups',
                  controller: _maxGroupsCtrl,
                  icon: Icons.groups_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1) return 'Min 1';
                    return null;
                  },
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFFFF4757).withValues(alpha: 0.15),
                border: Border.all(
                    color:
                        const Color(0xFFFF4757).withValues(alpha: 0.3)),
              ),
              child: Text(
                _error!,
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFFFF6B7A)),
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
                  : const Text('Create institution'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.institution, required this.onClose});
  final Map<String, dynamic> institution;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final id = institution['id']?.toString() ?? '?';
    final name = institution['name']?.toString() ?? '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF2ED573), Color(0xFF27AE60)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Text('Institution created',
                      style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
              const SizedBox(height: 10),
              Text(name,
                  style: GoogleFonts.inter(
                      fontSize: 14, color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Institution ID',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 4),
              SelectableText(id,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 12, color: Colors.white)),
              const SizedBox(height: 14),
              Text(
                'Next steps: an admin user must be seeded server-side, then '
                'sign in here and invite the first members from the home '
                'screen.',
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.white60),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: onClose,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
            ),
            child: const Text('Back to sign in'),
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
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
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
