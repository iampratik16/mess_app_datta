import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../data/media_api.dart';
import '../data/media_vault_store.dart';
import '../domain/media_models.dart';

/// Lets the user reattach existing vault items to a chat message
/// without re-uploading bytes. Multi-select; tap "Attach" to return
/// the chosen [MediaFile]s to the chat screen, which then sends one
/// chat message per item via `chat_api.sendMessage(mediaIds: …)`.
///
/// Source of truth is [MediaVaultStore.instance] — every upload from
/// the Media tab lands there immediately, so the picker stays in
/// sync without a network round-trip. The picker also calls the
/// best-effort `GET /media/` once on init, which is a no-op until
/// the backend deploys it.
///
/// Privacy: the backend `GET /media/` endpoint is uploader-scoped
/// (institution_id + uploader_id) so this picker can never surface
/// another user's media. A user cannot bypass this by guessing
/// UUIDs — `chat_api.sendMessage` re-validates ownership server-side
/// before accepting the share.
class MediaVaultPickerScreen extends StatefulWidget {
  const MediaVaultPickerScreen({super.key});

  @override
  State<MediaVaultPickerScreen> createState() => _MediaVaultPickerScreenState();
}

class _MediaVaultPickerScreenState extends State<MediaVaultPickerScreen> {
  final _api = MediaApi();
  MediaVaultStore get _store => MediaVaultStore.instance;

  String? _error;
  bool _refreshing = false;

  // Stored as ordered list so the user can see attach order matches
  // selection order, and so we can compose deterministic batch sends.
  final List<MediaFile> _selected = [];

  // Resolved presigned image URLs by media id. Filled lazily as the
  // user scrolls — never cached across screen rebuilds because GETs
  // expire in ~1 h (audit 5.5).
  final Map<String, String> _thumbUrls = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await _store.refreshFromServer(_api, force: true);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _toggle(MediaFile m) {
    setState(() {
      final idx = _selected.indexWhere((x) => x.id == m.id);
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(m);
      }
    });
  }

  Future<String?> _thumbUrl(MediaFile m) async {
    if (_thumbUrls.containsKey(m.id)) return _thumbUrls[m.id];
    try {
      final url = await _api.getDownloadUrl(m.id);
      if (!mounted) return null;
      setState(() => _thumbUrls[m.id] = url);
      return url;
    } on ApiError {
      return null;
    }
  }

  /// Confirm before throwing away an in-progress selection. If nothing
  /// is selected, just pop. The system back gesture and the AppBar
  /// back chevron both go through this so the behavior is uniform.
  Future<bool> _confirmCancel() async {
    if (_selected.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCreamCard,
        surfaceTintColor: kCreamCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: kHairline),
        ),
        title: Text(
          'Discard selection?',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: kInkDark,
          ),
        ),
        content: Text(
          '${_selected.length} item${_selected.length == 1 ? '' : 's'} '
          'selected. Going back now will not attach anything.',
          style: GoogleFonts.inter(fontSize: 13, color: kInkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: kInkMuted),
            child: const Text('Keep selecting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: kDangerInk,
              foregroundColor: Colors.white,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmCancel();
        if (!shouldPop) return;
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: ValueListenableBuilder<List<MediaFile>>(
        valueListenable: _store.items,
        builder: (_, items, _) => _buildScaffold(items),
      ),
    );
  }

  Widget _buildScaffold(List<MediaFile> items) {
    final selectedCount = _selected.length;
    return Scaffold(
      backgroundColor: kCream,
      appBar: CreamAppBar(
        title: 'Media vault',
        subtitle: selectedCount == 0
            ? '${items.length} ${items.length == 1 ? 'item' : 'items'}'
            : '$selectedCount selected',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kAccentDeep),
            onPressed: _refreshing ? null : _refresh,
            tooltip: 'Refresh',
          ),
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).pop<List<MediaFile>>(_selected),
                style: TextButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  'Attach ($selectedCount)',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(top: false, child: _buildBody(items)),
      ),
    );
  }

  Widget _buildBody(List<MediaFile> items) {
    if (_error != null && items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: kInkSubtle, size: 36),
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 13, color: kDangerInk)),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 48, color: kInkSubtle),
              const SizedBox(height: 12),
              Text(
                'Your vault is empty.',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  color: kInkDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Files you upload from the Media tab show up here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: kInkMuted),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final m = items[i];
        final selectedIdx = _selected.indexWhere((x) => x.id == m.id);
        return _VaultTile(
          media: m,
          selectedIndex: selectedIdx >= 0 ? selectedIdx + 1 : null,
          thumbUrlFuture: m.isImage ? _thumbUrl(m) : null,
          onTap: () => _toggle(m),
        );
      },
    );
  }
}

class _VaultTile extends StatelessWidget {
  const _VaultTile({
    required this.media,
    required this.selectedIndex,
    required this.thumbUrlFuture,
    required this.onTap,
  });

  final MediaFile media;
  final int? selectedIndex;
  final Future<String?>? thumbUrlFuture;
  final VoidCallback onTap;

  bool get _selected => selectedIndex != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPreview(),
            // Bottom name strip — readable on both image + icon previews.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.62),
                    ],
                  ),
                ),
                child: Text(
                  media.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (_selected)
              Container(
                color: kAccent.withValues(alpha: 0.25),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selected
                      ? kAccent
                      : Colors.black.withValues(alpha: 0.40),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: _selected
                    ? Text(
                        '$selectedIndex',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (media.isImage && thumbUrlFuture != null) {
      return FutureBuilder<String?>(
        future: thumbUrlFuture,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return _iconBox();
          final url = snap.data;
          if (url == null) return _iconBox();
          return Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _iconBox(),
          );
        },
      );
    }
    return _iconBox();
  }

  Widget _iconBox() {
    return Container(
      color: kCreamCard,
      alignment: Alignment.center,
      child: Icon(
        _iconFor(media),
        color: kAccentDeep,
        size: 36,
      ),
    );
  }

  IconData _iconFor(MediaFile m) {
    if (m.isImage) return Icons.image_outlined;
    if (m.isVideo) return Icons.videocam_outlined;
    if (m.isAudio) return Icons.audiotrack_outlined;
    return Icons.insert_drive_file_outlined;
  }
}
