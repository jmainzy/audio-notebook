
import 'dart:io';

import 'package:audionotebook/model/audio_item.dart';
import 'package:audionotebook/utils.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_waveform/just_waveform.dart';

class AudioDetailPage extends StatefulWidget {
  const AudioDetailPage({super.key, required this.entry});
  final AudioItem entry;

  @override
  State<AudioDetailPage> createState() => _AudioDetailPageState();
}

class _AudioDetailPageState extends State<AudioDetailPage> {
  final _player = AudioPlayer();
  Waveform? _waveform;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadAudio();
  }

  Future<void> _loadAudio() async {
    try {
      await _player.setFilePath(widget.entry.file.path);
      final waveFile = File(
        '${Directory.systemTemp.path}/${widget.entry.file.uri.pathSegments.last}.waveform',
      );
      await for (final progress in JustWaveform.extract(
        audioInFile: widget.entry.file,
        waveOutFile: waveFile,
      )) {
        if (!mounted) return;
        if (progress.waveform != null)
          setState(() => _waveform = progress.waveform);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
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
            Text(
              'LOADED AUDIO',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 2,
                color: const Color(0xffd97757),
                fontWeight: FontWeight.bold,
              ),
            ),
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
                              onPressed: _waveform == null
                                  ? null
                                  : () => playing
                                        ? _player.pause()
                                        : _player.play(),
                              tooltip: playing
                                  ? 'Pause recording'
                                  : 'Play recording',
                              icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                                color: _waveform == null
                                    ? Colors.white38
                                    : Colors.white,
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
    final waveform = _waveform;
    if (waveform == null)
      return const Center(
        child: CircularProgressIndicator(color: Color(0xffd97757)),
      );
    final total = widget.entry.duration.inMilliseconds;
    final progress = total == 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return CustomPaint(
      painter: WaveformPainter(
        waveform: waveform,
        color: const Color(0xffd97757),
        progress: progress,
      ),
      size: Size.infinite,
    );
  }
}

class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.waveform,
    required this.color,
    required this.progress,
  });
  final Waveform waveform;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final count = waveform.length;
    if (count == 0 || size.width <= 0) return;
    final barWidth = size.width / count;
    final playedPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final remainingPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = const Color(0xff292521)
      ..strokeWidth = 2;
    final progressX = size.width * progress;
    for (var index = 0; index < count; index++) {
      final x = (index + 0.5) * barWidth;
      final max = waveform.getPixelMax(index).abs();
      final height = (max.clamp(0, 32767) / 32767) * size.height * 0.9;
      final start = Offset(x, (size.height - height) / 2);
      final end = Offset(x, (size.height + height) / 2);
      (x <= progressX ? playedPaint : remainingPaint).strokeWidth = barWidth
          .clamp(2, 6);
      canvas.drawLine(
        start,
        end,
        x <= progressX ? playedPaint : remainingPaint,
      );
    }
    canvas.drawLine(
      Offset(progressX, 0),
      Offset(progressX, size.height),
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.waveform != waveform || oldDelegate.progress != progress;
}