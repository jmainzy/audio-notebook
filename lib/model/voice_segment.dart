import 'dart:ui';

import 'package:audionotebook/utils/colors.dart';

enum SegmentLanguage { mvskoke, english, mixed, comment }

class Segment {
  /// The sequential internal identifier (0, 1, 2...)
  /// Critical for array lookups and UI list ordering.
  final int index;

  Segment({
    required this.index,
    required this.start,
    required this.end,
    this.text = "",
    this.notes = "",
    this.language = SegmentLanguage.mixed,
    this.isComment = false,
    this.audioPath,
  });

  double start;
  double end;
  final String text;
  final String notes;
  final SegmentLanguage language;
  final bool isComment;
  final String? audioPath;

  /// Helper to update real timing after alignment
  void setTiming({required double start, required double end}) {
    this.start = start;
    this.end = end;
  }
}

extension SegmentLanguageStyle on SegmentLanguage {
  String get label => switch (this) {
    SegmentLanguage.mvskoke => 'Mvskoke',
    SegmentLanguage.english => 'English',
    SegmentLanguage.mixed => 'Mixed',
    SegmentLanguage.comment => 'Comment',
  };

  Color get color => switch (this) {
    SegmentLanguage.mvskoke => AppColors.green,
    SegmentLanguage.english => AppColors.blue,
    SegmentLanguage.mixed => AppColors.orange,
    SegmentLanguage.comment => const Color(0xffc62828),
  };
}
