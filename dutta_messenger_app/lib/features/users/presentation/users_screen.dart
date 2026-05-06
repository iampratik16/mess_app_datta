import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/errors/api_error.dart';
import '../../auth/domain/auth_models.dart';
import '../../chat/domain/chat_type.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../dm/data/dm_repository.dart';
import '../../notifications/presentation/notifications_bell.dart';
import '../data/users_api.dart';
import '../domain/user_models.dart';
import '../../../core/ui/app_theme.dart';

/// Directory of users in the current institution. Search-as-you-type
/// hits /api/v1/users/search; clears back to a gentle empty state when
/// the query is under 2 characters.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.me});
  final AuthUser me;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _api = UsersApi();
  final _dm = DmRepository();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  bool _opening = false;
  String? _error;
  List<UserProfile> _results = [];
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    // Prime the list with a common-letter search so the screen isn't empty.
    _runSearch('a');
  }

  Future<void> _openDm(UserProfile target) async {
    if (target.id == widget.me.id) return;
    setState(() => _opening = true);
    try {
      final group = await _dm.openDm(meId: widget.me.id, otherId: target.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            groupId: group.id,
            groupName: target.fullName ?? target.email ?? 'Direct message',
            me: widget.me,
            chatType: ChatType.dm,
            peer: target,
          ),
        ),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open DM: ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    _lastQuery = q;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _api.search(q);
      if (!mounted || _lastQuery != q) return;
      // Overlay live online status. /users/search doesn't include it, so
      // ask /users/online separately and merge. Failure is ignored —
      // online dot is best-effort.
      try {
        final online = await _api.bulkOnlineStatus(results.map((u) => u.id));
        if (!mounted || _lastQuery != q) return;
        setState(() {
          _results = results
              .map((u) => UserProfile(
                    id: u.id,
                    fullName: u.fullName,
                    email: u.email,
                    avatarUrl: u.avatarUrl,
                    bio: u.bio,
                    status: u.status,
                    isOnline: online.contains(u.id) || u.isOnline,
                    lastSeenAt: u.lastSeenAt,
                  ))
              .toList();
          _loading = false;
        });
      } on ApiError {
        if (!mounted || _lastQuery != q) return;
        setState(() {
          _results = results;
          _loading = false;
        });
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message}';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: const CreamAppBar(
        title: 'People',
        actions: [NotificationsBell()],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kCream, kCreamDeep],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildSearchBar(),
              Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onQueryChanged,
        cursorColor: kAccentDeep,
        style: GoogleFonts.inter(color: kInkDark, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search name or email',
          hintStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: kInkSubtle),
          filled: true,
          fillColor: kCreamField,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: kHairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: kAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _results.isEmpty) {
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
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searchCtrl.text.trim().isEmpty
              ? 'Type a name or email to search'
              : 'No users match',
          style: GoogleFonts.inter(color: kInkMuted, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        thickness: 1,
        color: kHairline,
        indent: 84,
        endIndent: 16,
      ),
      itemBuilder: (ctx, i) {
        final u = _results[i];
        final isMe = u.id == widget.me.id;
        return _UserTile(
          user: u,
          isMe: isMe,
          onTap: (isMe || _opening) ? null : () => _openDm(u),
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.isMe,
    required this.onTap,
  });
  final UserProfile user;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final displayName = user.fullName ?? '(no name)';
    final avatarColor = avatarColorFor(displayName);
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
                      user.initials,
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (user.isOnline)
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
                      displayName,
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
                      user.email ?? user.id,
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
              if (isMe)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: kAccent.withValues(alpha: 0.15),
                    border: Border.all(
                      color: kAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'YOU',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kAccentDeep,
                      letterSpacing: 0.8,
                    ),
                  ),
                )
              else
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kAccent.withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.chat_bubble_outline,
                      color: kAccentDeep, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
