import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/errors/api_error.dart';
import '../../auth/domain/auth_models.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../groups/domain/group_models.dart';
import '../../users/data/users_api.dart';
import '../../users/domain/user_models.dart';
import '../../users/presentation/users_screen.dart';
import '../data/dm_repository.dart';

/// Lists the caller's direct-message conversations. Each row shows the
/// *other* party — we resolve their profile via /users/{id}. Tapping a row
/// opens the chat; the FAB jumps to People to start a new DM.
class DmListScreen extends StatefulWidget {
  const DmListScreen({super.key, required this.me});
  final AuthUser me;

  @override
  State<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends State<DmListScreen> {
  final _dm = DmRepository();
  final _usersApi = UsersApi();
  bool _loading = true;
  String? _error;
  List<_DmEntry> _entries = [];

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
      final groups = await _dm.listDmGroups();
      final entries = await Future.wait(groups.map((g) async {
        final otherId = DmRepository.otherUserId(g, widget.me.id);
        UserProfile? other;
        if (otherId != null) {
          try {
            other = await _usersApi.getById(otherId);
          } on ApiError {
            other = null;
          }
        }
        return _DmEntry(group: g, other: other);
      }));
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message}';
        _loading = false;
      });
    }
  }

  void _openEntry(_DmEntry e) {
    final title = e.other?.fullName ?? e.other?.email ?? 'Direct message';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          groupId: e.group.id,
          groupName: title,
          me: widget.me,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Direct messages',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF667EEA),
        icon: const Icon(Icons.edit, color: Colors.white),
        label: const Text('New message',
            style: TextStyle(color: Colors.white)),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UsersScreen(me: widget.me)),
        ),
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
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: const Color(0xFFFF6B7A), fontSize: 13)),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 48, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text('No direct messages yet',
                  style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70)),
              const SizedBox(height: 6),
              Text(
                "Tap the button below to find someone to message.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF667EEA),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _DmRow(
          entry: _entries[i],
          onTap: () => _openEntry(_entries[i]),
        ),
      ),
    );
  }
}

class _DmEntry {
  const _DmEntry({required this.group, required this.other});
  final Group group;
  final UserProfile? other;
}

class _DmRow extends StatelessWidget {
  const _DmRow({required this.entry, required this.onTap});
  final _DmEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = entry.other?.fullName ?? 'Unknown user';
    final sub = entry.other?.email ?? entry.group.name;
    final initials = entry.other?.initials ?? '?';
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
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                ),
                child: Text(
                  initials,
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.white54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
