import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../domain/auth_models.dart';
import '../../../core/errors/api_error.dart';

/// Raw API calls for the auth module.
/// All endpoints are at /api/v1/auth/* and /api/v1/institutions
class AuthApi {
  final Dio _dio;

  AuthApi() : _dio = ApiClient().dio;

  /// POST /api/v1/institutions
  /// Create an institution. Open endpoint — no auth required.
  Future<Map<String, dynamic>> createInstitution({
    required String name,
    required String domain,
  }) async {
    try {
      final response = await _dio.post(
        '/institutions',
        data: {'name': name, 'domain': domain},
      );
      return response.data['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /api/v1/auth/login
  /// Login with email + password. Returns access_token + refresh_token.
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return LoginResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /api/v1/auth/invite
  /// Invite a user by email. Requires Bearer token.
  /// IMPORTANT: Direct registration is blocked. Users MUST be invited first.
  Future<InviteResponse> inviteUser({required String email}) async {
    try {
      final response = await _dio.post(
        '/auth/invite',
        data: {'email': email},
        // Authorization header is attached automatically by AuthInterceptor
      );
      return InviteResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /api/v1/auth/register
  /// Complete registration using an invitation token.
  /// The invitation_token comes from the email that the invitee receives.
  /// In dev/test — read it directly from the DB (see smoke test docs).
  Future<LoginResponse> registerWithInvite({
    required String email,
    required String password,
    required String fullName,
    required String invitationToken,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'invitation_token': invitationToken,
        },
      );
      return LoginResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /api/v1/auth/refresh
  /// Exchange a refresh token for a new token pair.
  Future<TokenPair> refreshTokens({
    required String refreshToken,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        // Current access token attached by AuthInterceptor
      );
      return TokenPair.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}
