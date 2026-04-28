import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/ui/app_theme.dart';
import '../data/media_api.dart';
import '../data/media_uploader.dart';
import '../domain/media_models.dart';

enum _MediaFilter { all, images, videos, files }

/// Upload-and-manage view for the media module. Covers the shippable
/// portion of `docs/ui-contract/media.md` §"Minimum 'attach file to
/// message' implementation".
class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  final _api = MediaApi();
  final _uploader = MediaUploader();
  final _imagePicker = ImagePicker();

  final List<MediaFile> _uploads = []; // session-local; no list endpoint yet

  _UploadTask? _active;
  String? _error;
  _MediaFilter _filter = _MediaFilter.all;

  Future<void> _pickFromGallery() async {
    try {
      final xfile = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      await _upload(File(xfile.path),
          nameOverride: xfile.name, mimeHint: xfile.mimeType);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open gallery: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final xfile = await _imagePicker.pickImage(source: ImageSource.camera);
      if (xfile == null) return;
      await _upload(File(xfile.path),
          nameOverride: xfile.name, mimeHint: xfile.mimeType);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open camera: $e');
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final xfile =
          await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (xfile == null) return;
      await _upload(File(xfile.path),
          nameOverride: xfile.name, mimeHint: xfile.mimeType);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open video library: $e');
    }
  }

  Future<void> _recordVideo() async {
    try {
      final xfile = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (xfile == null) return;
      await _upload(File(xfile.path),
          nameOverride: xfile.name, mimeHint: xfile.mimeType);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not record video: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      final path = res?.files.single.path;
      if (path == null) return;
      await _upload(File(path), nameOverride: res!.files.single.name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open file picker: $e');
    }
  }

  Future<void> _upload(File file,
      {String? nameOverride, String? mimeHint}) async {
    final name = nameOverride ?? file.uri.pathSegments.last;
    setState(() {
      _error = null;
      _active = _UploadTask(name: name);
    });
    try {
      final media = await _uploader.upload(
        file: file,
        fileName: nameOverride,
        mimeType: mimeHint,
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() {
            _active = _UploadTask(
              name: name,
              sentBytes: sent,
              totalBytes: total,
            );
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _uploads.insert(0, media);
        _active = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Uploaded ${media.fileName}'),
        ),
      );
    } on MediaUploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _active = null;
        _error = e.message;
      });
    }
  }

  Future<void> _delete(MediaFile m) async {
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
          'Delete ${m.fileName}?',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.playfairDisplay(
            color: kInkDark,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'The file moves to the recycle bin for 30 days, then is '
          'permanently deleted.',
          style: GoogleFonts.inter(color: kInkMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: kInkMuted),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: kDangerInk,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteMedia(m.id);
      if (!mounted) return;
      setState(() => _uploads.removeWhere((x) => x.id == m.id));
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kDangerInk,
          content: Text('Delete failed: ${e.message}'),
        ),
      );
    }
  }

  Future<void> _preview(MediaFile m) async {
    try {
      final url = await _api.getDownloadUrl(m.id);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _MediaPreviewScreen(media: m, downloadUrl: url),
      ));
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kDangerInk,
          content: Text('Preview failed: ${e.message}'),
        ),
      );
    }
  }

  void _showPickerSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCreamCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: kHairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _PickerTile(
                icon: Icons.photo_library_outlined,
                label: 'Photo library',
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
              _PickerTile(
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
              _PickerTile(
                icon: Icons.video_library_outlined,
                label: 'Video library',
                onTap: () {
                  Navigator.pop(context);
                  _pickVideoFromGallery();
                },
              ),
              _PickerTile(
                icon: Icons.videocam_outlined,
                label: 'Record a video',
                onTap: () {
                  Navigator.pop(context);
                  _recordVideo();
                },
              ),
              _PickerTile(
                icon: Icons.insert_drive_file_outlined,
                label: 'File (PDF, DOC, …)',
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MediaFile> get _filtered {
    return switch (_filter) {
      _MediaFilter.all => _uploads,
      _MediaFilter.images => _uploads.where((m) => m.isImage).toList(),
      _MediaFilter.videos => _uploads.where((m) => m.isVideo).toList(),
      _MediaFilter.files => _uploads
          .where((m) => !m.isImage && !m.isVideo && !m.isAudio)
          .toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final uploading = _active != null;
    return Scaffold(
      backgroundColor: kCream,
      appBar: const CreamAppBar(
        title: 'Media',
        subtitle: 'Shared in your institution',
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: uploading ? null : _showPickerSheet,
        icon: const Icon(Icons.upload_file),
        label: Text('Upload',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kCreamBackgroundGradient),
        child: SafeArea(top: false, child: _buildBody(uploading)),
      ),
    );
  }

  Widget _buildBody(bool uploading) {
    return Column(
      children: [
        const SizedBox(height: 4),
        CreamFilterChips<_MediaFilter>(
          options: const [
            (value: _MediaFilter.all, label: 'All'),
            (value: _MediaFilter.images, label: 'Images'),
            (value: _MediaFilter.videos, label: 'Videos'),
            (value: _MediaFilter.files, label: 'Files'),
          ],
          selected: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
        if (uploading) _ActiveUploadCard(task: _active!),
        if (_error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kDangerBg.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kDangerBg.withValues(alpha: 0.40)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: kDangerInk, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: kDangerInk)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: kDangerInk),
                onPressed: () => setState(() => _error = null),
              ),
            ]),
          ),
        Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildGrid() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_upload_outlined,
                  size: 56, color: kInkSubtle),
              const SizedBox(height: 14),
              Text('No uploads yet',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kInkDark)),
              const SizedBox(height: 6),
              Text(
                'Tap Upload to pick an image, photo, or file. '
                'Images up to 10 MB, documents up to 50 MB.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: kInkMuted),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final m = items[i];
        return _MediaTile(
          media: m,
          api: _api,
          onTap: () => _preview(m),
          onLongPress: () => _delete(m),
        );
      },
    );
  }
}

