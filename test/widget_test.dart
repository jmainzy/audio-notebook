import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:audionotebook/main.dart';
import 'package:audionotebook/utils/vad.dart';

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

  test('detects separated voice activity regions', () async {
    final samples = <double>[];
    for (var index = 0; index < 1000; index++) {
      final inFirstBurst = index >= 100 && index < 300;
      final inSecondBurst = index >= 600 && index < 850;
      final inVoice = inFirstBurst || inSecondBurst;
      samples.add(inVoice ? 0.2 * math.sin(index * 1.2) : 0.001);
    }

    final segments = await detectVoiceSegments(samples, 1000);

    expect(segments.length, 2);
    expect(segments.first.start, closeTo(0.1, 0.03));
    expect(segments.first.end, closeTo(0.3, 0.03));
    expect(segments.last.start, closeTo(0.6, 0.03));
    expect(segments.last.end, closeTo(0.85, 0.03));
  });

  test('joins short inactive gaps inside one voice region', () async {
    final samples = <double>[];
    for (var index = 0; index < 1000; index++) {
      final inVoice = index >= 100 && index < 850;
      final shortGap = index >= 400 && index < 420;
      samples.add(inVoice && !shortGap ? 0.2 * math.sin(index * 1.2) : 0.001);
    }

    final segments = await detectVoiceSegments(samples, 1000);

    expect(segments.length, 1);
    expect(segments.single.start, closeTo(0.1, 0.03));
    expect(segments.single.end, closeTo(0.85, 0.03));
  });
}
