import 'package:audionotebook/model/voice_segment.dart';

/// A simple energy-based Voice Activity Detection (VAD) algorithm.
///
/// This is a Dart port of a Python `EnergyVAD` class that operated on
/// `np.ndarray`. Here the input is a `List<double>` representing a mono
/// waveform with samples already normalized to the range [-1, 1] (as you'd
/// get after decoding raw audio bytes). Because the input is guaranteed to
/// be a flat, single-channel list, the original stereo-detection /
/// mono-conversion step has been dropped.
///
///
///
final int frameShift = 20; // milliseconds
final double energyThreshold = 0.1;
final double preEmphasis = 0.90;
const int _silenceGapToleranceMs = 250;
const int _targetSegmentDurationMs = 8000;
int sampleRate = 16000;
int frameLength = 25;

Future<List<Segment>> detectVoiceSegments(
  List<double> waveform,
  int sampleR,
) async {
  if (waveform.isEmpty || sampleR <= 0) return <Segment>[];

  sampleRate = sampleR;
  final decisions = detect(waveform);
  return _decisionsToSegments(decisions, waveform.length);
}

/// Dart classes can define a `call` method, which lets an instance be
/// invoked like a function: `final vad = EnergyVad(); vad(waveform);`
/// This mirrors Python's `__call__`.
///
/// Returns one entry per frame: 1 if that frame is voiced, 0 otherwise.
List<int> detect(List<double> waveform) {
  final preEmphasized = _applyPreEmphasis(waveform);
  final energy = computeEnergy(preEmphasized);
  return computeVad(energy);
}

List<double> _applyPreEmphasis(List<double> waveform) {
  if (waveform.isEmpty) return <double>[];

  final result = List<double>.filled(waveform.length, 0.0);
  result[0] = waveform[0];
  for (var i = 1; i < waveform.length; i++) {
    result[i] = waveform[i] - preEmphasis * waveform[i - 1];
  }
  return result;
}

/// Computes the per-frame energy (sum of squared samples) of [waveform].
List<double> computeEnergy(List<double> waveform) {
  final frameLenSamples = frameLength * sampleRate ~/ 1000;
  final frameShiftSamples = frameShift * sampleRate ~/ 1000;

  final numFrames =
      (waveform.length - frameLenSamples + frameShiftSamples) ~/
      frameShiftSamples;

  // Guard against a waveform shorter than one frame, which would make
  // numFrames negative (the Python version would raise instead).
  if (numFrames <= 0) return <double>[];

  final energy = List<double>.filled(numFrames, 0.0);
  for (var i = 0; i < numFrames; i++) {
    final start = i * frameShiftSamples;
    final end = start + frameLenSamples;
    var sum = 0.0;
    for (var j = start; j < end; j++) {
      sum += waveform[j] * waveform[j];
    }
    energy[i] = sum;
  }
  return energy;
}

/// Thresholds [energy] into a binary VAD decision per frame.
List<int> computeVad(List<double> energy) {
  return energy.map((e) => e > energyThreshold ? 1 : 0).toList();
}

List<Segment> _decisionsToSegments(List<int> decisions, int sampleCount) {
  if (decisions.isEmpty || sampleCount == 0) return <Segment>[];

  final frameShiftSamples = frameShift * sampleRate ~/ 1000;
  final frameLengthSamples = frameLength * sampleRate ~/ 1000;
  final gapToleranceFrames =
      (_silenceGapToleranceMs + frameShift - 1) ~/ frameShift;
  final smoothedDecisions = _fillShortGaps(decisions, gapToleranceFrames);
  final segments = <Segment>[];
  var startSample = -1;

  for (var frame = 0; frame <= smoothedDecisions.length; frame++) {
    final voiced =
        frame < smoothedDecisions.length && smoothedDecisions[frame] == 1;
    if (voiced && startSample == -1) {
      startSample = frame * frameShiftSamples;
    } else if (!voiced && startSample != -1) {
      final endSample = ((frame - 1) * frameShiftSamples + frameLengthSamples)
          .clamp(startSample, sampleCount);
      if (endSample - startSample >= sampleRate) {
        segments.addAll(
          _splitIntoTargetSegments(startSample, endSample, sampleCount),
        );
      }
      startSample = -1;
    }
  }

  return segments;
}

List<int> _fillShortGaps(List<int> decisions, int gapToleranceFrames) {
  final smoothed = List<int>.from(decisions);
  var frame = 0;
  while (frame < smoothed.length) {
    if (smoothed[frame] == 1) {
      frame++;
      continue;
    }

    final gapStart = frame;
    while (frame < smoothed.length && smoothed[frame] == 0) {
      frame++;
    }
    final gapEnd = frame;
    final gapIsInternal = gapStart > 0 && gapEnd < smoothed.length;
    if (gapIsInternal && gapEnd - gapStart <= gapToleranceFrames) {
      for (var index = gapStart; index < gapEnd; index++) {
        smoothed[index] = 1;
      }
    }
  }
  return smoothed;
}

List<Segment> _splitIntoTargetSegments(
  int startSample,
  int endSample,
  int sampleCount,
) {
  final targetSamples = _targetSegmentDurationMs * sampleRate ~/ 1000;
  final duration = endSample - startSample;
  final segmentCount = (duration + targetSamples - 1) ~/ targetSamples;
  final segmentLength = (duration / segmentCount).round();
  final segments = <Segment>[];

  for (var index = 0; index < segmentCount; index++) {
    final segmentStart = startSample + index * segmentLength;
    final segmentEnd = index == segmentCount - 1
        ? endSample
        : startSample + (index + 1) * segmentLength;
    segments.add(
      Segment(
        start: (segmentStart / sampleCount).clamp(0.0, 1.0),
        end: (segmentEnd / sampleCount).clamp(0.0, 1.0),
        index: index,
      ),
    );
  }
  return segments;
}

/// Returns [waveform] with only the voiced frames kept, concatenated.
List<double> applyVad(List<double> waveform) {
  final vad = detect(waveform);
  final shift = frameShift * sampleRate ~/ 1000;

  final result = <double>[];
  for (var i = 0; i < vad.length; i++) {
    if (vad[i] == 1) {
      final start = i * shift;
      final end = (start + shift < waveform.length)
          ? start + shift
          : waveform.length;
      result.addAll(waveform.sublist(start, end));
    }
  }
  return result;
}
