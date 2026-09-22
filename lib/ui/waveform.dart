import 'package:flutter/material.dart';

import '../model/voice_segment.dart';

class WaveformWidget extends StatelessWidget {
  final List<double> samples;
  final Color color;
  final List<VoiceSegment> segments;
  final Color highlightColor = const Color.fromARGB(255, 77, 109, 159);

  const WaveformWidget({
    super.key,
    required this.samples,
    required this.color,
    this.segments = const [],
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WaveformPainter(
        samples: samples,
        color: color,
        segments: segments,
        highlightColor: highlightColor,
      ),
      size: Size.infinite,
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final double barWidth;
  final double gap;
  final List<VoiceSegment> segments;
  final Color highlightColor;

  WaveformPainter({
    required this.samples,
    required this.color,
    required this.highlightColor,
    this.segments = const [],
    this.barWidth = 0.5,
    this.gap = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final totalBarWidth = barWidth + gap;
    final barCount = (size.width / totalBarWidth).floor();
    if (barCount <= 0 || samples.isEmpty) return;

    final highlightPaint = Paint()..color = highlightColor;
    for (final segment in segments) {
      canvas.drawRect(
        Rect.fromLTRB(
          size.width * segment.start.clamp(0.0, 1.0),
          0,
          size.width * segment.end.clamp(0.0, 1.0),
          size.height,
        ),
        highlightPaint,
      );
    }

    final center = size.height / 2;
    for (var barIndex = 0; barIndex < barCount; barIndex++) {
      final start = (barIndex * samples.length / barCount).floor();
      final end = ((barIndex + 1) * samples.length / barCount).ceil().clamp(
        start + 1,
        samples.length,
      );
      var peak = 0.0;
      for (var sampleIndex = start; sampleIndex < end; sampleIndex++) {
        peak = peak < samples[sampleIndex].abs()
            ? samples[sampleIndex].abs()
            : peak;
      }

      final x = barIndex * totalBarWidth + (barWidth / 2);
      final barHeight = size.height * peak.clamp(0.0, 1.0);

      final double top = center - (barHeight / 2);
      final double bottom = center + (barHeight / 2);

      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.color != color ||
        oldDelegate.segments != segments;
  }
}
