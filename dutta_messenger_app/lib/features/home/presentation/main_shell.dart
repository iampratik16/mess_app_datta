import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/ui/app_theme.dart';
import '../../auth/domain/auth_models.dart';
import '../../dm/presentation/dm_list_screen.dart';
import '../../groups/presentation/groups_screen.dart';
import '../../media/presentation/media_screen.dart';
import '../../users/presentation/profile_screen.dart';
import '../../users/presentation/users_screen.dart';

/// Root tab shell used as the post-sign-in landing surface. Lands on
/// "Chats" (Direct messages) and surfaces Groups / People / Media /
/// Profile through a floating glassmorphism nav at the bottom.
///
/// Each tab keeps its own Scaffold + AppBar; the shell only owns the
/// bottom nav, the IndexedStack, and the cream backdrop. Sub-screens
/// pushed from a tab (e.g. Chat from Chats) overlay the nav by virtue
/// of being pushed onto the Navigator stack above the shell.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.user});
  final AuthUser user;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps each tab alive across switches so list state +
    // WS streams aren't reset when the user nav-toggles.
    final tabs = <Widget>[
      DmListScreen(me: widget.user),
      GroupsScreen(me: widget.user),
      UsersScreen(me: widget.user),
      const MediaScreen(),
      ProfileScreen(me: widget.user),
    ];

    return Scaffold(
      backgroundColor: kCream,
      extendBody: true,
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: _GlassBottomNav(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Floating glass pill nav. Backdrop blur over a translucent ink-dark
/// surface with rounded ends; active item gets a solid amber chip behind
/// the icon and an amber label. Matches the reference at the top of the
/// shell screen — recoloured for the cream theme.
class _GlassBottomNav extends StatelessWidget {
  const _GlassBottomNav({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (icon: Icons.chat_bubble_outline, label: 'Chats'),
    (icon: Icons.groups_outlined, label: 'Groups'),
    (icon: Icons.people_alt_outlined, label: 'People'),
    (icon: Icons.cloud_outlined, label: 'Media'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            // Warm bronze glass: a translucent amber-tinted dark with
            // a top-edge highlight so the pill catches a subtle gleam.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC7A604A),
                Color(0xE03A2D24),
              ],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 28,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_items.length, (i) {
                  final item = _items[i];
                  return _NavItem(
                    icon: item.icon,
                    label: item.label,
                    selected: i == index,
                    onTap: () => onChanged(i),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = kCream.withValues(alpha: 0.78);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  // Active pill: amber gradient with a top highlight so it
                  // reads as raised glass, plus a soft amber glow shadow.
                  gradient: selected
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFE29A4D), kAccentDeep],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: kAccent.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? Colors.white : inactive,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : inactive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
