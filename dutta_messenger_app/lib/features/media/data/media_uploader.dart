import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';

import '../../../core/errors/api_error.dart';
import '../domain/media_models.dart';
import 'media_api.dart';

/// MIME + size ceilings per `docs/ui-contract/media.md` §"File limits".
/// Client-side gate so the user gets instant feedback instead of waiting
/// for a 422 from the server.
class MediaLimits {
  static const image = _Category(
    maxBytes: 10 * 1024 * 1024,
    mimes: {'image/jpeg', 'image/png', 'image/gif', 'image/webp'},
  );
  static const video = _Category(
    maxBytes: 100 * 1024 * 1024,
    mimes: {'video/mp4', 'video/quicktime', 'video/webm'},
  );
  static const audio = _Category(
    maxBytes: 20 * 1024 * 1024,
    mimes: {'audio/mpeg', 'audio/ogg', 'audio/wav', 'audio/aac'},
  );
  static const document = _Category(
    maxBytes: 50 * 1024 * 1024,
    mimes: {
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    },
  );
  static const blockedExtensions = {
    '.exe', '.sh', '.bat', '.cmd', '.com', '.scr',
    '.ps1', '.msi', '.dll', '.jar', '.app', '.pkg',
  };

  /// Hard ceiling regardless of category.
  static const hardMax = 100 * 1024 * 1024;

  /// Returns `null` if OK, else a human-readable error string.
  static String? validate({
    required String fileName,
    required int fileSize,
    required String mimeType,
  }) {
    final lowerName = fileName.toLowerCase();
    for (final ext in blockedExtensions) {
      if (lowerName.endsWith(ext)) {
        return 'File type "$ext" is not allowed.';
      }
    }
    if (fileSize <= 0) return 'File is empty.';
    if (fileSize > hardMax) {
      return 'File exceeds the 100 MB hard limit.';
    }
    final cat = _pick(mimeType);
    if (cat == null) {
      return 'MIME type $mimeType is not allowed.';
    }
    if (fileSize > cat.maxBytes) {
      final mb = (cat.maxBytes / (1024 * 1024)).round();
      return 'File exceeds the ${mb} MB limit for this type.';
    }
    return null;
  }

  static _Category? _pick(String mimeType) {
    if (image.mimes.contains(mimeType)) return image;
    if (video.mimes.contains(mimeType)) return video;
    if (audio.mimes.contains(mimeType)) return audio;
    if (document.mimes.contains(mimeType)) return document;
    return null;
  }
}

class _Category {
  final int maxBytes;
  final Set<String> mimes;
  const _Category({required this.maxBytes, required this.mimes});
}

/// Result callback for progress reporting. `sent` and `total` are bytes.
typedef UploadProgress = void Function(int sent, int total);

/// Thrown when the uploader fails anywhere in the 3-step flow.
class MediaUploadException implements Exception {
  final String message;
  final Object? cause;
  const MediaUploadException(this.message, {this.cause});
  @override
  String toString() => 'MediaUploadException: $message';
}

/// Orchestrates the 3-step S3 upload described in `media.md` §"Read this
/// before anything else". Keeps the `Idempotency-Key` stable across
/// retries of the same user action so the backend returns the same
/// upload_id instead of minting a new one.
class MediaUploader {
  final MediaApi _api;

  /// Plain Dio instance for the direct-to-S3 PUT — no auth interceptor,
  /// no extra headers, nothing. Sending our Bearer token to S3 would
  /// trigger `403 SignatureDoesNotMatch`.
  final Dio _s3;

  MediaUploader({MediaApi? api, Dio? s3Client})
      : _api = api ?? MediaApi(),
        _s3 = s3Client ?? Dio();

