/// Metadata for a file stored in the institution's media bucket.
/// Matches the response of POST /media/upload/complete and GET /media/{id}.
class MediaFile {
  final String id;
  final String institutionId;
  final String uploaderId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final String storageKey;
  final String? thumbnailKey;
  final String uploadStatus; // 'pending' | 'completed' | 'failed'
  final DateTime? recycleBinAt;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MediaFile({
    required this.id,
    required this.institutionId,
    required this.uploaderId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.storageKey,
    required this.uploadStatus,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnailKey,
    this.recycleBinAt,
    this.deletedAt,
  });

  factory MediaFile.fromJson(Map<String, dynamic> j) => MediaFile(
        id: j['id'] as String,
        institutionId: j['institution_id'] as String,
        uploaderId: j['uploader_id'] as String,
        fileName: j['file_name'] as String,
        fileSize: (j['file_size'] as num).toInt(),
        mimeType: j['mime_type'] as String,
        storageKey: j['storage_key'] as String,
        thumbnailKey: j['thumbnail_key'] as String?,
        uploadStatus: j['upload_status'] as String? ?? 'completed',
        recycleBinAt: j['recycle_bin_at'] == null
            ? null
            : DateTime.tryParse(j['recycle_bin_at'] as String),
        deletedAt: j['deleted_at'] == null
            ? null
            : DateTime.tryParse(j['deleted_at'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isDocument => !isImage && !isVideo && !isAudio;
  bool get isInRecycleBin => recycleBinAt != null;
}

/// Response of GET /media/{id}/download — a short-lived presigned
/// GET URL plus the absolute timestamp at which it expires.
///
/// The audit (5.5 / 5.8) calls out that these URLs are 1 h by default
/// and that holding one in app state past the TTL surfaces as a
/// 403 SignatureExpired in the user's chat bubble. Treating
/// `expiresAt` as load-bearing — pre-emptively refetching when within
/// 60 s of it — is the demo-safe behaviour.
class MediaDownloadInfo {
  const MediaDownloadInfo({required this.url, required this.expiresAt});
  final String url;
  final DateTime expiresAt;
}

/// Response of POST /media/upload/init — the presigned PUT URL the
/// client streams the bytes to.
class MediaUploadInit {
  final String uploadId;
  final String uploadUrl;
  final String storageKey;
  final int expiresIn;

  const MediaUploadInit({
    required this.uploadId,
    required this.uploadUrl,
    required this.storageKey,
    required this.expiresIn,
  });

  factory MediaUploadInit.fromJson(Map<String, dynamic> j) => MediaUploadInit(
        uploadId: j['upload_id'] as String,
        uploadUrl: j['upload_url'] as String,
        storageKey: j['storage_key'] as String,
        expiresIn: (j['expires_in'] as num).toInt(),
      );
}
