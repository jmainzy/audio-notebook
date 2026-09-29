import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audionotebook/model/voice_segment.dart';
import 'package:audionotebook/services/audio_service.dart';
import 'package:audionotebook/ui/audio_page_state.dart';
import 'package:audionotebook/utils/vad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:wav/wav_file.dart';

Logger logger = Logger();

const _modelAssetDirectory = 'assets/sherpa-model';
const _modelDirectory = 'sherpa-model';

class AudioPageManager extends ValueNotifier<AudioPageState> {
  final AudioService _audioService = AudioService();
  final playbackPosition = ValueNotifier(Duration.zero);

  AudioPageManager() : super(AudioPageState(zoomLevel: 10.0)) {
    _audioService.positionStream.listen((pos) {
      playbackPosition.value = pos;
    });
    _audioService.stateStream.listen((s) {
      value = value.copyWith(isPlaying: s.playing);
    });
  }

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

  Future<void> transcribe() async {
    final audioPath = value.audioPath;
    if (audioPath == null || value.isTranscribing) return;

    value = value.copyWith(isTranscribing: true);
    try {
      final wav = Wav.read(await File(audioPath).readAsBytes());
      if (wav.channels.isEmpty || wav.channels.first.isEmpty) {
        throw const FormatException('The audio file contains no samples.');
      }

      final samples = Float32List(wav.channels.first.length);
      for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
        var mixedSample = 0.0;
        for (final channel in wav.channels) {
          mixedSample += channel[sampleIndex];
        }
        samples[sampleIndex] = mixedSample / wav.channels.length;
      }

      final modelPaths = await _prepareSherpaModel();
      final sampleRate = wav.samplesPerSecond;
      final transcription = await Isolate.run(
        () => _transcribeWithSherpa(samples, sampleRate, modelPaths),
        debugName: 'Sherpa ASR',
      );
      final text = transcription.trim();
      final segments = text.isEmpty
          ? <Segment>[]
          : [
              Segment(
                index: 0,
                start: 0,
                end: samples.length / sampleRate,
                text: text,
              ),
            ];
      value = value.copyWith(fragments: segments);
      await _saveSegments(audioPath, segments);
    } catch (error, stackTrace) {
      logger.e(
        'Sherpa transcription failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      value = value.copyWith(isTranscribing: false);
    }
  }

  Future<String> _prepareSherpaModel() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final modelDirectory = Directory(
      path.join(supportDirectory.path, _modelDirectory),
    );
    await modelDirectory.create(recursive: true);

    for (final filename in [
      'tiny.en-encoder.int8.onnx',
      'tiny.en-decoder.int8.onnx',
      'tiny.en-tokens.txt',
    ]) {
      final modelFile = File(path.join(modelDirectory.path, filename));
      if (await modelFile.exists()) continue;

      final asset = await rootBundle.load('$_modelAssetDirectory/$filename');
      await modelFile.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        flush: true,
      );
    }

    return modelDirectory.path;
  }

  String _transcribeWithSherpa(
    Float32List samples,
    int sampleRate,
    String modelDirectory,
  ) {
    sherpa_onnx.initBindings();
    final recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(
        model: sherpa_onnx.OfflineModelConfig(
          whisper: sherpa_onnx.OfflineWhisperModelConfig(
            encoder: path.join(modelDirectory, 'tiny.en-encoder.int8.onnx'),
            decoder: path.join(modelDirectory, 'tiny.en-decoder.int8.onnx'),
            language: 'en',
            task: 'transcribe',
          ),
          tokens: path.join(modelDirectory, 'tiny.en-tokens.txt'),
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text;
    } finally {
      stream.free();
      recognizer.free();
    }
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
}
