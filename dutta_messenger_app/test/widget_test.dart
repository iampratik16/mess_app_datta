import 'package:flutter_test/flutter_test.dart';
import 'package:dutta_messenger_app/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DuttaMessengerApp());
    expect(find.text('DuttaMessenger'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
