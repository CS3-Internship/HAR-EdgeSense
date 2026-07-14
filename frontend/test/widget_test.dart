import 'package:flutter_test/flutter_test.dart';
import 'package:edge_sense/main.dart';

void main() {
  testWidgets('EdgeSense smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EdgeSenseApp());

    // Verify the app starts on the session entry screen.
    expect(find.text('EdgeSense'), findsOneWidget);
    expect(find.text('Start Session'), findsOneWidget);
  });
}
