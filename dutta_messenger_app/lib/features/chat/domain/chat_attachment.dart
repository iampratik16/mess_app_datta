import 'dart:convert';

/// Parsed attachment riding on a chat message's `content` field.
///
/// The backend's `SendMessageRequest` accepts only `content` today — no
/// `media_file_ids`. To ship file/image sharing without a backend change
/// we encode the attachment metadata as a header inside `content`:
///
/// ```
/// [attachment:v1]
/// {"id":"<media_id>","name":"photo.jpg","mime":"image/jpeg","size":12345}
/// optional caption text (may be multi-line)
/// ```
///
/// Clients that don't understand the header still see readable text
/// (useful for debugging). Receivers that DO understand it fetch the
/// media metadata + presigned URL lazily via `/api/v1/media/{id}`.
class ChatAttachment {
  static const _header = '[attachment:v1]';

  final String mediaId;
  final String fileName;
  final String mimeType;
  final int fileSize;

  const ChatAttachment({
    required this.mediaId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isDocument => !isImage && !isVideo && !isAudio;

  /// Encode [attachment] + optional [caption] into a single `content`
  /// string suitable for POST /chat/.../messages.
  static String encode(ChatAttachment attachment, {String? caption}) {
    final payload = jsonEncode({
      'id': attachment.mediaId,
      'name': attachment.fileName,
      'mime': attachment.mimeType,
      'size': attachment.fileSize,
    });
    final trailer = (caption == null || caption.trim().isEmpty)
        ? ''
        : '\n${caption.trim()}';
    return '$_header\n$payload$trailer';
  }

  /// Returns null if [content] is a plain text message.
  static ParsedMessage parse(String content) {
    if (!content.startsWith(_header)) {
      return ParsedMessage(text: content);
    }
    final rest = content.substring(_header.length).trimLeft();
    final newline = rest.indexOf('\n');
    final jsonLine = newline == -1 ? rest : rest.substring(0, newline);
    final caption = newline == -1 ? '' : rest.substring(newline + 1).trim();
    try {
      final decoded = jsonDecode(jsonLine) as Map<String, dynamic>;
      final att = ChatAttachment(
        mediaId: decoded['id'] as String,
        fileName: decoded['name'] as String? ?? 'attachment',
        mimeType: decoded['mime'] as String? ?? 'application/octet-stream',
        fileSize: (decoded['size'] as num?)?.toInt() ?? 0,
      );
      return ParsedMessage(attachment: att, text: caption);
    } catch (_) {
      return ParsedMessage(text: content);
    }
  }
}

/// Result of [ChatAttachment.parse]. Either [attachment] is non-null
/// (file/image message, [text] holds caption), or it's null (plain text,
/// [text] holds the whole body).
class ParsedMessage {
  final ChatAttachment? attachment;
  final String text;
  const ParsedMessage({this.attachment, this.text = ''});

  bool get hasAttachment => attachment != null;
  bool get hasText => text.trim().isNotEmpty;
}
