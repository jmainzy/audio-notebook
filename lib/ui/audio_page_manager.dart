import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audionotebook/model/voice_segment.dart';
import 'package:audionotebook/services/audio_service.dart';
import 'package:audionotebook/ui/audio_page_state.dart';
import 'package:audionotebook/utils/vad.dart';
import 'package:audionotebook/vad/model.dart' as model;
import 'package:audionotebook/vad/vad_asr_manager.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_audio_toolkit/flutter_audio_toolkit.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:wav/wav_file.dart';

Logger logger = Logger();

class AudioPageManager extends ValueNotifier<AudioPageState> {
  final AudioService _audioService = AudioService();
  final playbackPosition = ValueNotifier(Duration.zero);
  final audioToolkit = FlutterAudioToolkit();
  late final VadAsrManager _asrManager;

  AudioPageManager() : super(AudioPageState(zoomLevel: 10.0)) {
    _audioService.positionStream.listen((pos) {
      playbackPosition.value = pos;
    });
    _audioService.stateStream.listen((s) {
      value = value.copyWith(isPlaying: s.playing);
    });
  }

  // Future<sherpa_onnx.OfflineRecognizer> createOfflineRecognizer() async {
  //   final type = 2;
  //   final modelConfig = await getOfflineModelConfig(type: type);
  //   final config = sherpa_onnx.OfflineRecognizerConfig(model: modelConfig);
  //   return sherpa_onnx.OfflineRecognizer(config);
  // }

  Future<void> loadAudio(String filepath) async {
    try {
      final duration = await _audioService.load(filepath);
      value = value.copyWith(
        audioPath: filepath,
        audioDuration: duration,
        fragments: const [],
      );
      await _restoreSegments(filepath);
      _generateWaveform(filepath);
      // _asrService = await createOfflineRecognizer();
      _asrManager = VadAsrManager();
    } catch (error) {
      // if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _generateWaveform(String audioPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) await tempDir.create(recursive: true);

      final stat = await File(audioPath).stat();
      final fileHash = '${stat.size}_${stat.modified.millisecondsSinceEpoch}';

      final waveFile = File(
        path.join(tempDir.path, '${path.basename(audioPath)}_$fileHash.wave'),
      );

      JustWaveform.extract(
        audioInFile: File(audioPath),
        waveOutFile: waveFile,
      ).listen((event) {
        if (event.waveform != null) {
          value = value.copyWith(waveform: event.waveform);
        }
      });
    } catch (e) {
      debugPrint("Waveform error: $e");
    }
  }

  Future<void> detectSegments() async {
    value = value.copyWith(isSegmenting: true);
    try {
      final audioPath = value.audioPath;
      if (audioPath == null) return;

      final bytes = await File(audioPath).readAsBytes();
      final wav = Wav.read(bytes);
      sampleRate = wav.samplesPerSecond;
      final audioData = wav.channels[0];
      final detected = await detectVoiceSegments(audioData, sampleRate);
      final durationSeconds = value.audioDuration.inMilliseconds / 1000.0;

      // VAD returns normalized positions; the waveform painter uses seconds.
      final segments = [
        for (var index = 0; index < detected.length; index++)
          Segment(
            index: index,
            start: detected[index].start * durationSeconds,
            end: detected[index].end * durationSeconds,
            text: detected[index].text,
          ),
      ];
      value = value.copyWith(fragments: segments);
      await _saveSegments(audioPath, segments);
    } finally {
      value = value.copyWith(isSegmenting: false);
    }
  }

