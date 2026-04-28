import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/errors/api_error.dart';
import '../core/storage/secure_storage.dart';
import '../features/notifications/data/notifications_api.dart';
import '../firebase_options.dart';

/// Owns the FCM lifecycle for the signed-in user.
///
/// Backend endpoints used:
///   POST   /api/v1/notifications/tokens
///   DELETE /api/v1/notifications/tokens/{token_id}
///
/// Init is wrapped in try/catch so the app keeps running on devices /
/// builds where Firebase has not been configured yet (no
/// `GoogleService-Info.plist` on iOS, no `google-services.json` on
/// Android). In that state [state] reports `notConfigured`; everything
/// else continues to work.
class PushTokenService {
  PushTokenService._();
  static final PushTokenService instance = PushTokenService._();

  final _api = NotificationsApi();
  StreamSubscription<String>? _refreshSub;
  PushState _state = PushState.idle;
  String? _lastError;

  PushState get state => _state;
  String? get lastError => _lastError;

  /// Call after a successful sign-in. Idempotent.
  Future<void> registerForCurrentUser() async {
    _state = PushState.initializing;
    try {
      // Use the flutterfire-generated options so iOS + Android pull the
      // right Firebase project (project-aura-msg). Falling back to bare
      // `Firebase.initializeApp()` would still work on iOS where the
      // plist auto-loads, but is brittle and breaks on Android.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      // No platform config, simulator without APNs cert, etc. Don't
      // bring the app down — push just won't work.
      if (e.code == 'no-app' ||
          e.code == 'duplicate-app' ||
          e.code == 'plugin') {
        _state = PushState.notConfigured;
        _lastError = e.message;
        if (kDebugMode) {
          debugPrint('PushTokenService: Firebase init: ${e.code} ${e.message}');
        }
        return;
      }
      _state = PushState.failed;
      _lastError = e.message;
      return;
    } catch (e) {
      _state = PushState.notConfigured;
      _lastError = e.toString();
      if (kDebugMode) {
        debugPrint('PushTokenService: Firebase init failed: $e');
      }
      return;
    }

    final messaging = FirebaseMessaging.instance;

    try {
      final perms = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (perms.authorizationStatus == AuthorizationStatus.denied) {
        _state = PushState.permissionDenied;
        return;
      }

      // iOS needs the APNs token before FCM hands out one — wait briefly.
      if (Platform.isIOS) {
        var attempt = 0;
        while (attempt < 5 &&
            await messaging.getAPNSToken() == null) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          attempt++;
        }
      }

      final fcmToken = await messaging.getToken();
      if (fcmToken == null) {
        _state = PushState.failed;
        _lastError = 'FCM did not return a token';
        return;
      }
      await _registerWithBackend(fcmToken);

      // React to token rotations: re-register and DELETE the old row.
      _refreshSub?.cancel();
      _refreshSub =
          messaging.onTokenRefresh.listen(_onTokenRefresh, onError: (_) {});
    } on ApiError catch (e) {
      _state = PushState.failed;
      _lastError = e.message;
    } catch (e) {
      _state = PushState.failed;
      _lastError = e.toString();
    }
  }

  Future<void> _registerWithBackend(String fcmToken) async {
    final result = await _api.registerFcmToken(
      token: fcmToken,
      deviceType: _platformLabel(),
      deviceName: _deviceLabel(),
    );
    await SecureTokenStorage.saveFcmRegistration(
      tokenId: result.tokenId,
      tokenValue: fcmToken,
    );
    _state = PushState.registered;
    _lastError = null;
  }

  Future<void> _onTokenRefresh(String newToken) async {
    final oldId = await SecureTokenStorage.getFcmTokenId();
    try {
      await _registerWithBackend(newToken);
    } on ApiError {
      return;
    }
    if (oldId != null && oldId.isNotEmpty) {
      try {
        await _api.revokeFcmToken(oldId);
      } on ApiError {
        // Best-effort cleanup; the new token is already registered.
      }
    }
  }

  /// Call on sign-out. Best-effort — never throws.
  Future<void> revokeAndForget() async {
    final id = await SecureTokenStorage.getFcmTokenId();
    if (id != null && id.isNotEmpty) {
      try {
        await _api.revokeFcmToken(id);
      } on ApiError {
        // Token row may already be inactive — ignore.
      }
    }
    await SecureTokenStorage.clearFcmRegistration();
    await _refreshSub?.cancel();
    _refreshSub = null;
    _state = PushState.idle;
    _lastError = null;
  }

  String _platformLabel() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'web';
  }

  String _deviceLabel() {
    if (Platform.isIOS) return 'iOS device';
    if (Platform.isAndroid) return 'Android device';
    return 'Web';
  }
}

enum PushState {
  /// Not yet attempted in this session.
  idle,

  /// Firebase init / token fetch in progress.
  initializing,

  /// Firebase isn't set up on this build (no plist / json). Push
  /// notifications won't work but the app continues to run normally.
  notConfigured,

  /// User declined push permissions.
  permissionDenied,

  /// Token retrieved and registered with the backend.
  registered,

  /// Something else went wrong; see [lastError].
  failed,
}
