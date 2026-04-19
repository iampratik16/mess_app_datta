/// Returned by POST /api/v1/chat/conversations/open-group.
class Conversation {
  final String id;
  final String type; // 'group' | 'direct' | 'topic'
  final String? groupId;
  final String? topicId;

  const Conversation({
    required this.id,
    required this.type,
    this.groupId,
    this.topicId,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'group',
        groupId: j['group_id'] as String?,
        topicId: j['topic_id'] as String?,
      );
}

/// A chat message.
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String? senderName;
  final String content;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.senderName,
    this.editedAt,
    this.deletedAt,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        senderId: j['sender_id'] as String,
        senderName: (j['sender'] as Map<String, dynamic>?)?['full_name']
            as String?,
        content: j['content'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        editedAt: j['edited_at'] == null
            ? null
            : DateTime.parse(j['edited_at'] as String),
        deletedAt: j['deleted_at'] == null
            ? null
            : DateTime.parse(j['deleted_at'] as String),
      );

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
}
