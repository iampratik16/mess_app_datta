import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'features/auth/presentation/login_screen.dart';
import 'services/chat_service.dart';

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
  StreamSubscription<String>? _wsErrorSub;

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
  }

  @override
  void dispose() {
    _wsErrorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DuttaMessenger',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
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
