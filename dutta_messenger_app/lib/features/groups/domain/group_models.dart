/// Response of /api/v1/groups (list) and /api/v1/groups/{id}.
class Group {
  final String id;
  final String institutionId;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String mode; // 'simple' | 'topics'
  final int memberCount;
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
  });

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: j['id'] as String,
        institutionId: j['institution_id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        mode: j['mode'] as String? ?? 'simple',
        memberCount: (j['member_count'] as int?) ?? 0,
        createdAt:
            DateTime.parse(j['created_at'] as String? ?? DateTime.now().toIso8601String()),
      );
}
