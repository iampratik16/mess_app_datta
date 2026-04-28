import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

/// Real-time chat connection. One instance per logged-in user.
///
/// Usage:
///   ChatService.instance.connect(jwtAccessToken);     // on login
///   ChatService.instance.subscribe(conversationId);   // when opening a chat screen
///   ChatService.instance.messages(conversationId)     // returns Stream<Map>
///   ChatService.instance.disconnect();                // on logout
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  WebSocketChannel? _channel;
  String? _token;
  final Set<String> _subscribed = <String>{};
  final Map<String, StreamController<Map<String, dynamic>>> _streams = {};
  // Server-emitted error frames (`{"type":"error","message":"..."}`).
  // UI listens via [errors] to surface SnackBars without coupling the
  // service to BuildContext.
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  bool _authed = false;
  bool _disposed = false;
  Timer? _reconnectTimer;

  /// Broadcast stream of server-side error messages received over the
  /// chat WebSocket. Listen once at app shell level and show a SnackBar.
  Stream<String> get errors => _errorController.stream;

  /// Returns a broadcast stream of `message` objects for the given conversation.
  /// Safe to call before `connect` — the stream starts emitting once the socket
  /// is connected and subscribed.
  Stream<Map<String, dynamic>> messages(String conversationId) {
    final controller = _streams.putIfAbsent(
      conversationId,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );
    return controller.stream;
  }

  /// Open the WebSocket. Idempotent — calling twice with the same token is a no-op.
  void connect(String jwtAccessToken) {
    if (_token == jwtAccessToken && _channel != null) return;
    _token = jwtAccessToken;
    _disposed = false;
    _openSocket();
  }

  /// Subscribe to real-time messages for a conversation. Safe to call multiple
  /// times — duplicate subscribes are deduped server-side.
  void subscribe(String conversationId) {
    _subscribed.add(conversationId);
    if (_authed) {
      _send({'type': 'subscribe', 'conversation_id': conversationId});
    }
  }

  /// Close the socket permanently. Call on logout.
  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _authed = false;
    _subscribed.clear();
    for (final c in _streams.values) {
      c.close();
    }
    _streams.clear();
    _token = null;
  }

  // ---- internals -------------------------------------------------------

  void _openSocket() {
    final apiBase = dotenv.env['API_BASE'] ?? '';
    if (apiBase.isEmpty) {
      throw StateError('API_BASE missing from .env');
    }
    final wsUrl = apiBase
            .replaceFirst('https://', 'wss://')
            .replaceFirst('http://', 'ws://') +
        '/api/v1/ws/chat';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    } catch (_) {
      _scheduleReconnect();
      return;
    }

    _authed = false;
    _send({'type': 'auth', 'token': _token});

    _channel!.stream.listen(
      _onFrame,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _onFrame(dynamic raw) {
    final Map<String, dynamic> frame;
    try {
      frame = json.decode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (frame['type']) {
      case 'connection.established':
        _authed = true;
        // Re-subscribe to everything (covers first-connect + reconnect)
        for (final cid in _subscribed) {
          _send({'type': 'subscribe', 'conversation_id': cid});
        }
        break;
      case 'message.new':
        final msg = frame['message'] as Map<String, dynamic>?;
        if (msg == null) return;
        final cid = msg['conversation_id'] as String?;
        if (cid == null) return;
        final controller = _streams[cid];
        controller?.add(msg);
        break;
      case 'error':
        final m = frame['message']?.toString() ?? 'WebSocket error';
        if (!_errorController.isClosed) _errorController.add(m);
        break;
      default:
        // ignore subscribed, pong, etc.
        break;
    }
  }

  void _send(Map<String, dynamic> frame) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(json.encode(frame));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _authed = false;
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), _openSocket);
  }
}
