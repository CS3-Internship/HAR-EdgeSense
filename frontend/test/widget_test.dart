import 'package:flutter_test/flutter_test.dart';
import 'package:edge_sense/main.dart';

void main() {
  testWidgets('EdgeSense smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EdgeSenseApp());

    // Verify that our app starts in the offline state.
    expect(find.text('Node Offline'), findsOneWidget);
    expect(find.text('Node Linked'), findsNothing);
  });
}