  /// Upload [file] and return the completed [MediaFile].
  /// [fileName] overrides the basename if given (useful on iOS where
  /// image_picker returns a tmp path).
  ///
  /// Retries are safe: pass the same [idempotencyKey] to reuse the same
  /// upload slot. A new key = new upload.
  Future<MediaFile> upload({
    required File file,
    String? fileName,
    UploadProgress? onProgress,
    String? idempotencyKey,
    String? mimeType,
  }) async {
    final name = fileName ?? file.uri.pathSegments.last;
    final stat = await file.stat();
    final size = stat.size;
    // Order: explicit override → mime pkg lookup by path → lookup by
    // filename → sniff magic bytes → last-resort octet-stream. Android
    // image_picker returns temp files like `/cache/REC12345` with no
    // extension for videos, so path-based lookup fails and the old
    // default of octet-stream tripped MediaLimits.validate. Sniffing the
    // first 64 bytes recovers the mime from the container signature.
    final sniffed = await _sniffMime(file);
    final mime = mimeType ??
        lookupMimeType(file.path) ??
        lookupMimeType(name) ??
        sniffed ??
        'application/octet-stream';

    final clientError =
        MediaLimits.validate(fileName: name, fileSize: size, mimeType: mime);
    if (clientError != null) {
      throw MediaUploadException(clientError);
    }

    final key = idempotencyKey ?? MediaApi.newIdempotencyKey();

    // Step 1: init — can be retried with the same key
    final MediaUploadInit init;
    try {
      init = await _api.initUpload(
        fileName: name,
        fileSize: size,
        mimeType: mime,
        idempotencyKey: key,
      );
    } on ApiError catch (e) {
      throw MediaUploadException('init failed: ${e.message}', cause: e);
    }

    // Step 2: PUT directly to S3 with the presigned URL.
    // Content-Type MUST match the mime sent in step 1 or S3 returns
    // 403 SignatureDoesNotMatch — spec "Common pitfalls".
    try {
      await _s3.put(
        init.uploadUrl,
        data: file.openRead(),
        options: Options(
          headers: {
            'Content-Type': mime,
            Headers.contentLengthHeader: size,
          },
        ),
        onSendProgress: onProgress,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 403) {
        throw MediaUploadException(
          'Upload URL rejected (likely expired — call init again).',
          cause: e,
        );
      }
      throw MediaUploadException(
        'S3 PUT failed (${status ?? "network"}).',
        cause: e,
      );
    }

    // Step 3: complete — finalises the DB row and returns the media_id.
    try {
      return await _api.completeUpload(init.uploadId);
    } on ApiError catch (e) {
      throw MediaUploadException('complete failed: ${e.message}', cause: e);
    }
  }

  /// Read the first 32 bytes and detect common container signatures.
  /// Covers the MIME types the backend accepts per `media.md` — mainly
  /// needed for videos, where Android's temp filenames lose the extension
  /// and `lookupMimeType` returns null.
  Future<String?> _sniffMime(File file) async {
    try {
      final raf = await file.open();
      final head = await raf.read(32);
      await raf.close();
      if (head.length < 12) return null;
      // ISO BMFF (mp4, mov): bytes 4..7 == 'ftyp'
      if (head[4] == 0x66 &&
          head[5] == 0x74 &&
          head[6] == 0x79 &&
          head[7] == 0x70) {
        // Brand at 8..11 disambiguates mp4 vs mov. `qt  ` = QuickTime.
        final brand = String.fromCharCodes(head.sublist(8, 12));
        if (brand.startsWith('qt')) return 'video/quicktime';
        return 'video/mp4';
      }
      // WebM / Matroska (EBML header): 0x1A 0x45 0xDF 0xA3
      if (head[0] == 0x1A &&
          head[1] == 0x45 &&
          head[2] == 0xDF &&
          head[3] == 0xA3) {
        return 'video/webm';
      }
      // JPEG: FF D8 FF
      if (head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) {
        return 'image/jpeg';
      }
      // PNG: 89 50 4E 47
      if (head[0] == 0x89 &&
          head[1] == 0x50 &&
          head[2] == 0x4E &&
          head[3] == 0x47) {
        return 'image/png';
      }
      // GIF: 'GIF8'
      if (head[0] == 0x47 &&
          head[1] == 0x49 &&
          head[2] == 0x46 &&
          head[3] == 0x38) {
        return 'image/gif';
      }
      // PDF: '%PDF'
      if (head[0] == 0x25 &&
          head[1] == 0x50 &&
          head[2] == 0x44 &&
          head[3] == 0x46) {
        return 'application/pdf';
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
