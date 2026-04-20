/// A topic within a topics-mode group. One conversation per topic.
/// The group auto-creates a "General" topic that cannot be deleted.
class Topic {
  final String id;
  final String groupId;
  final String name;
  final String? description;
  final String? iconEmoji;
  final DateTime? createdAt;

  const Topic({
    required this.id,
    required this.groupId,
    required this.name,
    this.description,
    this.iconEmoji,
    this.createdAt,
  });

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
        id: j['id'] as String,
        groupId: j['group_id'] as String,
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        iconEmoji: j['icon_emoji'] as String?,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'] as String),
      );

  /// "General" is the server-created default topic and is undeletable.
  bool get isDefault => name.toLowerCase() == 'general';
}

/// Response of /api/v1/groups (list) and /api/v1/groups/{id}.
class Group {
  final String id;
  final String institutionId;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String mode; // 'simple' | 'topics'
  final int memberCount;
  final String? createdByUserId;
  final bool isArchived;
  final DateTime createdAt;

  const Group({
    required this.id,
    required this.institutionId,
    required this.name,
    required this.mode,
    required this.memberCount,
    required this.createdAt,
    this.description,
    this.avatarUrl,
    this.createdByUserId,
    this.isArchived = false,
  });

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: j['id'] as String,
        institutionId: j['institution_id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        mode: j['mode'] as String? ?? 'simple',
        memberCount: (j['member_count'] as int?) ?? 0,
        createdByUserId: j['created_by_user_id'] as String?,
        isArchived: (j['is_archived'] as bool?) ?? false,
        createdAt: DateTime.parse(
            j['created_at'] as String? ?? DateTime.now().toIso8601String()),
      );
}
