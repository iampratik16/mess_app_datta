import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_storage.dart';

/// Centralised access-token refresh, proactive scheduling, and rotation
/// broadcast. One instance per app process.
///
/// Why this lives outside the Dio interceptor: the WebSocket also needs
/// to know when tokens rotate (so it can reconnect with the new JWT —
/// the audit's root-cause #1 for mid-session pain). Keeping refresh in
/// the interceptor would couple WS reconnects to HTTP traffic; pulling
/// it into a singleton lets both layers subscribe to the same event.
///
/// Usage:
/// - On login or successful refresh, call [scheduleProactiveRefresh] with
///   the server's `expires_in_seconds`. A one-shot timer fires at
///   `expires_in_seconds - 60` and triggers [refresh].
/// - The Dio 401 interceptor calls [refresh] when it observes an expired
///   access token; the proactive timer normally beats it to the punch.
/// - Subscribe to [rotated] to react to a fresh token pair (e.g.
///   `ChatService.reconnectWithFreshToken`).
class AuthSession {
  AuthSession._();
  static final AuthSession instance = AuthSession._();

  /// Bare Dio with no interceptors so refresh requests don't recursively
  /// trigger themselves through the global `_AuthInterceptor`.
  late final Dio _refreshDio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  final StreamController<void> _rotatedController =
      StreamController<void>.broadcast();
  Timer? _proactiveTimer;
  Future<bool>? _inFlight;

  /// Fires once after every successful refresh. Listeners can read the
  /// new access token from [SecureTokenStorage] inside the handler.
  Stream<void> get rotated => _rotatedController.stream;

  /// Schedule a proactive `/auth/refresh` at `expiresInSeconds - 60` so
  /// the new JWT lands before the current one expires. Replaces any
  /// previously-scheduled timer.
  ///
  /// Margins below 60s collapse to "refresh in 30s" — a token whose TTL
  /// is already shorter than our safety margin should be rotated quickly,
  /// not left to die.
  void scheduleProactiveRefresh(int expiresInSeconds) {
    _proactiveTimer?.cancel();
    final marginSeconds = expiresInSeconds - 60;
    final delay = Duration(seconds: marginSeconds > 30 ? marginSeconds : 30);
    _proactiveTimer = Timer(delay, () {
      // Best-effort. Failures are surfaced via [refresh] returning false;
      // the next 401 from the interceptor will retry naturally.
      refresh();
    });
  }

  /// Force a refresh now. Coalesces concurrent callers onto a single
  /// in-flight request — matters because the Dio 401 interceptor and the
  /// proactive timer can fire within milliseconds of each other.
  ///
  /// Returns true on success (tokens persisted, [rotated] emitted) and
  /// false on any failure. Callers should NOT clear tokens on false —
  /// the interceptor handles forced logout for terminal refresh failures.
  Future<bool> refresh() {
    return _inFlight ??= _refreshOnce().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<bool> _refreshOnce() async {
    final accessToken = await SecureTokenStorage.getAccessToken();
    final refreshToken = await SecureTokenStorage.getRefreshToken();
    if (accessToken == null || refreshToken == null) return false;
    try {
      final response = await _refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final newAccess = data['access_token'] as String;
      final newRefresh = data['refresh_token'] as String;
      final expires = (data['expires_in_seconds'] as int?) ?? 30 * 60;
      await SecureTokenStorage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      scheduleProactiveRefresh(expires);
      if (!_rotatedController.isClosed) _rotatedController.add(null);
      return true;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Tear down on logout — cancels the proactive timer. The rotation
  /// stream stays open so subsequent logins can re-subscribe without
  /// rebuilding listeners.
  void cancel() {
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
  }
}
