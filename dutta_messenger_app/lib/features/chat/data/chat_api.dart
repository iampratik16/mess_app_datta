import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_client.dart';
import '../domain/chat_models.dart';

/// Raw Dio calls for /api/v1/chat.
class ChatApi {
  static const _uuid = Uuid();
  final Dio _dio;

  ChatApi() : _dio = ApiClient().dio;

  /// POST /chat/conversations/open-group
  Future<Conversation> openGroupConversation(String groupId) async {
    try {
      final r = await _dio.post(
        '/chat/conversations/open-group',
        data: {'group_id': groupId},
      );
      return Conversation.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// GET /chat/conversations/{id}/messages
  Future<List<Message>> listMessages(String conversationId,
      {int limit = 50, String? cursor}) async {
    try {
      final r = await _dio.get(
        '/chat/conversations/$conversationId/messages',
        queryParameters: {
          'limit': limit,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final data = r.data['data'];
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(Message.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /chat/conversations/{id}/messages — sends a text message.
  /// Adds a `client_message_id` and `Idempotency-Key` for safe retries.
  Future<Message> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    try {
      final idempotencyKey = _uuid.v4();
      final r = await _dio.post(
        '/chat/conversations/$conversationId/messages',
        data: {
          'content': content,
          'client_message_id': _uuid.v4(),
        },
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return Message.fromJson(r.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// POST /chat/conversations/{id}/read
  Future<void> markRead({
    required String conversationId,
    required String lastReadMessageId,
  }) async {
    try {
      await _dio.post(
        '/chat/conversations/$conversationId/read',
        data: {'last_read_message_id': lastReadMessageId},
      );
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  /// DELETE /chat/messages/{id}
  Future<void> deleteMessage(String messageId) async {
    try {
      await _dio.delete('/chat/messages/$messageId');
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }
}
