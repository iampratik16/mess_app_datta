import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Warm cream / amber palette shared across every screen of the app.
const kCream = Color(0xFFF6ECE0);
const kCreamDeep = Color(0xFFEFE2D2);
const kCreamCard = Color(0xFFFBF3E7);
const kCreamField = Color(0xFFFFFBF4);
const kInkDark = Color(0xFF2A2520);
const kInkMuted = Color(0xFF6B5B4F);
const kInkSubtle = Color(0xFF8C7A6B);
const kAccent = Color(0xFFC8843D);
const kAccentDeep = Color(0xFFB47230);
const kHairline = Color(0xFFE3D3BD);
const kOnlineGreen = Color(0xFF6BAE5E);
const kDangerInk = Color(0xFFB94A33);
const kDangerBg = Color(0xFFE07260);

const kAvatarPalette = <Color>[
  Color(0xFFB85C46), // terracotta
  Color(0xFFC8843D), // amber
  Color(0xFF4F6E7B), // dusty teal
  Color(0xFF8B6F3F), // bronze
  Color(0xFFA8794D), // tan
  Color(0xFF7A5C8A), // muted plum
  Color(0xFF5C7A5C), // sage
  Color(0xFFB8923D), // gold
];

/// Deterministic warm avatar color picked by the first character of [seed].
Color avatarColorFor(String seed) {
  if (seed.isEmpty) return kAvatarPalette[0];
  return kAvatarPalette[seed.codeUnitAt(0) % kAvatarPalette.length];
}

/// Solid warm-toned circular avatar with serif initials and an optional
/// green online dot. Reused on every list screen with people in it.
class CreamAvatar extends StatelessWidget {
  const CreamAvatar({
    super.key,
    required this.seed,
    required this.initials,
    this.size = 52,
    this.online = false,
    this.ringColor = kCream,
  });

  final String seed;
  final String initials;
  final double size;
  final bool online;

  /// Color the online ring sits against (so it cleanly punches through
  /// whatever background the avatar appears on).
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarColorFor(seed),
            ),
            child: Text(
              initials,
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kOnlineGreen,
                  border: Border.all(color: ringColor, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Soft cream gradient that every full-screen `body` Container uses.
const kCreamBackgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kCream, kCreamDeep],
);

/// Standard divider used between list rows on cream backgrounds.
/// Indented past the leading 16-px gutter + 52-px avatar + 14-px spacer.
const kListDivider = Divider(
  height: 1,
  thickness: 1,
  color: kHairline,
  indent: 84,
  endIndent: 16,
);

/// Soft rounded-square cream tile with a centered glyph (text or emoji).
/// Used as the leading avatar for topic / channel rows where a # or
/// emoji is the natural identifier rather than initials.
class CreamSquareAvatar extends StatelessWidget {
  const CreamSquareAvatar({
    super.key,
    required this.glyph,
    this.size = 52,
    this.glyphFontSize,
  });

  final String glyph;
  final double size;
  final double? glyphFontSize;

  @override
  Widget build(BuildContext context) {
    final isEmoji = glyph.runes.any((r) => r > 0x1000);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kCreamCard,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: kHairline),
      ),
      child: Text(
        glyph,
        style: isEmoji
            ? TextStyle(fontSize: glyphFontSize ?? size * 0.48)
            : GoogleFonts.inter(
                fontSize: glyphFontSize ?? size * 0.42,
                fontWeight: FontWeight.w700,
                color: kInkDark,
              ),
      ),
    );
  }
}

/// Compact pill used for state labels like "default", "read-only".
class CreamTag extends StatelessWidget {
  const CreamTag({
    super.key,
    required this.label,
    this.tone = CreamTagTone.muted,
  });

