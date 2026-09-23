import 'dart:core';

import 'package:audionotebook/model/audio_item.dart';
import 'package:audionotebook/ui/audio_page_manager.dart';
import 'package:audionotebook/ui/audio_page_state.dart';
import 'package:audionotebook/ui/waveform/fragment_list.dart';
import 'package:audionotebook/ui/waveform/waveform_view.dart';
import 'package:audionotebook/utils/dimens.dart';
import 'package:audionotebook/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:logger/web.dart';

Logger logger = Logger();

class AudioDetailPage extends StatefulWidget {
  const AudioDetailPage({
    super.key,
    required this.pageManager,
    required this.entry,
  });
  final AudioPageManager pageManager;
  final AudioItem entry;

  @override
  State<AudioDetailPage> createState() => _AudioDetailPageState();
}

class _AudioDetailPageState extends State<AudioDetailPage> {
  Object? _error;
  int? sampleRate;
  final ScrollController _waveScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.pageManager.loadAudio(widget.entry.file.path);
  }

  @override
  void didUpdateWidget(covariant AudioDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageManager.value.audioPath !=
        widget.pageManager.value.audioPath) {
      widget.pageManager.loadAudio(widget.entry.file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text(
          'Recording',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              entry.title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xff292521),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.filename,
              style: const TextStyle(
                fontFamily: 'Arial',
                color: Color(0xff887b70),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${formatDate(context, entry.createdAt)}  ·  ${formatTime(context, entry.createdAt)}',
              style: const TextStyle(
                fontFamily: 'Arial',
                color: Color(0xff887b70),
              ),
            ),
            const SizedBox(height: 34),
            Expanded(
              child: ValueListenableBuilder<AudioPageState>(
                valueListenable: widget.pageManager,
                builder: (context, state, _) {
                  // final position = snapshot.data ?? Duration.zero;
                  return Column(
                    children: [
                      Row(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed: state.isSegmenting
                                  ? null
                                  : widget.pageManager.detectSegments,
                              label: const Text('Detect Segments'),
                            ),
                          ),
                          SizedBox(width: Dimens.marginShort),
                          FilledButton.icon(
                            onPressed: state.isTranscribing
                                ? null
                                : widget.pageManager.transcribe,
                            label: const Text('Transcribe'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 160,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 26,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xffd97757)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: WaveformView(
                            controller: widget.pageManager,
                            state: state,
                            scrollController: _waveScroll,
                            playbackNotifier:
                                widget.pageManager.playbackPosition,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDuration(
                              widget.pageManager.playbackPosition.value,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Arial',
                              fontSize: 12,
                              color: Color(0xff887b70),
                            ),
                          ),
                          Text(
                            formatDuration(entry.duration),
                            style: const TextStyle(
                              fontFamily: 'Arial',
                              fontSize: 12,
                              color: Color(0xff887b70),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Expanded(child: _segmentList()),
                      Expanded(
                        child: FragmentList(
                          fragments: state.fragments,
                          playbackNotifier: widget.pageManager.playbackPosition,
                          selectedIndex: state.selectedFragmentIndex,
                          onSelect: widget.pageManager.selectFragment,
                          onCapture: (i) => widget.pageManager
                              .captureFragmentTiming(context, i),
                          onClear: widget.pageManager.clearFragmentTiming,
                          onJumpTo: (idx) {
                            widget.pageManager.exitFocusMode();
                            final frag = state.fragments[idx];
                            widget.pageManager.seekTo(
                              Duration(
                                milliseconds: (frag.start * 1000).ceil(),
                              ),
                            );
                          },
                          onDoubleTap: (idx) {
                            widget.pageManager.enterFocusMode(idx);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xff292521),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: IconButton(
                          onPressed: state.audioPath == null
                              ? null
                              : widget.pageManager.togglePlayback,
                          tooltip: state.isPlaying
                              ? 'Pause recording'
                              : 'Play recording',
                          icon: Icon(
                            state.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'This file could not be loaded.',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Widget _segmentList() {
  //   if (_voiceSegments.isEmpty) {
  //     return const Center(
  //       child: Text(
  //         'Detected segments will appear here.',
  //         style: TextStyle(fontFamily: 'Arial', color: Color(0xff887b70)),
  //       ),
  //     );
  //   }

  //   if (_noteControllers.length != _voiceSegments.length) {
  //     for (final controller in _noteControllers) {
  //       controller.dispose();
  //     }
  //     _noteControllers = [
  //       for (var index = 0; index < _voiceSegments.length; index++)
  //         TextEditingController(),
  //     ];
  //   }

  //   return ListView.separated(
  //     itemCount: _voiceSegments.length,
  //     padding: EdgeInsets.zero,
  //     separatorBuilder: (_, _) => const SizedBox(height: 10),
  //     itemBuilder: (context, index) {
  //       final segment = _voiceSegments[index];
  //       final start = Duration(
  //         milliseconds: (segment.start * widget.entry.duration.inMilliseconds)
  //             .round(),
  //       );
  //       final end = Duration(
  //         milliseconds: (segment.end * widget.entry.duration.inMilliseconds)
  //             .round(),
  //       );
  //       return _SegmentCard(
  //         index: index,
  //         segment: segment,
  //         samples: _audioData!,
  //         noteController: _noteControllers[index],
  //         start: start,
  //         end: end,
  //         onTap: () => _player.seek(start),
  //       );
  //     },
  //   );
  // }
}
