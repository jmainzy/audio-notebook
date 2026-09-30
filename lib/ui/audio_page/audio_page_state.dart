import 'package:audionotebook/model/voice_segment.dart';
import 'package:just_waveform/just_waveform.dart';

enum PlaybackMode { fullRecording, segments, transcribed }

class AudioPageState {
  final bool isProcessing;
  final double progress;
  final String? audioPath;
  final List<Segment> fragments;
  final Waveform? waveform;
  final Duration audioDuration;
  final bool isPlaying;
  final double zoomLevel;
  final int? focusedFragmentIndex;
  final bool hasUnsavedChanges;
  final int? selectedFragmentIndex;
  final bool isReadOnly;
  final bool isTranscribing;
  final bool isSegmenting;
  final PlaybackMode playbackMode;
  // final ClaimInfo? activeClaim;

  const AudioPageState({
    this.isProcessing = false,
    this.progress = 0.0,
    this.audioPath,
    this.fragments = const [],
    this.waveform,
    this.audioDuration = Duration.zero,
    this.isPlaying = false,
    this.zoomLevel = 1.0,
    this.focusedFragmentIndex,
    this.hasUnsavedChanges = false,
    this.selectedFragmentIndex,
    this.isReadOnly = false,
    this.isTranscribing = false,
    this.isSegmenting = false,
    this.playbackMode = PlaybackMode.fullRecording,
  });

  AudioPageState copyWith({
    bool? isProcessing,
    String? statusMessage,
    double? progress,
    String? audioPath,
    String? textPath,
    String? dictPath,
    bool? hasIds,
    List<Segment>? fragments,
    Waveform? waveform,
    bool clearWaveform = false,
    Duration? audioDuration,
    bool? isPlaying,
    double? zoomLevel,
    int? focusedFragmentIndex,
    bool clearFocus = false,
    String? autoSavePath,
    bool? hasUnsavedChanges,
    Map<String, String>? transliterationRules,
    int? selectedFragmentIndex,
    bool clearSelection = false,
    bool? isReadOnly,
    bool? isTranscribing,
    bool? isSegmenting,
    PlaybackMode? playbackMode,
  }) {
    return AudioPageState(
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      audioPath: audioPath ?? this.audioPath,
      fragments: fragments ?? this.fragments,
      waveform: clearWaveform ? null : (waveform ?? this.waveform),
      audioDuration: audioDuration ?? this.audioDuration,
      isPlaying: isPlaying ?? this.isPlaying,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      focusedFragmentIndex: clearFocus
          ? null
          : (focusedFragmentIndex ?? this.focusedFragmentIndex),
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      selectedFragmentIndex: clearSelection
          ? null
          : (selectedFragmentIndex ?? this.selectedFragmentIndex),
      isReadOnly: isReadOnly ?? this.isReadOnly,
      isTranscribing: isTranscribing ?? this.isTranscribing,
      isSegmenting: isSegmenting ?? this.isSegmenting,
      playbackMode: playbackMode ?? this.playbackMode,
    );
  }
}
