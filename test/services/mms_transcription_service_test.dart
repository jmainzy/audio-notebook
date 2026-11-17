import 'package:audionotebook/services/mms_transcription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeCtc', () {
    const tokens = {0: '|', 1: 'a', 2: 'v', 3: '[PAD]'};

    test(
      'collapses repeats, preserves repeats separated by blank, and spaces',
      () {
        final logits = <double>[
          0,
          5,
          0,
          0,
          0,
          5,
          0,
          0,
          0,
          0,
          0,
          5,
          0,
          5,
          0,
          0,
          5,
          0,
          0,
          0,
          0,
          0,
          5,
          0,
        ];

        expect(decodeCtc(logits, 4, tokens, 3), 'aa v');
      },
    );

    test('rejects incomplete output frames', () {
      expect(() => decodeCtc([1.0, 2.0], 4, tokens, 3), throwsFormatException);
    });
  });
}