  Future<File> _segmentsCacheFile() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(path.join(directory.path, 'segments.json'));
  }

  Future<void> _restoreSegments(String audioPath) async {
    try {
      final cacheFile = await _segmentsCacheFile();
      if (!await cacheFile.exists()) return;

      final cache = jsonDecode(await cacheFile.readAsString());
      final stored = cache[audioPath];
      if (stored is! List) return;

      final segments = stored
          .whereType<Map>()
          .map(
            (item) => Segment(
              index: item['index'] as int,
              start: (item['start'] as num).toDouble(),
              end: (item['end'] as num).toDouble(),
              text: item['text'] as String? ?? '',
            ),
          )
          .toList();
      value = value.copyWith(fragments: segments);
    } catch (error) {
      logger.w('Could not restore saved segments: $error');
    }
  }

  Future<void> _saveSegments(String audioPath, List<Segment> segments) async {
    try {
      final cacheFile = await _segmentsCacheFile();
      final cache = <String, dynamic>{};
      if (await cacheFile.exists()) {
        final existing = jsonDecode(await cacheFile.readAsString());
        if (existing is Map) {
          cache.addAll(Map<String, dynamic>.from(existing));
        }
      }
      cache[audioPath] = [
        for (final segment in segments)
          {
            'index': segment.index,
            'start': segment.start,
            'end': segment.end,
            'text': segment.text,
          },
      ];
      await cacheFile.writeAsString(jsonEncode(cache));
    } catch (error) {
      logger.w('Could not save segments: $error');
    }
  }

  Future<bool> _initAsrIfNeeded() async {
    if (_asrManager.state != VadAsrState.uninitialized) return true;
    try {
      // Copy model assets to disk and get resolved paths.
      await model.prepareModelConfig();
      final dirs = await model.prepareModelDirs();
      await _asrManager.init(
        modelDir: dirs.asrModelDir,
        vadModelDir: dirs.baseDir,
      );
      return true;
    } catch (e) {
      logger.e("error initializing ASR: $e");
      return false;
    }
  }

  Future<void> transcribe() async {
    value = value.copyWith(isTranscribing: true);
    logger.i('transcribe');
    // _asrService ??= await createOfflineRecognizer();
    final filename = value.audioPath!;

    final decoded = await decodeAudioFile(filename);
    if (decoded == null) {
      logger.e("Error decoding file");
      return;
    }

    _initAsrIfNeeded();

    _asrManager.runVad(
      samples: decoded.samples,
      sampleRate: decoded.sampleRate,
      threshold: 0.02,
      minSilenceDuration: 1,
      minSpeechDuration: 0.2,
      maxSpeechDuration: 7,
    );

    value = value.copyWith(isTranscribing: false);
  }

  Future<String> writeTempWav(String filename) async {
    const targetRate = 16000;

    final directory = await getTemporaryDirectory();
    final outputPath = path.join(
      directory.path,
      '${path.basenameWithoutExtension(filename)}_16khz.wav',
    );
    audioToolkit.convertAudio(
      inputPath: filename,
      outputPath: outputPath,
      format: AudioFormat.copy,
      sampleRate: targetRate,
    );

    return outputPath;
  }

  void selectFragment(int? index) {
    value = value.copyWith(selectedFragmentIndex: index);
  }

  void enterFocusMode(int index) {
    if (value.audioDuration.inMilliseconds == 0) return;

    final totalSeconds = value.audioDuration.inMilliseconds / 1000.0;
    final targetZoom = (totalSeconds / 10.0).clamp(1.0, 500.0);

    final startSeconds = value.fragments[index].start;

    seekTo(Duration(milliseconds: (startSeconds * 1000).ceil()));

    value = value.copyWith(zoomLevel: targetZoom, focusedFragmentIndex: index);
  }

  void exitFocusMode() {
    value = value.copyWith(clearFocus: true);
  }

  void setZoom(double z) {
    final clampedZoom = z.clamp(1.0, 500.0);
    value = value.copyWith(zoomLevel: clampedZoom);
    // _settings.setLastZoom(clampedZoom);
  }

  void setHoveredFragmentIndex(int? hoveredIdx) {}

  void seekTo(Duration d) => _audioService.seek(d);

  Future<void> togglePlayback() async {
    if (value.isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  void toggleFragmentPin(int index) {}

  void clearFragmentTiming(int index) {
    if (value.isReadOnly) return;
    final frags = List<Segment>.from(value.fragments);
    final duration = value.audioDuration.inMilliseconds / 1000.0;

    Segment? prevTimed;
    for (int i = index - 1; i >= 0; i--) {
      if (frags[i].start >= 0) {
        prevTimed = frags[i];
        break;
      }
    }
    Segment? nextTimed;
    for (int i = index + 1; i < frags.length; i++) {
      if (frags[i].start >= 0) {
        nextTimed = frags[i];
        break;
      }
    }

    if (prevTimed != null) {
      double newEnd = nextTimed != null ? nextTimed.start : duration;
      prevTimed.setTiming(start: prevTimed.start, end: newEnd);
    }

    frags[index].setTiming(start: -1.0, end: -1.0);
    // frags[index].clearPinnedTiming();

    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
  }

  void updateFragment(int index, double newStart, double newEnd) {
    if (value.isReadOnly) return;
    final frags = List<Segment>.from(value.fragments);
    final duration = value.audioDuration.inMilliseconds / 1000.0;

    double s = newStart.clamp(0.0, duration);
    double e = newEnd.clamp(0.0, duration);

    if (e <= s + 0.01) {
      if (s != frags[index].start) {
        s = e - 0.01;
      } else {
        e = s + 0.01;
      }
    }

    frags[index].setTiming(start: s, end: e);

    Segment? prevTimed;
    for (int i = index - 1; i >= 0; i--) {
      if (frags[i].start >= 0) {
        prevTimed = frags[i];
        break;
      }
    }
    if (prevTimed != null) {
      double prevStart = prevTimed.start;
      if (prevStart > s) prevStart = s;
      prevTimed.setTiming(start: prevStart, end: s);
    }

    Segment? nextTimed;
    for (int i = index + 1; i < frags.length; i++) {
      if (frags[i].start >= 0) {
        nextTimed = frags[i];
        break;
      }
    }
    if (nextTimed != null) {
      double nextEnd = nextTimed.end;
      if (nextEnd < e) nextEnd = e;
      nextTimed.setTiming(start: e, end: nextEnd);
    }

    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
  }

  void captureFragmentTiming(BuildContext context, int i) {}

  /// Decode audio bytes to 16kHz mono Float32 PCM samples using FFmpeg.
  /// Returns null if decoding fails.
  Future<DecodedAudio?> decodeAudioBytes(Uint8List bytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      await tempDir.create(recursive: true);
      final inputPath =
          '${tempDir.path}/vad_input_${DateTime.now().microsecondsSinceEpoch}';
      final file = File(inputPath);
      await file.writeAsBytes(bytes);
      final result = await _decodePath(inputPath);
      try {
        await file.delete();
      } catch (_) {}
      return result;
    } catch (e) {
      print('Audio decode error: $e');
      return null;
    }
  }

  /// Decode an audio file to 16kHz mono Float32 PCM samples using FFmpeg.
  /// Returns null if decoding fails.
  Future<DecodedAudio?> decodeAudioFile(String filePath) async {
    return _decodePath(filePath);
  }

  Future<DecodedAudio?> _decodePath(String filePath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      await tempDir.create(recursive: true);
      final outputPath =
          '${tempDir.path}/decoded_${DateTime.now().microsecondsSinceEpoch}.raw';

      // Use FFmpeg to convert any audio/video to 16kHz mono Float32 PCM.
      final command =
          '-i "$filePath" -ar 16000 -ac 1 -f f32le -acodec pcm_f32le -y "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getOutput();
        print('FFmpeg error: $logs');
        return null;
      }

      final outFile = File(outputPath);
      if (!await outFile.exists()) {
        print('FFmpeg output file not found: $outputPath');
        return null;
      }

      final bytes = await outFile.readAsBytes();
      await outFile.delete();

      if (bytes.length < 4) return null;

      final numSamples = bytes.length ~/ 4;
      final samples = Float32List(numSamples);
      final bd = bytes.buffer.asByteData(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      for (int i = 0; i < numSamples; i++) {
        samples[i] = bd.getFloat32(i * 4, Endian.little);
      }

      final duration = numSamples / 16000.0;

      return DecodedAudio(
        samples: samples,
        sampleRate: 16000,
        duration: duration,
      );
    } catch (e) {
      print('Audio decode error: $e');
      return null;
    }
  }
}

/// Result of decoding an audio file.
class DecodedAudio {
  final Float32List samples;
  final int sampleRate;
  final double duration;
  const DecodedAudio({
    required this.samples,
    required this.sampleRate,
    required this.duration,
  });
}
