/// App-wide configuration. Update ngrokBaseUrl every time you restart ngrok.
class AppConfig {
  // Default: ngrok HTTPS tunnel for mobile device testing.
  // For web testing against a local backend, swap to http://127.0.0.1:8765.
  static const String ngrokBaseUrl =
      'https://pried-unbent-prelude.ngrok-free.dev';
  // static const String ngrokBaseUrl = 'http://127.0.0.1:8765';

  static const String apiVersion = '/api/v1';
  static String get baseUrl => '$ngrokBaseUrl$apiVersion';

  // Required on every request to ngrok tunnels.
  static const Map<String, String> ngrokHeaders = {
    'ngrok-skip-browser-warning': '1',
  };
}

