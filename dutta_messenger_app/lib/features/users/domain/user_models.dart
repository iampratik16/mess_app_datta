/// A lightweight user record returned by /users/search, /users/{id}, /users/me.
class UserProfile {
  final String id;
  final String? fullName;
  final String? email;
  final String? avatarUrl;
  final String? bio;
  final String? status; // online|offline|away etc.
  final bool isOnline;
  final DateTime? lastSeenAt;

  const UserProfile({
    required this.id,
    this.fullName,
    this.email,
    this.avatarUrl,
    this.bio,
    this.status,
    this.isOnline = false,
    this.lastSeenAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        fullName: j['full_name'] as String?,
        email: j['email'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        bio: j['bio'] as String?,
        status: j['status'] as String?,
        isOnline: (j['is_online'] as bool?) ?? false,
        lastSeenAt: j['last_seen_at'] == null
            ? null
            : DateTime.tryParse(j['last_seen_at'] as String),
      );

  String get initials {
    final name = (fullName ?? email ?? '?').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0].substring(0, 1).toUpperCase();
  }
}

/// Per-user notification + UI settings (GET /users/me/settings).
class UserSettings {
  final bool notificationMessages;
  final bool notificationGroups;
  final bool notificationSound;
  final String theme;
  final String language;

  const UserSettings({
    required this.notificationMessages,
    required this.notificationGroups,
    required this.notificationSound,
    required this.theme,
    required this.language,
  });

  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
        notificationMessages: (j['notification_messages'] as bool?) ?? true,
        notificationGroups: (j['notification_groups'] as bool?) ?? true,
        notificationSound: (j['notification_sound'] as bool?) ?? true,
        theme: (j['theme'] as String?) ?? 'system',
        language: (j['language'] as String?) ?? 'en',
      );
}