  final String label;
  final CreamTagTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      CreamTagTone.muted => (kHairline, kInkMuted),
      CreamTagTone.accent => (kAccent.withValues(alpha: 0.15), kAccentDeep),
      CreamTagTone.info => (
          const Color(0xFF4F6E7B).withValues(alpha: 0.18),
          const Color(0xFF3A5460),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

enum CreamTagTone { muted, accent, info }

/// Horizontal filter chip row with one selected entry. The active chip is
/// dark-filled (kInkDark) with cream text, inactive chips are white pills
/// with a hairline border. Used on screens like Media to switch between
/// All / Images / Videos / Files.
class CreamFilterChips<T> extends StatelessWidget {
  const CreamFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          for (final o in options) ...[
            _CreamFilterChip(
              label: o.label,
              selected: o.value == selected,
              onTap: () => onChanged(o.value),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _CreamFilterChip extends StatelessWidget {
  const _CreamFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kInkDark : Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected ? kInkDark : kHairline,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? kCream : kInkDark,
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard input decoration for cream-themed text fields. Centralises
/// label / fill / border styling so every form across the app can share
/// the same look without re-declaring it.
InputDecoration creamInputDecoration({
  String? label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  Color? fillColor,
}) {
  return InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 13),
    floatingLabelStyle: GoogleFonts.inter(color: kAccentDeep, fontSize: 13),
    hintText: hint,
    hintStyle: GoogleFonts.inter(color: kInkSubtle, fontSize: 14),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: fillColor ?? kCreamField,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kHairline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kAccent, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kDangerInk),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kDangerInk, width: 1.5),
    ),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

/// Small all-caps section label used above form fields and section
/// groupings. Optional [trailing] sits on the right side (e.g. a hint
/// like "Minimum 8 characters").
class CreamFieldLabel extends StatelessWidget {
  const CreamFieldLabel({super.key, required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: kInkMuted,
            letterSpacing: 1.6,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// Amber-tinted info banner with a leading icon and rich text body.
/// Used to surface short, important notices above forms (e.g. "Changing
/// your password signs you out everywhere else").
class CreamInfoBanner extends StatelessWidget {
  const CreamInfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
  });

  final InlineSpan text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kAccentDeep, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              text,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: kInkDark,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Telegram-style three-pill header with frosted-glass pills sitting on
/// the page background. Uses backdrop blur + translucent cream fills +
/// hairline white borders so it matches the rest of the app's palette.
///
/// Layout (left → right):
///   [ back-pill ]  [ title + subtitle pill — expanded ]  [ actions pill? ]  [ avatar circle? ]
///
/// - Back pill is auto-omitted on root routes that can't pop.
/// - Tapping the avatar fires [onAvatarTap] (e.g. open members on chat).
class CreamAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CreamAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingAvatar,
    this.onAvatarTap,
    this.onTitleTap,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  final String title;
  final String? subtitle;

  /// Small widget shown as a glass circle on the right edge of the header
  /// — typically a [CreamAvatar] for the conversation/group face.
  final Widget? leadingAvatar;

  /// Tap handler for [leadingAvatar]. Optional; if null the avatar is not
  /// interactive.
  final VoidCallback? onAvatarTap;

  /// Tap handler for the title/subtitle area. Used by chat headers to open
  /// a peer-info sheet on DM screens. If null the area is inert.
  final VoidCallback? onTitleTap;

  /// Trailing icon-button actions packaged into one glass pill that sits
  /// between the title pill and the avatar.
  final List<Widget>? actions;

  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => const Size.fromHeight(108);

  @override
  Widget build(BuildContext context) {
    final canPop =
        automaticallyImplyLeading && Navigator.of(context).canPop();
    final hasActions = actions != null && actions!.isNotEmpty;
    final hasAvatar = leadingAvatar != null;

    return Container(
      // The pills are glass — paint the same gradient behind them so the
      // backdrop blur has something gradient-like to soften.
      decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                if (canPop) ...[
                  _GlassPill(
                    onTap: () => Navigator.of(context).maybePop(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: kInkDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTitleTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kInkDark,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: kInkMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (hasActions) ...[
                  const SizedBox(width: 8),
                  _GlassPill(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions!,
                    ),
                  ),
                ],
                if (hasAvatar) ...[
                  const SizedBox(width: 8),
                  _GlassCircle(
                    onTap: onAvatarTap,
                    child: leadingAvatar!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable frosted-glass pill: backdrop blur + translucent cream fill +
/// hairline highlight. Used by [CreamAppBar] for back / title / actions.
class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.child,
    this.onTap,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: kCreamCard.withValues(alpha: 0.78),
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              padding: padding,
              child: Center(
                heightFactor: 1,
                widthFactor: 1,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted-glass circle for the avatar slot in [CreamAppBar].
class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: kCreamCard.withValues(alpha: 0.45),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
