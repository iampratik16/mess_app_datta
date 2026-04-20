import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/api_error.dart';
import '../data/media_api.dart';
import '../data/media_uploader.dart';
import '../domain/media_models.dart';

/// Upload-and-manage view for the media module. Covers the shippable
/// portion of `docs/ui-contract/media.md` §"Minimum 'attach file to
/// message' implementation":
/// ✓ File picker (image_picker + file_picker)
/// ✓ Client-side size + MIME checks (via [MediaLimits])
/// ✓ Idempotency-Key per upload
/// ✓ Progress bar during S3 PUT
/// ✓ Expired upload_url handled (re-init on 403)
/// ✓ Lazy-load download URLs (fetched only when the user previews)
/// ✗ "Save media_id on the message" — backend does not yet accept a
///   media_file_ids field on POST /messages, so attach-to-chat is
///   deferred. Uploaded files live in this screen for download / delete.
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

  Future<void> _pickFromGallery() async {
    try {
      final xfile = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      await _upload(File(xfile.path), nameOverride: xfile.name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open gallery: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final xfile = await _imagePicker.pickImage(source: ImageSource.camera);
      if (xfile == null) return;
      await _upload(File(xfile.path), nameOverride: xfile.name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open camera: $e');
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

  Future<void> _upload(File file, {String? nameOverride}) async {
    final name = nameOverride ?? file.uri.pathSegments.last;
    setState(() {
      _error = null;
      _active = _UploadTask(name: name);
    });
    try {
      final media = await _uploader.upload(
        file: file,
        fileName: nameOverride,
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
        backgroundColor: const Color(0xFF1E1B3A),
        title: Text('Delete ${m.fileName}?',
            style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'The file moves to the recycle bin for 30 days, then is '
          'permanently deleted.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4757)),
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
          backgroundColor: const Color(0xFFFF4757),
          content: Text('Delete failed: ${e.message}'),
        ),
      );
    }
  }

  Future<void> _preview(MediaFile m) async {
    try {
      // Lazy: fetch a fresh download URL at the moment of use per spec.
      final url = await _api.getDownloadUrl(m.id);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _MediaPreviewScreen(media: m, downloadUrl: url),
      ));
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFF4757),
          content: Text('Preview failed: ${e.message}'),
        ),
      );
    }
  }

  void _showPickerSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1B3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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

  @override
  Widget build(BuildContext context) {
    final uploading = _active != null;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Media',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF667EEA),
        onPressed: uploading ? null : _showPickerSheet,
        icon: const Icon(Icons.upload_file, color: Colors.white),
        label: const Text('Upload', style: TextStyle(color: Colors.white)),
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
        child: SafeArea(child: _buildBody(uploading)),
      ),
    );
  }

  Widget _buildBody(bool uploading) {
    return Column(
      children: [
        if (uploading) _ActiveUploadCard(task: _active!),
        if (_error != null)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4757).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFFF4757).withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFFF6B7A), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFFFF6B7A))),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 16, color: Color(0xFFFF6B7A)),
                onPressed: () => setState(() => _error = null),
              ),
            ]),
          ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_uploads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 56, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text('No uploads yet',
                  style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70)),
              const SizedBox(height: 6),
              Text(
                'Tap Upload to pick an image, photo, or file. '
                'Images up to 10 MB, documents up to 50 MB.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _uploads.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final m = _uploads[i];
        return _MediaRow(
          media: m,
          onTap: () => _preview(m),
          onDelete: () => _delete(m),
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
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.cloud_upload,
                color: Color(0xFF8A9CF5), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Uploading ${task.name}',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (task.fraction != null)
              Text('${(task.fraction! * 100).round()}%',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Colors.white70)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.fraction,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF8A9CF5)),
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
            Icon(icon, color: const Color(0xFF8A9CF5)),
            const SizedBox(width: 14),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.media,
    required this.onTap,
    required this.onDelete,
  });
  final MediaFile media;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  IconData get _typeIcon {
    if (media.isImage) return Icons.image_outlined;
    if (media.isVideo) return Icons.videocam_outlined;
    if (media.isAudio) return Icons.audiotrack_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF667EEA).withValues(alpha: 0.25),
                ),
                child: Icon(_typeIcon,
                    color: const Color(0xFF8A9CF5), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.fileName,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatBytes(media.fileSize)} · ${media.mimeType}',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.white54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Color(0xFFFF6B7A)),
                tooltip: 'Move to recycle bin',
                onPressed: onDelete,
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
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
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
                      'Non-image previews aren\'t built yet — use the URL above to download.',
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