/// In-flight upload progress card.
class _UploadTask {
  const _UploadTask({
    required this.name,
    this.sentBytes = 0,
    this.totalBytes = 0,
  });
  final String name;
  final int sentBytes;
  final int totalBytes;

  double? get fraction =>
      totalBytes > 0 ? (sentBytes / totalBytes).clamp(0.0, 1.0) : null;
}

class _ActiveUploadCard extends StatelessWidget {
  const _ActiveUploadCard({required this.task});
  final _UploadTask task;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: kCreamCard,
        border: Border.all(color: kHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.cloud_upload, color: kAccentDeep, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Uploading ${task.name}',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kInkDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (task.fraction != null)
              Text('${(task.fraction! * 100).round()}%',
                  style: GoogleFonts.inter(fontSize: 12, color: kInkMuted)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.fraction,
              minHeight: 6,
              backgroundColor: kHairline,
              valueColor: const AlwaysStoppedAnimation<Color>(kAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kAccent.withValues(alpha: 0.14),
              ),
              child: Icon(icon, color: kAccentDeep, size: 18),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kInkDark)),
          ],
        ),
      ),
    );
  }
}

/// Soft, deterministic gradient palettes used for the media grid tiles.
/// Each entry is a (start, end) pair tuned to sit nicely on cream.
const _tileGradients = <List<Color>>[
  [Color(0xFFE6B36A), Color(0xFFCC8A3F)], // amber
  [Color(0xFF7E97A6), Color(0xFF4F6E7B)], // dusty teal
  [Color(0xFFD89384), Color(0xFFB85C46)], // terracotta
  [Color(0xFFB8A07A), Color(0xFF8B6F3F)], // bronze
  [Color(0xFFC2A6CC), Color(0xFF7A5C8A)], // muted plum
  [Color(0xFF9DB39D), Color(0xFF5C7A5C)], // sage
  [Color(0xFFD9BB7C), Color(0xFFB8923D)], // gold
  [Color(0xFFC4A082), Color(0xFFA8794D)], // tan
];

List<Color> _tileGradientFor(String seed) {
  if (seed.isEmpty) return _tileGradients[0];
  return _tileGradients[seed.codeUnitAt(0) % _tileGradients.length];
}

/// Square media grid tile. For images, lazily loads and renders the
/// thumbnail; for everything else paints a soft gradient with a file
/// icon and surfaces a label pill at the bottom-left. Long-press deletes.
class _MediaTile extends StatefulWidget {
  const _MediaTile({
    required this.media,
    required this.api,
    required this.onTap,
    required this.onLongPress,
  });
  final MediaFile media;
  final MediaApi api;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  String? _thumbUrl;
  bool _thumbLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.media.isImage) _fetchThumb();
  }

  Future<void> _fetchThumb() async {
    setState(() => _thumbLoading = true);
    try {
      final url = await widget.api.getDownloadUrl(widget.media.id);
      if (!mounted) return;
      setState(() {
        _thumbUrl = url;
        _thumbLoading = false;
      });
    } on ApiError {
      if (!mounted) return;
      setState(() => _thumbLoading = false);
    }
  }

  IconData get _typeIcon {
    if (widget.media.isVideo) return Icons.play_arrow_rounded;
    if (widget.media.isAudio) return Icons.audiotrack_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    final gradient = _tileGradientFor(m.fileName);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background — gradient fallback or thumbnail.
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                ),
              ),
              if (m.isImage && _thumbUrl != null)
                Image.network(
                  _thumbUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              if (m.isImage && _thumbLoading)
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              // Center icon for non-image types.
              if (!m.isImage)
                Center(
                  child: Icon(_typeIcon,
                      size: 38, color: Colors.white.withValues(alpha: 0.95)),
                ),
              // Top-right play badge for video thumbnails.
              if (m.isVideo)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kInkDark.withValues(alpha: 0.55),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        size: 18, color: Colors.white),
                  ),
                ),
              // Bottom-left filename pill.
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: kInkDark.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    m.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
}

class _MediaPreviewScreen extends StatelessWidget {
  const _MediaPreviewScreen({required this.media, required this.downloadUrl});
  final MediaFile media;
  final String downloadUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          media.fileName,
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: media.isImage
            ? InteractiveViewer(
                child: Image.network(
                  downloadUrl,
                  loadingBuilder: (_, child, progress) =>
                      progress == null
                          ? child
                          : const CircularProgressIndicator(
                              color: Colors.white70),
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image,
                      color: Colors.white54, size: 64),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.insert_drive_file,
                        color: Colors.white38, size: 72),
                    const SizedBox(height: 20),
                    SelectableText(
                      downloadUrl,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 11, color: Colors.white54),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Non-image previews aren't built yet — use the URL above to download.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
