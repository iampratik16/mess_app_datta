import '../../../core/errors/api_error.dart';
import '../domain/media_models.dart';
import 'media_api.dart';

/// Per-attachment URL cache with TTL-aware refetch.
///
/// Why this exists: presigned GET URLs from `/media/{id}/download`
/// expire in ~1 h (audit 5.5 / 5.8). When the user scrolls back to a
/// chat from yesterday, every image/video bubble's URL is a stale 403.
/// The audit's UI contract is explicit: don't cache presigned URLs at
/// the global state layer. Each bubble owns its own resolver, lifecycle
/// matches the bubble's, and the URL is refetched on-demand.
///
/// Behaviour:
/// - First `resolve()` does a network fetch and stores `(url, expiresAt)`.
/// - Subsequent `resolve()` returns the cached URL until it's within
///   60 s of expiry, at which point the next call refetches.
/// - `resolve(forceRefresh: true)` always refetches — used by
///   widget error handlers when the underlying load fails (a 403
///   doesn't always mean "expired" — could be the object was rotated).
/// - `MediaUnavailableException` propagates when the row is gone (404
///   from `/media/{id}/download`) so the UI can switch to a final
///   "Media unavailable" placeholder rather than retry forever.
class MediaUrlResolver {
  MediaUrlResolver({required this.api, required this.mediaId});

  final MediaApi api;
  final String mediaId;

  /// 60 s buffer mirrors Prompt 2's proactive token-refresh strategy.
  /// Anything inside this window is treated as expired so the next
  /// network round-trip lands while the old URL is still valid (gives
  /// us a backstop if the refetch races against an in-flight image
  /// load).
  static const Duration _safetyMargin = Duration(seconds: 60);

  String? _url;
  DateTime? _expiresAt;
  Future<MediaDownloadInfo>? _inFlight;

  bool get _isExpiringSoon {
    final exp = _expiresAt;
    if (_url == null || exp == null) return true;
    return DateTime.now().add(_safetyMargin).isAfter(exp);
  }

  /// Returns a usable URL, refetching from the server if the cached
  /// one is missing, near expiry, or `forceRefresh` was requested.
  Future<String> resolve({bool forceRefresh = false}) async {
    if (!forceRefresh && !_isExpiringSoon) return _url!;
    final inflight = _inFlight ??= _fetch();
    try {
      final info = await inflight;
      _url = info.url;
      _expiresAt = info.expiresAt;
      return info.url;
    } finally {
      _inFlight = null;
    }
  }

  Future<MediaDownloadInfo> _fetch() async {
    try {
      return await api.getDownloadInfo(mediaId);
    } on ApiError catch (e) {
      // 404 is terminal — the media row was deleted. Anything else
      // (timeouts, 5xx, network) is a transient failure; the caller
      // can retry from a placeholder.
      if (e.statusCode == 404) {
        throw MediaUnavailableException(mediaId, e.message);
      }
      rethrow;
    }
  }
}

/// Raised by [MediaUrlResolver] when the underlying media row no
/// longer exists. UI should switch to a permanent "Media unavailable"
/// state rather than offer a retry.
class MediaUnavailableException implements Exception {
  const MediaUnavailableException(this.mediaId, this.reason);
  final String mediaId;
  final String reason;

  @override
  String toString() => 'MediaUnavailableException($mediaId): $reason';
}
