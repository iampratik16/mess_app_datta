import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../core/auth/auth_session.dart';
import '../core/storage/secure_storage.dart';

/// Real-time chat connection. One instance per logged-in user.
///
/// Token rotation: subscribes to [AuthSession.rotated] in [connect] so a
/// proactive `/auth/refresh` (or a 401-driven one) automatically tears
/// down the current socket and re-authenticates with the new JWT. The
/// audit identified mid-session WS-auth staleness as the dominant cause
/// of "tokens kept expiring during testing" — this is the fix.
///
/// Heartbeat: a 25 s `ping` keeps NATs / load balancers from silently
/// killing idle sockets, and a 10 s pong watchdog detects half-open
/// connections (where the TCP layer thinks it's fine but the peer is
/// gone) so we can reconnect proactively instead of waiting for a send
/// to fail.
///
/// Usage:
///   ChatService.instance.connect(jwtAccessToken);     // on login
///   ChatService.instance.subscribe(conversationId);   // when opening a chat screen
///   ChatService.instance.messages(conversationId)     // returns Stream<Map>
///   ChatService.instance.connected                    // listen to refetch on reconnect
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
  // Fires every time the server confirms a (re-)authenticated session.
  // ChatScreen listens to this to re-fetch missed messages after a
  // reconnect (the audit's smoke-test step about pulling the cable).
  final StreamController<void> _connectedController =
      StreamController<void>.broadcast();
  // Fires when the server notifies that the current user's roles
  // changed (assign / revoke from another device). Profile / shell
  // listeners refetch /users/me to apply the new permissions without
  // requiring a sign-out (audit 4.7 cross-device gap).
  final StreamController<void> _roleChangedController =
      StreamController<void>.broadcast();
  // Per-group composition events. Carries `{group_id}` so listeners can
  // filter to "my open group" without re-fetching everything.
  final StreamController<String> _groupMembershipChangedController =
      StreamController<String>.broadcast();
  bool _authed = false;
  bool _disposed = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _pongWatchdog;
  StreamSubscription<void>? _rotatedSub;

  static const _heartbeatInterval = Duration(seconds: 25);
  static const _pongTimeout = Duration(seconds: 10);

  /// Broadcast stream of server-side error messages received over the
  /// chat WebSocket. Listen once at app shell level and show a SnackBar.
  Stream<String> get errors => _errorController.stream;

  /// Fires whenever the server has accepted a fresh `auth` frame and
  /// resubscribed the connection. First connect AND every reconnect.
  /// Use this to refetch any state that may have advanced during the
  /// gap (e.g. messages on the open chat screen).
  Stream<void> get connected => _connectedController.stream;

  /// Fires on every server-pushed `user.role_changed` frame for this
  /// user (cross-device role change). Listeners should refetch any
  /// permission-derived state — typically `GET /users/me`.
  Stream<void> get roleChanged => _roleChangedController.stream;

  /// Fires on `group.member_added` / `group.member_removed` frames.
  /// Stream payload is the affected `group_id`; listeners filter and
  /// refetch the group / member list as needed.
  Stream<String> get groupMembershipChanged =>
      _groupMembershipChangedController.stream;

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
    _rotatedSub ??= AuthSession.instance.rotated.listen((_) {
      reconnectWithFreshToken();
    });
    _openSocket();
  }

  /// Close the current socket and reopen with the latest access token
  /// from secure storage. Triggered by [AuthSession.rotated] after a
  /// successful refresh; safe to call manually too. No-op if the
  /// service has been disposed (logout).
  Future<void> reconnectWithFreshToken() async {
    if (_disposed) return;
    final newToken = await SecureTokenStorage.getAccessToken();
    if (newToken == null) return;
    _token = newToken;
    _heartbeatTimer?.cancel();
    _pongWatchdog?.cancel();
    _authed = false;
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {/* ignored */}
    _channel = null;
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
    _heartbeatTimer?.cancel();
    _pongWatchdog?.cancel();
    _rotatedSub?.cancel();
    _rotatedSub = null;
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
    final wsBase = apiBase
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final wsUrl = '$wsBase/api/v1/ws/chat';

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

    // Any inbound frame proves the peer is alive, so reset the pong
    // watchdog. This is intentionally more lenient than "only pong
    // resets it" — a chatty connection is by definition not dead.
    _pongWatchdog?.cancel();

    switch (frame['type']) {
      case 'connection.established':
        _authed = true;
        // Re-subscribe to everything (covers first-connect + reconnect)
        for (final cid in _subscribed) {
          _send({'type': 'subscribe', 'conversation_id': cid});
        }
        _startHeartbeat();
        if (!_connectedController.isClosed) _connectedController.add(null);
        break;
      case 'message.new':
        final msg = frame['message'] as Map<String, dynamic>?;
        if (msg == null) return;
        final cid = msg['conversation_id'] as String?;
        if (cid == null) return;
        final controller = _streams[cid];
        controller?.add(msg);
        break;
      case 'pong':
        // Already covered by the watchdog reset above; nothing else to do.
        break;
      case 'user.role_changed':
        if (!_roleChangedController.isClosed) {
          _roleChangedController.add(null);
        }
        break;
      case 'group.member_added':
      case 'group.member_removed':
        final gid = frame['group_id']?.toString();
        if (gid != null && !_groupMembershipChangedController.isClosed) {
          _groupMembershipChangedController.add(gid);
        }
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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_channel == null || !_authed) return;
      _send({'type': 'ping'});
      _pongWatchdog?.cancel();
      _pongWatchdog = Timer(_pongTimeout, () {
        // No frame at all in 10 s after a ping — connection is half-open.
        // Tear down and let _scheduleReconnect bring us back.
        try {
          _channel?.sink.close(ws_status.goingAway);
        } catch (_) {/* ignored */}
        _scheduleReconnect();
      });
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _authed = false;
    _channel = null;
    _heartbeatTimer?.cancel();
    _pongWatchdog?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), _openSocket);
  }
}
