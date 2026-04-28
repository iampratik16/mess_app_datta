import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
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

/// Attaches JWT to every request. Handles 401 by refreshing token once.
class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  bool _isRefreshing = false;

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
    // Auto-refresh on 401 (token expired)
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await SecureTokenStorage.getRefreshToken();
        final accessToken = await SecureTokenStorage.getAccessToken();
        if (refreshToken != null && accessToken != null) {
          final response = await _dio.post(
            '/auth/refresh',
            data: {'refresh_token': refreshToken},
            options: Options(
              headers: {'Authorization': 'Bearer $accessToken'},
            ),
          );
          final data = response.data['data'];
          await SecureTokenStorage.saveTokens(
            accessToken: data['access_token'] as String,
            refreshToken: data['refresh_token'] as String,
          );
          // Retry original request
          final retryOptions = err.requestOptions;
          retryOptions.headers['Authorization'] =
              'Bearer ${data['access_token']}';
          final retryResponse = await _dio.fetch(retryOptions);
          handler.resolve(retryResponse);
          return;
        }
      } catch (_) {
        // Refresh failed — clear tokens, user must log in again
        await SecureTokenStorage.clearAll();
      } finally {
        _isRefreshing = false;
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
