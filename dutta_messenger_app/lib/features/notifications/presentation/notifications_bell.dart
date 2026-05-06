import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../data/notifications_api.dart';

/// App-bar bell that polls /notifications/unread-count on init and on tap.
/// Tapping opens a cream-themed sheet with a "Mark all read" action.
/// Used inside the trailing actions slot of [CreamAppBar].
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
      // Best-effort: a stale count is fine.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSheet() async {
    await _fetch();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCreamCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: kHairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kAccent.withValues(alpha: 0.18),
                    ),
                    child: const Icon(Icons.notifications_active,
                        color: kAccentDeep, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Notifications',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kInkDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _unread == 0
                    ? "You're all caught up."
                    : '$_unread unread notification${_unread == 1 ? "" : "s"}.',
                style: GoogleFonts.inter(
                    color: kInkMuted, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 22),
              if (_unread > 0)
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
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
                    label: Text('Mark all read',
                        style:
                            GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  ),
                )
              else
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAccentDeep,
                      side: const BorderSide(color: kHairline, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Close',
                        style:
                            GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: kAccentDeep),
                )
              : const Icon(Icons.notifications_none, color: kAccentDeep),
          onPressed: _openSheet,
          tooltip: 'Notifications',
        ),
        if (_unread > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1.5),
              constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: kDangerInk,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kCream, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                _unread > 99 ? '99+' : '$_unread',
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
