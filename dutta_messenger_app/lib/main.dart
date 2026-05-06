import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/auth/auth_events.dart';
import 'core/auth/auth_session.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/presentation/login_screen.dart';
import 'services/chat_service.dart';
import 'services/push_token_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  runApp(const DuttaMessengerApp());
}

/// Root application widget for DuttaMessenger.
class DuttaMessengerApp extends StatefulWidget {
  const DuttaMessengerApp({super.key});

  @override
  State<DuttaMessengerApp> createState() => _DuttaMessengerAppState();
}

class _DuttaMessengerAppState extends State<DuttaMessengerApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _wsErrorSub;
  StreamSubscription<AuthEvent>? _authEventSub;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    // Surface server-side `{"type":"error"}` WS frames as SnackBars so
    // problems (`not_a_member`, `subscribe_first`, …) become visible
    // instead of vanishing into a debug log.
    _wsErrorSub = ChatService.instance.errors.listen((message) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFFF4757),
          behavior: SnackBarBehavior.floating,
          content: Text('Chat: $message'),
        ),
      );
    });

    // The single global handler for forced and user-initiated logout.
    // Refresh failures and revocation 403s emit through this bus from
    // the Dio interceptor; the sign-out button emits through it too.
    _authEventSub = AuthEvents.instance.stream.listen(_handleAuthEvent);
  }

  Future<void> _handleAuthEvent(AuthEvent event) async {
    // Multiple in-flight HTTP calls can each see a 401 / revocation
    // 403 within milliseconds and emit. The first one wins; the rest
    // become no-ops.
    if (_signingOut) return;
    _signingOut = true;
    try {
      // Tear down side-effects in the order that minimises late
      // surprises: stop scheduling refreshes, drop the chat socket,
      // best-effort revoke FCM, and only then clear local tokens.
      AuthSession.instance.cancel();
      ChatService.instance.disconnect();
      try {
        await PushTokenService.instance.revokeAndForget();
      } catch (_) {/* best-effort */}
      await SecureTokenStorage.clearAll();

      final nav = _navigatorKey.currentState;
      if (nav != null) {
        await nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }

      final message = switch (event) {
        AuthEvent.sessionExpired => 'Your session expired. Please log in again.',
        AuthEvent.forbidden => 'Your access has been revoked.',
        AuthEvent.userLoggedOut => null,
      };
      if (message != null) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF4757),
            behavior: SnackBarBehavior.floating,
            content: Text(message),
          ),
        );
      }
    } finally {
      _signingOut = false;
    }
  }

  @override
  void dispose() {
    _wsErrorSub?.cancel();
    _authEventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Datta Messenger',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF667EEA),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0C29),
      ),
      home: const LoginScreen(),
    );
  }
}
