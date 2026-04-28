import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for JWT tokens. Never store tokens in SharedPreferences.
///
/// Every call is backed by an in-memory cache and bounded by a 2-second
/// timeout. This keeps the UI responsive on platforms whose native keychain
/// is slow to wake up (notably the iOS simulator on first access), while
/// still persisting tokens to the real keychain in the background.
class SecureTokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _institutionIdKey = 'institution_id';
  static const _userIdKey = 'user_id';
  static const _fcmTokenIdKey = 'fcm_token_id';
  static const _fcmTokenValueKey = 'fcm_token_value';

  static const _writeTimeout = Duration(seconds: 2);
  static const _readTimeout = Duration(seconds: 2);

  // In-memory mirror of the keychain. Survives as long as the app process.
  static final Map<String, String?> _cache = {};

  static Future<void> _write(String key, String value) async {
    _cache[key] = value;
    try {
      await _storage
          .write(key: key, value: value)
          .timeout(_writeTimeout, onTimeout: () {});
    } catch (_) {
      // Swallow — in-memory cache still holds the value.
    }
  }

  static Future<String?> _read(String key) async {
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final v = await _storage
          .read(key: key)
          .timeout(_readTimeout, onTimeout: () => null);
      if (v != null) _cache[key] = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _write(_accessTokenKey, accessToken),
      _write(_refreshTokenKey, refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() => _read(_accessTokenKey);
  static Future<String?> getRefreshToken() => _read(_refreshTokenKey);

  static Future<void> saveUserContext({
    required String institutionId,
    required String userId,
  }) async {
    await Future.wait([
      _write(_institutionIdKey, institutionId),
      _write(_userIdKey, userId),
    ]);
  }

  static Future<String?> getInstitutionId() => _read(_institutionIdKey);

  /// Persist the server's token row id (returned by POST /notifications/tokens)
  /// so we can DELETE it on logout / token rotation.
  static Future<void> saveFcmRegistration({
    required String tokenId,
    required String tokenValue,
  }) async {
    await Future.wait([
      _write(_fcmTokenIdKey, tokenId),
      _write(_fcmTokenValueKey, tokenValue),
    ]);
  }

  static Future<String?> getFcmTokenId() => _read(_fcmTokenIdKey);
  static Future<String?> getFcmTokenValue() => _read(_fcmTokenValueKey);

  static Future<void> clearFcmRegistration() async {
    _cache.remove(_fcmTokenIdKey);
    _cache.remove(_fcmTokenValueKey);
    try {
      await Future.wait([
        _storage.delete(key: _fcmTokenIdKey).timeout(_writeTimeout,
            onTimeout: () {}),
        _storage.delete(key: _fcmTokenValueKey).timeout(_writeTimeout,
            onTimeout: () {}),
      ]);
    } catch (_) {/* ignored */}
  }

  static Future<void> clearAll() async {
    _cache.clear();
    try {
      await _storage
          .deleteAll()
          .timeout(_writeTimeout, onTimeout: () {});
    } catch (_) {/* ignored */}
  }
}
