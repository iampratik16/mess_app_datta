import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-wide configuration. `API_BASE` is the only URL source — read from
/// `.env` at startup (see `main.dart` → `dotenv.load()`). Never hardcode
/// the backend URL anywhere else in the app; that's a one-way ticket to
/// shipping a build that points at a dead dev tunnel. See
/// `docs/ui-contract/environments.md`.
class AppConfig {
  /// The backend's public URL, loaded from the `.env` asset at startup.
  /// For the production DuttaMessenger deployment this is
  /// `https://dattamessenger.duckdns.org`.
  static String get apiBaseUrl => dotenv.env['API_BASE'] ?? '';

  static const String apiVersion = '/api/v1';
  static String get baseUrl => '$apiBaseUrl$apiVersion';

  /// Credentials that pre-fill the login form. Override per-device at
  /// build time:
  ///   flutter build ios ... \
  ///       --dart-define=DEFAULT_EMAIL=alice@demo.test \
  ///       --dart-define=DEFAULT_PASSWORD=DemoP@ss123!
  static const String defaultLoginEmail = String.fromEnvironment(
    'DEFAULT_EMAIL',
    defaultValue: 'admin@demo.school',
  );
  static const String defaultLoginPassword = String.fromEnvironment(
    'DEFAULT_PASSWORD',
    defaultValue: 'Pratik@16abab',
  );
}
