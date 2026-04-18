import '../../../core/storage/secure_storage.dart';
import '../../../core/errors/api_error.dart';
import 'auth_api.dart';
import '../domain/auth_models.dart';

class AuthRepository {
  final AuthApi _api;

  AuthRepository() : _api = AuthApi();

  /// Login and persist tokens securely.
  /// Returns the authenticated user on success.
  /// Throws [ApiError] on failure.
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.login(email: email, password: password);
    await SecureTokenStorage.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
    await SecureTokenStorage.saveUserContext(
      institutionId: response.user.institutionId,
      userId: response.user.id,
    );
    return response.user;
  }

  /// Send an invitation email to a new user.
  /// The invitee will receive an email with a registration link.
  Future<InviteResponse> inviteUser({required String email}) =>
      _api.inviteUser(email: email);

  /// Complete registration with an invitation token.
  /// [invitationToken] comes from the invitation email link.
  Future<AuthUser> registerWithInvite({
    required String email,
    required String password,
    required String fullName,
    required String invitationToken,
  }) async {
    final response = await _api.registerWithInvite(
      email: email,
      password: password,
      fullName: fullName,
      invitationToken: invitationToken,
    );
    await SecureTokenStorage.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
    await SecureTokenStorage.saveUserContext(
      institutionId: response.user.institutionId,
      userId: response.user.id,
    );
    return response.user;
  }

  /// Logout — clear all stored tokens.
  Future<void> logout() => SecureTokenStorage.clearAll();

  /// Check if user is currently logged in.
  Future<bool> isLoggedIn() async {
    final token = await SecureTokenStorage.getAccessToken();
    return token != null;
  }
}
