import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../auth/auth_events.dart';
import '../auth/auth_session.dart';
import '../config/app_config.dart';
import '../errors/api_error.dart';
import '../storage/secure_storage.dart';

/// Global Dio HTTP client with auth + request-id logging.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(_dio),
      _RequestIdInterceptor(),
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint(o.toString()),
      ),
    ]);
  }

  Dio get dio => _dio;
}

/// Attaches JWT to every request. Handles 401 by delegating to
/// [AuthSession.refresh] (which is also driven by the proactive
/// expiry timer and which broadcasts to WebSocket listeners).
class _AuthInterceptor extends Interceptor {
  final Dio _dio;

  _AuthInterceptor(this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureTokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      final ok = await AuthSession.instance.refresh();
      if (ok) {
        final newToken = await SecureTokenStorage.getAccessToken();
        if (newToken != null) {
          final retryOptions = err.requestOptions;
          retryOptions.headers['Authorization'] = 'Bearer $newToken';
          try {
            final retryResponse = await _dio.fetch(retryOptions);
            handler.resolve(retryResponse);
            return;
          } catch (_) {
            // Fall through to surface the original error.
          }
        }
      } else {
        // Refresh terminally failed — clear tokens, cancel the
        // proactive timer, and let the app shell tear the rest down
        // (WS, FCM, navigation, toast) via the AuthEvents bus.
        await SecureTokenStorage.clearAll();
        AuthSession.instance.cancel();
        AuthEvents.instance.emit(AuthEvent.sessionExpired);
      }
    } else if (err.response?.statusCode == 403) {
      // Most 403s are feature-level "this user can't do that" — surface
      // them as normal errors. Only the codes in [sessionEndingForbiddenCodes]
      // mean the account itself is gone, in which case treat as a forced
      // logout.
      final code = ApiError.fromDioException(err).code;
      if (sessionEndingForbiddenCodes.contains(code)) {
        await SecureTokenStorage.clearAll();
        AuthSession.instance.cancel();
        AuthEvents.instance.emit(AuthEvent.forbidden);
      }
    }
    handler.next(DioException(
      requestOptions: err.requestOptions,
      error: ApiError.fromDioException(err),
      response: err.response,
      type: err.type,
    ));
  }
}

/// Attaches a unique X-Request-ID to every request for backend tracing.
class _RequestIdInterceptor extends Interceptor {
  static const _uuid = Uuid();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Request-ID'] = _uuid.v4();
    options.headers['X-Client-Version'] = '1.0.0';
    handler.next(options);
  }
}
