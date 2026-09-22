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
final double energyThreshold = 0.05;
final double preEmphasis = 0.95;
int sampleRate = 16000;
int frameLength = 25;

Future<List<VoiceSegment>> detectVoiceSegments(
  List<double> waveform,
  int sampleR,
) async {
  if (waveform.isEmpty || sampleR <= 0) return <VoiceSegment>[];

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

List<VoiceSegment> _decisionsToSegments(List<int> decisions, int sampleCount) {
  if (decisions.isEmpty || sampleCount == 0) return <VoiceSegment>[];

  final frameShiftSamples = frameShift * sampleRate ~/ 1000;
  final frameLengthSamples = frameLength * sampleRate ~/ 1000;
  final segments = <VoiceSegment>[];
  var startSample = -1;

  for (var frame = 0; frame <= decisions.length; frame++) {
    final voiced = frame < decisions.length && decisions[frame] == 1;
    if (voiced && startSample == -1) {
      startSample = frame * frameShiftSamples;
    } else if (!voiced && startSample != -1) {
      final endSample = ((frame - 1) * frameShiftSamples + frameLengthSamples)
          .clamp(startSample, sampleCount);
      segments.add(
        VoiceSegment(
          start: (startSample / sampleCount).clamp(0.0, 1.0),
          end: (endSample / sampleCount).clamp(0.0, 1.0),
        ),
      );
      startSample = -1;
    }
  }

  return _mergeNearbySegments(segments, sampleCount);
}

List<VoiceSegment> _mergeNearbySegments(
  List<VoiceSegment> segments,
  int sampleCount,
) {
  if (segments.length < 2) return segments;

  final merged = <VoiceSegment>[segments.first];
  final maxGap = (frameShift * sampleRate / 1000) / sampleCount;
  for (final segment in segments.skip(1)) {
    final previous = merged.last;
    if (segment.start - previous.end <= maxGap) {
      merged[merged.length - 1] = VoiceSegment(
        start: previous.start,
        end: segment.end,
      );
    } else {
      merged.add(segment);
    }
  }
  return merged;
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
