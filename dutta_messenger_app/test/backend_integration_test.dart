import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dutta_messenger_app/features/auth/data/auth_repository.dart';
import 'package:dutta_messenger_app/features/auth/domain/auth_models.dart';

// Restore real HttpClient — flutter_test default returns 400 for all requests.
class _RealHttpOverrides extends HttpOverrides {}

void main() {
  HttpOverrides.global = _RealHttpOverrides();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Backend Integration Tests', () {
    final repo = AuthRepository();

    test('1. Login with admin credentials', () async {
      final user = await repo.login(
        email: 'admin@smoke.test',
        password: 'Sup3rStr0ng!',
      );
      expect(user, isA<AuthUser>());
      expect(user.email, 'admin@smoke.test');
      expect(user.status, 'offline');
    });

    test('2. Tokens are stored securely', () async {
      final hasToken = await repo.isLoggedIn();
      expect(hasToken, isTrue);
    });

    test('3. Invite a new user (Authenticated Request)', () async {
      final inviteEmail = 'test-e2e-${DateTime.now().millisecondsSinceEpoch}@smoke.test';
      final response = await repo.inviteUser(email: inviteEmail);
      expect(response.message, contains('Invitation sent'));
    });

    test('4. Logout clears tokens', () async {
      await repo.logout();
      final hasToken = await repo.isLoggedIn();
      expect(hasToken, isFalse);
    });
  });
}
