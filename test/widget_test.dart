import 'package:flutter_test/flutter_test.dart';

import 'package:audionotebook/main.dart';

void main() {
  testWidgets('loads recordings from the example_audio folder', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Your recordings'), findsOneWidget);
    expect(find.text('Morning Birds, Tulsa'), findsNothing);
    expect(find.text('AUDIO NOTEBOOK'), findsOneWidget);
  });
}
