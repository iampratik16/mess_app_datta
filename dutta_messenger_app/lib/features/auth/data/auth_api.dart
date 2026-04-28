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
  /// Create an institution (multi-tenant bootstrap). Open endpoint — no auth.
  /// Returns the new institution row (id, name, domain, tier, limits, …).
  /// Path is `/institutions`, not `/auth/institutions` — see auth_routes.py.
  Future<Map<String, dynamic>> createInstitution({
    required String name,
    String? description,
    String? domain,
    String? logoUrl,
    String subscriptionTier = 'free',
    int maxUsers = 50,
    int maxGroups = 20,
  }) async {
    try {
      final response = await _dio.post(
        '/institutions',
        data: {
          'name': name,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (domain != null && domain.isNotEmpty) 'domain': domain,
          if (logoUrl != null && logoUrl.isNotEmpty) 'logo_url': logoUrl,
          'subscription_tier': subscriptionTier,
          'max_users': maxUsers,
          'max_groups': maxGroups,
        },
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
  /// Complete registration using an invitation token. The backend returns
  /// only `{user, message}` — no tokens — so this method does NOT auto-log
  /// the new user in. Call [login] right after if you want a session.
  /// (See [AuthRepository.registerWithInvite] for the chained version.)
  Future<AuthUser> registerWithInvite({
    required String email,
    required String password,
    required String fullName,
    required String invitationToken,
    String? phoneNumber,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'invitation_token': invitationToken,
          if (phoneNumber != null && phoneNumber.isNotEmpty)
            'phone_number': phoneNumber,
        },
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      return AuthUser.fromJson(user);
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

  /// POST /api/v1/auth/change-password
  /// Change the authenticated user's password. Requires the current
  /// password for confirmation — prevents session-token theft from being
  /// a password reset.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post(
        '/auth/change-password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}
