import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'media_api.dart';
import 'media_uploader.dart';

/// One-call avatar flow shared by user profile + group edit screens.
///
/// 1. Opens the OS image picker (gallery, image-only).
/// 2. Uploads via the standard 3-step `/media/upload` flow.
/// 3. Resolves a presigned download URL via `/media/{id}/download`.
/// 4. Returns that URL — caller PATCHes it into `avatar_url`.
///
/// Returns `null` if the user cancels or anything fails (with a SnackBar
/// on failure). Designed so the calling screen can drop it into a button
/// `onPressed` without needing extra plumbing.
class AvatarPicker {
  static final _picker = ImagePicker();

  static Future<String?> pickAndUpload(BuildContext context) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      // Compress to keep avatar uploads small and fast.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final uploader = MediaUploader();
    final api = MediaApi();
    try {
      final mediaFile = await uploader.upload(
        file: File(picked.path),
        fileName: picked.name,
      );
      return await api.getDownloadUrl(mediaFile.id);
    } on MediaUploadException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF4757),
            content: Text('Avatar upload failed: ${e.message}'),
          ),
        );
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF4757),
            content: Text('Avatar upload failed: $e'),
          ),
        );
      }
      return null;
    }
  }
}
