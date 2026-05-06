import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../domain/media_models.dart';

/// Raw Dio calls for /api/v1/media. Upload is a 3-step flow per
/// `docs/ui-contract/media.md` — this wrapper covers steps 1 + 3 + the
/// read/delete endpoints. Step 2 (PUT to S3) runs through a **separate,
/// auth-less** Dio instance to avoid sending our Bearer token to S3;
/// see [MediaUploader].
class MediaApi {
  static const _uuid = Uuid();
  final Dio _dio;

  MediaApi() : _dio = ApiClient().dio;

  /// POST /media/upload/init — returns the presigned PUT URL.
  /// The spec REQUIRES `Idempotency-Key` (UUID4). Pass the same value on
  /// retries of the same user action so the backend returns the same
  /// upload_id instead of minting a new one.
  Future<MediaUploadInit> initUpload({
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String idempotencyKey,
  }) async {
    try {
      final r = await _dio.post(
        '/media/upload/init',
        data: {
          'file_name': fileName,
          'file_size': fileSize,
          'mime_type': mimeType,
        },
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return MediaUploadInit.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /media/upload/complete — call after the S3 PUT succeeds.
  /// Returns the final [MediaFile] with the canonical media_id.
  Future<MediaFile> completeUpload(String uploadId) async {
    try {
      final r = await _dio.post(
        '/media/upload/complete',
        data: {'upload_id': uploadId},
      );
      return MediaFile.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /media/ — the caller's own vault, newest-first. Server scopes
  /// to (institution_id, uploader_id) so this endpoint can never leak
  /// another user's media; treat the result as authoritative.
  ///
  /// Pass [beforeId] for cursor-paginated history.
  Future<List<MediaFile>> listVault({int limit = 50, String? beforeId}) async {
    try {
      final r = await _dio.get(
        '/media/',
        queryParameters: {
          'limit': limit,
          if (beforeId != null) 'before_id': beforeId,
        },
      );
      final data = r.data['data'];
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(MediaFile.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /media/{id} — metadata.
  Future<MediaFile> getMedia(String mediaId) async {
    try {
      final r = await _dio.get('/media/$mediaId');
      return MediaFile.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /media/{id}/download — presigned GET URL (expires in ~1 h).
  /// Do not cache the URL itself at the global state layer — keep it
  /// widget-local. Use [getDownloadInfo] when you need the TTL too
  /// (Prompt 11 defensive refetch).
  Future<String> getDownloadUrl(String mediaId) async {
    final info = await getDownloadInfo(mediaId);
    return info.url;
  }

  /// GET /media/{id}/download with TTL — used by [MediaUrlResolver]
  /// to pre-emptively refetch before the URL expires.
  Future<MediaDownloadInfo> getDownloadInfo(String mediaId) async {
    try {
      final r = await _dio.get('/media/$mediaId/download');
      final data = r.data['data'] as Map<String, dynamic>;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      return MediaDownloadInfo(
        url: data['download_url'] as String,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// DELETE /media/{id} — soft-delete (30-day grace in recycle bin).
  Future<void> deleteMedia(String mediaId) async {
    try {
      await _dio.delete('/media/$mediaId');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// Convenience — mint a fresh idempotency key.
  static String newIdempotencyKey() => _uuid.v4();
}
