/// User authentication response from POST /api/v1/auth/login
class LoginResponse {
  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  const LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    // Backend wraps in {"data": {...}}
    final data = json['data'] as Map<String, dynamic>;
    return LoginResponse(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
    );
  }
}

/// User object returned after login or register
class AuthUser {
  final String id;
  final String institutionId;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String status;
  final DateTime createdAt;

  const AuthUser({
    required this.id,
    required this.institutionId,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    required this.status,
    required this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        institutionId: json['institution_id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        avatarUrl: json['avatar_url'] as String?,
        status: json['status'] as String? ?? 'active',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Invitation response from POST /api/v1/auth/invite
class InviteResponse {
  final String email;
  final String message;

  const InviteResponse({required this.email, required this.message});

  factory InviteResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return InviteResponse(
      email: (data['invitation'] as Map<String, dynamic>?)
              ?['email'] as String? ??
          '',
      message: data['message'] as String? ?? '',
    );
  }
}

/// Token pair from POST /api/v1/auth/refresh
class TokenPair {
  final String accessToken;
  final String refreshToken;

  const TokenPair({required this.accessToken, required this.refreshToken});

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return TokenPair(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );
  }
}
