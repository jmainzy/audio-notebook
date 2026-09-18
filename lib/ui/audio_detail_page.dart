import 'dart:io';

import 'package:audionotebook/model/audio_item.dart';
import 'package:audionotebook/ui/waveform.dart';
import 'package:audionotebook/utils.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wav/wav_file.dart';

class AudioDetailPage extends StatefulWidget {
  const AudioDetailPage({super.key, required this.entry});
  final AudioItem entry;

  @override
  State<AudioDetailPage> createState() => _AudioDetailPageState();
}

class _AudioDetailPageState extends State<AudioDetailPage> {
  final _player = AudioPlayer();
  List<double>? _audioData;
  Object? _error;

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

  Future<List<double>> extractAudioData(File file) async {
    // Extract file as normalized values between 0.0 and 1.0
    final bytes = await file.readAsBytes();

    // Read the WAV file
    Wav wav = Wav.read(bytes);
    // Extract the audio data (left channel)
    return wav.channels[0];
  }

  @override
  void dispose() {
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
                      Expanded(
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
                      const SizedBox(height: 24),
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
        child: CircularProgressIndicator(color: Color(0xffd97757)),
      );
    }
    return Stack(
      children: [
        WaveformWidget(color: Color(0xffd97757), samples: waveform),
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
}
