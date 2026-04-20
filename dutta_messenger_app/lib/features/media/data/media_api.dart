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
  /// Do not cache the URL itself — refetch when you need to render.
  Future<String> getDownloadUrl(String mediaId) async {
    try {
      final r = await _dio.get('/media/$mediaId/download');
      return r.data['data']['download_url'] as String;
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
