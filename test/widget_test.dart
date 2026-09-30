import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:audionotebook/main.dart';
import 'package:audionotebook/model/voice_segment.dart';
import 'package:audionotebook/utils/vad.dart';

void main() {
  test('updates segment timing', () {
    final segment = Segment(index: 0, start: 1, end: 2);

    segment.setTiming(start: 1.5, end: 2.5);

    expect(segment.start, 1.5);
    expect(segment.end, 2.5);
  });

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
    for (var index = 0; index < 3000; index++) {
      final inFirstBurst = index >= 100 && index < 1300;
      final inSecondBurst = index >= 1600 && index < 2800;
      final inVoice = inFirstBurst || inSecondBurst;
      samples.add(inVoice ? 0.2 * math.sin(index * 1.2) : 0.001);
    }

    final segments = await detectVoiceSegments(samples, 1000);

    expect(segments.length, 2);
    expect(segments.first.start, closeTo(0.033, 0.03));
    expect(segments.first.end, closeTo(0.433, 0.03));
    expect(segments.last.start, closeTo(0.533, 0.03));
    expect(segments.last.end, closeTo(0.933, 0.03));
  });

  test('discards voice activity regions shorter than one second', () async {
    final samples = <double>[];
    for (var index = 0; index < 3000; index++) {
      final inShortBurst = index >= 100 && index < 950;
      final inLongBurst = index >= 1400 && index < 2700;
      samples.add(
        inShortBurst || inLongBurst ? 0.2 * math.sin(index * 1.2) : 0.001,
      );
    }

    final segments = await detectVoiceSegments(samples, 1000);

    expect(segments.length, 1);
    expect(segments.single.start, closeTo(0.433, 0.03));
    expect(segments.single.end, closeTo(0.9, 0.03));
  });

  test('joins short inactive gaps inside one voice region', () async {
    final samples = <double>[];
    for (var index = 0; index < 3000; index++) {
      final inVoice = index >= 100 && index < 2850;
      final shortGap = index >= 1400 && index < 1420;
      samples.add(inVoice && !shortGap ? 0.2 * math.sin(index * 1.2) : 0.001);
    }

    final segments = await detectVoiceSegments(samples, 1000);

    expect(segments.length, 1);
    expect(segments.single.start, closeTo(0.033, 0.03));
    expect(segments.single.end, closeTo(0.95, 0.03));
  });
}
