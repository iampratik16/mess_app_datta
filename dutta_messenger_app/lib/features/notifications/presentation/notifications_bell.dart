import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/errors/api_error.dart';
import '../data/notifications_api.dart';

/// App-bar bell that polls /notifications/unread-count on init and on tap.
/// Tapping opens a bottom sheet with a "Mark all read" action.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key});

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> {
  final _api = NotificationsApi();
  int _unread = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final n = await _api.unreadCount();
      if (!mounted) return;
      setState(() => _unread = n);
    } on ApiError {
      // swallow — count is best-effort
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSheet() async {
    await _fetch();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1B3A),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: Color(0xFF8A9CF5)),
                const SizedBox(width: 10),
                Text(
                  'Notifications',
                  style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _unread == 0
                  ? "You're all caught up."
                  : '$_unread unread notification${_unread == 1 ? "" : "s"}.',
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (_unread > 0)
              FilledButton.icon(
                onPressed: () async {
                  final marked = await _api.markAllRead();
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  setState(() => _unread = 0);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text('Marked $marked as read'),
                    ),
                  );
                },
                icon: const Icon(Icons.done_all),
                label: const Text('Mark all read'),
              )
            else
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white70))
              : const Icon(Icons.notifications_none),
          onPressed: _openSheet,
          tooltip: 'Notifications',
        ),
        if (_unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              constraints:
                  const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4757),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF0F0C29), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                _unread > 99 ? '99+' : '$_unread',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
