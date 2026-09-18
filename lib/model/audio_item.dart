import 'dart:io';

class AudioItem {
  const AudioItem({
    required this.file,
    required this.createdAt,
    required this.duration,
  });

  final File file;
  final DateTime createdAt;
  final Duration duration;

  String get filename => file.uri.pathSegments.last;
  String get title => filename
      .replaceFirst(RegExp(r'\.[^.]+$'), '')
      .replaceAll(RegExp(r'[_-]+'), ' ');
}
