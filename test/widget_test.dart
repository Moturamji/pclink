import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/main.dart';

void main() {
  testWidgets('PCLink smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PCLinkApp());

    // Verify that the title 'PCLink' is rendered
    expect(find.text('PCLink'), findsOneWidget);
  });
}
