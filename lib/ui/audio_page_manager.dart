import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audionotebook/model/voice_segment.dart';
import 'package:audionotebook/services/audio_service.dart';
import 'package:audionotebook/ui/audio_page_state.dart';
import 'package:audionotebook/utils/vad.dart';
import 'package:flutter/material.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:wav/wav_file.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

Logger logger = Logger();

class AudioPageManager extends ValueNotifier<AudioPageState> {
  final AudioService _audioService = AudioService();
  final playbackPosition = ValueNotifier(Duration.zero);
  final asrController = WhisperController();
  bool _segmentPlaybackActive = false;
  int _segmentPlaybackGeneration = 0;

  AudioPageManager() : super(AudioPageState(zoomLevel: 10.0)) {
    _audioService.positionStream.listen((pos) {
      playbackPosition.value = pos;
    });
    _audioService.stateStream.listen((s) {
      value = value.copyWith(isPlaying: _segmentPlaybackActive || s.playing);
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
      final random = Random();

      // VAD returns normalized positions; the waveform painter uses seconds.
      final segments = [
        for (var index = 0; index < detected.length; index++)
          Segment(
            index: index,
            start: detected[index].start * durationSeconds,
            end: detected[index].end * durationSeconds,
            text: detected[index].text,
            language: SegmentLanguage
                .values[random.nextInt(SegmentLanguage.values.length)],
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
              notes: item['notes'] as String? ?? '',
              language: SegmentLanguage.values.firstWhere(
                (language) => language.name == item['language'],
                orElse: () => SegmentLanguage.mixed,
              ),
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
            'notes': segment.notes,
            'language': segment.language.name,
          },
      ];
      await cacheFile.writeAsString(jsonEncode(cache));
    } catch (error) {
      logger.w('Could not save segments: $error');
    }
  }

  Future<void> transcribe() async {
    value = value.copyWith(isTranscribing: true);
    logger.i('transcribe');
    if (value.audioPath != null) {
      final result = await asrController.transcribe(
        model: WhisperModel.tiny,
        audioPath: value.audioPath!,
        lang: 'en',
      );
      print(result?.transcription.text);
    }
    value = value.copyWith(isTranscribing: false);
  }

  void selectFragment(int? index) {
    value = value.copyWith(selectedFragmentIndex: index);
  }

  void deleteFragment(int index) {
    if (value.isReadOnly || index < 0 || index >= value.fragments.length) {
      return;
    }

    final remaining = List<Segment>.from(value.fragments)..removeAt(index);
    final fragments = [
      for (var newIndex = 0; newIndex < remaining.length; newIndex++)
        Segment(
          index: newIndex,
          start: remaining[newIndex].start,
          end: remaining[newIndex].end,
          text: remaining[newIndex].text,
          notes: remaining[newIndex].notes,
          language: remaining[newIndex].language,
        ),
    ];
    final selectedIndex = value.selectedFragmentIndex;
    final focusedIndex = value.focusedFragmentIndex;

    value = value.copyWith(
      fragments: fragments,
      hasUnsavedChanges: true,
      clearSelection: selectedIndex == index,
      selectedFragmentIndex: selectedIndex != null && selectedIndex > index
          ? selectedIndex - 1
          : selectedIndex,
      clearFocus: focusedIndex == index,
      focusedFragmentIndex: focusedIndex != null && focusedIndex > index
          ? focusedIndex - 1
          : focusedIndex,
    );

    final audioPath = value.audioPath;
    if (audioPath != null) unawaited(_saveSegments(audioPath, fragments));
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

  void setPlaybackMode(PlaybackMode mode) {
    value = value.copyWith(playbackMode: mode);
  }

  Future<void> togglePlayback() async {
    if (value.isPlaying) {
      if (_segmentPlaybackActive) {
        _segmentPlaybackGeneration++;
        _segmentPlaybackActive = false;
      }
      await _audioService.pause();
      value = value.copyWith(isPlaying: false);
    } else {
      switch (value.playbackMode) {
        case PlaybackMode.fullRecording:
          await _audioService.play();
        case PlaybackMode.segments:
        case PlaybackMode.transcribed:
          final segments = _segmentsForPlayback();
          if (segments.isEmpty) return;
          final generation = ++_segmentPlaybackGeneration;
          _segmentPlaybackActive = true;
          value = value.copyWith(isPlaying: true);
          unawaited(_playSegments(segments, generation));
      }
    }
  }

  List<Segment> _segmentsForPlayback() {
    final segments = value.fragments.where((segment) {
      if (segment.start < 0 || segment.end <= segment.start) return false;
      if (value.playbackMode == PlaybackMode.transcribed) {
        return segment.text.trim().isNotEmpty ||
            segment.notes.trim().isNotEmpty;
      }
      return true;
    }).toList()..sort((first, second) => first.start.compareTo(second.start));
    return segments;
  }

  Future<void> _playSegments(List<Segment> segments, int generation) async {
    try {
      for (final segment in segments) {
        if (generation != _segmentPlaybackGeneration) break;

        final end = Duration(milliseconds: (segment.end * 1000).round());
        await _audioService.seek(
          Duration(milliseconds: (segment.start * 1000).round()),
        );
        if (generation != _segmentPlaybackGeneration) break;

        unawaited(_audioService.play());
        while (generation == _segmentPlaybackGeneration &&
            _audioService.position < end) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        if (generation != _segmentPlaybackGeneration) break;
        await _audioService.pause();
      }
    } catch (error) {
      logger.w('Segment playback stopped: $error');
    } finally {
      if (generation == _segmentPlaybackGeneration) {
        _segmentPlaybackActive = false;
        value = value.copyWith(isPlaying: false);
      }
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

    // Segment? prevTimed;
    // for (int i = index - 1; i >= 0; i--) {
    //   if (frags[i].start >= 0) {
    //     prevTimed = frags[i];
    //     break;
    //   }
    // }
    // if (prevTimed != null) {
    //   double prevStart = prevTimed.start;
    //   if (prevStart > s) prevStart = s;
    //   prevTimed.setTiming(start: prevStart, end: s);
    // }

    // Segment? nextTimed;
    // for (int i = index + 1; i < frags.length; i++) {
    //   if (frags[i].start >= 0) {
    //     nextTimed = frags[i];
    //     break;
    //   }
    // }
    // if (nextTimed != null) {
    //   double nextEnd = nextTimed.end;
    //   if (nextEnd < e) nextEnd = e;
    //   nextTimed.setTiming(start: e, end: nextEnd);
    // }

    value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
  }

  void updateFragmentText(int index, String text) {
    if (value.isReadOnly || index < 0 || index >= value.fragments.length) {
      return;
    }

    final fragments = List<Segment>.from(value.fragments);
    final fragment = fragments[index];
    fragments[index] = Segment(
      index: fragment.index,
      start: fragment.start,
      end: fragment.end,
      text: text,
      notes: fragment.notes,
      language: fragment.language,
    );
    value = value.copyWith(fragments: fragments, hasUnsavedChanges: true);

    final audioPath = value.audioPath;
    if (audioPath != null) unawaited(_saveSegments(audioPath, fragments));
  }

  void updateFragmentLanguage(int index, SegmentLanguage language) {
    if (value.isReadOnly || index < 0 || index >= value.fragments.length) {
      return;
    }

    final fragments = List<Segment>.from(value.fragments);
    final fragment = fragments[index];
    fragments[index] = Segment(
      index: fragment.index,
      start: fragment.start,
      end: fragment.end,
      text: fragment.text,
      notes: fragment.notes,
      language: language,
    );
    value = value.copyWith(fragments: fragments, hasUnsavedChanges: true);

    final audioPath = value.audioPath;
    if (audioPath != null) unawaited(_saveSegments(audioPath, fragments));
  }

  void updateFragmentNotes(int index, String notes) {
    if (value.isReadOnly || index < 0 || index >= value.fragments.length) {
      return;
    }

    final fragments = List<Segment>.from(value.fragments);
    final fragment = fragments[index];
    fragments[index] = Segment(
      index: fragment.index,
      start: fragment.start,
      end: fragment.end,
      text: fragment.text,
      notes: notes,
      language: fragment.language,
    );
    value = value.copyWith(fragments: fragments, hasUnsavedChanges: true);

    final audioPath = value.audioPath;
    if (audioPath != null) unawaited(_saveSegments(audioPath, fragments));
  }

  void captureFragmentTiming(BuildContext context, int i) {}
}
