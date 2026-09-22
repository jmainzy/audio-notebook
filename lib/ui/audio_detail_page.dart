import 'dart:core';
import 'dart:io';

import 'package:audionotebook/model/audio_item.dart';
import 'package:audionotebook/model/voice_segment.dart';
import 'package:audionotebook/ui/waveform.dart';
import 'package:audionotebook/utils/dimens.dart' as Dimens;
import 'package:audionotebook/utils/utils.dart';
import 'package:audionotebook/utils/vad.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logger/web.dart';
import 'package:wav/wav_file.dart';

Logger logger = Logger();

class AudioDetailPage extends StatefulWidget {
  const AudioDetailPage({super.key, required this.entry});
  final AudioItem entry;

  @override
  State<AudioDetailPage> createState() => _AudioDetailPageState();
}

class _AudioDetailPageState extends State<AudioDetailPage> {
  final _player = AudioPlayer();
  List<double>? _audioData;
  List<VoiceSegment> _voiceSegments = const [];
  List<TextEditingController> _noteControllers = const [];
  bool _detectingSegments = false;
  Object? _error;
  int? sampleRate;

  @override
  void initState() {
    super.initState();
    _loadAudio();
  }

  Future<void> _loadAudio() async {
    try {
      await _player.setFilePath(widget.entry.file.path);
      _audioData = await extractAudioData(widget.entry.file);
      setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _detectSegments() async {
    final waveform = _audioData;
    logger.i("Detecting segments");
    if (waveform == null || _detectingSegments) return;
    setState(() => _detectingSegments = true);
    final segments = await detectVoiceSegments(waveform, sampleRate!);
    logger.i("Detected ${segments.length} segments");
    if (!mounted) return;
    setState(() {
      _voiceSegments = segments;
      for (final controller in _noteControllers) {
        controller.dispose();
      }
      _noteControllers = [
        for (var index = 0; index < segments.length; index++)
          TextEditingController(),
      ];
      _detectingSegments = false;
    });
  }

  Future<List<double>> extractAudioData(File file) async {
    // Extract file as normalized values between 0.0 and 1.0
    final bytes = await file.readAsBytes();

    // Read the WAV file
    Wav wav = Wav.read(bytes);
    sampleRate = wav.samplesPerSecond;
    // Extract the audio data (left channel)
    return wav.channels[0];
  }

  @override
  void dispose() {
    for (final controller in _noteControllers) {
      controller.dispose();
    }
    _player.dispose();
    super.dispose();
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
              child: StreamBuilder<Duration>(
                stream: _player.positionStream,
                initialData: Duration.zero,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  return Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: _audioData == null || _detectingSegments
                              ? null
                              : _detectSegments,
                          // icon: _detectingSegments
                          //     ? const SizedBox(
                          //         width: 16,
                          //         height: 16,
                          //         child: CircularProgressIndicator(
                          //           strokeWidth: 2,
                          //         ),
                          //       )
                          //     : const Icon(Icons.auto_graph),
                          label: const Text('Detect Segments'),
                        ),
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
                          child: _waveformView(position),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDuration(position),
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
                      Expanded(child: _segmentList()),
                      const SizedBox(height: 16),
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, snapshot) {
                          final playing = snapshot.data?.playing ?? false;
                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xff292521),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: IconButton(
                              onPressed: () =>
                                  playing ? _player.pause() : _player.play(),
                              tooltip: playing
                                  ? 'Pause recording'
                                  : 'Play recording',
                              icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          );
                        },
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

  Widget _waveformView(Duration position) {
    final waveform = _audioData;
    if (waveform == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color.fromARGB(255, 195, 62, 18),
        ),
      );
    }
    return Stack(
      children: [
        WaveformWidget(
          color: const Color.fromARGB(255, 194, 59, 14),
          samples: waveform,
          segments: _voiceSegments,
        ),
        Transform.translate(
          offset: Offset(
            position.inMilliseconds /
                widget.entry.duration.inMilliseconds *
                MediaQuery.of(context).size.width,
            0,
          ),
          child: Container(width: 2, color: Colors.black),
        ),
      ],
    );
  }

  Widget _segmentList() {
    if (_voiceSegments.isEmpty) {
      return const Center(
        child: Text(
          'Detected segments will appear here.',
          style: TextStyle(fontFamily: 'Arial', color: Color(0xff887b70)),
        ),
      );
    }

    if (_noteControllers.length != _voiceSegments.length) {
      for (final controller in _noteControllers) {
        controller.dispose();
      }
      _noteControllers = [
        for (var index = 0; index < _voiceSegments.length; index++)
          TextEditingController(),
      ];
    }

    return ListView.separated(
      itemCount: _voiceSegments.length,
      padding: EdgeInsets.zero,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final segment = _voiceSegments[index];
        final start = Duration(
          milliseconds: (segment.start * widget.entry.duration.inMilliseconds)
              .round(),
        );
        final end = Duration(
          milliseconds: (segment.end * widget.entry.duration.inMilliseconds)
              .round(),
        );
        return _SegmentCard(
          index: index,
          segment: segment,
          samples: _audioData!,
          noteController: _noteControllers[index],
          start: start,
          end: end,
          onTap: () => _player.seek(start),
        );
      },
    );
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({
    required this.index,
    required this.segment,
    required this.samples,
    required this.noteController,
    required this.start,
    required this.end,
    required this.onTap,
  });

  final int index;
  final VoiceSegment segment;
  final List<double> samples;
  final TextEditingController noteController;
  final Duration start;
  final Duration end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final startSample = (segment.start * samples.length).floor().clamp(
      0,
      samples.length,
    );
    final endSample = (segment.end * samples.length).ceil().clamp(
      startSample + 1,
      samples.length,
    );
    final segmentSamples = samples.sublist(startSample, endSample);

    return Material(
      color: Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        focusColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.marginLarge,
            Dimens.marginLarge,
            Dimens.marginShort,
            Dimens.marginLarge,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${formatDuration(start)} - ${formatDuration(end)}',
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      fontSize: 12,
                      color: Color(0xff887b70),
                    ),
                  ),
                  Spacer(),
                  IconButton(onPressed: () => {}, icon: Icon(Icons.more_horiz)),
                ],
              ),
              SizedBox(
                height: 42,
                width: double.infinity,
                child: WaveformWidget(
                  color: const Color.fromARGB(255, 194, 59, 14),
                  samples: segmentSamples,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                minLines: 1,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Add a note for this segment',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
