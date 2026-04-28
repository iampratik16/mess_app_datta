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
import '../../../core/ui/app_theme.dart';

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
  Set<String> _onlineIds = {};

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
      // Best-effort online dot via /users/online — failure is silent.
      Set<String> online = const {};
      final ids = entries
          .map((e) => e.other?.id)
          .whereType<String>()
          .toList();
      if (ids.isNotEmpty) {
        try {
          online = await _usersApi.bulkOnlineStatus(ids);
        } on ApiError {
          online = const {};
        }
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _onlineIds = online;
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
      backgroundColor: kCream,
      appBar: CreamAppBar(
        title: 'Direct messages',
        subtitle: (!_loading && _error == null)
            ? '${_entries.length} ${_entries.length == 1 ? 'direct message' : 'direct messages'}'
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kAccentDeep),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        elevation: 2,
        tooltip: 'New message',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UsersScreen(me: widget.me)),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kCream, kCreamDeep],
          ),
        ),
        child: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: kAccentDeep));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: const Color(0xFFB94A33), fontSize: 13)),
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
              const Icon(Icons.chat_bubble_outline,
                  size: 56, color: kInkSubtle),
              const SizedBox(height: 14),
              Text(
                'No direct messages yet',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: kInkDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap the button below to find someone to message.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: kInkMuted),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: kAccentDeep,
      backgroundColor: kCream,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          thickness: 1,
          color: kHairline,
          indent: 84,
          endIndent: 16,
        ),
        itemBuilder: (ctx, i) {
          final entry = _entries[i];
          final isOnline = entry.other != null &&
              _onlineIds.contains(entry.other!.id);
          return _DmRow(
            entry: entry,
            isOnline: isOnline,
            onTap: () => _openEntry(entry),
          );
        },
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
  const _DmRow({
    required this.entry,
    required this.onTap,
    this.isOnline = false,
  });
  final _DmEntry entry;
  final VoidCallback onTap;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final name = entry.other?.fullName ?? 'Unknown user';
    final sub = entry.other?.email ?? entry.group.name;
    final initials = entry.other?.initials ?? '?';
    final avatarColor = avatarColorFor(name);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: kAccent.withValues(alpha: 0.08),
        highlightColor: kAccent.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatarColor,
                    ),
                    child: Text(
                      initials,
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kOnlineGreen,
                          border: Border.all(color: kCream, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kInkDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: kInkMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kInkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
